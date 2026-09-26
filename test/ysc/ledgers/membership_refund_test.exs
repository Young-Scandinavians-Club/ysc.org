defmodule Ysc.Ledgers.MembershipRefundTest do
  @moduledoc """
  Refunds for subscription payments, which the ledger stores under their
  Stripe invoice ID (`in_...`) rather than a payment intent ID.
  """
  use Ysc.DataCase, async: false

  import Mox

  alias Ysc.Ledgers
  alias Ysc.LedgersFixtures
  alias Ysc.Stripe.InvoiceHelpers
  alias Ysc.Stripe.WebhookHandler
  alias Ysc.Tickets

  setup :verify_on_exit!

  setup do
    previous_client = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    on_exit(fn ->
      if previous_client,
        do: Application.put_env(:ysc, :stripe_client, previous_client),
        else: Application.delete_env(:ysc, :stripe_client)
    end)

    invoice_id = "in_membership_#{System.unique_integer([:positive])}"
    payment_intent_id = "pi_membership_#{System.unique_integer([:positive])}"

    payment =
      LedgersFixtures.payment_fixture(%{
        amount: Money.new(:USD, "45.00"),
        entity_type: :membership,
        external_payment_id: invoice_id
      })

    %{
      payment: payment,
      invoice_id: invoice_id,
      payment_intent_id: payment_intent_id
    }
  end

  defp invoice_with_payments(invoice_id, payments) do
    %Stripe.Invoice{
      id: invoice_id,
      payments: %Stripe.List{object: "list", data: payments, has_more: false}
    }
  end

  defp invoice_payment(invoice_id, payment_intent_id, status) do
    %Stripe.InvoicePayment{
      id: "inpay_#{System.unique_integer([:positive])}",
      invoice: invoice_id,
      status: status,
      payment: %{type: "payment_intent", payment_intent: payment_intent_id}
    }
  end

  defp membership_revenue_debits(refund) do
    refund.id
    |> Ledgers.get_entries_by_refund()
    |> Enum.filter(
      &(&1.account.name == "membership_revenue" and &1.debit_credit == :debit)
    )
  end

  describe "InvoiceHelpers.refundable_payment_intent_id/1" do
    test "passes payment intent IDs through without calling Stripe" do
      assert {:ok, "pi_direct"} =
               InvoiceHelpers.refundable_payment_intent_id("pi_direct")
    end

    test "resolves an invoice to the payment intent of its paid payment", %{
      invoice_id: invoice_id,
      payment_intent_id: payment_intent_id
    } do
      expect(Ysc.StripeMock, :retrieve_invoice, fn ^invoice_id,
                                                   %{expand: ["payments"]} ->
        {:ok,
         invoice_with_payments(invoice_id, [
           invoice_payment(invoice_id, "pi_failed_attempt", "canceled"),
           invoice_payment(invoice_id, payment_intent_id, "paid")
         ])}
      end)

      assert {:ok, ^payment_intent_id} =
               InvoiceHelpers.refundable_payment_intent_id(invoice_id)
    end

    test "errors when the invoice has no paid payment", %{
      invoice_id: invoice_id
    } do
      expect(Ysc.StripeMock, :retrieve_invoice, fn ^invoice_id, _params ->
        {:ok, invoice_with_payments(invoice_id, [])}
      end)

      assert {:error, :no_paid_payment_intent_for_invoice} =
               InvoiceHelpers.refundable_payment_intent_id(invoice_id)
    end
  end

  describe "admin refund of a membership payment (Tickets.refund_via_stripe/4)" do
    test "refunds the invoice's payment intent and reverses membership revenue",
         %{
           payment: payment,
           invoice_id: invoice_id,
           payment_intent_id: payment_intent_id
         } do
      expect(Ysc.StripeMock, :retrieve_invoice, fn ^invoice_id, _params ->
        {:ok,
         invoice_with_payments(invoice_id, [
           invoice_payment(invoice_id, payment_intent_id, "paid")
         ])}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _params ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           latest_charge: %Stripe.Charge{id: "ch_membership"},
           metadata: %{}
         }}
      end)

      assert {:ok, {%Ledgers.Refund{} = refund, _transaction, _entries}} =
               Tickets.refund_via_stripe(
                 payment,
                 Money.new(:USD, "45.00"),
                 "Member requested refund"
               )

      assert refund.payment_id == payment.id
      assert Money.equal?(refund.amount, Money.new(:USD, "45.00"))
      assert Ledgers.get_payment(payment.id).status == :refunded
      assert [_] = membership_revenue_debits(refund)
    end

    test "returns a Stripe error without touching the ledger when the invoice can't be resolved",
         %{payment: payment, invoice_id: invoice_id} do
      expect(Ysc.StripeMock, :retrieve_invoice, fn ^invoice_id, _params ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message: "No such invoice"
         }}
      end)

      assert {:error, {:stripe_error, _}} =
               Tickets.refund_via_stripe(
                 payment,
                 Money.new(:USD, "45.00"),
                 "Member requested refund"
               )

      assert Ledgers.list_refunds_for_payment(payment.id) == []
      assert Ledgers.get_payment(payment.id).status == :completed
    end
  end

  describe "refund.created webhook for a membership payment" do
    test "maps the refund's payment intent back to the invoice-keyed payment",
         %{
           payment: payment,
           invoice_id: invoice_id,
           payment_intent_id: payment_intent_id
         } do
      expect(Ysc.StripeMock, :list_invoice_payments, fn params, _opts ->
        assert params.payment == %{
                 type: "payment_intent",
                 payment_intent: payment_intent_id
               }

        {:ok,
         %Stripe.List{
           object: "list",
           has_more: false,
           data: [invoice_payment(invoice_id, payment_intent_id, "paid")]
         }}
      end)

      refund_id = "re_membership_#{System.unique_integer([:positive])}"

      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "refund.created",
                 %Stripe.Refund{
                   id: refund_id,
                   charge: "ch_membership",
                   amount: 4500,
                   status: "succeeded",
                   payment_intent: payment_intent_id,
                   metadata: %{}
                 }
               )

      refund = Ledgers.get_refund_by_external_id(refund_id)
      assert refund.payment_id == payment.id
      assert refund.reason == "Membership refund"
      assert Ledgers.get_payment(payment.id).status == :refunded
      assert [_] = membership_revenue_debits(refund)
    end

    test "records nothing when the payment intent didn't pay an invoice", %{
      payment: payment,
      payment_intent_id: payment_intent_id
    } do
      expect(Ysc.StripeMock, :list_invoice_payments, fn _params, _opts ->
        {:ok, %Stripe.List{object: "list", has_more: false, data: []}}
      end)

      refund_id = "re_unmatched_#{System.unique_integer([:positive])}"

      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "refund.created",
                 %Stripe.Refund{
                   id: refund_id,
                   charge: "ch_unmatched",
                   amount: 4500,
                   status: "succeeded",
                   payment_intent: payment_intent_id,
                   metadata: %{}
                 }
               )

      assert Ledgers.get_refund_by_external_id(refund_id) == nil
      assert Ledgers.list_refunds_for_payment(payment.id) == []
    end
  end
end

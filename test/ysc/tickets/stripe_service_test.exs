defmodule Ysc.Tickets.StripeServiceTest do
  @moduledoc """
  Tests for Ysc.Tickets.StripeService module.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Mox
  alias Ysc.Tickets.StripeService
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
      {:ok, %{"Id" => "qb_customer_default"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params, _opts ->
      {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
      {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _name ->
      {:ok, %{"Id" => "qb_account_default"}}
    end)

    user = user_fixture()

    # Give user lifetime membership
    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

    event = event_fixture()
    tier = ticket_tier_fixture(%{event_id: event.id})

    ticket_selections = %{tier.id => 1}

    {:ok, ticket_order} =
      Ysc.Tickets.create_ticket_order(user.id, event.id, ticket_selections)

    # Configure Stripe client mock
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    %{user: user, ticket_order: ticket_order}
  end

  defp cancel_timeout_jobs_for_order!(ticket_order_id) do
    from(j in Oban.Job,
      where: j.worker == "Ysc.Tickets.TimeoutWorker",
      where: fragment("?->>'ticket_order_id' = ?", j.args, ^ticket_order_id),
      where: j.state in ["available", "scheduled", "retryable"]
    )
    |> Ysc.Repo.delete_all()
  end

  describe "create_payment_intent/2" do
    test "creates payment intent with correct parameters", %{
      ticket_order: ticket_order
    } do
      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        # $50.00 in cents
        assert params.amount == 5000
        assert params.currency == "usd"
        # Metadata uses atom keys in the code
        assert params.metadata[:ticket_order_id] == ticket_order.id
        {:ok, %{id: "pi_test_123", status: "requires_payment_method"}}
      end)

      assert {:ok, payment_intent} =
               StripeService.create_payment_intent(ticket_order)

      assert payment_intent.id == "pi_test_123"
    end

    test "includes customer_id when provided", %{ticket_order: ticket_order} do
      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        assert params.customer == "cus_test_123"
        {:ok, %{id: "pi_test_123", status: "requires_payment_method"}}
      end)

      assert {:ok, _} =
               StripeService.create_payment_intent(ticket_order,
                 customer_id: "cus_test_123"
               )
    end

    test "handles Stripe errors gracefully", %{ticket_order: ticket_order} do
      expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:error,
         %Stripe.Error{
           message: "Card declined",
           source: :api,
           code: "card_declined"
         }}
      end)

      assert {:error, "Card declined"} =
               StripeService.create_payment_intent(ticket_order)
    end
  end

  describe "cancel_payment_intent/1" do
    test "cancels payment intent successfully" do
      expect(Ysc.StripeMock, :cancel_payment_intent, fn _id, _opts ->
        {:ok, %{id: "pi_test_123", status: "canceled"}}
      end)

      assert :ok = StripeService.cancel_payment_intent("pi_test_123")
    end

    test "handles already canceled payment intent" do
      expect(Ysc.StripeMock, :cancel_payment_intent, fn _id, _opts ->
        {:error,
         %Stripe.Error{
           message: "PaymentIntent already canceled",
           source: :api,
           code: "payment_intent_already_canceled"
         }}
      end)

      assert :ok = StripeService.cancel_payment_intent("pi_test_123")
    end

    test "returns error for other Stripe errors" do
      expect(Ysc.StripeMock, :cancel_payment_intent, fn _id, _opts ->
        {:error,
         %Stripe.Error{
           message: "Invalid payment intent",
           source: :api,
           code: "invalid_payment_intent"
         }}
      end)

      assert {:error, "Invalid payment intent"} =
               StripeService.cancel_payment_intent("pi_test_123")
    end

    test "returns ok for nil payment intent" do
      assert :ok = StripeService.cancel_payment_intent(nil)
    end
  end

  describe "process_successful_payment/1" do
    defp payment_intent_for_order(ticket_order, overrides \\ []) do
      amount_cents =
        ticket_order.total_amount.amount
        |> Decimal.mult(100)
        |> Decimal.to_integer()

      defaults = %{
        id: "pi_success_#{ticket_order.id}",
        status: "succeeded",
        amount: amount_cents,
        metadata: %{"ticket_order_id" => ticket_order.id}
      }

      struct(Stripe.PaymentIntent, Map.merge(defaults, Map.new(overrides)))
    end

    test "completes pending order when given a payment intent id", %{
      ticket_order: ticket_order
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        payment_intent_id = "pi_by_id_#{ticket_order.id}"

        payment_intent =
          payment_intent_for_order(ticket_order, id: payment_intent_id)

        cancel_timeout_jobs_for_order!(ticket_order.id)

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                            _opts ->
          {:ok, payment_intent}
        end)

        assert {:ok, completed} =
                 StripeService.process_successful_payment(payment_intent_id)

        assert completed.status == :completed
        assert completed.payment_id
      end)
    end

    test "completes pending order from a preloaded payment intent without refetching",
         %{
           ticket_order: ticket_order
         } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        payment_intent = payment_intent_for_order(ticket_order)

        cancel_timeout_jobs_for_order!(ticket_order.id)
        deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

        assert {:ok, completed} =
                 StripeService.process_successful_payment(payment_intent)

        assert completed.status == :completed
        assert completed.payment_id
      end)
    end

    test "returns error when payment intent metadata is missing ticket order id" do
      payment_intent =
        struct(Stripe.PaymentIntent, %{
          id: "pi_no_metadata",
          status: "succeeded",
          amount: 5000,
          metadata: %{}
        })

      deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

      assert {:error, :no_ticket_order_metadata} =
               StripeService.process_successful_payment(payment_intent)
    end

    test "returns error when ticket order id in metadata does not exist" do
      payment_intent =
        struct(Stripe.PaymentIntent, %{
          id: "pi_missing_order",
          status: "succeeded",
          amount: 5000,
          metadata: %{"ticket_order_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV"}
        })

      deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

      assert {:error, :ticket_order_not_found} =
               StripeService.process_successful_payment(payment_intent)
    end

    test "returns error when payment intent amount does not match order total",
         %{
           ticket_order: ticket_order
         } do
      payment_intent =
        payment_intent_for_order(ticket_order, amount: 1)

      deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

      assert {:error, :amount_mismatch} =
               StripeService.process_successful_payment(payment_intent)
    end

    test "returns error when payment intent has not succeeded", %{
      ticket_order: ticket_order
    } do
      payment_intent =
        payment_intent_for_order(ticket_order,
          status: "requires_payment_method"
        )

      deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

      assert {:error, :payment_not_succeeded} =
               StripeService.process_successful_payment(payment_intent)
    end
  end

  describe "handle_failed_payment/2" do
    defp failed_payment_intent_for_order(ticket_order, overrides) do
      defaults = %{
        id: "pi_failed_#{ticket_order.id}",
        status: "requires_payment_method",
        amount: 5000,
        metadata: %{"ticket_order_id" => ticket_order.id}
      }

      struct(Stripe.PaymentIntent, Map.merge(defaults, Map.new(overrides)))
    end

    test "cancels a pending ticket order after payment failure" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        ticket_order = ticket_order_fixture()
        payment_intent_id = "pi_fail_cancel_#{ticket_order.id}"

        cancel_timeout_jobs_for_order!(ticket_order.id)

        payment_intent =
          failed_payment_intent_for_order(ticket_order, id: payment_intent_id)

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                            _opts ->
          {:ok, payment_intent}
        end)

        assert {:ok, cancelled} =
                 StripeService.handle_failed_payment(
                   payment_intent_id,
                   "Card declined"
                 )

        assert cancelled.status == :cancelled
        assert cancelled.cancellation_reason == "Card declined"
      end)
    end

    test "returns completed order without cancelling when payment already succeeded" do
      ticket_order = ticket_order_fixture(%{status: :completed})
      payment_intent_id = "pi_fail_done_#{ticket_order.id}"

      payment_intent =
        failed_payment_intent_for_order(ticket_order, id: payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent}
      end)

      assert {:ok, returned} =
               StripeService.handle_failed_payment(
                 payment_intent_id,
                 "Too late"
               )

      assert returned.status == :completed
      assert returned.id == ticket_order.id
    end
  end
end

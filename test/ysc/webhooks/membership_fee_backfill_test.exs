defmodule Ysc.Webhooks.MembershipFeeBackfillTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.Ledgers
  alias Ysc.Stripe.HttpClient.ReqStub
  alias Ysc.Webhooks.MembershipFeeBackfill

  setup :verify_on_exit!

  setup context do
    Req.Test.set_req_test_from_context(context)

    previous_client = Application.get_env(:ysc, :stripe_client)
    previous_req_opts = Application.get_env(:ysc, :stripe_http_req_opts)

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
    Application.put_env(:ysc, :stripe_http_req_opts, plug: {Req.Test, ReqStub})

    on_exit(fn ->
      restore_env(:ysc, :stripe_client, previous_client)
      restore_env(:ysc, :stripe_http_req_opts, previous_req_opts)
    end)

    Ledgers.ensure_basic_accounts()
    user = user_fixture()

    %{user: user}
  end

  defp restore_env(app, key, value) do
    if value != nil do
      Application.put_env(app, key, value)
    else
      Application.delete_env(app, key)
    end
  end

  defp insert_invoice_payment(user, invoice_id) do
    {:ok, payment} =
      Ledgers.create_payment(%{
        user_id: user.id,
        amount: Money.new(6500, :USD),
        external_provider: :stripe,
        external_payment_id: invoice_id,
        status: :completed,
        payment_date: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })

    payment
  end

  describe "backfill_payment/1" do
    test "resolves the fee via a live invoice re-fetch and books it", %{
      user: user
    } do
      uniq = System.unique_integer([:positive])
      invoice_id = "in_backfill_e2e_#{uniq}"
      payment_intent_id = "pi_backfill_e2e_#{uniq}"
      charge_id = "ch_backfill_e2e_#{uniq}"

      payment = insert_invoice_payment(user, invoice_id)

      invoice_path = "/v1/invoices/#{invoice_id}"
      payment_intent_path = "/v1/payment_intents/#{payment_intent_id}"

      Req.Test.stub(ReqStub, fn conn ->
        cond do
          conn.request_path == invoice_path ->
            Req.Test.json(conn, %{
              "id" => invoice_id,
              "object" => "invoice",
              "payments" => %{
                "object" => "list",
                "data" => [
                  %{
                    "id" => "inpay_#{uniq}",
                    "object" => "invoice_payment",
                    "payment" => %{
                      "type" => "payment_intent",
                      "payment_intent" => payment_intent_id
                    }
                  }
                ],
                "has_more" => false
              }
            })

          conn.request_path == payment_intent_path ->
            Req.Test.json(conn, %{
              "id" => payment_intent_id,
              "object" => "payment_intent",
              "latest_charge" => charge_id
            })
        end
      end)

      stub(Ysc.StripeMock, :retrieve_charge, fn ^charge_id, _opts ->
        {:ok,
         %Stripe.Charge{
           id: charge_id,
           balance_transaction: %Stripe.BalanceTransaction{fee: 219}
         }}
      end)

      assert {:ok, [fee_expense, stripe_credit]} =
               MembershipFeeBackfill.backfill_payment(payment)

      assert fee_expense.amount == Money.new(:USD, "2.19")
      assert fee_expense.debit_credit == :debit
      assert stripe_credit.debit_credit == :credit

      refute payment.id in Enum.map(
               Ledgers.list_payments_missing_stripe_fee(),
               & &1.id
             )
    end
  end

  describe "list_affected_payments/1 and run/1" do
    test "dry run reports affected payments without writing anything", %{
      user: user
    } do
      uniq = System.unique_integer([:positive])
      payment = insert_invoice_payment(user, "in_dry_run_#{uniq}")

      result = MembershipFeeBackfill.run(dry_run: true)

      assert Enum.any?(result.would_process, &(&1.id == payment.id))

      # Nothing was booked - the payment still shows up as affected
      assert payment.id in Enum.map(
               Ledgers.list_payments_missing_stripe_fee(),
               & &1.id
             )
    end
  end
end

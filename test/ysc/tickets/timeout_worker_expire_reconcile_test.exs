defmodule Ysc.Tickets.TimeoutWorkerExpireReconcileTest do
  @moduledoc """
  TimeoutWorker is the production 15-minute checkout timeout path.

  #1202 made `expire_ticket_order/1` cancel the PaymentIntent *before*
  releasing inventory, and fulfill when Stripe reveals the charge already
  succeeded. Existing TimeoutWorker tests never set `payment_intent_id`, so
  they never exercised that reconcile.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Mox
  import Ysc.TicketsFixtures

  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder
  alias Ysc.Tickets.TimeoutWorker

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    original_stripe_client = Application.get_env(:ysc, :stripe_client)
    original_quickbooks_client = Application.get_env(:ysc, :quickbooks_client)
    original_oban_config = Application.get_env(:ysc, Oban, [])

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
    Ysc.TestHelpers.setup_quickbooks_mocks()

    Application.put_env(
      :ysc,
      Oban,
      Keyword.put(original_oban_config, :testing, :manual)
    )

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
      Application.put_env(:ysc, :quickbooks_client, original_quickbooks_client)
      Application.put_env(:ysc, Oban, original_oban_config)
    end)

    :ok
  end

  defp payment_intent(status, id) do
    %Stripe.PaymentIntent{id: id, status: status, amount: 2500}
  end

  defp stripe_unexpected_state_error do
    %Stripe.Error{
      source: :stripe,
      code: :payment_intent_unexpected_state,
      message: "cannot cancel",
      extra: %{}
    }
  end

  defp past_due_order(order) do
    order
    |> Ecto.Changeset.change(%{
      expires_at:
        DateTime.utc_now()
        |> DateTime.add(-60, :second)
        |> DateTime.truncate(:second)
    })
    |> Ysc.Repo.update!()
  end

  defp expect_expire_cancel_reveals_succeeded(
         payment_intent_id,
         succeeded_payment_intent
       ) do
    expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
      {:ok, payment_intent("requires_payment_method", payment_intent_id)}
    end)

    expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      {:error, stripe_unexpected_state_error()}
    end)

    expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
      {:ok, succeeded_payment_intent}
    end)
  end

  describe "expire_specific_order/1 payment reconcile" do
    test "fulfills instead of expiring when Stripe cancel reveals the payment already succeeded" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        order = ticket_order_fixture() |> past_due_order()
        payment_intent_id = "pi_timeout_already_succeeded_#{order.id}"

        assert {:ok, order} =
                 Tickets.update_payment_intent(order, payment_intent_id)

        amount_cents = Ysc.MoneyHelper.money_to_cents(order.total_amount)

        succeeded_payment_intent =
          struct(Stripe.PaymentIntent, %{
            id: payment_intent_id,
            status: "succeeded",
            amount: amount_cents,
            metadata: %{
              "ticket_order_id" => order.id,
              "user_id" => order.user_id
            }
          })

        expect_expire_cancel_reveals_succeeded(
          payment_intent_id,
          succeeded_payment_intent
        )

        assert {:ok, "Expired specific ticket order"} =
                 TimeoutWorker.perform(%Oban.Job{
                   args: %{"ticket_order_id" => order.id}
                 })

        reloaded = Tickets.get_ticket_order(order.id)
        assert reloaded.status == :completed
        assert reloaded.payment_id

        tickets =
          Ysc.Repo.all(
            from t in Ysc.Events.Ticket,
              where: t.ticket_order_id == ^order.id
          )

        assert tickets != []
        assert Enum.all?(tickets, &(&1.status == :confirmed))
      end)
    end

    test "returns a retryable error when succeeded payment cannot be fulfilled" do
      order = ticket_order_fixture() |> past_due_order()
      payment_intent_id = "pi_timeout_fulfillment_fail_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      succeeded_payment_intent =
        struct(Stripe.PaymentIntent, %{
          id: payment_intent_id,
          status: "succeeded",
          amount: 1,
          metadata: %{
            "ticket_order_id" => order.id,
            "user_id" => order.user_id
          }
        })

      expect_expire_cancel_reveals_succeeded(
        payment_intent_id,
        succeeded_payment_intent
      )

      # expire_specific_order rollbacks `{:error, reason}`, so Oban sees a nested
      # error tuple. That still fails the job (retry); do not unwrap it here.
      assert {:error,
              {:error,
               {:payment_succeeded_fulfillment_failed, :amount_mismatch}}} =
               TimeoutWorker.perform(%Oban.Job{
                 args: %{"ticket_order_id" => order.id}
               })

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end

    test "leaves the order pending when Stripe cancel is refused because payment is still processing" do
      order = ticket_order_fixture() |> past_due_order()
      payment_intent_id = "pi_timeout_processing_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("requires_payment_method", payment_intent_id)}
      end)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, stripe_unexpected_state_error()}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("processing", payment_intent_id)}
      end)

      assert {:ok, "Expired specific ticket order"} =
               TimeoutWorker.perform(%Oban.Job{
                 args: %{"ticket_order_id" => order.id}
               })

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end
  end

  # Oban.Cron runs TimeoutWorker with empty args every 5 minutes. That batch
  # path also calls expire_ticket_order/1, but unlike expire_specific_order/1
  # it does not rollback-and-retry on fulfillment failure.
  describe "perform/1 cron batch payment reconcile" do
    test "fulfills instead of expiring when Stripe cancel reveals the payment already succeeded" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        order = ticket_order_fixture() |> past_due_order()
        payment_intent_id = "pi_cron_already_succeeded_#{order.id}"

        assert {:ok, order} =
                 Tickets.update_payment_intent(order, payment_intent_id)

        amount_cents = Ysc.MoneyHelper.money_to_cents(order.total_amount)

        succeeded_payment_intent =
          struct(Stripe.PaymentIntent, %{
            id: payment_intent_id,
            status: "succeeded",
            amount: amount_cents,
            metadata: %{
              "ticket_order_id" => order.id,
              "user_id" => order.user_id
            }
          })

        expect_expire_cancel_reveals_succeeded(
          payment_intent_id,
          succeeded_payment_intent
        )

        assert {:ok, message} = TimeoutWorker.perform(%Oban.Job{args: %{}})
        assert message =~ "timed out ticket orders"

        reloaded = Tickets.get_ticket_order(order.id)
        assert reloaded.status == :completed
        assert reloaded.payment_id

        tickets =
          Ysc.Repo.all(
            from t in Ysc.Events.Ticket,
              where: t.ticket_order_id == ^order.id
          )

        assert tickets != []
        assert Enum.all?(tickets, &(&1.status == :confirmed))
      end)
    end

    test "counts a fulfillment failure and leaves the order pending" do
      order = ticket_order_fixture() |> past_due_order()
      payment_intent_id = "pi_cron_fulfillment_fail_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      succeeded_payment_intent =
        struct(Stripe.PaymentIntent, %{
          id: payment_intent_id,
          status: "succeeded",
          amount: 1,
          metadata: %{
            "ticket_order_id" => order.id,
            "user_id" => order.user_id
          }
        })

      expect_expire_cancel_reveals_succeeded(
        payment_intent_id,
        succeeded_payment_intent
      )

      assert {:ok, "Expired 0 timed out ticket orders (1 failed)"} =
               TimeoutWorker.perform(%Oban.Job{args: %{}})

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end

    test "leaves the order pending when Stripe cancel is refused because payment is still processing" do
      order = ticket_order_fixture() |> past_due_order()
      payment_intent_id = "pi_cron_processing_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("requires_payment_method", payment_intent_id)}
      end)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, stripe_unexpected_state_error()}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("processing", payment_intent_id)}
      end)

      assert {:ok, message} = TimeoutWorker.perform(%Oban.Job{args: %{}})
      assert message =~ "timed out ticket orders"

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end
  end
end

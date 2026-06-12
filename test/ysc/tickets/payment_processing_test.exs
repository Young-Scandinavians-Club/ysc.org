defmodule Ysc.Tickets.PaymentProcessingTest do
  @moduledoc """
  Regression tests for ticket order payment idempotency.

  Covers the race between Stripe webhooks and redirect-based payment completion
  introduced in the "already paid" fix (process_ticket_order_payment/2).
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Mox
  import Ysc.TicketsFixtures

  alias Ysc.Ledgers.Payment
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
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

    :ok
  end

  defp payment_intent_for_order(ticket_order, payment_intent_id) do
    amount_cents =
      ticket_order.total_amount.amount
      |> Decimal.mult(100)
      |> Decimal.to_integer()

    build_payment_intent(%{
      id: payment_intent_id,
      status: "succeeded",
      amount: amount_cents
    })
  end

  defp build_payment_intent(attrs) do
    defaults = %{
      id: "pi_test_#{System.unique_integer([:positive])}",
      status: "succeeded",
      amount: 5000,
      currency: "usd",
      metadata: %{}
    }

    struct(Stripe.PaymentIntent, Map.merge(defaults, attrs))
  end

  defp count_payments_for_intent(payment_intent_id) do
    Payment
    |> where([p], p.external_payment_id == ^payment_intent_id)
    |> Repo.aggregate(:count)
  end

  defp count_confirmation_email_jobs(ticket_order_id) do
    idempotency_key = "ticket_confirmation_#{ticket_order_id}"

    from(j in Oban.Job,
      where: j.worker == "YscWeb.Workers.EmailNotifier",
      where: fragment("?->>'idempotency_key' = ?", j.args, ^idempotency_key)
    )
    |> Repo.aggregate(:count)
  end

  describe "process_ticket_order_payment/2 idempotency" do
    test "returns completed order without calling Stripe when already completed" do
      ticket_order =
        ticket_order_fixture(%{status: :completed})

      payment_intent_id = "pi_already_done_#{ticket_order.id}"

      deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

      assert {:ok, returned} =
               Tickets.process_ticket_order_payment(
                 ticket_order,
                 payment_intent_id
               )

      assert returned.status == :completed
      assert returned.id == ticket_order.id
    end

    test "confirms pending tickets when order is already completed" do
      ticket_order =
        ticket_order_fixture(%{status: :completed})

      pending_tickets =
        from(t in Ysc.Events.Ticket,
          where: t.ticket_order_id == ^ticket_order.id and t.status == :pending
        )
        |> Repo.all()

      assert pending_tickets != []

      payment_intent_id = "pi_recover_tickets_#{ticket_order.id}"

      deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

      assert {:ok, returned} =
               Tickets.process_ticket_order_payment(
                 ticket_order,
                 payment_intent_id
               )

      assert returned.status == :completed

      assert Repo.all(
               from(t in Ysc.Events.Ticket,
                 where: t.ticket_order_id == ^ticket_order.id
               )
             )
             |> Enum.all?(&(&1.status == :confirmed))
    end

    test "does not re-confirm cancelled tickets when retrying already-completed order" do
      event = Ysc.EventsFixtures.event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          event: event,
          tier: tier,
          ticket_selections: %{tier.id => 2},
          status: :completed
        })

      from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^ticket_order.id)
      |> Repo.update_all(set: [status: :confirmed])

      [ticket_to_refund | remaining] =
        from(t in Ysc.Events.Ticket,
          where: t.ticket_order_id == ^ticket_order.id,
          order_by: [asc: t.id]
        )
        |> Repo.all()

      assert length(remaining) == 1

      ticket_order = Tickets.get_ticket_order(ticket_order.id)

      assert {:ok, _} =
               Tickets.refund_tickets(
                 ticket_order,
                 [ticket_to_refund.id],
                 "Partial refund"
               )

      assert Repo.get!(Ysc.Events.Ticket, ticket_to_refund.id).status ==
               :cancelled

      payment_intent_id = "pi_partial_refund_#{ticket_order.id}"

      deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

      assert {:ok, returned} =
               Tickets.process_ticket_order_payment(
                 ticket_order,
                 payment_intent_id
               )

      assert returned.status == :completed

      assert Repo.get!(Ysc.Events.Ticket, ticket_to_refund.id).status ==
               :cancelled

      assert Repo.aggregate(
               from(t in Ysc.Events.Ticket,
                 where:
                   t.ticket_order_id == ^ticket_order.id and
                     t.status == :confirmed
               ),
               :count
             ) == 1
    end

    test "confirms expired tickets when order is already completed" do
      ticket_order =
        ticket_order_fixture(%{status: :completed})

      from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^ticket_order.id)
      |> Repo.update_all(set: [status: :expired])

      payment_intent_id = "pi_recover_expired_#{ticket_order.id}"

      deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

      assert {:ok, returned} =
               Tickets.process_ticket_order_payment(
                 ticket_order,
                 payment_intent_id
               )

      assert returned.status == :completed

      assert Repo.all(
               from(t in Ysc.Events.Ticket,
                 where: t.ticket_order_id == ^ticket_order.id
               )
             )
             |> Enum.all?(&(&1.status == :confirmed))
    end

    test "accepts a preloaded payment intent struct without refetching from Stripe" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        ticket_order = ticket_order_fixture()

        payment_intent =
          payment_intent_for_order(ticket_order, "pi_struct_#{ticket_order.id}")

        deny(Ysc.StripeMock, :retrieve_payment_intent, 2)

        assert {:ok, completed} =
                 Tickets.process_ticket_order_payment(
                   ticket_order,
                   payment_intent
                 )

        assert completed.status == :completed
        assert completed.payment_id
      end)
    end

    test "duplicate processing creates a single payment and one confirmation email" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        ticket_order = ticket_order_fixture()
        payment_intent_id = "pi_dup_#{ticket_order.id}"

        payment_intent =
          payment_intent_for_order(ticket_order, payment_intent_id)

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                            _opts ->
          {:ok, payment_intent}
        end)

        assert {:ok, first} =
                 Tickets.process_ticket_order_payment(
                   ticket_order,
                   payment_intent_id
                 )

        assert first.status == :completed

        assert {:ok, second} =
                 Tickets.process_ticket_order_payment(
                   ticket_order,
                   payment_intent_id
                 )

        assert second.status == :completed
        assert second.id == first.id
        assert count_payments_for_intent(payment_intent_id) == 1
        assert count_confirmation_email_jobs(ticket_order.id) == 1
      end)
    end

    @tag :capture_log
    test "concurrent duplicate processing completes order once", %{
      sandbox_owner: owner
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        ticket_order = ticket_order_fixture()
        payment_intent_id = "pi_race_#{ticket_order.id}"

        payment_intent =
          payment_intent_for_order(ticket_order, payment_intent_id)

        stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
          {:ok, payment_intent}
        end)

        results =
          1..2
          |> Task.async_stream(
            fn _ ->
              Ysc.DataCase.allow_sandbox(self(), owner)

              Tickets.process_ticket_order_payment(
                ticket_order,
                payment_intent_id
              )
            end,
            max_concurrency: 2,
            timeout: 10_000
          )
          |> Enum.map(fn {:ok, result} -> result end)

        assert length(results) == 2

        assert Enum.all?(
                 results,
                 &match?({:ok, %TicketOrder{status: :completed}}, &1)
               )

        [{:ok, order1}, {:ok, order2}] = results
        assert order1.id == order2.id
        assert order1.status == :completed
        assert count_payments_for_intent(payment_intent_id) == 1
      end)
    end
  end
end

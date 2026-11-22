defmodule Ysc.Tickets.GuestRefundEmailTest do
  @moduledoc """
  Ticket refund emails. Guest payments have no `user_id`, so the ledger must
  not gate the email on one; and the admin flows record the refund before they
  cancel the tickets, so they defer the email until after cancellation.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Events.Ticket
  alias Ysc.Ledgers
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder

  defmodule Notifier do
    @moduledoc false
    def schedule_email(a, b, c, d, e, f, g),
      do: schedule_email(a, b, c, d, e, f, g, nil)

    def schedule_email(to, _key, _subject, template, vars, _f, _g, _h) do
      send(Application.fetch_env!(:ysc, :guest_refund_test_pid), {
        :email,
        to,
        template,
        Enum.map(vars.refunded_tickets, & &1.reference_id)
      })

      %Oban.Job{id: 1}
    end
  end

  setup do
    Ledgers.ensure_basic_accounts()

    prev = Application.get_env(:ysc, :ledger_refund_email_notifier)
    Application.put_env(:ysc, :ledger_refund_email_notifier, Notifier)
    Application.put_env(:ysc, :guest_refund_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:ysc, :guest_refund_test_pid)

      if prev == nil do
        Application.delete_env(:ysc, :ledger_refund_email_notifier)
      else
        Application.put_env(:ysc, :ledger_refund_email_notifier, prev)
      end
    end)

    :ok
  end

  defp pay_order(order, user_id) do
    {:ok, {payment, _, _}} =
      Ledgers.process_payment(%{
        user_id: user_id,
        amount: order.total_amount,
        entity_type: :event,
        entity_id: order.event_id,
        external_payment_id:
          "pi_refund_email_#{System.unique_integer([:positive])}",
        stripe_fee: Money.new(100, :USD),
        description: "Event tickets - Order #{order.reference_id}",
        property: nil,
        payment_method_id: nil
      })

    order
    |> Ecto.Changeset.change(%{payment_id: payment.id, status: :completed})
    |> Repo.update!()

    payment
  end

  defp cancel_tickets(order, ticket_ids \\ nil) do
    query = from(t in Ticket, where: t.ticket_order_id == ^order.id)

    query =
      if ticket_ids, do: where(query, [t], t.id in ^ticket_ids), else: query

    Repo.update_all(query, set: [status: :cancelled])
  end

  defp order_tickets(order) do
    Repo.all(
      from(t in Ticket,
        where: t.ticket_order_id == ^order.id,
        order_by: t.inserted_at
      )
    )
  end

  defp refund(payment, amount, opts \\ []) do
    Ledgers.process_refund(
      Map.merge(
        %{
          payment_id: payment.id,
          refund_amount: amount,
          reason: "Event cancelled",
          external_refund_id: "re_#{System.unique_integer([:positive])}"
        },
        Map.new(opts)
      )
    )
  end

  defp guest_order do
    event = Ysc.EventsFixtures.event_fixture()
    tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

    order =
      %TicketOrder{}
      |> TicketOrder.guest_create_changeset(%{
        guest_email: "Guest.Buyer@Example.com",
        guest_first_name: "Gus",
        guest_last_name: "Buyer",
        event_id: event.id,
        total_amount: Money.new(25, :USD),
        expires_at:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 300)
      })
      |> Repo.insert!()

    %Ticket{}
    |> Ecto.Changeset.change(%{
      event_id: event.id,
      ticket_tier_id: tier.id,
      ticket_order_id: order.id,
      status: :confirmed,
      expires_at:
        DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 300),
      reference_id: "TKT-GUESTREFUND-#{System.unique_integer([:positive])}"
    })
    |> Repo.insert!()

    order
  end

  test "a guest ticket refund emails the guest address" do
    order = guest_order()
    payment = pay_order(order, nil)
    assert payment.user_id == nil
    cancel_tickets(order)

    assert {:ok, {_refund, _tx, _entries}} = refund(payment, payment.amount)

    assert_received {:email, "guest.buyer@example.com", "ticket_order_refund",
                     [_ref]}
  end

  test "a member ticket refund still emails the member" do
    user = user_fixture()
    order = ticket_order_fixture(%{user: user, status: :completed})
    payment = pay_order(order, user.id)
    cancel_tickets(order)

    assert {:ok, {_refund, _tx, _entries}} = refund(payment, payment.amount)

    email = user.email
    assert_received {:email, ^email, "ticket_order_refund", [_ref]}
  end

  describe "admin flow: refund recorded before the tickets are cancelled" do
    test "send_email: false records the refund without emailing, then notify sends" do
      order = guest_order()
      payment = pay_order(order, nil)

      assert {:ok, {_refund, _tx, _entries}} =
               result = refund(payment, payment.amount, send_email: false)

      refute_received {:email, _, _, _}

      %{id: ticket_id, reference_id: ref} = hd(order_tickets(order))
      cancel_tickets(order)

      assert :ok = Tickets.notify_ticket_refund(result, ticket_ids: [ticket_id])

      assert_received {:email, "guest.buyer@example.com", "ticket_order_refund",
                       [^ref]}

      refute_received {:email, _, _, _}
    end

    test "a second partial refund lists only its own ticket" do
      user = user_fixture()
      event = Ysc.EventsFixtures.event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          ticket_selections: %{tier.id => 2},
          status: :completed
        })

      payment = pay_order(order, user.id)
      [first, second] = order_tickets(order)
      half = Money.div!(payment.amount, 2)

      # First partial refund: record, cancel its ticket, then notify.
      {:ok, {_, _, _}} = r1 = refund(payment, half, send_email: false)
      cancel_tickets(order, [first.id])
      Tickets.notify_ticket_refund(r1, ticket_ids: [first.id])

      email = user.email
      first_ref = first.reference_id
      assert_received {:email, ^email, "ticket_order_refund", [^first_ref]}

      # Second partial refund: the first ticket is already cancelled, but the
      # email must list only the ticket this refund covered.
      {:ok, {_, _, _}} = r2 = refund(payment, half, send_email: false)
      refute_received {:email, _, _, _}

      cancel_tickets(order, [second.id])
      Tickets.notify_ticket_refund(r2, ticket_ids: [second.id])

      second_ref = second.reference_id
      assert_received {:email, ^email, "ticket_order_refund", [^second_ref]}
      refute_received {:email, _, _, _}
    end
  end

  test "notify_ticket_refund ignores results without a refund" do
    assert :ok =
             Tickets.notify_ticket_refund(
               {:ok, {:skipped_zero_amount, nil, nil}}
             )

    assert :ok = Tickets.notify_ticket_refund({:error, :no_stripe_payment})
    refute_received {:email, _, _, _}
  end
end

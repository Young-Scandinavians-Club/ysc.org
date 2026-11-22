defmodule Ysc.Tickets.GuestRefundEmailTest do
  @moduledoc """
  Refunding a guest ticket order emails the guest. Guest payments have no
  `user_id`, so the ledger must not gate the ticket refund email on one.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Ledgers
  alias Ysc.Tickets.TicketOrder

  defmodule Notifier do
    @moduledoc false
    def schedule_email(a, b, c, d, e, f, g),
      do: schedule_email(a, b, c, d, e, f, g, nil)

    def schedule_email(to, _key, _subject, template, _vars, _f, _g, _h) do
      send(Application.fetch_env!(:ysc, :guest_refund_test_pid), {
        :email,
        to,
        template
      })

      {:ok, %{id: 1}}
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

  defp pay_and_cancel_one_ticket(order, user_id) do
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

    from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^order.id)
    |> Repo.update_all(set: [status: :cancelled])

    payment
  end

  defp refund(payment) do
    Ledgers.process_refund(%{
      payment_id: payment.id,
      refund_amount: payment.amount,
      reason: "Event cancelled",
      external_refund_id: "re_#{System.unique_integer([:positive])}"
    })
  end

  test "a guest ticket refund emails the guest address" do
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

    %Ysc.Events.Ticket{}
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

    payment = pay_and_cancel_one_ticket(order, nil)
    assert payment.user_id == nil

    assert {:ok, {_refund, _tx, _entries}} = refund(payment)

    assert_received {:email, "guest.buyer@example.com", "ticket_order_refund"}
  end

  test "a member ticket refund still emails the member" do
    user = user_fixture()
    order = ticket_order_fixture(%{user: user, status: :completed})

    payment = pay_and_cancel_one_ticket(order, user.id)

    assert {:ok, {_refund, _tx, _entries}} = refund(payment)

    email = user.email
    assert_received {:email, ^email, "ticket_order_refund"}
  end
end

defmodule Ysc.Tickets.AdminGrantCheckoutBlockTest do
  @moduledoc """
  Admin grant blocking when a recipient has an in-flight Stripe checkout.

  Uses `async: false` because `:stripe_client` is pinned via Application env,
  which races with DataCase setup in parallel tests.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Mox
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    user =
      user_fixture()
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

    admin = user_fixture(%{role: "admin"})
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})

    tier1 =
      ticket_tier_fixture(%{event_id: event.id, name: "General Admission"})

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
    end)

    %{admin: admin, user: user, event: event, tier1: tier1}
  end

  test "rejects grant when recipient checkout payment is in flight", %{
    admin: admin,
    user: user,
    event: event,
    tier1: tier1
  } do
    assert {:ok, pending_order} =
             Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

    payment_intent_id = "pi_grant_block_#{pending_order.id}"

    assert {:ok, pending_order} =
             Tickets.update_payment_intent(pending_order, payment_intent_id)

    expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: payment_intent_id,
         status: "processing",
         amount: Ysc.MoneyHelper.money_to_cents(pending_order.total_amount)
       }}
    end)

    assert {:error, :checkout_payment_in_progress} =
             Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
               tier1.id => 1
             })

    pending_order = Tickets.get_ticket_order(pending_order.id)
    assert pending_order.status == :pending

    assert [] ==
             Ysc.Repo.all(
               from to in TicketOrder,
                 where:
                   to.user_id == ^user.id and to.event_id == ^event.id and
                     to.status == :completed and to.granted_by_id == ^admin.id
             )
  end

  test "rejects grant when checkout payment starts after precheck but before commit",
       %{
         admin: admin,
         user: user,
         event: event,
         tier1: tier1
       } do
    assert {:ok, pending_order} =
             Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

    payment_intent_id = "pi_grant_toctou_#{pending_order.id}"

    assert {:ok, pending_order} =
             Tickets.update_payment_intent(pending_order, payment_intent_id)

    retrieve_calls = :counters.new(1, [])

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      call = :counters.add(retrieve_calls, 1, 1)

      status =
        if call == 1 do
          "requires_payment_method"
        else
          "processing"
        end

      {:ok,
       %Stripe.PaymentIntent{
         id: payment_intent_id,
         status: status,
         amount: Ysc.MoneyHelper.money_to_cents(pending_order.total_amount)
       }}
    end)

    assert {:error, :checkout_payment_in_progress} =
             Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
               tier1.id => 1
             })

    pending_order = Tickets.get_ticket_order(pending_order.id)
    assert pending_order.status == :pending

    assert [] ==
             Ysc.Repo.all(
               from to in TicketOrder,
                 where:
                   to.user_id == ^user.id and to.event_id == ^event.id and
                     to.status == :completed and to.granted_by_id == ^admin.id
             )
  end
end

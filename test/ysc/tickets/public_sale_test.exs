defmodule Ysc.Tickets.PublicSaleTest do
  @moduledoc """
  Server-side rules for tiers sold to the general public
  (`TicketTier.sale_audience == :public`): a signed-in non-member may buy
  them, but any member tier in the selection still needs a membership.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Events
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder

  defp unique_user do
    user_fixture(%{
      email: "ps#{:erlang.unique_integer([:positive, :monotonic])}@example.com"
    })
  end

  defp member do
    unique_user()
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()
  end

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    organizer = unique_user()

    {:ok, event} =
      Events.create_event(%{
        title: "Public Sale Event",
        description: "Open to all",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    tier = fn name, attrs ->
      {:ok, tier} =
        Events.create_ticket_tier(
          Map.merge(
            %{
              name: name,
              type: :paid,
              price: Money.new(25, :USD),
              quantity: 50,
              event_id: event.id
            },
            attrs
          )
        )

      tier
    end

    %{
      event: event,
      public_tier: tier.("Public GA", %{sale_audience: :public}),
      public_tier_2: tier.("Public Late", %{sale_audience: :public}),
      guest_tier: tier.("Member guest", %{}),
      member_only_tier: tier.("Members only", %{sale_audience: :members_only})
    }
  end

  test "a non-member can buy a public tier", %{
    event: event,
    public_tier: public_tier
  } do
    buyer = unique_user()

    assert {:ok, %TicketOrder{user_id: user_id}} =
             Tickets.create_ticket_order(buyer.id, event.id, %{
               public_tier.id => 2
             })

    assert user_id == buyer.id
  end

  test "a non-member can buy several public tiers in one order", %{
    event: event,
    public_tier: a,
    public_tier_2: b
  } do
    buyer = unique_user()

    assert {:ok, order} =
             Tickets.create_ticket_order(buyer.id, event.id, %{
               a.id => 1,
               b.id => 1
             })

    assert length(Repo.preload(order, :tickets).tickets) == 2
  end

  test "a non-member still cannot buy a member-guest tier", %{
    event: event,
    guest_tier: guest_tier
  } do
    buyer = unique_user()

    assert {:error, :membership_required} =
             Tickets.create_ticket_order(buyer.id, event.id, %{
               guest_tier.id => 1
             })
  end

  test "a non-member cannot buy a members-only tier", %{
    event: event,
    member_only_tier: member_only_tier
  } do
    buyer = unique_user()

    assert {:error, :membership_required} =
             Tickets.create_ticket_order(buyer.id, event.id, %{
               member_only_tier.id => 1
             })
  end

  test "a mixed selection needs a membership", %{
    event: event,
    public_tier: public_tier,
    guest_tier: guest_tier
  } do
    buyer = unique_user()

    assert {:error, :membership_required} =
             Tickets.create_ticket_order(buyer.id, event.id, %{
               public_tier.id => 1,
               guest_tier.id => 1
             })
  end

  test "a member can mix public and member tiers", %{
    event: event,
    public_tier: public_tier,
    guest_tier: guest_tier
  } do
    buyer = member()

    assert {:ok, _order} =
             Tickets.create_ticket_order(buyer.id, event.id, %{
               public_tier.id => 1,
               guest_tier.id => 1
             })
  end

  test "door sales (bypass_guards) still need a membership", %{
    event: event,
    public_tier: public_tier
  } do
    buyer = unique_user()

    assert {:error, :membership_required} =
             Tickets.create_ticket_order(
               buyer.id,
               event.id,
               %{public_tier.id => 1},
               bypass_guards: true
             )
  end

  test "a ticket without an account is refused for a non-public tier", %{
    event: event,
    guest_tier: guest_tier,
    public_tier: public_tier
  } do
    attrs = fn tier ->
      %{
        event_id: event.id,
        ticket_tier_id: tier.id,
        status: :pending,
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      }
    end

    refused =
      Ysc.Events.Ticket.changeset(%Ysc.Events.Ticket{}, attrs.(guest_tier),
        guest: true,
        public_sale: false
      )

    refute refused.valid?
    assert %{ticket_tier_id: ["is not sold to the public"]} = errors_on(refused)

    allowed =
      Ysc.Events.Ticket.changeset(%Ysc.Events.Ticket{}, attrs.(public_tier),
        guest: true,
        public_sale: true
      )

    assert allowed.valid?
  end

  test "an unknown buyer is rejected for a public tier", %{
    event: event,
    public_tier: public_tier
  } do
    assert {:error, :user_not_found} =
             Tickets.create_ticket_order(
               Ecto.ULID.generate(),
               event.id,
               %{public_tier.id => 1}
             )
  end
end

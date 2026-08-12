defmodule Ysc.Tickets.AdminGrantsTest do
  @moduledoc """
  Tests for Ysc.Tickets.AdminGrants — admin-granted complimentary tickets.

  Previously untested directly; coverage only came incidentally from other
  suites exercising the admin UI.
  """
  use Ysc.DataCase, async: true

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketDetail
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.AdminGrants

  defp member_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)

    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

  defp grant_setup do
    Ysc.Ledgers.ensure_basic_accounts()
    admin = user_fixture()
    member = member_fixture()
    event = event_fixture()
    tier = ticket_tier_fixture(%{event_id: event.id, quantity: 5})

    %{admin: admin, member: member, event: event, tier: tier}
  end

  describe "grant_admin_tickets/5 happy path" do
    setup do
      grant_setup()
    end

    test "creates a completed $0 order with confirmed tickets", %{
      admin: admin,
      member: member,
      event: event,
      tier: tier
    } do
      assert {:ok, order} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 2
               })

      assert order.user_id == member.id
      assert order.event_id == event.id
      assert order.total_amount == Money.new(0, :USD)
      assert order.discount_amount == Money.new(0, :USD)
      assert order.granted_by_id == admin.id
      assert order.completed_at

      tickets = order.tickets
      assert length(tickets) == 2
      assert Enum.all?(tickets, &(&1.status == :confirmed))
      assert Enum.all?(tickets, &(&1.ticket_tier_id == tier.id))
      assert Enum.all?(tickets, &(&1.user_id == member.id))
    end

    test "records admin_grant_notes when provided", %{
      admin: admin,
      member: member,
      event: event,
      tier: tier
    } do
      assert {:ok, order} =
               AdminGrants.grant_admin_tickets(
                 admin.id,
                 member.id,
                 event.id,
                 %{tier.id => 1},
                 admin_grant_notes: "Migrated from legacy system"
               )

      assert order.admin_grant_notes == "Migrated from legacy system"
    end

    test "sets expires_at from the event end date/time when both are present", %{
      admin: admin,
      member: member
    } do
      event =
        event_fixture(%{
          end_date: DateTime.truncate(DateTime.utc_now(), :second),
          end_time: ~T[18:00:00]
        })

      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 5})

      assert {:ok, order} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 1
               })

      [ticket] = order.tickets
      assert ticket.expires_at.hour == 18
    end

    test "falls back to now + 365 days when the event has no end date/time", %{
      admin: admin,
      member: member,
      tier: tier,
      event: event
    } do
      assert {:ok, order} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 1
               })

      [ticket] = order.tickets
      assert DateTime.diff(ticket.expires_at, DateTime.utc_now(), :day) in 363..366
    end

    test "cancels the recipient's other pending orders for the same event", %{
      admin: admin,
      member: member,
      event: event,
      tier: tier
    } do
      assert {:ok, pending_order} =
               Tickets.create_ticket_order(member.id, event.id, %{tier.id => 1})

      assert {:ok, _grant_order} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 1
               })

      reloaded = Repo.reload!(pending_order)
      assert reloaded.status == :cancelled
      assert reloaded.cancellation_reason == "Superseded by admin ticket grant"

      pending_tickets =
        from(t in Ticket, where: t.ticket_order_id == ^pending_order.id)
        |> Repo.all()

      assert Enum.all?(pending_tickets, &(&1.status == :cancelled))
    end

    test "inserts registration details for tiers that require registration", %{
      admin: admin,
      event: event
    } do
      member =
        member_fixture(%{
          first_name: "Jamie",
          last_name: "Rivera",
          email: "jamie.rivera.#{System.unique_integer([:positive])}@example.com"
        })

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          quantity: 5,
          requires_registration: true
        })

      assert {:ok, order} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 1
               })

      [ticket] = order.tickets
      details = Repo.get_by!(TicketDetail, ticket_id: ticket.id)
      assert details.first_name == "Jamie"
      assert details.last_name == "Rivera"
    end
  end

  describe "grant_admin_tickets/5 validation errors" do
    setup do
      grant_setup()
    end

    test "returns user_not_found for an unknown recipient", %{
      admin: admin,
      event: event,
      tier: tier
    } do
      assert {:error, :user_not_found} =
               AdminGrants.grant_admin_tickets(
                 admin.id,
                 Ecto.ULID.generate(),
                 event.id,
                 %{tier.id => 1}
               )
    end

    test "returns event_not_found for an unknown event", %{
      admin: admin,
      member: member,
      tier: tier
    } do
      assert {:error, :event_not_found} =
               AdminGrants.grant_admin_tickets(
                 admin.id,
                 member.id,
                 Ecto.ULID.generate(),
                 %{tier.id => 1}
               )
    end

    test "returns partiful_event when the event links out to Partiful", %{
      admin: admin,
      member: member,
      tier: tier
    } do
      event = event_fixture(%{partiful_link: "https://partiful.com/e/abc123"})

      assert {:error, :partiful_event} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 1
               })
    end

    test "returns empty_selection when no tiers are selected", %{
      admin: admin,
      member: member,
      event: event
    } do
      assert {:error, :empty_selection} =
               AdminGrants.grant_admin_tickets(
                 admin.id,
                 member.id,
                 event.id,
                 %{}
               )
    end

    test "returns invalid_ticket_tier when a tier does not belong to the event", %{
      admin: admin,
      member: member,
      event: event
    } do
      other_tier = ticket_tier_fixture()

      assert {:error, :invalid_ticket_tier} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 other_tier.id => 1
               })
    end

    test "returns donation_tier_not_grantable for a donation tier", %{
      admin: admin,
      member: member,
      event: event
    } do
      donation_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :donation,
          price: Money.new(0, :USD)
        })

      assert {:error, :donation_tier_not_grantable} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 donation_tier.id => 1
               })
    end

    test "returns invalid_quantity for a zero quantity selection", %{
      admin: admin,
      member: member,
      event: event,
      tier: tier
    } do
      assert {:error, :invalid_quantity} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 0
               })
    end

    test "returns invalid_quantity for a non-integer quantity", %{
      admin: admin,
      member: member,
      event: event,
      tier: tier
    } do
      assert {:error, :invalid_quantity} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 1.5
               })
    end

    test "returns incomplete_member_profile when a registration tier recipient is missing profile fields",
         %{admin: admin, event: event} do
      incomplete_member =
        member_fixture()
        |> Ecto.Changeset.change(first_name: "", last_name: "")
        |> Repo.update!()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          quantity: 5,
          requires_registration: true
        })

      assert {:error, :incomplete_member_profile} =
               AdminGrants.grant_admin_tickets(
                 admin.id,
                 incomplete_member.id,
                 event.id,
                 %{tier.id => 1}
               )
    end
  end

  describe "grant_admin_tickets/5 capacity" do
    setup do
      grant_setup()
    end

    test "returns an error when requested quantity exceeds remaining tier capacity",
         %{admin: admin, member: member, event: event} do
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 1})

      assert {:error, _reason} =
               AdminGrants.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 2
               })
    end

    test "skip_capacity: true bypasses remaining tier capacity checks", %{
      admin: admin,
      member: member,
      event: event
    } do
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 1})

      assert {:ok, order} =
               AdminGrants.grant_admin_tickets(
                 admin.id,
                 member.id,
                 event.id,
                 %{tier.id => 2},
                 skip_capacity: true
               )

      assert length(order.tickets) == 2
    end
  end
end

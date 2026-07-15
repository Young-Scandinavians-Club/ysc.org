defmodule Ysc.Events.TicketReservationAvailabilityTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures
  import Ysc.AccountsFixtures

  alias Ysc.Events
  alias Ysc.Events.TicketReservation
  alias Ysc.Repo

  describe "batch_count_reserved_tickets_for_tiers/1" do
    test "returns active reservation totals per tier" do
      event = event_fixture()
      organizer = user_fixture()

      tier_a =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "General",
          quantity: 10
        })

      tier_b =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "VIP",
          quantity: 5
        })

      user_a = user_fixture()
      user_b = user_fixture()

      insert_reservation!(tier_a.id, user_a.id, organizer.id, 2)
      insert_reservation!(tier_a.id, user_b.id, organizer.id, 1)
      insert_reservation!(tier_b.id, user_a.id, organizer.id, 3)

      counts =
        Events.batch_count_reserved_tickets_for_tiers([tier_a.id, tier_b.id])

      assert counts[tier_a.id] == 3
      assert counts[tier_b.id] == 3
    end

    test "ignores expired active reservations" do
      event = event_fixture()
      organizer = user_fixture()
      user = user_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          quantity: 5
        })

      reservation = insert_reservation!(tier.id, user.id, organizer.id, 2)

      past =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      reservation
      |> Ecto.Changeset.change(%{expires_at: past})
      |> Repo.update!()

      assert Events.batch_count_reserved_tickets_for_tiers([tier.id]) == %{}
    end
  end

  describe "non_donation_reserved_count_from_tiers/2" do
    test "excludes donation tiers from event-level reserved totals" do
      event = event_fixture()
      organizer = user_fixture()
      user = user_fixture()

      paid_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :paid,
          quantity: 10
        })

      donation_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :donation
        })

      insert_reservation!(paid_tier.id, user.id, organizer.id, 2)
      insert_reservation!(donation_tier.id, user.id, organizer.id, 5)

      reserved_counts =
        Events.batch_count_reserved_tickets_for_tiers([
          paid_tier.id,
          donation_tier.id
        ])

      tiers = Events.list_ticket_tiers_for_event(event.id)

      assert Events.non_donation_reserved_count_from_tiers(
               tiers,
               reserved_counts
             ) ==
               2
    end
  end

  defp insert_reservation!(tier_id, user_id, created_by_id, quantity) do
    %TicketReservation{}
    |> TicketReservation.changeset(%{
      ticket_tier_id: tier_id,
      user_id: user_id,
      quantity: quantity,
      created_by_id: created_by_id,
      status: "active"
    })
    |> Repo.insert!()
  end
end

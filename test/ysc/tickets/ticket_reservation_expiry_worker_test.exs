defmodule Ysc.Tickets.TicketReservationExpiryWorkerTest do
  use Ysc.DataCase, async: true

  alias Ysc.Tickets.TicketReservationExpiryWorker
  alias Ysc.Events
  alias Ysc.Events.TicketReservation
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  defp with_lifetime_membership(%Ysc.Accounts.User{} = user) do
    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

  defp insert_reservation_past_expiry!(tier, user, organizer) do
    {:ok, reservation} =
      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: user.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })
      |> Repo.insert()

    reservation
    |> Ecto.Changeset.change(%{
      expires_at: DateTime.add(DateTime.utc_now(), -120, :second)
    })
    |> Repo.update!()
  end

  describe "Events.expire_passed_ticket_reservations/1" do
    test "cancels active reservations whose expires_at has passed" do
      organizer = user_fixture() |> with_lifetime_membership()
      buyer = user_fixture() |> with_lifetime_membership()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      reservation = insert_reservation_past_expiry!(tier, buyer, organizer)

      assert {:ok, %{cancelled: 1, failed: 0}} =
               Events.expire_passed_ticket_reservations()

      updated = Repo.get!(TicketReservation, reservation.id)
      assert updated.status == "cancelled"
      assert updated.cancelled_at
    end

    test "does not cancel active reservations with no expires_at" do
      organizer = user_fixture() |> with_lifetime_membership()
      buyer = user_fixture() |> with_lifetime_membership()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: buyer.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active"
      })
      |> Repo.insert!()

      assert {:ok, %{cancelled: 0, failed: 0}} =
               Events.expire_passed_ticket_reservations()
    end

    test "does not cancel reservations still before expires_at" do
      organizer = user_fixture() |> with_lifetime_membership()
      buyer = user_fixture() |> with_lifetime_membership()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: buyer.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })
      |> Repo.insert!()

      assert {:ok, %{cancelled: 0, failed: 0}} =
               Events.expire_passed_ticket_reservations()
    end
  end

  describe "TicketReservationExpiryWorker" do
    test "perform/1 runs expiry" do
      organizer = user_fixture() |> with_lifetime_membership()
      buyer = user_fixture() |> with_lifetime_membership()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      insert_reservation_past_expiry!(tier, buyer, organizer)

      assert {:ok, message} =
               TicketReservationExpiryWorker.perform(%Oban.Job{args: %{}})

      assert message =~ "Cancelled 1"
    end
  end
end

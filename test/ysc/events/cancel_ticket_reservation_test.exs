defmodule Ysc.Events.CancelTicketReservationTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Events
  alias Ysc.Events.TicketReservation
  alias Ysc.Repo

  defp insert_active_reservation!(tier, user, organizer) do
    {:ok, reservation} =
      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: user.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active",
        expires_at: nil
      })
      |> Repo.insert()

    reservation
  end

  describe "cancel_ticket_reservation/1" do
    setup do
      organizer = user_fixture()
      buyer = user_fixture()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 50})

      %{organizer: organizer, buyer: buyer, event: event, tier: tier}
    end

    test "cancels an active reservation", %{
      tier: tier,
      buyer: buyer,
      organizer: organizer
    } do
      reservation = insert_active_reservation!(tier, buyer, organizer)

      assert {:ok, cancelled} = Events.cancel_ticket_reservation(reservation)
      assert cancelled.status == "cancelled"
      assert cancelled.cancelled_at

      reloaded = Repo.get!(TicketReservation, reservation.id)
      assert reloaded.status == "cancelled"
    end

    test "returns reservation_not_active for fulfilled holds without corrupting order link",
         %{
           tier: tier,
           buyer: buyer,
           organizer: organizer,
           event: event
         } do
      reservation = insert_active_reservation!(tier, buyer, organizer)

      order =
        ticket_order_fixture(%{
          user: buyer,
          event: event,
          tier: tier
        })

      fulfilled =
        reservation
        |> Ecto.Changeset.change(%{
          status: "fulfilled",
          ticket_order_id: order.id,
          fulfilled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      assert {:error, :reservation_not_active} =
               Events.cancel_ticket_reservation(fulfilled)

      reloaded = Repo.get!(TicketReservation, reservation.id)
      assert reloaded.status == "fulfilled"
      assert reloaded.ticket_order_id == order.id
      refute reloaded.cancelled_at
    end

    test "returns reservation_not_active when reservation is already cancelled",
         %{
           tier: tier,
           buyer: buyer,
           organizer: organizer
         } do
      reservation = insert_active_reservation!(tier, buyer, organizer)
      assert {:ok, _} = Events.cancel_ticket_reservation(reservation)

      assert {:error, :reservation_not_active} =
               Events.cancel_ticket_reservation(reservation)
    end
  end
end

defmodule Ysc.Tickets.TicketReservationExpiryWorkerTest do
  # async: false — concurrent Task tests share the SQL sandbox with the test process
  use Ysc.DataCase, async: false

  alias Ysc.Tickets.{BookingLocker, TicketReservationExpiryWorker}
  alias Ysc.TicketsFixtures
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
    future =
      DateTime.utc_now()
      |> DateTime.add(3600, :second)
      |> DateTime.truncate(:second)

    past =
      DateTime.utc_now()
      |> DateTime.add(-120, :second)
      |> DateTime.truncate(:second)

    {:ok, reservation} =
      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: user.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active",
        expires_at: future
      })
      |> Repo.insert()

    reservation
    |> Ecto.Changeset.change(%{expires_at: past})
    |> Repo.update!()
  end

  describe "Events.expire_passed_ticket_reservations/1" do
    test "cancels active reservations whose expires_at has passed" do
      organizer = user_fixture() |> with_lifetime_membership()
      buyer = user_fixture() |> with_lifetime_membership()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      reservation = insert_reservation_past_expiry!(tier, buyer, organizer)

      assert {:ok, stats} = Events.expire_passed_ticket_reservations()
      assert stats.cancelled == 1
      assert stats.failed == 0
      assert stats.total_pending == 1
      assert stats.backlog_remaining == 0

      updated = Repo.get!(TicketReservation, reservation.id)
      assert updated.status == "cancelled"
      assert updated.cancelled_at
    end

    test "concurrent fulfill vs expiry never yields cancelled status with a linked order" do
      organizer = user_fixture() |> with_lifetime_membership()
      buyer = user_fixture() |> with_lifetime_membership()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      parent = self()

      for _ <- 1..10 do
        reservation = insert_reservation_past_expiry!(tier, buyer, organizer)

        order =
          TicketsFixtures.ticket_order_fixture(%{
            user: buyer,
            event: event,
            tier: tier
          })

        expiry_task =
          Task.async(fn ->
            Ysc.DataCase.allow_sandbox(self(), parent)
            Events.expire_passed_ticket_reservations()
          end)

        fulfill_task =
          Task.async(fn ->
            Ysc.DataCase.allow_sandbox(self(), parent)
            Events.fulfill_ticket_reservation(reservation, order.id)
          end)

        Task.await(expiry_task, 10_000)
        Task.await(fulfill_task, 10_000)

        updated = Repo.get!(TicketReservation, reservation.id)

        refute updated.status == "cancelled" && updated.ticket_order_id,
               "reservation #{updated.id} must not be cancelled once linked to order #{inspect(updated.ticket_order_id)}"
      end
    end

    test "atomic_booking does not resurrect a hold cancelled before fulfill" do
      organizer = user_fixture() |> with_lifetime_membership()
      buyer = user_fixture() |> with_lifetime_membership()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 50})
      parent = self()

      future =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      for _ <- 1..10 do
        {:ok, reservation} =
          %TicketReservation{}
          |> TicketReservation.changeset(%{
            ticket_tier_id: tier.id,
            user_id: buyer.id,
            quantity: 1,
            created_by_id: organizer.id,
            status: "active",
            expires_at: future
          })
          |> Repo.insert()

        booking_task =
          Task.async(fn ->
            Ysc.DataCase.allow_sandbox(self(), parent)
            BookingLocker.atomic_booking(buyer.id, event.id, %{tier.id => 1})
          end)

        cancel_task =
          Task.async(fn ->
            Ysc.DataCase.allow_sandbox(self(), parent)
            Events.cancel_ticket_reservation(reservation)
          end)

        booking_result = Task.await(booking_task, 10_000)
        Task.await(cancel_task, 10_000)

        updated = Repo.get!(TicketReservation, reservation.id)

        case booking_result do
          {:ok, order} when updated.status == "fulfilled" ->
            assert updated.ticket_order_id == order.id

          {:error, :reservation_lapsed} ->
            assert updated.status == "cancelled"
            refute updated.ticket_order_id

          {:ok, _order} ->
            :ok

          other ->
            flunk("unexpected booking result: #{inspect(other)}")
        end

        refute updated.status == "cancelled" && updated.ticket_order_id,
               "hold must not be cancelled while linked to order #{inspect(updated.ticket_order_id)}"
      end
    end

    test "fulfill after expiry cancellation leaves reservation cancelled" do
      organizer = user_fixture() |> with_lifetime_membership()
      buyer = user_fixture() |> with_lifetime_membership()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      reservation = insert_reservation_past_expiry!(tier, buyer, organizer)

      assert {:ok, %{cancelled: 1}} = Events.expire_passed_ticket_reservations()

      order =
        TicketsFixtures.ticket_order_fixture(%{
          user: buyer,
          event: event,
          tier: tier
        })

      assert {:error, :reservation_not_active} =
               Events.fulfill_ticket_reservation(reservation, order.id)

      updated = Repo.get!(TicketReservation, reservation.id)
      assert updated.status == "cancelled"
      refute updated.ticket_order_id
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

      assert {:ok, stats} = Events.expire_passed_ticket_reservations()
      assert stats.cancelled == 0
      assert stats.failed == 0
      assert stats.total_pending == 0
      assert stats.backlog_remaining == 0
    end

    test "does not cancel reservations still before expires_at" do
      organizer = user_fixture() |> with_lifetime_membership()
      buyer = user_fixture() |> with_lifetime_membership()
      event = event_fixture(%{organizer_id: organizer.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      future =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: buyer.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active",
        expires_at: future
      })
      |> Repo.insert!()

      assert {:ok, stats} = Events.expire_passed_ticket_reservations()
      assert stats.cancelled == 0
      assert stats.failed == 0
      assert stats.total_pending == 0
      assert stats.backlog_remaining == 0
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

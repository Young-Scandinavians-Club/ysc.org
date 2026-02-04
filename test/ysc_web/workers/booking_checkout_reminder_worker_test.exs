defmodule YscWeb.Workers.BookingCheckoutReminderWorkerTest do
  @moduledoc """
  Tests for BookingCheckoutReminderWorker.
  """
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.BookingCheckoutReminderWorker
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()
    booking = booking_fixture(%{user_id: user.id, status: :complete})
    %{user: user, booking: booking}
  end

  describe "perform/1" do
    test "sends checkout reminder for active booking", %{booking: booking} do
      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckoutReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = BookingCheckoutReminderWorker.perform(job)
      assert result == :ok
    end

    test "skips reminder for cancelled booking", %{user: user} do
      # Create booking using changeset directly with skip_validation
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      booking =
        %Ysc.Bookings.Booking{}
        |> Ysc.Bookings.Booking.changeset(
          %{
            user_id: user.id,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 2,
            property: :tahoe,
            booking_mode: :buyout,
            status: :draft,
            total_price: Money.new(200, :USD)
          },
          skip_validation: true
        )
        |> Ysc.Repo.insert!()

      # Update to canceled status
      booking = booking |> Ysc.Repo.preload(:rooms)

      booking
      |> Ysc.Bookings.Booking.changeset(%{status: :canceled},
        rooms: booking.rooms,
        skip_validation: true
      )
      |> Ysc.Repo.update!()

      booking = Ysc.Repo.reload!(booking)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckoutReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = BookingCheckoutReminderWorker.perform(job)
      assert result == :ok
    end

    test "handles missing booking gracefully" do
      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.BookingCheckoutReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = BookingCheckoutReminderWorker.perform(job)
      assert result == :ok
    end
  end

  describe "schedule_reminder/2" do
    test "schedules reminder for future checkout date", %{booking: booking} do
      future_date = Date.add(Date.utc_today(), 7)

      result =
        BookingCheckoutReminderWorker.schedule_reminder(booking.id, future_date)

      assert result == :ok
    end

    test "sends immediately if checkout is less than 1 day away", %{
      booking: booking
    } do
      today = Date.utc_today()

      result =
        BookingCheckoutReminderWorker.schedule_reminder(booking.id, today)

      assert result == :ok
    end
  end
end

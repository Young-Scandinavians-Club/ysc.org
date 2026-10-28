defmodule YscWeb.Workers.BookingReminderTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings.Booking
  alias YscWeb.Emails.BookingCheckoutReminder
  alias YscWeb.Workers.BookingCheckoutReminderWorker
  alias YscWeb.Workers.BookingReminder

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()
    booking = booking_fixture(%{user_id: user.id, status: :complete})
    %{user: user, booking: booking}
  end

  describe "load_booking/1" do
    test "returns nil when the booking is missing" do
      assert BookingReminder.load_booking(Ecto.ULID.generate()) == nil
    end

    test "slim-loads user and rooms for a complete booking", %{booking: booking} do
      loaded = BookingReminder.load_booking(booking.id)

      assert loaded.id == booking.id
      assert Ecto.assoc_loaded?(loaded.user)
      assert Ecto.assoc_loaded?(loaded.rooms)
      assert loaded.user.email
      assert is_nil(loaded.user.hashed_password)
    end
  end

  describe "run_if_complete/3" do
    test "runs the callback for a complete booking", %{booking: booking} do
      assert {:ok, id} =
               BookingReminder.run_if_complete(
                 booking.id,
                 "checkout reminder",
                 fn loaded -> {:ok, loaded.id} end
               )

      assert id == booking.id
    end

    test "returns :ok when the booking is missing" do
      assert :ok =
               BookingReminder.run_if_complete(
                 Ecto.ULID.generate(),
                 "checkout reminder",
                 fn _booking -> flunk("should not run") end
               )
    end

    test "skips inactive bookings", %{user: user} do
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      booking =
        %Booking{}
        |> Booking.changeset(
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
        |> Repo.insert!()

      assert :ok =
               BookingReminder.run_if_complete(
                 booking.id,
                 "checkout reminder",
                 fn _booking -> flunk("should not run") end
               )
    end
  end

  describe "enqueue_or_run/4" do
    test "inserts a job when the scheduled time is in the future" do
      scheduled_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert :scheduled =
               BookingReminder.enqueue_or_run(
                 BookingCheckoutReminderWorker,
                 %{"booking_id" => Ecto.ULID.generate()},
                 scheduled_at,
                 fn -> flunk("should not run immediately") end
               )
    end

    test "runs the due callback when the scheduled time is in the past" do
      scheduled_at = DateTime.add(DateTime.utc_now(), -60, :second)

      assert :ran_now =
               BookingReminder.enqueue_or_run(
                 BookingCheckoutReminderWorker,
                 %{"booking_id" => Ecto.ULID.generate()},
                 scheduled_at,
                 fn -> :ran_now end
               )
    end
  end

  describe "schedule_booking_email/4" do
    test "enqueues a checkout reminder for a complete booking", %{
      booking: booking
    } do
      booking = BookingReminder.load_booking(booking.id)

      assert :ok =
               BookingReminder.schedule_booking_email(
                 booking,
                 BookingCheckoutReminder,
                 "booking_checkout_reminder_#{booking.id}",
                 label: "booking checkout reminder",
                 log: [checkout_date: booking.checkout_date]
               )
    end
  end
end

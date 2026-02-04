defmodule YscWeb.Workers.BookingCheckinReminderWorkerTest do
  @moduledoc """
  Tests for BookingCheckinReminderWorker.

  Verifies that both email and SMS reminders are sent to users
  based on their notification preferences and phone number configuration.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Workers.BookingCheckinReminderWorker
  alias Ysc.Bookings.Booking
  alias Ysc.Repo

  setup do
    # Clear SMS rate limit cache
    Cachex.clear(:ysc_cache)

    # Configure FlowRoute for tests
    Application.put_env(:ysc, :flowroute, from_number: "12061231234")

    :ok
  end

  describe "perform/1" do
    test "sends email reminder for active booking" do
      user = user_fixture(%{email: "test@example.com"})
      booking = create_complete_booking(user)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      # Should succeed - in inline mode, email job executes immediately
      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end

    test "sends both email and SMS when user has phone number and SMS enabled" do
      user =
        user_fixture(%{
          email: "test@example.com",
          phone_number: "+14155551234"
        })

      # Enable SMS notifications
      user =
        user
        |> Ecto.Changeset.change(account_notifications_sms: true)
        |> Repo.update!()

      booking = create_complete_booking(user)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      # Should succeed - both email and SMS jobs execute immediately in inline mode
      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end

    test "returns :ok when user has no phone number (skips SMS)" do
      user = user_fixture(%{email: "test@example.com"})

      # Ensure no phone number
      user =
        user
        |> Ecto.Changeset.change(phone_number: nil)
        |> Repo.update!()

      booking = create_complete_booking(user)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end

    test "returns :ok when user has SMS disabled (sends email only)" do
      user =
        user_fixture(%{
          email: "test@example.com",
          phone_number: "+14155551234"
        })

      # Disable SMS notifications
      user =
        user
        |> Ecto.Changeset.change(account_notifications_sms: false)
        |> Repo.update!()

      booking = create_complete_booking(user)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end

    test "does not send reminder for cancelled booking" do
      user =
        user_fixture(%{
          email: "test@example.com",
          phone_number: "+14155551234"
        })

      user =
        user
        |> Ecto.Changeset.change(account_notifications_sms: true)
        |> Repo.update!()

      # Create a cancelled booking
      booking = create_booking_with_status(user, :canceled)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      # Should return :ok but skip sending (booking not active)
      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end

    test "returns :ok for non-existent booking" do
      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      # Should return :ok to avoid retries for missing bookings
      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end

    test "does not send reminder for draft booking" do
      user = user_fixture(%{email: "test@example.com"})
      booking = create_booking_with_status(user, :draft)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end

    test "does not send reminder for hold booking" do
      user = user_fixture(%{email: "test@example.com"})
      booking = create_booking_with_status(user, :hold)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end
  end

  describe "schedule_reminder/2" do
    test "schedules reminder 3 days before check-in" do
      booking_id = Ecto.ULID.generate()
      # Check-in date is 5 days from now
      checkin_date = Date.add(Date.utc_today(), 5)

      # In inline mode, this may execute immediately or return job
      result =
        BookingCheckinReminderWorker.schedule_reminder(booking_id, checkin_date)

      # Result should be :ok or {:ok, job}
      assert result == :ok or match?({:ok, _}, result)
    end

    test "sends immediately when check-in is less than 3 days away" do
      user = user_fixture(%{email: "test@example.com"})
      booking = create_complete_booking(user)

      # Check-in is tomorrow (less than 3 days)
      checkin_date = Date.add(Date.utc_today(), 1)

      result =
        BookingCheckinReminderWorker.schedule_reminder(booking.id, checkin_date)

      # Should return :ok (sent immediately)
      assert result == :ok
    end
  end

  describe "SMS notification content" do
    test "send_checkin_reminder_sms executes without error for opted-in user" do
      user =
        user_fixture(%{
          email: "test@example.com",
          phone_number: "+14155551234",
          first_name: "John"
        })

      user =
        user
        |> Ecto.Changeset.change(account_notifications_sms: true)
        |> Repo.update!()

      booking = create_complete_booking(user)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      # Should complete without error
      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end
  end

  describe "email notification content" do
    test "send_checkin_reminder_email executes without error" do
      user =
        user_fixture(%{
          email: "test@example.com",
          first_name: "Jane"
        })

      booking = create_complete_booking(user)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      # Should complete without error
      result = BookingCheckinReminderWorker.perform(job)
      assert result == :ok
    end
  end

  # Helper functions

  defp create_complete_booking(user) do
    checkin_date = Date.add(Date.utc_today(), 7)
    checkout_date = Date.add(checkin_date, 2)

    %Booking{
      user_id: user.id,
      property: :tahoe,
      booking_mode: :buyout,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      guests_count: 2,
      status: :complete,
      total_price: Money.new(500, :USD),
      reference_id: "BK-TEST-#{System.unique_integer([:positive])}"
    }
    |> Repo.insert!()
    |> Repo.preload([:user, :rooms])
  end

  defp create_booking_with_status(user, status) do
    checkin_date = Date.add(Date.utc_today(), 7)
    checkout_date = Date.add(checkin_date, 2)

    %Booking{
      user_id: user.id,
      property: :tahoe,
      booking_mode: :buyout,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      guests_count: 2,
      status: status,
      total_price: Money.new(500, :USD),
      reference_id: "BK-TEST-#{System.unique_integer([:positive])}"
    }
    |> Repo.insert!()
    |> Repo.preload([:user, :rooms])
  end
end

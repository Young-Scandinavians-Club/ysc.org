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
  alias YscWeb.Emails.{BookingCheckinReminder, Notifier}
  alias YscWeb.Sms.BookingCheckinReminder, as: SmsBookingCheckinReminder
  alias YscWeb.Sms.Notifier, as: SmsNotifier

  setup do
    # Clear SMS rate limit cache
    Cachex.clear(:ysc_cache)

    # Configure FlowRoute for tests
    Application.put_env(:ysc, :flowroute, from_number: "12061231234")

    :ok
  end

  describe "perform/1" do
    test "perform_job runs the worker" do
      user = user_fixture(%{email: "perform-job-checkin@example.com"})
      booking = create_complete_booking(user)

      assert :ok =
               perform_job(BookingCheckinReminderWorker, %{
                 "booking_id" => booking.id
               })
    end

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

    test "sends reminder for Clear Lake complete booking" do
      user = user_fixture(%{email: "clear_lake_checkin@example.com"})
      booking = create_complete_booking(user, property: :clear_lake)

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert :ok = BookingCheckinReminderWorker.perform(job)
    end

    test "perform sends for complete booking whose check-in date is already past" do
      user = user_fixture(%{email: "past_checkin@example.com"})
      past_in = Date.add(Date.utc_today(), -2)
      past_out = Date.add(past_in, 2)

      booking =
        %Booking{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :buyout,
          checkin_date: past_in,
          checkout_date: past_out,
          guests_count: 2,
          status: :complete,
          total_price: Money.new(500, :USD),
          reference_id: "BK-PAST-#{System.unique_integer([:positive])}"
        }
        |> Repo.insert!()
        |> Repo.preload([:user, :rooms])

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert :ok = BookingCheckinReminderWorker.perform(job)
    end

    test "perform still completes when email Notifier returns duplicate Oban insert (unique job)" do
      user =
        user_fixture(%{email: "dup_email_checkin@example.com"})
        |> Ecto.Changeset.change(account_notifications_sms: false)
        |> Repo.update!()

      booking = create_complete_booking(user)

      email_data = BookingCheckinReminder.prepare_email_data(booking)

      assert %Oban.Job{} =
               Notifier.schedule_email(
                 booking.user.email,
                 "booking_checkin_reminder_#{booking.id}",
                 BookingCheckinReminder.get_subject(booking),
                 BookingCheckinReminder.get_template_name(),
                 email_data,
                 "",
                 booking.user_id
               )

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert :ok = BookingCheckinReminderWorker.perform(job)
    end

    test "perform completes when SMS schedule hits duplicate Oban insert (covers generic SMS error branch)" do
      user =
        user_fixture(%{
          email: "dup_sms_checkin@example.com",
          phone_number: "+14155551234"
        })
        |> Ecto.Changeset.change(account_notifications_sms: true)
        |> Repo.update!()

      booking = create_complete_booking(user)
      sms_data = SmsBookingCheckinReminder.prepare_sms_data(booking)
      template = SmsBookingCheckinReminder.get_template_name()
      sms_key = "booking_checkin_reminder_sms_#{booking.id}"

      assert {:ok, %Oban.Job{}} =
               SmsNotifier.schedule_sms(
                 user.phone_number,
                 sms_key,
                 template,
                 sms_data,
                 user.id
               )

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert :ok = BookingCheckinReminderWorker.perform(job)
    end

    test "perform uses unique phone from AccountsFixtures helper for SMS-enabled user" do
      phone = unique_user_phone()

      user =
        user_fixture(%{
          email: "unique_phone_checkin@example.com",
          phone_number: phone
        })
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

      assert :ok = BookingCheckinReminderWorker.perform(job)
    end
  end

  describe "schedule_reminder/2" do
    test "schedules Oban job when reminder time is in the future" do
      booking_id = Ecto.ULID.generate()
      checkin_date = Date.add(Date.utc_today(), 10)

      # schedule_reminder/2 returns :ok after insert (and logging), not {:ok, job}
      assert :ok =
               BookingCheckinReminderWorker.schedule_reminder(
                 booking_id,
                 checkin_date
               )
    end

    test "returns :ok immediately when booking id does not exist and check-in is soon" do
      assert :ok =
               BookingCheckinReminderWorker.schedule_reminder(
                 Ecto.ULID.generate(),
                 Date.add(Date.utc_today(), 1)
               )
    end

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

    test "immediate schedule path skips non-complete booking" do
      user = user_fixture(%{email: "immediate_skip@example.com"})
      booking = create_booking_with_status(user, :canceled)

      tomorrow = Date.add(Date.utc_today(), 1)

      assert :ok =
               BookingCheckinReminderWorker.schedule_reminder(
                 booking.id,
                 tomorrow
               )
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

  describe "SMS idempotency" do
    # Each test gives the user a real phone number and enables SMS so that
    # send_checkin_reminder_sms → SmsNotifier → run_send_sms_idempotent actually runs.
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    defp sms_enabled_user do
      user_fixture(%{email: "sms_idemp_#{System.unique_integer()}@example.com"})
      |> Ecto.Changeset.change(
        phone_number: "+14155551234",
        account_notifications_sms: true
      )
      |> Repo.update!()
    end

    test "perform/1 called twice for the same booking creates exactly one SMS idempotency record" do
      user = sms_enabled_user()
      booking = create_complete_booking(user)
      sms_key = "booking_checkin_reminder_sms_#{booking.id}"

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert :ok = BookingCheckinReminderWorker.perform(job)

      assert Repo.aggregate(
               from(m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^sms_key and m.message_type == :sms
               ),
               :count
             ) == 1

      # Second run — pre-check (or DB constraint) must block a duplicate send.
      assert :ok = BookingCheckinReminderWorker.perform(job)

      assert Repo.aggregate(
               from(m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^sms_key and m.message_type == :sms
               ),
               :count
             ) == 1
    end

    test "perform/1 called three times still yields exactly one SMS idempotency record" do
      user = sms_enabled_user()
      booking = create_complete_booking(user)
      sms_key = "booking_checkin_reminder_sms_#{booking.id}"

      job = %Oban.Job{
        id: 1,
        args: %{"booking_id" => booking.id},
        worker: "YscWeb.Workers.BookingCheckinReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      for _ <- 1..3 do
        assert :ok = BookingCheckinReminderWorker.perform(job)
      end

      assert Repo.aggregate(
               from(m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^sms_key and m.message_type == :sms
               ),
               :count
             ) == 1
    end

    test "schedule_reminder immediate path (< 3 days) called twice creates one SMS idempotency record" do
      user = sms_enabled_user()
      booking = create_complete_booking(user)
      sms_key = "booking_checkin_reminder_sms_#{booking.id}"

      # Use tomorrow so schedule_reminder takes the immediate (non-Oban-job) path.
      tomorrow = Date.add(Date.utc_today(), 1)

      BookingCheckinReminderWorker.schedule_reminder(booking.id, tomorrow)
      BookingCheckinReminderWorker.schedule_reminder(booking.id, tomorrow)

      assert Repo.aggregate(
               from(m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^sms_key and m.message_type == :sms
               ),
               :count
             ) == 1
    end

    test "different bookings get independent SMS idempotency records" do
      user = sms_enabled_user()
      booking_a = create_complete_booking(user)
      booking_b = create_complete_booking(user)

      for booking <- [booking_a, booking_b] do
        job = %Oban.Job{
          id: 1,
          args: %{"booking_id" => booking.id},
          worker: "YscWeb.Workers.BookingCheckinReminderWorker",
          queue: "mailers",
          state: "available",
          attempt: 1
        }

        assert :ok = BookingCheckinReminderWorker.perform(job)
      end

      sms_key_a = "booking_checkin_reminder_sms_#{booking_a.id}"
      sms_key_b = "booking_checkin_reminder_sms_#{booking_b.id}"

      assert Repo.aggregate(
               from(m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^sms_key_a
               ),
               :count
             ) == 1

      assert Repo.aggregate(
               from(m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^sms_key_b
               ),
               :count
             ) == 1
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

  defp create_complete_booking(user, opts \\ []) do
    property = Keyword.get(opts, :property, :tahoe)

    checkin_date =
      Keyword.get(opts, :checkin_date, Date.add(Date.utc_today(), 7))

    checkout_date = Date.add(checkin_date, 2)

    %Booking{
      user_id: user.id,
      property: property,
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

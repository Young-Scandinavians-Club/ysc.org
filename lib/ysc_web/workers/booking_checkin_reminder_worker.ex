defmodule YscWeb.Workers.BookingCheckinReminderWorker do
  @moduledoc """
  Oban worker for sending booking check-in reminder emails and SMS.

  Sends an email and SMS (if user is opted in) 3 days before check-in at 8:00 AM PST
  with door code, location, and check-in information.
  """
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Repo
  alias Ysc.Bookings.Booking
  alias YscWeb.Emails.{Notifier, BookingCheckinReminder}
  alias YscWeb.Sms.Notifier, as: SmsNotifier
  alias YscWeb.Sms.BookingCheckinReminder, as: SmsBookingCheckinReminder

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"booking_id" => booking_id}}) do
    Logger.info("Processing booking check-in reminder",
      booking_id: booking_id
    )

    case Repo.get(Booking, booking_id) |> Repo.preload([:user, :rooms]) do
      nil ->
        Logger.warning("Booking not found for check-in reminder",
          booking_id: booking_id
        )

        :ok

      booking ->
        # Only send if booking is still active (not cancelled or refunded)
        if booking.status in [:complete] do
          send_checkin_reminder_email(booking)
          send_checkin_reminder_sms(booking)
        else
          Logger.info("Booking is not active, skipping check-in reminder",
            booking_id: booking_id,
            status: booking.status
          )

          :ok
        end
    end
  end

  defp send_checkin_reminder_email(booking) do
    require Logger

    try do
      email_module = BookingCheckinReminder
      email_data = email_module.prepare_email_data(booking)
      subject = email_module.get_subject(booking)
      template_name = email_module.get_template_name()

      # Generate idempotency key to prevent duplicate emails
      idempotency_key = "booking_checkin_reminder_#{booking.id}"

      Logger.info("Sending booking check-in reminder",
        booking_id: booking.id,
        user_id: booking.user_id,
        checkin_date: booking.checkin_date,
        property: booking.property
      )

      case Notifier.schedule_email(
             booking.user.email,
             idempotency_key,
             subject,
             template_name,
             email_data,
             "",
             booking.user_id
           ) do
        %Oban.Job{} ->
          Logger.info("Booking check-in reminder scheduled successfully",
            booking_id: booking.id
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to schedule booking check-in reminder",
            booking_id: booking.id,
            error: inspect(reason)
          )

          # Report to Sentry
          Sentry.capture_message("Failed to schedule booking check-in reminder",
            level: :error,
            extra: %{
              booking_id: booking.id,
              user_id: booking.user_id,
              error: inspect(reason)
            },
            tags: %{
              email_template: template_name,
              reminder_type: "checkin_reminder"
            }
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Failed to send booking check-in reminder",
          booking_id: booking.id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        # Report to Sentry
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            booking_id: booking.id,
            user_id: booking.user_id
          },
          tags: %{
            email_template: "booking_checkin_reminder",
            reminder_type: "checkin_reminder"
          }
        )

        {:error, error}
    end
  end

  defp send_checkin_reminder_sms(booking) do
    require Logger

    try do
      # Check if user has SMS notifications enabled and has a phone number
      if Ysc.Accounts.SmsCategories.should_send_sms?(
           booking.user,
           "booking_checkin_reminder"
         ) &&
           Ysc.Accounts.SmsCategories.has_phone_number?(booking.user) do
        sms_module = SmsBookingCheckinReminder
        sms_data = sms_module.prepare_sms_data(booking)
        template_name = sms_module.get_template_name()

        # Generate idempotency key to prevent duplicate SMS
        idempotency_key = "booking_checkin_reminder_sms_#{booking.id}"

        Logger.info("Sending booking check-in reminder SMS",
          booking_id: booking.id,
          user_id: booking.user_id,
          checkin_date: booking.checkin_date,
          property: booking.property
        )

        case SmsNotifier.schedule_sms(
               booking.user.phone_number,
               idempotency_key,
               template_name,
               sms_data,
               booking.user_id
             ) do
          {:ok, %Oban.Job{}} ->
            Logger.info("Booking check-in reminder SMS scheduled successfully",
              booking_id: booking.id
            )

            :ok

          {:error, :notifications_disabled} ->
            Logger.info("SMS not sent - user has disabled SMS notifications",
              booking_id: booking.id,
              user_id: booking.user_id
            )

            :ok

          {:error, :no_phone_number} ->
            Logger.info("SMS not sent - user has no phone number",
              booking_id: booking.id,
              user_id: booking.user_id
            )

            :ok

          {:error, reason} ->
            Logger.error("Failed to schedule booking check-in reminder SMS",
              booking_id: booking.id,
              error: inspect(reason)
            )

            # Report to Sentry
            Sentry.capture_message(
              "Failed to schedule booking check-in reminder SMS",
              level: :error,
              extra: %{
                booking_id: booking.id,
                user_id: booking.user_id,
                error: inspect(reason)
              },
              tags: %{
                sms_template: template_name,
                reminder_type: "checkin_reminder"
              }
            )

            :ok
        end
      else
        Logger.info(
          "Skipping SMS check-in reminder - user not opted in or no phone number",
          booking_id: booking.id,
          user_id: booking.user_id,
          has_phone: Ysc.Accounts.SmsCategories.has_phone_number?(booking.user),
          sms_enabled:
            Ysc.Accounts.SmsCategories.should_send_sms?(
              booking.user,
              "booking_checkin_reminder"
            )
        )

        :ok
      end
    rescue
      error ->
        Logger.error("Failed to send booking check-in reminder SMS",
          booking_id: booking.id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        # Report to Sentry
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            booking_id: booking.id,
            user_id: booking.user_id
          },
          tags: %{
            sms_template: "booking_checkin_reminder",
            reminder_type: "checkin_reminder"
          }
        )

        :ok
    end
  end

  @doc """
  Schedules a check-in reminder email for a booking.

  The email will be sent 3 days before the check-in date at 8:00 AM PST.
  If check-in is less than 3 days away, the email is sent immediately.
  """
  def schedule_reminder(booking_id, checkin_date) do
    require Logger

    # Calculate 3 days before check-in date
    reminder_date = Date.add(checkin_date, -3)

    # Create datetime at 8:00 AM PST (America/Los_Angeles)
    reminder_datetime_pst =
      reminder_date
      |> DateTime.new!(~T[08:00:00], "America/Los_Angeles")

    # Convert to UTC for Oban scheduling
    reminder_datetime_utc =
      DateTime.shift_zone!(reminder_datetime_pst, "Etc/UTC")

    now = DateTime.utc_now()

    # Check if the scheduled time is in the future
    if DateTime.compare(reminder_datetime_utc, now) == :gt do
      # Schedule for 3 days before check-in at 8:00 AM PST
      %{
        "booking_id" => booking_id
      }
      |> new(scheduled_at: reminder_datetime_utc)
      |> Oban.insert()

      Logger.info("Scheduled check-in reminder email",
        booking_id: booking_id,
        checkin_date: checkin_date,
        reminder_date: reminder_date,
        scheduled_at_pst: reminder_datetime_pst,
        scheduled_at_utc: reminder_datetime_utc
      )
    else
      # If check-in is less than 3 days away, send immediately
      Logger.info(
        "Check-in is less than 3 days away, sending reminder immediately",
        booking_id: booking_id,
        checkin_date: checkin_date
      )

      # Load booking and send email immediately
      case Repo.get(Booking, booking_id) |> Repo.preload([:user, :rooms]) do
        nil ->
          Logger.warning("Booking not found for immediate check-in reminder",
            booking_id: booking_id
          )

          :ok

        booking ->
          # Only send if booking is still active
          if booking.status == :complete do
            send_checkin_reminder_email(booking)
            send_checkin_reminder_sms(booking)
          else
            Logger.info(
              "Booking is not active, skipping immediate check-in reminder",
              booking_id: booking_id,
              status: booking.status
            )

            :ok
          end
      end
    end
  end
end

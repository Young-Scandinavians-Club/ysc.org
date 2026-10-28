defmodule YscWeb.Workers.BookingCheckinReminderWorker do
  @moduledoc """
  Oban worker for sending booking check-in reminder emails and SMS.

  Sends an email and SMS (if user is opted in) 3 days before check-in at 8:00 AM PST
  with door code, location, and check-in information.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :mailers,
    max_attempts: 3,
    unique: [
      fields: [:args],
      keys: [:booking_id],
      states: :incomplete,
      period: :infinity
    ]

  alias YscWeb.Emails.BookingCheckinReminder
  alias YscWeb.Sms.Notifier, as: SmsNotifier
  alias YscWeb.Sms.BookingCheckinReminder, as: SmsBookingCheckinReminder
  alias YscWeb.TimeZone
  alias YscWeb.Workers.BookingReminder

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"booking_id" => booking_id}}) do
    Ysc.Logging.info("Processing booking check-in reminder",
      booking_id: booking_id
    )

    BookingReminder.run_if_complete(
      booking_id,
      "check-in reminder",
      fn booking ->
        send_checkin_reminder_email(booking)
        send_checkin_reminder_sms(booking)
      end
    )
  end

  defp send_checkin_reminder_email(booking) do
    BookingReminder.schedule_booking_email(
      booking,
      BookingCheckinReminder,
      "booking_checkin_reminder_#{booking.id}",
      label: "booking check-in reminder",
      subject: BookingCheckinReminder.get_subject(booking),
      log: [checkin_date: booking.checkin_date]
    )
  end

  defp send_checkin_reminder_sms(booking) do
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

        Ysc.Logging.info("Sending booking check-in reminder SMS",
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
            Ysc.Logging.info(
              "Booking check-in reminder SMS scheduled successfully",
              booking_id: booking.id
            )

            :ok

          {:error, :notifications_disabled} ->
            Ysc.Logging.info(
              "SMS not sent - user has disabled SMS notifications",
              booking_id: booking.id,
              user_id: booking.user_id
            )

            :ok

          {:error, :no_phone_number} ->
            Ysc.Logging.info("SMS not sent - user has no phone number",
              booking_id: booking.id,
              user_id: booking.user_id
            )

            :ok

          {:error, reason} ->
            Ysc.Logging.error(
              "Failed to schedule booking check-in reminder SMS",
              booking_id: booking.id,
              error: inspect(reason)
            )

            :ok
        end
      else
        Ysc.Logging.info(
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
        Ysc.Logging.error("Failed to send booking check-in reminder SMS",
          booking_id: booking.id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
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
    reminder_date = Date.add(checkin_date, -3)
    reminder_datetime_pst = TimeZone.at(reminder_date, ~T[08:00:00])
    reminder_datetime_utc = TimeZone.at_utc(reminder_date, ~T[08:00:00])

    case BookingReminder.enqueue_or_run(
           __MODULE__,
           %{"booking_id" => booking_id},
           reminder_datetime_utc,
           fn -> send_immediate(booking_id, checkin_date) end
         ) do
      :scheduled ->
        Ysc.Logging.info("Scheduled check-in reminder email",
          booking_id: booking_id,
          checkin_date: checkin_date,
          reminder_date: reminder_date,
          scheduled_at_pst: reminder_datetime_pst,
          scheduled_at_utc: reminder_datetime_utc
        )

        :ok

      other ->
        other
    end
  end

  defp send_immediate(booking_id, checkin_date) do
    Ysc.Logging.info(
      "Check-in is less than 3 days away, sending reminder immediately",
      booking_id: booking_id,
      checkin_date: checkin_date
    )

    BookingReminder.run_if_complete(
      booking_id,
      "immediate check-in reminder",
      fn booking ->
        send_checkin_reminder_email(booking)
        send_checkin_reminder_sms(booking)
      end
    )
  end
end

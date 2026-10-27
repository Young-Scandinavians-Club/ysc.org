defmodule YscWeb.Workers.BookingCheckoutReminderWorker do
  @moduledoc """
  Oban worker for sending booking checkout reminder emails.

  Sends an email the evening before checkout (6:00 PM PST) with checkout instructions for the specific property.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias YscWeb.Emails.BookingCheckoutReminder
  alias YscWeb.TimeZone
  alias YscWeb.Workers.BookingReminder

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"booking_id" => booking_id}}) do
    Ysc.Logging.info("Processing booking checkout reminder",
      booking_id: booking_id
    )

    BookingReminder.run_if_complete(
      booking_id,
      "checkout reminder",
      &send_checkout_reminder_email/1
    )
  end

  defp send_checkout_reminder_email(booking) do
    BookingReminder.schedule_booking_email(
      booking,
      BookingCheckoutReminder,
      "booking_checkout_reminder_#{booking.id}",
      label: "booking checkout reminder",
      log: [checkout_date: booking.checkout_date]
    )
  end

  @doc """
  Schedules a checkout reminder email for a booking.

  The email will be sent the evening before checkout (6:00 PM PST) on the day before checkout.
  If checkout is less than 1 day away, the email is sent immediately.
  """
  def schedule_reminder(booking_id, checkout_date) do
    reminder_date = Date.add(checkout_date, -1)
    reminder_datetime_pst = TimeZone.at(reminder_date, ~T[18:00:00])
    reminder_datetime_utc = TimeZone.at_utc(reminder_date, ~T[18:00:00])

    case BookingReminder.enqueue_or_run(
           __MODULE__,
           %{"booking_id" => booking_id},
           reminder_datetime_utc,
           fn -> send_immediate(booking_id, checkout_date) end
         ) do
      :scheduled ->
        Ysc.Logging.info("Scheduled checkout reminder email",
          booking_id: booking_id,
          checkout_date: checkout_date,
          reminder_date: reminder_date,
          scheduled_at_pst: reminder_datetime_pst,
          scheduled_at_utc: reminder_datetime_utc
        )

        :ok

      other ->
        other
    end
  end

  defp send_immediate(booking_id, checkout_date) do
    Ysc.Logging.info(
      "Checkout is less than 1 day away, sending reminder immediately",
      booking_id: booking_id,
      checkout_date: checkout_date
    )

    BookingReminder.run_if_complete(
      booking_id,
      "immediate checkout reminder",
      &send_checkout_reminder_email/1
    )
  end
end

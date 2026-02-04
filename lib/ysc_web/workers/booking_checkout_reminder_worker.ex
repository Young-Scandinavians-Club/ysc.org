defmodule YscWeb.Workers.BookingCheckoutReminderWorker do
  @moduledoc """
  Oban worker for sending booking checkout reminder emails.

  Sends an email the evening before checkout (6:00 PM PST) with checkout instructions for the specific property.
  """
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Repo
  alias Ysc.Bookings.Booking
  alias YscWeb.Emails.{Notifier, BookingCheckoutReminder}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"booking_id" => booking_id}}) do
    Logger.info("Processing booking checkout reminder",
      booking_id: booking_id
    )

    case Repo.get(Booking, booking_id) |> Repo.preload([:user, :rooms]) do
      nil ->
        Logger.warning("Booking not found for checkout reminder",
          booking_id: booking_id
        )

        :ok

      booking ->
        # Only send if booking is still active (not cancelled or refunded)
        if booking.status in [:complete] do
          send_checkout_reminder_email(booking)
        else
          Logger.info("Booking is not active, skipping checkout reminder",
            booking_id: booking_id,
            status: booking.status
          )

          :ok
        end
    end
  end

  defp send_checkout_reminder_email(booking) do
    require Logger

    try do
      email_module = BookingCheckoutReminder
      email_data = email_module.prepare_email_data(booking)
      subject = email_module.get_subject()
      template_name = email_module.get_template_name()

      # Generate idempotency key to prevent duplicate emails
      idempotency_key = "booking_checkout_reminder_#{booking.id}"

      Logger.info("Sending booking checkout reminder",
        booking_id: booking.id,
        user_id: booking.user_id,
        checkout_date: booking.checkout_date,
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
          Logger.info("Booking checkout reminder scheduled successfully",
            booking_id: booking.id
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to schedule booking checkout reminder",
            booking_id: booking.id,
            error: inspect(reason)
          )

          # Report to Sentry
          Sentry.capture_message("Failed to schedule booking checkout reminder",
            level: :error,
            extra: %{
              booking_id: booking.id,
              user_id: booking.user_id,
              error: inspect(reason)
            },
            tags: %{
              email_template: template_name,
              reminder_type: "checkout_reminder"
            }
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Failed to send booking checkout reminder",
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
            email_template: "booking_checkout_reminder",
            reminder_type: "checkout_reminder"
          }
        )

        {:error, error}
    end
  end

  @doc """
  Schedules a checkout reminder email for a booking.

  The email will be sent the evening before checkout (6:00 PM PST) on the day before checkout.
  If checkout is less than 1 day away, the email is sent immediately.
  """
  def schedule_reminder(booking_id, checkout_date) do
    require Logger

    # Calculate 1 day before checkout date
    reminder_date = Date.add(checkout_date, -1)

    # Create datetime at 6:00 PM PST (America/Los_Angeles) - evening time
    reminder_datetime_pst =
      reminder_date
      |> DateTime.new!(~T[18:00:00], "America/Los_Angeles")

    # Convert to UTC for Oban scheduling
    reminder_datetime_utc =
      DateTime.shift_zone!(reminder_datetime_pst, "Etc/UTC")

    now = DateTime.utc_now()

    # Check if the scheduled time is in the future
    if DateTime.compare(reminder_datetime_utc, now) == :gt do
      # Schedule for 1 day before checkout at 6:00 PM PST
      %{
        "booking_id" => booking_id
      }
      |> new(scheduled_at: reminder_datetime_utc)
      |> Oban.insert()

      Logger.info("Scheduled checkout reminder email",
        booking_id: booking_id,
        checkout_date: checkout_date,
        reminder_date: reminder_date,
        scheduled_at_pst: reminder_datetime_pst,
        scheduled_at_utc: reminder_datetime_utc
      )
    else
      # If checkout is less than 1 day away, send immediately
      Logger.info(
        "Checkout is less than 1 day away, sending reminder immediately",
        booking_id: booking_id,
        checkout_date: checkout_date
      )

      # Load booking and send email immediately
      case Repo.get(Booking, booking_id) |> Repo.preload([:user, :rooms]) do
        nil ->
          Logger.warning("Booking not found for immediate checkout reminder",
            booking_id: booking_id
          )

          :ok

        booking ->
          # Only send if booking is still active
          if booking.status == :complete do
            send_checkout_reminder_email(booking)
          else
            Logger.info(
              "Booking is not active, skipping immediate checkout reminder",
              booking_id: booking_id,
              status: booking.status
            )

            :ok
          end
      end
    end
  end
end

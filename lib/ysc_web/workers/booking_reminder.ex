defmodule YscWeb.Workers.BookingReminder do
  @moduledoc """
  Shared booking lookup, Pacific scheduling, and reminder-email enqueue
  for check-in and check-out reminder workers.

  Load a complete booking and enqueue mail:

      BookingReminder.run_if_complete(id, "checkout reminder", fn booking ->
        BookingReminder.schedule_booking_email(
          booking,
          YscWeb.Emails.BookingCheckoutReminder,
          "booking_checkout_reminder_" <> booking.id,
          label: "booking checkout reminder",
          log: [checkout_date: booking.checkout_date]
        )
      end)

  Schedule an Oban job at a Pacific wall-clock time, or run immediately
  when that instant is already in the past:

      utc = YscWeb.TimeZone.at_utc(Date.add(checkin_date, -3), ~T[08:00:00])

      BookingReminder.enqueue_or_run(
        __MODULE__,
        %{"booking_id" => id},
        utc,
        fn -> :ok end
      )
  """
  require Ysc.Logging

  alias Ysc.Repo
  alias Ysc.Bookings.Booking
  alias YscWeb.Emails.{Helpers, Notifier}

  @doc """
  Loads a booking and slim-loads `:user` and `:rooms` for reminder templates.

  Returns `nil` when the booking is missing.
  """
  def load_booking(booking_id) do
    case Repo.get(Booking, booking_id) do
      nil ->
        nil

      booking ->
        Helpers.ensure_booking(booking, [:user, :rooms])
    end
  end

  @doc """
  Runs `fun` when the booking is still `:complete`.

  Missing and inactive bookings log and return `:ok` so Oban does not retry.
  """
  def run_if_complete(booking_id, label, fun)
      when is_binary(label) and is_function(fun, 1) do
    case load_booking(booking_id) do
      nil ->
        Ysc.Logging.warning("Booking not found for #{label}",
          booking_id: booking_id
        )

        :ok

      %{status: :complete} = booking ->
        fun.(booking)

      booking ->
        Ysc.Logging.info("Booking is not active, skipping #{label}",
          booking_id: booking_id,
          status: booking.status
        )

        :ok
    end
  end

  @doc """
  Inserts `args` on `worker` when `scheduled_at` is in the future.

  Returns `:scheduled` after insert. Otherwise runs `on_due` and returns
  its result.
  """
  def enqueue_or_run(worker, args, %DateTime{} = scheduled_at, on_due)
      when is_atom(worker) and is_map(args) and is_function(on_due, 0) do
    if DateTime.compare(scheduled_at, DateTime.utc_now()) == :gt do
      args
      |> worker.new(scheduled_at: scheduled_at)
      |> Oban.insert()

      :scheduled
    else
      on_due.()
    end
  end

  @doc """
  Enqueues a booking reminder email via `Notifier.schedule_email/8`.

  `label` is interpolated into the sending / success / failure log lines.
  Pass `subject:` when the email module's `get_subject/1` needs the booking
  (check-in). Extra `log:` keywords are merged into the "Sending …" line.
  """
  def schedule_booking_email(booking, email_module, idempotency_key, opts)
      when is_list(opts) do
    label = Keyword.fetch!(opts, :label)
    extra = Keyword.get(opts, :log, [])

    subject =
      Keyword.get_lazy(opts, :subject, fn -> email_module.get_subject() end)

    try do
      email_data = email_module.prepare_email_data(booking)
      template_name = email_module.get_template_name()

      Ysc.Logging.info(
        "Sending #{label}",
        [
          booking_id: booking.id,
          user_id: booking.user_id,
          property: booking.property
        ] ++ extra
      )

      case Notifier.schedule_email(
             booking.user.email,
             idempotency_key,
             subject,
             template_name,
             email_data,
             "",
             booking.user_id,
             Ysc.EmailConfig.booking_reply_to(booking.property)
           ) do
        %Oban.Job{} ->
          Ysc.Logging.info(
            "#{String.capitalize(label)} scheduled successfully",
            booking_id: booking.id
          )

          :ok

        {:error, reason} ->
          Ysc.Logging.error("Failed to schedule #{label}",
            booking_id: booking.id,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send #{label}",
          booking_id: booking.id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        {:error, error}
    end
  end
end

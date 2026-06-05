defmodule YscWeb.Workers.EventNotificationWorker do
  @moduledoc """
  Oban worker for sending event notification emails.

  Sends emails to all users with event notifications enabled 1 hour after an event is published.
  Only sends if the event is still published at that time.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Events
  alias Ysc.Repo
  alias Ysc.Events.Event
  alias Ysc.Accounts.User
  alias YscWeb.Emails.{Notifier, EventNotification}
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    Ysc.Logging.info("Processing event notification",
      event_id: event_id
    )

    case Repo.get(Event, event_id)
         |> Repo.preload([:organizer, :cover_image]) do
      nil ->
        Ysc.Logging.warning("Event not found for notification",
          event_id: event_id
        )

        :ok

      event ->
        # Only send if event is still published
        if event.state == "published" or event.state == :published do
          # Only send if event date is in the future (not retroactive)
          if event_in_future?(event) do
            send_event_notifications(event)
          else
            Ysc.Logging.info(
              "Event is retroactive (past date), skipping notifications",
              event_id: event_id,
              start_date: event.start_date,
              start_time: event.start_time
            )

            :ok
          end
        else
          Ysc.Logging.info(
            "Event is no longer published, skipping notifications",
            event_id: event_id,
            state: event.state
          )

          :ok
        end
    end
  end

  @doc """
  Send event notification emails to all users with event notifications enabled.
  """
  def send_event_notifications(event) do
    require Ysc.Logging

    try do
      # Get all users with event notifications enabled
      users =
        from(u in User,
          where: u.event_notifications == true,
          where: u.state == :active
        )
        |> Repo.all()

      Ysc.Logging.info("Sending event notifications",
        event_id: event.id,
        event_title: event.title,
        user_count: length(users)
      )

      # Send email to each user
      results =
        Enum.map(users, fn user ->
          send_event_notification_email(event, user)
        end)

      # Count successes and failures
      success_count = Enum.count(results, &match?({:ok, _}, &1))
      failure_count = length(results) - success_count

      Ysc.Logging.info("Event notifications sent",
        event_id: event.id,
        success_count: success_count,
        failure_count: failure_count
      )

      recipient_count = length(users)

      if success_count == recipient_count do
        case Events.mark_event_notification_sent(event, recipient_count) do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            Ysc.Logging.error("Failed to mark event notification sent",
              event_id: event.id,
              errors: inspect(changeset.errors)
            )

            {:error, :db_update_failed}
        end
      else
        Ysc.Logging.warning("Event notifications partially failed",
          event_id: event.id,
          success_count: success_count,
          recipient_count: recipient_count
        )

        {:error, :partial_failure}
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send event notifications",
          event_id: event.id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        {:error, error}
    end
  end

  defp send_event_notification_email(event, user) do
    require Ysc.Logging

    try do
      email_module = EventNotification
      email_data = email_module.prepare_email_data(event, user)
      subject = email_module.get_subject(event)
      template_name = email_module.get_template_name()

      # Generate idempotency key to prevent duplicate emails
      idempotency_key = "event_notification_#{event.id}_#{user.id}"

      case Notifier.schedule_email(
             user.email,
             idempotency_key,
             subject,
             template_name,
             email_data,
             "",
             user.id
           ) do
        %Oban.Job{} ->
          {:ok, :scheduled}

        {:error, reason} ->
          Ysc.Logging.error("Failed to schedule event notification",
            event_id: event.id,
            user_id: user.id,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send event notification",
          event_id: event.id,
          user_id: user.id,
          error: Exception.message(error)
        )

        {:error, error}
    end
  end

  @doc """
  Schedules event notification emails for all users with event notifications enabled.

  The emails will be sent 1 hour after the event is published.
  """
  def schedule_notifications(event_id, published_at) do
    require Ysc.Logging

    # Calculate 1 hour after publish time
    notification_datetime = DateTime.add(published_at, 3600, :second)

    now = DateTime.utc_now()

    # Check if the scheduled time is in the future
    if DateTime.compare(notification_datetime, now) == :gt do
      # Schedule for 1 hour after publish
      %{
        "event_id" => event_id
      }
      |> new(scheduled_at: notification_datetime)
      |> Oban.insert()

      Ysc.Logging.info("Scheduled event notification emails",
        event_id: event_id,
        published_at: published_at,
        scheduled_at: notification_datetime
      )
    else
      # If 1 hour has already passed, send immediately
      Ysc.Logging.info(
        "1 hour has already passed since publish, sending notifications immediately",
        event_id: event_id,
        published_at: published_at
      )

      # Load event and send emails immediately
      case Repo.get(Event, event_id)
           |> Repo.preload([:organizer, :cover_image]) do
        nil ->
          Ysc.Logging.warning("Event not found for immediate notification",
            event_id: event_id
          )

          :ok

        event ->
          # Only send if event is still published
          if event.state == "published" or event.state == :published do
            # Only send if event date is in the future (not retroactive)
            if event_in_future?(event) do
              send_event_notifications(event)
            else
              Ysc.Logging.info(
                "Event is retroactive (past date), skipping immediate notification",
                event_id: event_id,
                start_date: event.start_date,
                start_time: event.start_time
              )

              :ok
            end
          else
            Ysc.Logging.info(
              "Event is not published, skipping immediate notification",
              event_id: event_id,
              state: event.state
            )

            :ok
          end
      end
    end
  end

  # Check if the event's start datetime is in the future
  defp event_in_future?(event) do
    start_datetime = combine_date_time(event.start_date, event.start_time)

    case start_datetime do
      nil ->
        # If we can't determine the start datetime, don't send notifications
        false

      datetime ->
        # Compare with current time to see if event is in the future
        DateTime.compare(datetime, DateTime.utc_now()) == :gt
    end
  end

  # Combine date and time into a DateTime, similar to Event.combine_date_time/2
  defp combine_date_time(nil, _), do: nil
  defp combine_date_time(_, nil), do: nil

  defp combine_date_time(%DateTime{} = date, %Time{} = time) do
    naive_date = DateTime.to_naive(date)
    date_part = NaiveDateTime.to_date(naive_date)
    naive_datetime = NaiveDateTime.new!(date_part, time)
    DateTime.from_naive!(naive_datetime, "Etc/UTC")
  end

  defp combine_date_time(date, time)
       when not is_nil(date) and not is_nil(time) do
    NaiveDateTime.new!(date, time)
    |> DateTime.from_naive!("Etc/UTC")
  end
end

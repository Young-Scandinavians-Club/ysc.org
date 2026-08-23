defmodule YscWeb.Workers.EventNotificationWorker do
  @moduledoc """
  Oban worker for sending event notification emails.

  Sends emails to all users with event notifications enabled 1 hour after an event is published.
  Only sends if the event is still published at that time.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :bulk_mail,
    max_attempts: 3,
    unique: [
      fields: [:args, :worker],
      keys: [:event_id],
      states: :incomplete,
      period: :infinity
    ],
    replace: [scheduled: [:scheduled_at]]

  import Ecto.Query

  alias Ysc.Events
  alias Ysc.Repo
  alias Ysc.Events.Event
  alias Ysc.Events.EventDateTime
  alias Ysc.Accounts
  alias YscWeb.Emails.{Notifier, EventNotification}
  alias YscWeb.Emails.Helpers, as: EmailHelpers

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

      %Event{notification_sent_at: sent_at} when not is_nil(sent_at) ->
        Ysc.Logging.info("Event notifications already sent, skipping",
          event_id: event_id
        )

        :ok

      event ->
        send_event_notifications(event)
    end
  end

  @doc """
  Send event notification emails to all users with event notifications enabled.

  Guards against already-sent, unpublished, and retroactive (past-date) events itself
  — not just via `perform/1` — so a direct call (e.g. from a console) can't bypass
  those checks the way a scheduled job would.
  """
  def send_event_notifications(%Event{} = event) do
    require Ysc.Logging

    cond do
      not is_nil(event.notification_sent_at) ->
        Ysc.Logging.info("Event notifications already sent, skipping",
          event_id: event.id
        )

        :ok

      event.state not in [:published, "published"] ->
        Ysc.Logging.info(
          "Event is no longer published, skipping notifications",
          event_id: event.id,
          state: event.state
        )

        :ok

      not EventDateTime.in_future?(event) ->
        Ysc.Logging.info(
          "Event is retroactive (past date), skipping notifications",
          event_id: event.id,
          start_date: event.start_date,
          start_time: event.start_time
        )

        :ok

      true ->
        do_send_event_notifications(event)
    end
  end

  defp do_send_event_notifications(event) do
    require Ysc.Logging

    try do
      users = Accounts.list_event_notification_recipients()
      shared = EventNotification.prepare_shared_email_data(event)
      subject = EventNotification.get_subject(event)
      template_name = EventNotification.get_template_name()

      Ysc.Logging.info("Sending event notifications",
        event_id: event.id,
        event_title: event.title,
        user_count: length(users)
      )

      inserted =
        users
        |> Enum.map(fn user ->
          %{
            recipient: user.email,
            idempotency_key: "event_notification_#{event.id}_#{user.id}",
            subject: subject,
            template: template_name,
            variables:
              Map.put(
                shared,
                :first_name,
                EmailHelpers.member_greeting_name(user)
              ),
            text_body: "",
            user_id: user.id
          }
        end)
        |> Notifier.schedule_emails()

      success_count = length(inserted)
      recipient_count = length(users)
      failure_count = recipient_count - success_count

      Ysc.Logging.info("Event notifications sent",
        event_id: event.id,
        success_count: success_count,
        failure_count: failure_count
      )

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

  @doc """
  Schedules event notification emails for all users with event notifications enabled.

  The emails will be sent 1 hour after the event is published. Safe to call again
  for the same event (e.g. after the admin edits event dates before the job has
  fired) — any previously scheduled job for this event is cancelled first, and a
  fresh one is always inserted via Oban rather than sent synchronously inline, so
  callers (like the admin editor's autosave) are never blocked on a mass email
  send. `perform/1` re-checks published state and future-ness at send time.
  """
  def schedule_notifications(event_id, published_at) do
    require Ysc.Logging

    cancel_pending_jobs(event_id)

    notification_datetime = DateTime.add(published_at, 3600, :second)

    case %{"event_id" => event_id}
         |> new(scheduled_at: notification_datetime)
         |> Oban.insert() do
      {:ok, _job} ->
        Ysc.Logging.info("Scheduled event notification emails",
          event_id: event_id,
          published_at: published_at,
          scheduled_at: notification_datetime
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.error("Failed to schedule event notification emails",
          event_id: event_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp cancel_pending_jobs(event_id) do
    from(j in Oban.Job,
      where: j.worker == "YscWeb.Workers.EventNotificationWorker",
      where: fragment("?->>'event_id' = ?", j.args, ^event_id),
      where: j.state in ["available", "scheduled", "retryable"]
    )
    |> Repo.update_all(
      set: [
        state: "cancelled",
        cancelled_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )
  end
end

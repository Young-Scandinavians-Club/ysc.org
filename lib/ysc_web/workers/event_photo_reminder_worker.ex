defmodule YscWeb.Workers.EventPhotoReminderWorker do
  @moduledoc """
  Sends post-event photo upload reminder emails to ticket holders the day after an event ends.

  Scheduled for 9:00 AM America/Los_Angeles on the calendar day after the event's effective end date.
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

  alias Ysc.EventPhotos
  alias Ysc.EventPhotos.Collection
  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Repo
  alias YscWeb.Emails.{EventPhotoUploadReminder, Notifier}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    Ysc.Logging.info("Processing event photo reminder", event_id: event_id)

    with %Event{} = event <- Repo.get(Event, event_id),
         %Collection{} = collection <- EventPhotos.get_by_event_id(event_id) do
      if should_send?(event, collection) do
        send_reminders(event, collection)
      else
        :ok
      end
    else
      _ -> :ok
    end
  end

  @doc "Sends reminder emails to all event attendees and marks the collection as sent."
  def send_reminders(%Event{} = event, %Collection{} = collection) do
    recipients = Events.list_event_update_recipients(event.id)

    if recipients == [] do
      Ysc.Logging.info("No photo reminder recipients", event_id: event.id)

      case EventPhotos.mark_reminder_sent(collection, 0) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          Ysc.Logging.error("Failed to mark photo reminder sent",
            event_id: event.id,
            errors: inspect(changeset.errors)
          )

          {:error, :db_update_failed}
      end
    else
      event = Repo.preload(event, [:organizer, :cover_image])
      template = EventPhotoUploadReminder
      subject = template.get_subject(event)
      template_name = template.get_template_name()
      upload_url = EventPhotos.upload_url(collection)
      shared = template.prepare_shared_email_data(event, upload_url)

      inserted =
        recipients
        |> Enum.map(fn recipient ->
          %{
            recipient: recipient.email,
            idempotency_key:
              "event_photo_reminder_#{event.id}_#{String.downcase(recipient.email)}",
            subject: subject,
            template: template_name,
            variables:
              Map.put(
                shared,
                :first_name,
                recipient[:first_name] || recipient["first_name"] || "there"
              ),
            text_body: "",
            user_id: nil
          }
        end)
        |> Notifier.schedule_emails()

      success_count = length(inserted)
      recipient_count = length(recipients)

      Ysc.Logging.info("Event photo reminders scheduled",
        event_id: event.id,
        success_count: success_count,
        recipient_count: recipient_count
      )

      if success_count == recipient_count do
        case EventPhotos.mark_reminder_sent(collection, recipient_count) do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            Ysc.Logging.error("Failed to mark photo reminder sent",
              event_id: event.id,
              errors: inspect(changeset.errors)
            )

            {:error, :db_update_failed}
        end
      else
        Ysc.Logging.warning("Event photo reminders partially failed",
          event_id: event.id,
          success_count: success_count,
          recipient_count: recipient_count
        )

        {:error, :partial_failure}
      end
    end
  rescue
    error ->
      Ysc.Logging.error("Failed to send event photo reminders",
        event_id: event.id,
        error: Exception.message(error),
        stacktrace: __STACKTRACE__
      )

      {:error, error}
  end

  @doc """
  Schedules the photo reminder for an event, or sends immediately if the time has passed.
  """
  def schedule_reminder(%Event{} = event) do
    # Event dates may change after this is first scheduled (e.g. an admin edits
    # a published event, including clearing the dates entirely). Cancel any
    # stale pending job up front so it can't fire on its old schedule — both
    # when we're about to reschedule it below, and when the event no longer
    # has dates to schedule against at all.
    cancel_pending_jobs(event.id)

    case EventPhotos.photo_reminder_scheduled_at(event) do
      nil ->
        Ysc.Logging.warning(
          "Cannot schedule photo reminder without event dates",
          event_id: event.id
        )

        :ok

      scheduled_at ->
        schedule_or_send_now(event.id, scheduled_at)
    end
  end

  def schedule_reminder(event_id) when is_binary(event_id) do
    case Repo.get(Event, event_id) do
      nil -> :ok
      event -> schedule_reminder(event)
    end
  end

  defp schedule_or_send_now(event_id, scheduled_at) do
    now = DateTime.utc_now()

    if DateTime.compare(scheduled_at, now) == :gt do
      case %{"event_id" => event_id}
           |> new(scheduled_at: scheduled_at)
           |> Oban.insert() do
        {:ok, _job} ->
          Ysc.Logging.info("Scheduled event photo reminder",
            event_id: event_id,
            scheduled_at: scheduled_at
          )

          :ok

        {:error, reason} ->
          Ysc.Logging.error("Failed to schedule event photo reminder",
            event_id: event_id,
            error: inspect(reason)
          )

          {:error, reason}
      end
    else
      with %Event{} = event <- Repo.get(Event, event_id),
           %Collection{} = collection <- EventPhotos.get_by_event_id(event_id),
           true <- should_send?(event, collection) do
        send_reminders(event, collection)
      else
        _ -> :ok
      end
    end
  end

  defp cancel_pending_jobs(event_id) do
    from(j in Oban.Job,
      where: j.worker == "YscWeb.Workers.EventPhotoReminderWorker",
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

  defp should_send?(%Event{}, %Collection{reminder_sent_at: sent_at})
       when not is_nil(sent_at),
       do: false

  defp should_send?(%Event{state: :published}, _collection), do: true
  defp should_send?(%Event{state: "published"}, _collection), do: true
  defp should_send?(_, _), do: false
end

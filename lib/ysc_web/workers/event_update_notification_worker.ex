defmodule YscWeb.Workers.EventUpdateNotificationWorker do
  @moduledoc """
  Oban worker for sending event update notification emails to all attendees.

  Collects deduplicated recipient emails (ticket buyers + registrants)
  and schedules a branded email for each via the Notifier pipeline.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Repo
  alias Ysc.Events
  alias Ysc.Events.EventUpdate
  alias YscWeb.Emails.{Notifier, EventUpdateNotification}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_update_id" => event_update_id}}) do
    Ysc.Logging.info("Processing event update notification",
      event_update_id: event_update_id
    )

    case Repo.get(EventUpdate, event_update_id) do
      nil ->
        Ysc.Logging.warning("EventUpdate not found",
          event_update_id: event_update_id
        )

        :ok

      update ->
        event =
          Repo.get!(Ysc.Events.Event, update.event_id)
          |> Repo.preload([:organizer, :cover_image])

        send_update_notifications(event, update)
    end
  end

  defp send_update_notifications(event, update) do
    try do
      recipients = Events.list_event_update_recipients(event.id)

      Ysc.Logging.info("Sending event update notifications",
        event_id: event.id,
        event_update_id: update.id,
        recipient_count: length(recipients)
      )

      template_module = EventUpdateNotification
      subject = template_module.get_subject(event, update)
      template_name = template_module.get_template_name()

      results =
        Enum.map(recipients, fn recipient ->
          send_single_notification(
            event,
            update,
            recipient,
            subject,
            template_name,
            template_module
          )
        end)

      success_count = Enum.count(results, &match?({:ok, _}, &1))
      failure_count = length(results) - success_count

      Ysc.Logging.info("Event update notifications sent",
        event_id: event.id,
        event_update_id: update.id,
        success_count: success_count,
        failure_count: failure_count
      )

      Events.mark_event_update_sent(update, success_count)

      :ok
    rescue
      error ->
        Ysc.Logging.error("Failed to send event update notifications",
          event_id: event.id,
          event_update_id: update.id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        {:error, error}
    end
  end

  defp send_single_notification(
         event,
         update,
         recipient,
         subject,
         template_name,
         template_module
       ) do
    try do
      email_data = template_module.prepare_email_data(event, update, recipient)

      idempotency_key =
        "event_update_#{update.id}_#{String.downcase(recipient.email)}"

      case Notifier.schedule_email(
             recipient.email,
             idempotency_key,
             subject,
             template_name,
             email_data,
             ""
           ) do
        %Oban.Job{} ->
          {:ok, :scheduled}

        {:error, reason} ->
          Ysc.Logging.error("Failed to schedule event update notification",
            event_update_id: update.id,
            recipient: recipient.email,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send event update notification",
          event_update_id: update.id,
          recipient: recipient.email,
          error: Exception.message(error)
        )

        {:error, error}
    end
  end
end

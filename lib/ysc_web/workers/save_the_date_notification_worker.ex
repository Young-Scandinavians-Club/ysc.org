defmodule YscWeb.Workers.SaveTheDateNotificationWorker do
  @moduledoc """
  Oban worker that sends "tickets now available" emails to users who opted in
  to save-the-date notifications for an event.

  Scheduled 1 hour after an admin clears the tickets_tbd flag, giving time to
  finish other configuration before emails go out.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Repo
  alias Ysc.Events
  alias Ysc.Events.Event
  alias YscWeb.Emails.{Notifier, SaveTheDateAvailable}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    Ysc.Logging.info("Processing save-the-date notifications",
      event_id: event_id
    )

    case Repo.get(Event, event_id)
         |> Repo.preload([:organizer, :cover_image]) do
      nil ->
        Ysc.Logging.warning("Event not found for save-the-date notification",
          event_id: event_id
        )

        :ok

      event ->
        if event.tickets_tbd do
          Ysc.Logging.info(
            "Event still marked TBD, skipping save-the-date notifications",
            event_id: event_id
          )

          :ok
        else
          send_notifications(event)
        end
    end
  end

  defp send_notifications(event) do
    subscribers =
      Events.get_event_notification_subscribers(event.id, "save_the_date")

    Ysc.Logging.info("Sending save-the-date notifications",
      event_id: event.id,
      subscriber_count: length(subscribers)
    )

    results =
      Enum.map(subscribers, fn user ->
        send_notification_email(event, user)
      end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))
    failure_count = length(results) - success_count

    Ysc.Logging.info("Save-the-date notifications sent",
      event_id: event.id,
      success_count: success_count,
      failure_count: failure_count
    )

    Events.delete_event_notification_subscriptions(event.id, "save_the_date")

    :ok
  end

  defp send_notification_email(event, user) do
    try do
      email_data = SaveTheDateAvailable.prepare_email_data(event, user)
      subject = SaveTheDateAvailable.get_subject(event)
      template_name = SaveTheDateAvailable.get_template_name()
      idempotency_key = "save_the_date_available_#{event.id}_#{user.id}"

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
          Ysc.Logging.error("Failed to schedule save-the-date email",
            event_id: event.id,
            user_id: user.id,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      error ->
        Ysc.Logging.error("Error sending save-the-date notification",
          event_id: event.id,
          user_id: user.id,
          error: Exception.message(error)
        )

        {:error, error}
    end
  end
end

defmodule YscWeb.Workers.SaveTheDateNotificationWorker do
  @moduledoc """
  Oban worker that sends "tickets now available" emails to users who opted in
  to save-the-date notifications for an event.

  Scheduled 1 hour after an admin clears the tickets_tbd flag, giving time to
  finish other configuration before emails go out.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :bulk_mail, max_attempts: 3

  alias Ysc.Repo
  alias Ysc.Events
  alias Ysc.Events.Event
  alias YscWeb.Emails.{Notifier, SaveTheDateAvailable}
  alias YscWeb.Emails.Helpers, as: EmailHelpers

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

    shared = SaveTheDateAvailable.prepare_shared_email_data(event)
    subject = SaveTheDateAvailable.get_subject(event)
    template_name = SaveTheDateAvailable.get_template_name()

    inserted =
      subscribers
      |> Enum.map(fn user ->
        %{
          recipient: user.email,
          idempotency_key: "save_the_date_available_#{event.id}_#{user.id}",
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
    failure_count = length(subscribers) - success_count

    Ysc.Logging.info("Save-the-date notifications sent",
      event_id: event.id,
      success_count: success_count,
      failure_count: failure_count
    )

    Events.delete_event_notification_subscriptions(event.id, "save_the_date")

    :ok
  end
end

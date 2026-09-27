defmodule YscWeb.Workers.EventCancellationNotificationWorker do
  @moduledoc """
  Oban worker that emails ticket holders when an event is cancelled.

  `Ysc.Events.cancel_event/2` inserts this job in the same transaction as the
  state change, with the recipient list snapshotted at cancellation time.
  Refunding from the cancellation modal flips tickets to `:cancelled`, so
  re-querying confirmed tickets here would silently drop anyone refunded
  before the job ran.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :bulk_mail, max_attempts: 3

  alias Ysc.Events.Event
  alias Ysc.Repo
  alias YscWeb.Emails.{EventCancellationNotification, Notifier}
  alias YscWeb.Emails.Helpers, as: EmailHelpers

  @doc """
  Builds the job for `event`, carrying `recipients` (maps with `:email` and
  `:first_name`) as the snapshot to notify.
  """
  def new_for_event(%Event{} = event, recipients, %DateTime{} = cancelled_at) do
    new(%{
      "event_id" => event.id,
      "cancelled_at" => DateTime.to_iso8601(cancelled_at),
      "recipients" =>
        Enum.map(recipients, fn recipient ->
          %{"email" => recipient.email, "first_name" => recipient.first_name}
        end)
    })
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "event_id" => event_id,
          "cancelled_at" => cancelled_at,
          "recipients" => recipients
        }
      }) do
    case Repo.get(Event, event_id) do
      nil ->
        Ysc.Logging.warning("Cancelled event not found", event_id: event_id)
        :ok

      %Event{state: :cancelled} = event ->
        send_cancellation_notifications(event, cancelled_at, recipients)

      %Event{} = event ->
        # Un-cancelled (e.g. unpublished back to draft) before the job ran.
        Ysc.Logging.info("Skipping cancellation notice for non-cancelled event",
          event_id: event.id,
          state: event.state
        )

        :ok
    end
  end

  defp send_cancellation_notifications(event, cancelled_at, recipients) do
    template_module = EventCancellationNotification
    subject = template_module.get_subject(event)
    template_name = template_module.get_template_name()
    shared = template_module.prepare_shared_email_data(event)

    inserted =
      recipients
      |> Enum.map(fn %{"email" => email} = recipient ->
        %{
          recipient: email,
          # cancelled_at scopes the key to this cancellation, so an event that
          # is un-cancelled and cancelled again still notifies attendees.
          idempotency_key:
            "event_cancelled_#{event.id}_#{cancelled_at}_#{String.downcase(email)}",
          subject: subject,
          template: template_name,
          variables:
            Map.put(
              shared,
              :first_name,
              EmailHelpers.attendee_greeting_name(recipient)
            ),
          text_body: "",
          user_id: nil
        }
      end)
      |> Notifier.schedule_emails()

    Ysc.Logging.info("Event cancellation notifications scheduled",
      event_id: event.id,
      recipient_count: length(recipients),
      scheduled_count: length(inserted)
    )

    :ok
  end
end

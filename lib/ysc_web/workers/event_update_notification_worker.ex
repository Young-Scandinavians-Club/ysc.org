defmodule YscWeb.Workers.EventUpdateNotificationWorker do
  @moduledoc """
  Oban worker for sending event update notification emails to all attendees.

  Collects deduplicated recipient emails (ticket buyers + registrants)
  and schedules a branded email for each via the Notifier pipeline.

  When `send_sms` is enabled on the update, also schedules SMS to ticket
  purchasers with SMS event notifications enabled.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :bulk_mail, max_attempts: 3

  alias Ysc.Repo
  alias Ysc.Events
  alias Ysc.Events.EventUpdate
  alias YscWeb.Emails.{Notifier, EventUpdateNotification}
  alias YscWeb.Sms.EventUpdateNotification, as: EventUpdateSms
  alias YscWeb.Sms.Notifier, as: SmsNotifier
  alias YscWeb.Sms.Segment

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
      shared = template_module.prepare_shared_email_data(event, update)

      inserted =
        recipients
        |> Enum.map(fn recipient ->
          %{
            recipient: recipient.email,
            idempotency_key:
              "event_update_#{update.id}_#{String.downcase(recipient.email)}",
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
      failure_count = length(recipients) - success_count

      Ysc.Logging.info("Event update notifications sent",
        event_id: event.id,
        event_update_id: update.id,
        success_count: success_count,
        failure_count: failure_count
      )

      {:ok, update} = Events.mark_event_update_sent(update, success_count)

      if update.send_sms do
        case send_update_sms_notifications(event, update) do
          :ok -> :ok
          {:error, _} = error -> error
        end
      else
        :ok
      end
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

  defp send_update_sms_notifications(event, update) do
    sms_analysis =
      Segment.build_event_update_sms(
        event.title || "",
        update.title,
        update.rendered_body || update.raw_body || ""
      )

    sms_body = update.sms_body || sms_analysis.body
    recipients = Events.list_event_update_sms_recipients(event.id)
    template_name = EventUpdateSms.get_template_name()

    Ysc.Logging.info("Sending event update SMS notifications",
      event_id: event.id,
      event_update_id: update.id,
      recipient_count: length(recipients),
      segment_count: sms_analysis.segment_count
    )

    inserted =
      recipients
      |> Enum.map(fn recipient ->
        %{
          phone_number: recipient.phone_number,
          idempotency_key:
            "event_update_sms_#{update.id}_#{recipient.phone_number}",
          template: template_name,
          variables:
            EventUpdateSms.prepare_sms_data(sms_body, recipient.first_name),
          user_id: recipient.user_id
        }
      end)
      |> sms_notifier().schedule_smses()

    scheduled_count = length(inserted)
    skipped_count = length(recipients) - scheduled_count
    failure_count = 0

    case Events.mark_event_update_sms_sent(update, scheduled_count, sms_body) do
      {:ok, _updated} ->
        Ysc.Logging.info("Event update SMS notifications scheduled",
          event_id: event.id,
          event_update_id: update.id,
          success_count: scheduled_count,
          skipped_count: skipped_count,
          failure_count: failure_count
        )

        :ok

      {:error, reason} = error ->
        Ysc.Logging.error("Failed to persist event update SMS send stats",
          event_id: event.id,
          event_update_id: update.id,
          error: inspect(reason)
        )

        error
    end
  end

  defp sms_notifier do
    Application.get_env(:ysc, :event_update_sms_notifier, SmsNotifier)
  end
end

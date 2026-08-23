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

    # Propagate Oban testing mode into async tasks (Process dict is not inherited).
    oban_testing = Process.get(:oban_testing)

    results =
      recipients
      |> Task.async_stream(
        fn recipient ->
          if oban_testing, do: Process.put(:oban_testing, oban_testing)

          send_single_sms(update, recipient, sms_body, template_name)
        end,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, reason}
      end)

    scheduled_count = Enum.count(results, &match?({:ok, :scheduled}, &1))
    skipped_count = Enum.count(results, &match?({:ok, :skipped}, &1))
    failure_count = Enum.count(results, &match?({:error, _}, &1))

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

  defp send_single_sms(update, recipient, sms_body, template_name) do
    try do
      variables =
        EventUpdateSms.prepare_sms_data(sms_body, recipient.first_name)

      idempotency_key =
        "event_update_sms_#{update.id}_#{recipient.phone_number}"

      case sms_notifier().schedule_sms(
             recipient.phone_number,
             idempotency_key,
             template_name,
             variables,
             recipient.user_id
           ) do
        {:ok, %Oban.Job{}} ->
          {:ok, :scheduled}

        {:error, :notifications_disabled} ->
          {:ok, :skipped}

        {:error, reason} ->
          Ysc.Logging.warning("Failed to schedule event update SMS",
            event_update_id: update.id,
            phone_number: recipient.phone_number,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send event update SMS",
          event_update_id: update.id,
          phone_number: recipient.phone_number,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        {:error, error}
    end
  end

  defp sms_notifier do
    Application.get_env(:ysc, :event_update_sms_notifier, SmsNotifier)
  end
end

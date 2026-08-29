defmodule YscWeb.Emails.EventPhotoUploadReminder do
  @moduledoc """
  Email inviting event attendees to upload photos after an event.
  """
  use MjmlEEx,
    mjml_template: "templates/event_photo_upload_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      attendee_greeting_name: 1,
      event_cover_image_url: 1,
      format_event_start_datetime: 2,
      notification_settings_url: 0,
      preload_event_associations: 2
    ]

  alias Ysc.Events.Event

  def get_template_name, do: "event_photo_upload_reminder"

  def get_subject(%Event{title: title}) do
    "[YSC] Share your photos — #{title}"
  end

  @doc "Prepares email data for the photo upload reminder template."
  def prepare_email_data(event, recipient, upload_url) do
    event
    |> prepare_shared_email_data(upload_url)
    |> Map.put(:first_name, attendee_greeting_name(recipient))
  end

  @doc """
  Event fields shared by every recipient of a photo-upload reminder blast.

  Compute this once per send, then `Map.put(:first_name, ...)` per attendee.
  """
  def prepare_shared_email_data(event, upload_url) do
    event = preload_event_associations(event, [:cover_image])

    %{
      event_title: event.title,
      event_date_time:
        format_event_start_datetime(event.start_date, event.start_time),
      event_image_url: event_cover_image_url(event),
      upload_url: upload_url,
      notification_settings_url: notification_settings_url()
    }
  end
end

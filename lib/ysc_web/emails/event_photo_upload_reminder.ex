defmodule YscWeb.Emails.EventPhotoUploadReminder do
  @moduledoc """
  Email inviting event attendees to upload photos after an event.
  """
  use MjmlEEx,
    mjml_template: "templates/event_photo_upload_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [absolute_url: 1, format_event_start_datetime: 2]

  alias Ysc.Events.Event
  alias Ysc.Media.Image
  alias Ysc.Repo

  def get_template_name, do: "event_photo_upload_reminder"

  def get_subject(%Event{title: title}) do
    "[YSC] Share your photos — #{title}"
  end

  def notification_settings_url do
    absolute_url("/users/notifications")
  end

  @doc "Prepares email data for the photo upload reminder template."
  def prepare_email_data(event, recipient, upload_url) do
    event
    |> prepare_shared_email_data(upload_url)
    |> Map.put(
      :first_name,
      recipient[:first_name] || recipient["first_name"] || "there"
    )
  end

  @doc """
  Event fields shared by every recipient of a photo-upload reminder blast.

  Compute this once per send, then `Map.put(:first_name, ...)` per attendee.
  """
  def prepare_shared_email_data(event, upload_url) do
    event = ensure_cover_image(event)

    %{
      event_title: event.title,
      event_date_time:
        format_event_start_datetime(event.start_date, event.start_time),
      event_image_url: event_image_url(event),
      upload_url: upload_url,
      notification_settings_url: notification_settings_url()
    }
  end

  defp ensure_cover_image(event) do
    if Ecto.assoc_loaded?(event.cover_image) do
      event
    else
      Repo.preload(event, :cover_image, force: true)
    end
  end

  defp event_image_url(event) do
    if Ecto.assoc_loaded?(event.cover_image) && event.cover_image do
      Image.display_path(event.cover_image)
    else
      nil
    end
  end
end

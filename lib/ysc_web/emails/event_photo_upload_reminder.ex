defmodule YscWeb.Emails.EventPhotoUploadReminder do
  @moduledoc """
  Email inviting event attendees to upload photos after an event.
  """
  use MjmlEEx,
    mjml_template: "templates/event_photo_upload_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1]

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
    event =
      if Ecto.assoc_loaded?(event.cover_image) do
        event
      else
        Repo.get!(Event, event.id) |> Repo.preload(:cover_image)
      end

    %{
      first_name: recipient[:first_name] || recipient["first_name"] || "there",
      event_title: event.title,
      event_date_time: format_event_datetime(event),
      event_image_url: event_image_url(event),
      upload_url: upload_url,
      notification_settings_url: notification_settings_url()
    }
  end

  defp format_event_datetime(event) do
    case {event.start_date, event.start_time} do
      {nil, _} ->
        nil

      {date, nil} ->
        date_only =
          if is_struct(date, DateTime), do: DateTime.to_date(date), else: date

        Calendar.strftime(date_only, "%B %d, %Y")

      {date, time} ->
        date_only =
          if is_struct(date, DateTime), do: DateTime.to_date(date), else: date

        datetime = DateTime.new!(date_only, time, "Etc/UTC")
        pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
        Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
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

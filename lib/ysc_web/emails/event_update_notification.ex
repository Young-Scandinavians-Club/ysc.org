defmodule YscWeb.Emails.EventUpdateNotification do
  @moduledoc """
  Email template for event update notifications sent by admins to attendees.
  """
  use MjmlEEx,
    mjml_template: "templates/event_update_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      attendee_greeting_name: 1,
      event_cover_image_url: 1,
      event_url: 1,
      format_event_start_datetime: 2,
      notification_settings_url: 0,
      plain_text_from_html: 1,
      preload_event_associations: 1
    ]

  def raw(content) when is_binary(content), do: {:safe, content}
  def raw(nil), do: {:safe, ""}

  def get_template_name() do
    "event_update_notification"
  end

  def get_subject(event, update) do
    title =
      if update.title && update.title != "",
        do: update.title,
        else: "Important Update"

    "[YSC] #{title} — #{event.title}"
  end

  @doc """
  Prepares email data for the event update notification template.
  """
  def prepare_email_data(event, update, recipient) do
    event
    |> prepare_shared_email_data(update)
    |> Map.put(:first_name, attendee_greeting_name(recipient))
  end

  @doc """
  Event and update fields shared by every recipient of an event-update blast.

  Compute this once per send, then `Map.put(:first_name, ...)` per recipient so
  we do not re-render dates, URLs, cover images, and HTML for every attendee.
  """
  def prepare_shared_email_data(event, update) do
    if is_nil(event), do: raise(ArgumentError, "Event cannot be nil")
    if is_nil(update), do: raise(ArgumentError, "Update cannot be nil")

    event = preload_event_associations(event)

    event_date_time =
      format_event_start_datetime(event.start_date, event.start_time)

    event_map = %{
      id: event.id,
      title: event.title,
      description: plain_text_from_html(event.description),
      start_date: event.start_date,
      start_time: event.start_time,
      location_name: event.location_name,
      address: event.address
    }

    %{
      event: event_map,
      update_title: update.title,
      update_body: constrain_media(update.rendered_body || ""),
      event_date_time: event_date_time,
      event_url: event_url(event.id),
      event_image_url: event_cover_image_url(event),
      notification_settings_url: notification_settings_url()
    }
  end

  defp constrain_media(html) do
    html
    |> inject_style("img", "max-width:100%;height:auto;")
    |> inject_style("figure", "max-width:100%;margin:8px 0;overflow:hidden;")
  end

  defp inject_style(html, tag, rules) do
    html
    |> String.replace(
      ~r/<#{tag}\b([^>]*)\bstyle="([^"]*)"([^>]*)>/,
      "<#{tag}\\1style=\"#{rules}\\2\"\\3>"
    )
    |> String.replace(
      ~r/<#{tag}\b(?![^>]*\bstyle=)([^>]*)>/,
      "<#{tag} style=\"#{rules}\"\\1>"
    )
  end
end

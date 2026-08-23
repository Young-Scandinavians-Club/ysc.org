defmodule YscWeb.Emails.EventUpdateNotification do
  @moduledoc """
  Email template for event update notifications sent by admins to attendees.
  """
  use MjmlEEx,
    mjml_template: "templates/event_update_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      format_event_start_datetime: 2,
      plain_text_from_html: 1
    ]

  alias Ysc.Events.Event
  alias Ysc.Media.Image
  alias Ysc.Repo

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

  def event_url(event_id) do
    absolute_url("/events/#{event_id}")
  end

  def notification_settings_url do
    absolute_url("/users/notifications")
  end

  @doc """
  Prepares email data for the event update notification template.
  """
  def prepare_email_data(event, update, recipient) do
    event
    |> prepare_shared_email_data(update)
    |> Map.put(
      :first_name,
      recipient[:first_name] || recipient["first_name"] || "there"
    )
  end

  @doc """
  Event and update fields shared by every recipient of an event-update blast.

  Compute this once per send, then `Map.put(:first_name, ...)` per recipient so
  we do not re-render dates, URLs, cover images, and HTML for every attendee.
  """
  def prepare_shared_email_data(event, update) do
    if is_nil(event), do: raise(ArgumentError, "Event cannot be nil")
    if is_nil(update), do: raise(ArgumentError, "Update cannot be nil")

    event = ensure_event_associations(event)

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
      event_image_url: get_event_image_url(event),
      notification_settings_url: notification_settings_url()
    }
  end

  defp ensure_event_associations(event) do
    if Ecto.assoc_loaded?(event.cover_image) and
         Ecto.assoc_loaded?(event.organizer) do
      event
    else
      case Repo.get(Event, event.id)
           |> Repo.preload([:organizer, :cover_image]) do
        nil -> raise ArgumentError, "Event not found: #{event.id}"
        loaded -> loaded
      end
    end
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

  defp get_event_image_url(event) do
    if Ecto.assoc_loaded?(event.cover_image) && event.cover_image do
      Image.display_path(event.cover_image)
    else
      nil
    end
  end
end

defmodule YscWeb.Emails.SaveTheDateAvailable do
  @moduledoc """
  Email sent to users who opted in to save-the-date notifications
  when the event's tickets_tbd flag is cleared (tickets become available).
  """
  use MjmlEEx,
    mjml_template: "templates/save_the_date_available.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      format_event_start_datetime: 2,
      member_greeting_name: 1,
      plain_text_from_html: 1
    ]

  alias Ysc.Events.Event
  alias Ysc.Media.Image
  alias Ysc.Repo

  def get_template_name(), do: "save_the_date_available"

  @subjects [
    "Tickets are now available: {title}",
    "{title} — tickets are live!",
    "You asked to be notified — {title} is ready",
    "Good news: tickets for {title} are here",
    "{title} is now open for registration"
  ]

  def get_subject(%Event{} = event) do
    "[YSC] " <>
      (@subjects |> Enum.random() |> String.replace("{title}", event.title))
  end

  def get_subject(nil), do: "[YSC] An event you saved is now available"

  def event_url(event_id) do
    absolute_url("/events/#{event_id}")
  end

  def notification_settings_url do
    absolute_url("/users/notifications")
  end

  def prepare_email_data(event, user) do
    if is_nil(user), do: raise(ArgumentError, "User cannot be nil")

    event
    |> prepare_shared_email_data()
    |> Map.put(:first_name, member_greeting_name(user))
  end

  @doc """
  Event fields shared by every recipient of a save-the-date blast.

  Compute this once per event, then `Map.put(:first_name, ...)` per subscriber
  so we do not re-render dates, URLs, and cover images for every opt-in.
  """
  def prepare_shared_email_data(event) do
    if is_nil(event), do: raise(ArgumentError, "Event cannot be nil")

    event = ensure_event_associations(event)

    event_map = %{
      id: event.id,
      title: event.title,
      description: plain_text_from_html(event.description),
      start_date: event.start_date,
      start_time: event.start_time,
      end_date: event.end_date,
      end_time: event.end_time,
      location_name: event.location_name,
      address: event.address,
      age_restriction: event.age_restriction
    }

    %{
      event: event_map,
      event_date_time:
        format_event_start_datetime(event.start_date, event.start_time),
      event_url: event_url(event.id),
      event_image_url: event_image_url(event),
      notification_settings_url: notification_settings_url()
    }
  end

  defp ensure_event_associations(event) do
    if Ecto.assoc_loaded?(event.organizer) &&
         Ecto.assoc_loaded?(event.cover_image) do
      event
    else
      case Repo.get(Event, event.id)
           |> Repo.preload([:organizer, :cover_image]) do
        nil -> raise ArgumentError, "Event not found: #{event.id}"
        loaded -> loaded
      end
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

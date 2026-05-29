defmodule YscWeb.Emails.SaveTheDateAvailable do
  @moduledoc """
  Email sent to users who opted in to save-the-date notifications
  when the event's tickets_tbd flag is cleared (tickets become available).
  """
  use MjmlEEx,
    mjml_template: "templates/save_the_date_available.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1, member_greeting_name: 1]

  alias Ysc.Events.Event
  alias HtmlSanitizeEx
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
    if is_nil(event), do: raise(ArgumentError, "Event cannot be nil")
    if is_nil(user), do: raise(ArgumentError, "User cannot be nil")

    event =
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

    event_map = %{
      id: event.id,
      title: event.title,
      description:
        event.description && HtmlSanitizeEx.strip_tags(event.description),
      start_date: event.start_date,
      start_time: event.start_time,
      end_date: event.end_date,
      end_time: event.end_time,
      location_name: event.location_name,
      address: event.address,
      age_restriction: event.age_restriction
    }

    event_image_url =
      if Ecto.assoc_loaded?(event.cover_image) && event.cover_image do
        Image.display_path(event.cover_image)
      else
        nil
      end

    %{
      first_name: member_greeting_name(user),
      event: event_map,
      event_date_time: format_event_datetime(event),
      event_url: event_url(event.id),
      event_image_url: event_image_url,
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
end

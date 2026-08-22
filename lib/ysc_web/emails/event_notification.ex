defmodule YscWeb.Emails.EventNotification do
  @moduledoc """
  Email template for event notifications.

  Sent to users 1 hour after an event is published (if event is still published).
  """
  use MjmlEEx,
    mjml_template: "templates/event_notification.mjml.eex",
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

  def get_template_name() do
    "event_notification"
  end

  @subjects_with_event [
    "Will we see you at {title}?",
    "Don't miss {title} 👀",
    "{title} is on the calendar — are you in?",
    "Just added: {title}",
    "Have you heard about {title}?",
    "You might like this → {title}"
  ]

  @subjects_save_the_date [
    "Save the date: {title}",
    "Mark your calendar — {title} is coming",
    "{title} is coming soon — save your spot",
    "Heads up: {title} is on the way"
  ]

  @subjects_without_event [
    "New on the calendar",
    "Something new just dropped",
    "Fresh event alert",
    "There's something happening soon"
  ]

  def get_subject(event \\ nil) do
    subject =
      cond do
        is_nil(event) ->
          Enum.random(@subjects_without_event)

        event.tickets_tbd ->
          @subjects_save_the_date
          |> Enum.random()
          |> String.replace("{title}", event.title)

        true ->
          @subjects_with_event
          |> Enum.random()
          |> String.replace("{title}", event.title)
      end

    "[YSC] " <> subject
  end

  def event_url(event_id) do
    absolute_url("/events/#{event_id}")
  end

  def notification_settings_url do
    absolute_url("/users/notifications")
  end

  @doc """
  Prepares event notification email data.

  ## Parameters:
  - `event`: The event that was published
  - `user`: The user to send the notification to

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(event, user) do
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    event
    |> prepare_shared_email_data()
    |> Map.put(:first_name, member_greeting_name(user))
  end

  @doc """
  Event fields shared by every recipient of an event notification blast.

  Compute this once per event, then `Map.put(:first_name, ...)` per user so
  we do not re-render dates, URLs, and organizer data for every member.
  """
  def prepare_shared_email_data(event) do
    if is_nil(event) do
      raise ArgumentError, "Event cannot be nil"
    end

    event = ensure_event_associations(event)

    event_date_time =
      format_event_start_datetime(event.start_date, event.start_time)

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
      age_restriction: event.age_restriction,
      organizer:
        if(Ecto.assoc_loaded?(event.organizer) && event.organizer,
          do: %{
            first_name: event.organizer.first_name,
            last_name: event.organizer.last_name
          },
          else: nil
        )
    }

    %{
      event: event_map,
      event_date_time: event_date_time,
      event_url: event_url(event.id),
      event_image_url: get_event_image_url(event),
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
        nil ->
          raise ArgumentError, "Event not found: #{event.id}"

        loaded_event ->
          loaded_event
      end
    end
  end

  defp get_event_image_url(event) do
    if Ecto.assoc_loaded?(event.cover_image) && event.cover_image do
      Image.display_path(event.cover_image)
    else
      nil
    end
  end
end

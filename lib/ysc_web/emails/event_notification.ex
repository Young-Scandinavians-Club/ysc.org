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
      event_notification_unsubscribe_url: 1,
      member_greeting_name: 1
    ]

  alias YscWeb.Emails.EventHelpers

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
    |> Map.put(:unsubscribe_url, event_notification_unsubscribe_url(user.id))
  end

  @doc """
  Event fields shared by every recipient of an event notification blast.

  Compute this once per event, then `Map.put(:first_name, ...)` per user so
  we do not re-render dates, URLs, and organizer data for every member.
  """
  def prepare_shared_email_data(event) do
    EventHelpers.event_display(event, organizer: true)
  end
end

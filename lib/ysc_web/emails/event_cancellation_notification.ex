defmodule YscWeb.Emails.EventCancellationNotification do
  @moduledoc """
  Email template sent to ticket holders when an event is cancelled.
  """
  use MjmlEEx,
    mjml_template: "templates/event_cancellation_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [attendee_greeting_name: 1, upcoming_events_url: 0]

  alias YscWeb.Emails.EventHelpers

  @events_email "events@ysc.org"

  def get_template_name() do
    "event_cancellation_notification"
  end

  def get_subject(event) do
    "[YSC] Cancelled: #{event.title}"
  end

  @doc """
  Prepares email data for the event cancellation template.
  """
  def prepare_email_data(event, recipient) do
    event
    |> prepare_shared_email_data()
    |> Map.put(:first_name, attendee_greeting_name(recipient))
  end

  @doc """
  Event fields shared by every recipient of a cancellation notice.

  Compute this once per send, then `Map.put(:first_name, ...)` per recipient.
  """
  def prepare_shared_email_data(event) do
    event
    |> EventHelpers.event_display(
      preload: [:cover_image],
      event_url: false,
      fields: [:id, :title, :location_name, :address]
    )
    |> Map.merge(%{
      upcoming_events_url: upcoming_events_url(),
      events_email: @events_email
    })
  end
end

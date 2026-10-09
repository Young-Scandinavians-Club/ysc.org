defmodule YscWeb.Emails.SaveTheDateAvailable do
  @moduledoc """
  Email sent to users who opted in to save-the-date notifications
  when the event's tickets_tbd flag is cleared (tickets become available).
  """
  use MjmlEEx,
    mjml_template: "templates/save_the_date_available.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [member_greeting_name: 1, notification_settings_url: 0]

  alias Ysc.Events.Event
  alias YscWeb.Emails.EventHelpers

  def get_template_name(), do: "save_the_date_available"

  @subjects [
    "Tickets are now available: {title}",
    "{title} — tickets are live!",
    "You asked to be notified — {title} is ready",
    "Good news: tickets for {title} are here",
    "{title} tickets are now available"
  ]

  def subject_templates, do: @subjects

  def get_subject(%Event{} = event) do
    "[YSC] " <>
      (@subjects |> Enum.random() |> String.replace("{title}", event.title))
  end

  def get_subject(nil), do: "[YSC] An event you saved is now available"

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
    event
    |> EventHelpers.event_display()
    |> Map.put(:notification_settings_url, notification_settings_url())
  end
end

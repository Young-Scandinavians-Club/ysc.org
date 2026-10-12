defmodule YscWeb.Emails.EventUpdateNotification do
  @moduledoc """
  Email template for event update notifications sent by admins to attendees.
  """
  use MjmlEEx,
    mjml_template: "templates/event_update_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [attendee_greeting_name: 1, notification_settings_url: 0]

  alias YscWeb.Emails.EventHelpers

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
    _ = EventHelpers.require_event!(event)
    if is_nil(update), do: raise(ArgumentError, "Update cannot be nil")

    event
    |> EventHelpers.event_display(
      fields: [
        :id,
        :title,
        :description,
        :start_date,
        :start_time,
        :location_name,
        :address
      ]
    )
    |> Map.merge(%{
      update_title: update.title,
      update_body: constrain_media(update.rendered_body || ""),
      notification_settings_url: notification_settings_url()
    })
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

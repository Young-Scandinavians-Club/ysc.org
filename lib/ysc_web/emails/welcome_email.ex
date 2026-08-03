defmodule YscWeb.Emails.WelcomeEmail do
  @moduledoc """
  Email template for the new-member welcome email.

  Sent once, 3 days after a member's first membership payment clears. Orients
  new members with a few upcoming events, how Tahoe's seasonal booking rules
  work, and a nudge to book Clear Lake.
  """
  use MjmlEEx,
    mjml_template: "templates/welcome_email.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Bookings.Season
  alias Ysc.Events
  alias Ysc.Media.Image

  import YscWeb.Emails.Helpers,
    only: [
      member_greeting_name: 1,
      absolute_url: 1,
      upcoming_events_url: 0,
      format_event_start_datetime: 2
    ]

  def get_template_name(), do: "welcome_email"

  def get_subject(), do: "Getting started at YSC"

  def prepare_email_data(user) do
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    %{
      first_name: member_greeting_name(user),
      events: upcoming_event_cards(),
      events_url: upcoming_events_url(),
      tahoe_url: absolute_url("/bookings/tahoe"),
      clear_lake_url: absolute_url("/bookings/clear-lake")
    }
    |> Map.merge(tahoe_season_copy())
  end

  defp upcoming_event_cards do
    3
    |> Events.list_upcoming_events_with_preload()
    |> Enum.map(&event_render_map/1)
  end

  defp event_render_map(event) do
    %{
      title: event.title,
      date_str: format_event_start_datetime(event.start_date, event.start_time),
      location_name: event.location_name,
      url: absolute_url("/events/#{event.id}"),
      image_url: Image.display_path(event.cover_image)
    }
  end

  defp tahoe_season_copy do
    today = Date.utc_today()
    season = Season.for_date(:tahoe, today)
    buyout_allowed = Season.buyout_allowed_on_date?(:tahoe, today)

    %{
      tahoe_season_name: (season && season.name) || "the current season",
      tahoe_buyout_allowed: buyout_allowed
    }
  end
end

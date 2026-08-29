defmodule YscWeb.Emails.TahoeSummerBuyoutAvailable do
  @moduledoc """
  Email announcing that the first whole weekend of the upcoming Tahoe Summer
  season has entered the bookable window for a full-cabin (buyout) booking.

  Sent once per Summer occurrence by
  `Ysc.Bookings.SeasonWeekendAvailabilityWorker`.
  """
  use MjmlEEx,
    mjml_template: "templates/tahoe_summer_buyout_available.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [absolute_url: 1, member_greeting_name: 1]

  def get_template_name, do: "tahoe_summer_buyout_available"

  def get_subject(cycle_label) do
    "[YSC] Book the whole cabin — Summer #{cycle_label} is open!"
  end

  def booking_url, do: absolute_url("/bookings/tahoe")

  def notification_settings_url, do: absolute_url("/users/notifications")

  @doc """
  Prepares email data for a recipient.

  `weekend_checkin`/`weekend_checkout` are the first bookable Friday→Sunday
  weekend of the season; `cycle_label` is e.g. `"2027"`.
  """
  def prepare_email_data(weekend_checkin, weekend_checkout, cycle_label, user) do
    %{
      first_name: member_greeting_name(user),
      cycle_label: cycle_label,
      weekend_range: format_weekend_range(weekend_checkin, weekend_checkout),
      booking_url: booking_url(),
      notification_settings_url: notification_settings_url()
    }
  end

  defp format_weekend_range(checkin, checkout) do
    "#{Calendar.strftime(checkin, "%A, %B %-d")} – #{Calendar.strftime(checkout, "%A, %B %-d, %Y")}"
  end
end

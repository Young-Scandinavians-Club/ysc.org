defmodule YscWeb.Emails.TahoeWinterWeekendAvailable do
  @moduledoc """
  Email announcing that the first whole weekend of the upcoming Tahoe Winter
  season has entered the bookable window.

  Sent once per Winter occurrence by
  `Ysc.Bookings.SeasonWeekendAvailabilityWorker`. Winter is rooms-only (no
  whole-cabin buyout), so this points members at room booking.
  """
  use MjmlEEx,
    mjml_template: "templates/tahoe_winter_weekend_available.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [absolute_url: 1, member_greeting_name: 1]

  def get_template_name, do: "tahoe_winter_weekend_available"

  def get_subject(cycle_label) do
    "[YSC] Winter #{cycle_label} weekends are open for booking!"
  end

  def booking_url, do: absolute_url("/bookings/tahoe")

  def notification_settings_url, do: absolute_url("/users/notifications")

  @doc """
  Prepares email data for a recipient.

  `weekend_checkin`/`weekend_checkout` are the first bookable Friday→Sunday
  weekend of the season; `cycle_label` is e.g. `"2026/2027"`.
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

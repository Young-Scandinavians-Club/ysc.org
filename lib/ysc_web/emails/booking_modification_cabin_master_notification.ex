defmodule YscWeb.Emails.BookingModificationCabinMasterNotification do
  @moduledoc """
  Email template for booking modification notification to Cabin Master.

  Sends an internal notification email to the Cabin Master when a booking at
  their property has its dates or guest counts changed.
  """
  use MjmlEEx,
    mjml_template:
      "templates/booking_modification_cabin_master_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      admin_booking_url: 1,
      ensure_booking: 1,
      format_date: 1,
      member_full_name: 1
    ]

  alias Ysc.Bookings.PropertyDisplay

  def get_template_name(), do: "booking_modification_cabin_master_notification"

  def get_subject(), do: "Booking Modification Notification"

  @doc """
  Prepares booking modification cabin master notification email data.

  ## Parameters:
  - `booking`: The modified booking with preloaded associations
  - `previous_details`: Map of the booking's prior `:checkin_date`,
    `:checkout_date`, `:guests_count`, `:children_count`

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(booking, previous_details) do
    booking = ensure_booking(booking)
    previous = normalize_previous_details(previous_details)

    %{
      booking: %{
        reference_id: booking.reference_id,
        property: PropertyDisplay.short_name(booking.property),
        checkin_date: format_date(booking.checkin_date),
        checkout_date: format_date(booking.checkout_date),
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0
      },
      previous: %{
        checkin_date: format_date(previous.checkin_date),
        checkout_date: format_date(previous.checkout_date),
        guests_count: previous.guests_count,
        children_count: previous.children_count
      },
      dates_changed:
        previous.checkin_date != booking.checkin_date or
          previous.checkout_date != booking.checkout_date,
      guests_changed:
        previous.guests_count != booking.guests_count or
          previous.children_count != (booking.children_count || 0),
      user: %{
        name: member_full_name(booking.user),
        email: booking.user.email
      },
      booking_url: admin_booking_url(booking.id)
    }
  end

  defp normalize_previous_details(details) when is_map(details) do
    %{
      checkin_date:
        Map.get(details, :checkin_date) || Map.get(details, "checkin_date"),
      checkout_date:
        Map.get(details, :checkout_date) || Map.get(details, "checkout_date"),
      guests_count:
        Map.get(details, :guests_count) || Map.get(details, "guests_count"),
      children_count:
        Map.get(details, :children_count) || Map.get(details, "children_count") ||
          0
    }
  end
end

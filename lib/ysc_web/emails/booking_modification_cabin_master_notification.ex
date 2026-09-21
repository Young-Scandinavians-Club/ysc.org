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

  import YscWeb.Emails.Helpers, only: [absolute_url: 1, format_date: 1]

  alias Ysc.Repo
  alias Ysc.Bookings.Booking
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
    if is_nil(booking) do
      raise ArgumentError, "Booking cannot be nil"
    end

    booking =
      if Ecto.assoc_loaded?(booking.user) do
        booking
      else
        case Repo.get(Booking, booking.id) |> Repo.preload(:user) do
          nil -> raise ArgumentError, "Booking not found: #{booking.id}"
          loaded_booking -> loaded_booking
        end
      end

    if is_nil(booking.user) do
      raise ArgumentError, "Booking missing user association: #{booking.id}"
    end

    previous = normalize_previous_details(previous_details)

    property_name = PropertyDisplay.short_name(booking.property)

    %{
      booking: %{
        reference_id: booking.reference_id,
        property: property_name,
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
        name:
          "#{booking.user.first_name || ""} #{booking.user.last_name || ""}"
          |> String.trim(),
        email: booking.user.email
      },
      booking_url: booking_url(booking.id)
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

  defp booking_url(booking_id) do
    absolute_url("/admin/bookings/#{booking_id}")
  end
end

defmodule YscWeb.Emails.BookingCheckinReminder do
  @moduledoc """
  Email template for booking check-in reminder.

  Sent 3 days before check-in with door code, location, and check-in information.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_checkin_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      booking_receipt_url: 1,
      booking_room_names: 1,
      ensure_booking: 2,
      member_greeting_name: 1,
      format_date: 1,
      property_as_string: 1
    ]

  alias Ysc.Bookings
  alias Ysc.Bookings.{BookingModeDisplay, CabinMaster, PropertyDisplay}
  alias YscWeb.BookingDisplay

  def get_template_name() do
    "booking_checkin_reminder"
  end

  def get_subject(booking) do
    property_name = PropertyDisplay.short_name(booking.property)
    "Your #{property_name} Check-In Instructions - YSC Cabin Stay 🏡"
  end

  def booking_url(booking_id), do: booking_receipt_url(booking_id)

  @doc """
  Prepares booking check-in reminder email data.

  ## Parameters:
  - `booking`: The booking with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(booking) do
    booking = ensure_booking(booking, [:user, :rooms])
    door_code = Bookings.get_active_door_code(booking.property)
    contact = CabinMaster.contact(booking.property)
    today_pst = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

    %{
      first_name: member_greeting_name(booking.user),
      door_code: if(door_code, do: door_code.code, else: "Not Available"),
      property: property_as_string(booking.property),
      property_name: PropertyDisplay.short_name(booking.property),
      property_address: PropertyDisplay.address(booking.property),
      checkin_date: format_date(booking.checkin_date),
      checkout_date: format_date(booking.checkout_date),
      checkin_time: BookingDisplay.checkin_time_label(),
      checkout_time: BookingDisplay.checkout_time_label(),
      days_until_checkin: Date.diff(booking.checkin_date, today_pst),
      booking_reference_id: booking.reference_id,
      booking_mode: BookingModeDisplay.label(booking.booking_mode),
      room_names: booking_room_names(booking),
      nights: Date.diff(booking.checkout_date, booking.checkin_date),
      is_buyout: BookingModeDisplay.buyout?(booking.booking_mode),
      guests_count: booking.guests_count,
      children_count: booking.children_count || 0,
      cabin_master_name: contact.name,
      cabin_master_email: contact.email,
      cabin_master_phone: contact.phone,
      booking_url: booking_url(booking.id),
      clear_lake_info_url: PropertyDisplay.training_videos_url(:clear_lake)
    }
  end
end

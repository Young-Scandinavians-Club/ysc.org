defmodule YscWeb.Emails.BookingCheckoutReminder do
  @moduledoc """
  Email template for booking checkout reminder.

  Sent the evening before checkout with checkout instructions for the specific property.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_checkout_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      booking_receipt_url: 1,
      ensure_booking: 2,
      member_greeting_name: 1,
      format_date: 1,
      property_as_string: 1
    ]

  alias Ysc.Bookings.{CabinMaster, PropertyDisplay}
  alias YscWeb.BookingDisplay

  def get_template_name() do
    "booking_checkout_reminder"
  end

  def get_subject() do
    "Leaving tomorrow — cabin check-out reminder 🏡"
  end

  def booking_url(booking_id), do: booking_receipt_url(booking_id)

  @doc """
  Prepares booking checkout reminder email data.

  ## Parameters:
  - `booking`: The booking with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(booking) do
    booking = ensure_booking(booking, [:user, :rooms])
    contact = CabinMaster.contact(booking.property)

    %{
      first_name: member_greeting_name(booking.user),
      property: property_as_string(booking.property),
      property_name: PropertyDisplay.short_name(booking.property),
      property_address: PropertyDisplay.address(booking.property),
      checkout_date: format_date(booking.checkout_date),
      checkout_time: BookingDisplay.checkout_time_label(),
      booking_reference_id: booking.reference_id,
      cabin_master_name: contact.name,
      cabin_master_email: contact.email,
      cabin_master_phone: contact.phone,
      booking_url: booking_url(booking.id)
    }
  end
end

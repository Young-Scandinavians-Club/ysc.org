defmodule YscWeb.Emails.BookingConfirmation do
  @moduledoc """
  Email template for booking confirmation.

  Sends a confirmation email to users after their booking has been confirmed.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      booking_receipt_url: 1,
      booking_room_names: 1,
      ensure_booking: 2,
      member_greeting_name: 1,
      format_date: 1,
      format_datetime: 1,
      format_money: 1
    ]

  alias Ysc.Bookings.{BookingModeDisplay, PropertyDisplay}

  def get_template_name() do
    "booking_confirmation"
  end

  def get_subject() do
    "Your booking is confirmed! 🏡"
  end

  def booking_url(booking_id), do: booking_receipt_url(booking_id)

  @doc """
  Prepares booking confirmation email data.

  ## Parameters:
  - `booking`: The confirmed booking with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(booking) do
    booking = ensure_booking(booking, [:user, :rooms])

    %{
      first_name: member_greeting_name(booking.user),
      booking: %{
        reference_id: booking.reference_id,
        property: PropertyDisplay.short_name(booking.property),
        checkin_date: format_date(booking.checkin_date),
        checkout_date: format_date(booking.checkout_date),
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0,
        booking_mode: BookingModeDisplay.label(booking.booking_mode),
        room_names: booking_room_names(booking),
        nights: Date.diff(booking.checkout_date, booking.checkin_date),
        is_buyout: BookingModeDisplay.buyout?(booking.booking_mode),
        booking_mode_raw: to_string(booking.booking_mode)
      },
      total_amount: format_money(booking.total_price),
      booking_date: format_datetime(booking.inserted_at),
      booking_url: booking_url(booking.id),
      cabin_email: Ysc.EmailConfig.booking_reply_to(booking.property)
    }
  end
end

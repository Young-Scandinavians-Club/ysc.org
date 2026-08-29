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
      absolute_url: 1,
      member_greeting_name: 1,
      format_date: 1,
      format_datetime: 1,
      format_money: 1
    ]

  alias Ysc.Repo
  alias Ysc.Bookings.{BookingModeDisplay, PropertyDisplay}

  def get_template_name() do
    "booking_confirmation"
  end

  def get_subject() do
    "Your booking is confirmed! 🏡"
  end

  def booking_url(booking_id) do
    absolute_url("/bookings/#{booking_id}/receipt")
  end

  @doc """
  Prepares booking confirmation email data.

  ## Parameters:
  - `booking`: The confirmed booking with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(booking) do
    # Validate input
    if is_nil(booking) do
      raise ArgumentError, "Booking cannot be nil"
    end

    if is_nil(booking.id) do
      raise ArgumentError, "Booking missing id: #{inspect(booking)}"
    end

    # Ensure we have all necessary preloaded data
    # Reload booking with associations if not already loaded
    booking =
      if Ecto.assoc_loaded?(booking.user) && Ecto.assoc_loaded?(booking.rooms) do
        booking
      else
        case Repo.get(Ysc.Bookings.Booking, booking.id)
             |> Repo.preload([:user, :rooms]) do
          nil ->
            raise ArgumentError, "Booking not found: #{booking.id}"

          loaded_booking ->
            loaded_booking
        end
      end

    # Validate required associations
    if is_nil(booking.user) do
      raise ArgumentError, "Booking missing user association: #{booking.id}"
    end

    # Format dates
    checkin_date = format_date(booking.checkin_date)
    checkout_date = format_date(booking.checkout_date)
    booking_date = format_datetime(booking.inserted_at)

    # Format money amounts
    total_amount = format_money(booking.total_price)

    # Get property name
    property_name = PropertyDisplay.short_name(booking.property)

    # Get booking mode description
    booking_mode_description = BookingModeDisplay.label(booking.booking_mode)

    # Get room names if applicable
    room_names =
      if booking.rooms && booking.rooms != [] do
        Enum.map_join(booking.rooms, ", ", & &1.name)
      else
        nil
      end

    # Calculate number of nights
    nights = Date.diff(booking.checkout_date, booking.checkin_date)

    # Check if this is a buyout booking
    is_buyout = BookingModeDisplay.buyout?(booking.booking_mode)

    %{
      first_name: member_greeting_name(booking.user),
      booking: %{
        reference_id: booking.reference_id,
        property: property_name,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0,
        booking_mode: booking_mode_description,
        room_names: room_names,
        nights: nights,
        is_buyout: is_buyout,
        booking_mode_raw: to_string(booking.booking_mode)
      },
      total_amount: total_amount,
      booking_date: booking_date,
      booking_url: booking_url(booking.id),
      cabin_email: Ysc.EmailConfig.booking_reply_to(booking.property)
    }
  end
end

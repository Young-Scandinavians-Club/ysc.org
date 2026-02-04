defmodule YscWeb.Emails.BookingConfirmation do
  @moduledoc """
  Email template for booking confirmation.

  Sends a confirmation email to users after their booking has been confirmed.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Repo

  def get_template_name() do
    "booking_confirmation"
  end

  def get_subject() do
    "Your booking is confirmed! 🏡"
  end

  def booking_url(booking_id) do
    YscWeb.Endpoint.url() <> "/bookings/#{booking_id}/receipt"
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
    property_name = get_property_name(booking.property)

    # Get booking mode description
    booking_mode_description =
      get_booking_mode_description(booking.booking_mode)

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
    # Use both boolean and string check for robustness across JSON serialization
    is_buyout =
      booking.booking_mode == :buyout ||
        booking_mode_description == "Property Buyout"

    %{
      first_name: booking.user.first_name || "Valued Member",
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
      booking_url: booking_url(booking.id)
    }
  end

  defp get_property_name(:clear_lake), do: "Clear Lake"
  defp get_property_name(:tahoe), do: "Tahoe"

  defp get_property_name(property) when is_atom(property),
    do: String.capitalize(to_string(property))

  defp get_property_name(property), do: to_string(property)

  defp get_booking_mode_description(:room), do: "Room Booking"
  defp get_booking_mode_description(:day), do: "Day Booking"
  defp get_booking_mode_description(:buyout), do: "Property Buyout"

  defp get_booking_mode_description(mode) when is_atom(mode),
    do: String.capitalize(to_string(mode))

  defp get_booking_mode_description(mode), do: to_string(mode)

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    # Convert to PST
    pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
  end

  defp format_money(%Money{} = money) do
    Money.to_string!(money,
      separator: ".",
      delimiter: ",",
      fractional_digits: 2
    )
  end

  defp format_money(_), do: "$0.00"
end

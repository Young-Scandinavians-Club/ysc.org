defmodule YscWeb.Emails.BookingCheckinReminder do
  @moduledoc """
  Email template for booking check-in reminder.

  Sent 2 days before check-in with door code, location, and check-in information.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_checkin_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Repo
  alias Ysc.Bookings
  alias YscWeb.Emails.OutageNotification

  def get_template_name() do
    "booking_checkin_reminder"
  end

  def get_subject(booking) do
    property_name = get_property_name(booking.property)
    "Your #{property_name} Check-In Instructions - YSC Cabin Stay 🏡"
  end

  def booking_url(booking_id) do
    YscWeb.Endpoint.url() <> "/bookings/#{booking_id}/receipt"
  end

  @doc """
  Prepares booking check-in reminder email data.

  ## Parameters:
  - `booking`: The booking with preloaded associations

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

    # Get active door code for the property
    door_code = Bookings.get_active_door_code(booking.property)

    # Get property information
    property_name = get_property_name(booking.property)
    property_address = get_property_address(booking.property)

    # Get cabin master information
    cabin_master = OutageNotification.get_cabin_master(booking.property)

    cabin_master_name =
      if cabin_master do
        "#{cabin_master.first_name || ""} #{cabin_master.last_name || ""}"
        |> String.trim()
      else
        nil
      end

    cabin_master_email =
      OutageNotification.get_cabin_master_email(booking.property)

    cabin_master_phone =
      if cabin_master, do: cabin_master.phone_number, else: nil

    # Format dates
    checkin_date = format_date(booking.checkin_date)
    checkout_date = format_date(booking.checkout_date)

    # Calculate days until check-in (using PST timezone)
    today_pst = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
    days_until_checkin = Date.diff(booking.checkin_date, today_pst)

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
    is_buyout = booking.booking_mode == :buyout

    # Normalize property to string for consistent comparison in templates
    # Email templates may serialize atoms to strings, so we normalize here
    property_string =
      case booking.property do
        atom when is_atom(atom) -> Atom.to_string(atom)
        string when is_binary(string) -> string
        _ -> to_string(booking.property)
      end

    %{
      first_name: booking.user.first_name || "Valued Member",
      door_code: if(door_code, do: door_code.code, else: "Not Available"),
      property: property_string,
      property_name: property_name,
      property_address: property_address,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      checkin_time: "3:00 PM",
      checkout_time: "11:00 AM",
      days_until_checkin: days_until_checkin,
      booking_reference_id: booking.reference_id,
      booking_mode: booking_mode_description,
      room_names: room_names,
      nights: nights,
      is_buyout: is_buyout,
      guests_count: booking.guests_count,
      children_count: booking.children_count || 0,
      cabin_master_name: cabin_master_name,
      cabin_master_email: cabin_master_email,
      cabin_master_phone: cabin_master_phone,
      booking_url: booking_url(booking.id)
    }
  end

  defp get_property_name(:clear_lake), do: "Clear Lake"
  defp get_property_name(:tahoe), do: "Tahoe"

  defp get_property_name(property) when is_atom(property),
    do: String.capitalize(to_string(property))

  defp get_property_name(property), do: to_string(property)

  defp get_property_address(:tahoe), do: "2685 Cedar Lane, Homewood, CA 96141"

  defp get_property_address(:clear_lake),
    do: "9325 Bass Road, Kelseyville, CA 95451"

  defp get_property_address(_), do: "Property Address"

  defp get_booking_mode_description(:room), do: "Room Booking"
  defp get_booking_mode_description(:day), do: "Day Booking"
  defp get_booking_mode_description(:buyout), do: "Property Buyout"

  defp get_booking_mode_description(mode) when is_atom(mode),
    do: String.capitalize(to_string(mode))

  defp get_booking_mode_description(mode), do: to_string(mode)

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end

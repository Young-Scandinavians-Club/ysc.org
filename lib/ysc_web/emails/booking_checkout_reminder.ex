defmodule YscWeb.Emails.BookingCheckoutReminder do
  @moduledoc """
  Email template for booking checkout reminder.

  Sent the evening before checkout with checkout instructions for the specific property.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_checkout_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Repo
  alias YscWeb.Emails.OutageNotification

  def get_template_name() do
    "booking_checkout_reminder"
  end

  def get_subject() do
    "Checkout Reminder - Your YSC Stay Ends Tomorrow 🏡"
  end

  def booking_url(booking_id) do
    YscWeb.Endpoint.url() <> "/bookings/#{booking_id}/receipt"
  end

  @doc """
  Prepares booking checkout reminder email data.

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
    checkout_date = format_date(booking.checkout_date)

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
      property: property_string,
      property_name: property_name,
      property_address: property_address,
      checkout_date: checkout_date,
      checkout_time: "11:00 AM",
      booking_reference_id: booking.reference_id,
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

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end

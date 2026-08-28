defmodule YscWeb.Sms.BookingCheckinReminder do
  @moduledoc """
  SMS template for booking check-in reminder.

  Sends a check-in reminder SMS with door code to users before their booking check-in.
  """

  alias Ysc.Bookings
  alias Ysc.Bookings.PropertyDisplay
  alias Ysc.Repo
  alias YscWeb.BookingDisplay
  alias YscWeb.Sms.Template

  @preview_keys [
    :first_name,
    :property_name,
    :checkin_date,
    :door_code,
    :checkin_time
  ]

  def preview_keys, do: @preview_keys

  @doc """
  Gets the template name.
  """
  def get_template_name do
    "booking_checkin_reminder"
  end

  @doc """
  Renders the SMS message body.

  ## Parameters:
  - `variables`: Map with booking data including door_code

  ## Returns:
  - String with SMS message body
  """
  def render(variables) do
    first_name = Template.first_name(variables)
    property_name = Map.get(variables, :property_name, "Property")
    checkin_date = Map.get(variables, :checkin_date, "")
    door_code = Map.get(variables, :door_code, "Not Available")

    checkin_time =
      Map.get(variables, :checkin_time, BookingDisplay.checkin_time_label())

    Template.format(
      "Hej #{first_name}! Your check-in at #{property_name} is on #{checkin_date} at #{checkin_time}. Your door code is: #{door_code}. See you soon!"
    )
  end

  @doc """
  Prepares booking check-in reminder SMS data.

  ## Parameters:
  - `booking`: The booking with preloaded associations

  ## Returns:
  - Map with all necessary data for the SMS template
  """
  def prepare_sms_data(booking) do
    # Validate input
    if is_nil(booking) do
      raise ArgumentError, "Booking cannot be nil"
    end

    if is_nil(booking.id) do
      raise ArgumentError, "Booking missing id: #{inspect(booking)}"
    end

    # Ensure we have all necessary preloaded data
    booking =
      if Ecto.assoc_loaded?(booking.user) do
        booking
      else
        case Repo.get(Ysc.Bookings.Booking, booking.id)
             |> Repo.preload([:user]) do
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

    # Get property name
    property_name = PropertyDisplay.short_name(booking.property)

    # Format dates
    checkin_date = format_date(booking.checkin_date)

    %{
      first_name: booking.user.first_name || "Valued Member",
      property_name: property_name,
      checkin_date: checkin_date,
      door_code: if(door_code, do: door_code.code, else: "Not Available"),
      checkin_time: BookingDisplay.checkin_time_label()
    }
  end

  defp format_date(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end
end

defmodule YscWeb.Emails.BookingCheckoutReminder do
  @moduledoc """
  Email template for booking checkout reminder.

  Sent the evening before checkout with checkout instructions for the specific property.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_checkout_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [absolute_url: 1, member_greeting_name: 1, format_date: 1]

  alias Ysc.Repo
  alias Ysc.Bookings.PropertyDisplay
  alias YscWeb.BookingDisplay
  alias YscWeb.Emails.OutageNotification

  def get_template_name() do
    "booking_checkout_reminder"
  end

  def get_subject() do
    "Leaving tomorrow — cabin check-out reminder 🏡"
  end

  def booking_url(booking_id) do
    absolute_url("/bookings/#{booking_id}/receipt")
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
    property_name = PropertyDisplay.short_name(booking.property)
    property_address = PropertyDisplay.address(booking.property)

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
      if cabin_master,
        do:
          Ysc.Extensions.PhoneNumber.format_for_display(
            cabin_master.phone_number
          ) ||
            cabin_master.phone_number,
        else: nil

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
      first_name: member_greeting_name(booking.user),
      property: property_string,
      property_name: property_name,
      property_address: property_address,
      checkout_date: checkout_date,
      checkout_time: BookingDisplay.checkout_time_label(),
      booking_reference_id: booking.reference_id,
      cabin_master_name: cabin_master_name,
      cabin_master_email: cabin_master_email,
      cabin_master_phone: cabin_master_phone,
      booking_url: booking_url(booking.id)
    }
  end
end

defmodule YscWeb.Emails.BookingModificationConfirmation do
  @moduledoc """
  Email template sent when a member modifies an existing booking.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_modification_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      member_greeting_name: 1,
      format_date: 1,
      format_money: 1
    ]

  alias Ysc.Repo
  alias Ysc.Bookings.PropertyDisplay

  def get_template_name, do: "booking_modification_confirmation"

  def get_subject, do: "Your reservation has been updated"

  def booking_url(booking_id),
    do: absolute_url("/bookings/#{booking_id}/receipt")

  @doc """
  Prepares booking modification confirmation email data.
  """
  def prepare_email_data(booking, previous_details) do
    if is_nil(booking) do
      raise ArgumentError, "Booking with user is required"
    end

    booking =
      if Ecto.assoc_loaded?(booking.user) && Ecto.assoc_loaded?(booking.rooms) do
        booking
      else
        Repo.get(Ysc.Bookings.Booking, booking.id)
        |> Repo.preload([:user, :rooms])
      end

    if is_nil(booking.user) do
      raise ArgumentError, "Booking with user is required"
    end

    property_name = PropertyDisplay.short_name(booking.property)

    room_names =
      if booking.rooms && booking.rooms != [] do
        Enum.map_join(booking.rooms, ", ", & &1.name)
      else
        nil
      end

    nights = Date.diff(booking.checkout_date, booking.checkin_date)

    previous = normalize_previous_details(previous_details)

    additional_payment =
      case previous.additional_payment do
        %Money{} = money ->
          if Money.positive?(money), do: format_money(money), else: nil

        _ ->
          nil
      end

    %{
      first_name: member_greeting_name(booking.user),
      booking: %{
        reference_id: booking.reference_id,
        property: property_name,
        checkin_date: format_date(booking.checkin_date),
        checkout_date: format_date(booking.checkout_date),
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0,
        room_names: room_names,
        nights: nights,
        total_amount: format_money(booking.total_price)
      },
      previous: %{
        checkin_date: format_date(previous.checkin_date),
        checkout_date: format_date(previous.checkout_date),
        guests_count: previous.guests_count,
        children_count: previous.children_count,
        total_amount: format_money(previous.total_price)
      },
      dates_changed:
        previous.checkin_date != booking.checkin_date or
          previous.checkout_date != booking.checkout_date,
      guests_changed:
        previous.guests_count != booking.guests_count or
          previous.children_count != (booking.children_count || 0),
      additional_payment: additional_payment,
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
          0,
      total_price:
        Map.get(details, :total_price) || Map.get(details, "total_price"),
      additional_payment:
        Map.get(details, :additional_payment) ||
          Map.get(details, "additional_payment")
    }
  end

end

defmodule Ysc.Bookings.ModificationDateAvailability do
  @moduledoc """
  Builds calendar constraints for member booking modifications.

  Generates date tooltip maps used by the date range picker to disable dates
  that would violate booking policy or availability for the existing booking.
  """

  import Ecto.Query, warn: false

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, Season, SeasonHelpers}
  alias Ysc.Repo

  @cabin_timezone "America/Los_Angeles"

  @doc """
  Returns calendar bounds and metadata for a booking modification picker.
  """
  def calendar_context(%Booking{} = booking) do
    booking = Repo.preload(booking, :rooms)
    today = today_pst()
    seasons = Bookings.list_seasons(booking.property)

    max_booking_date =
      SeasonHelpers.calculate_max_booking_date(booking.property, today, seasons)

    %{
      today: today,
      seasons: seasons,
      min_date: today,
      max_date: max_booking_date,
      max_nights: max_nights_for_checkin(booking, booking.checkin_date)
    }
  end

  @doc """
  Returns a map of ISO date strings to unavailability messages for check-in dates.
  """
  def checkin_date_tooltips(
        %Booking{} = booking,
        min_date,
        max_date,
        today,
        seasons
      ) do
    booking = Repo.preload(booking, :rooms)

    Date.range(min_date, max_date)
    |> Enum.reduce(%{}, fn date, acc ->
      case checkin_unavailability_reason(
             booking,
             date,
             min_date,
             max_date,
             today,
             seasons
           ) do
        nil -> acc
        reason -> Map.put(acc, Date.to_iso8601(date), reason)
      end
    end)
  end

  @doc """
  Returns a map of ISO date strings to unavailability messages for checkout dates
  given a selected check-in date.
  """
  def checkout_date_tooltips(
        %Booking{} = booking,
        checkin_date,
        max_date,
        today,
        seasons
      ) do
    booking = Repo.preload(booking, :rooms)

    if is_nil(checkin_date) or Date.compare(checkin_date, max_date) == :gt do
      %{}
    else
      max_nights = max_nights_for_checkin(booking, checkin_date)
      latest_checkout = min_date(Date.add(checkin_date, max_nights), max_date)
      first_checkout = Date.add(checkin_date, 1)

      if Date.compare(first_checkout, latest_checkout) == :gt do
        %{}
      else
        Date.range(first_checkout, latest_checkout)
        |> Enum.reduce(%{}, fn checkout, acc ->
          case checkout_unavailability_reason(
                 booking,
                 checkin_date,
                 checkout,
                 today,
                 seasons
               ) do
            nil -> acc
            reason -> Map.put(acc, Date.to_iso8601(checkout), reason)
          end
        end)
      end
    end
  end

  defp checkin_unavailability_reason(
         booking,
         date,
         min_date,
         max_date,
         today,
         seasons
       ) do
    cond do
      Date.compare(date, min_date) == :lt ->
        "Past dates cannot be selected"

      Date.compare(date, max_date) == :gt ->
        "Reservations are not open for this date yet"

      not SeasonHelpers.date_selectable?(booking.property, date, today, seasons) ->
        "Bookings for this season are not yet open"

      blackout_on_date?(booking.property, date) ->
        "This date is unavailable"

      buyout_on_date?(booking.property, date) and booking.booking_mode == :room ->
        "Full cabin buyout is already reserved on this date"

      not has_valid_checkout?(booking, date, max_date, today, seasons) ->
        availability_message(booking)

      true ->
        nil
    end
  end

  defp checkout_unavailability_reason(
         booking,
         checkin,
         checkout,
         today,
         seasons
       ) do
    cond do
      not SeasonHelpers.date_selectable?(
        booking.property,
        checkout,
        today,
        seasons
      ) ->
        "Bookings for this season are not yet open"

      weekend_invalid?(booking.property, checkin, checkout) ->
        "Bookings containing Saturday must also include Sunday (full weekend required)"

      true ->
        case modification_availability_error(booking, checkin, checkout) do
          nil -> nil
          reason -> availability_error_message(reason)
        end
    end
  end

  defp has_valid_checkout?(booking, checkin, max_date, today, seasons) do
    max_nights = max_nights_for_checkin(booking, checkin)
    latest_checkout = min_date(Date.add(checkin, max_nights), max_date)
    first_checkout = Date.add(checkin, 1)

    if Date.compare(first_checkout, latest_checkout) == :gt do
      false
    else
      Enum.any?(Date.range(first_checkout, latest_checkout), fn checkout ->
        not weekend_invalid?(booking.property, checkin, checkout) and
          is_nil(modification_availability_error(booking, checkin, checkout)) and
          SeasonHelpers.date_selectable?(
            booking.property,
            checkout,
            today,
            seasons
          )
      end)
    end
  end

  defp modification_availability_error(booking, checkin, checkout) do
    parsed = %{
      checkin_date: checkin,
      checkout_date: checkout,
      guests_count: booking.guests_count,
      children_count: booking.children_count || 0
    }

    case Bookings.validate_modification_availability(booking, parsed) do
      :ok ->
        if Bookings.has_blackout?(booking.property, checkin, checkout) do
          :blackout_conflict
        else
          nil
        end

      {:error, reason} ->
        reason
    end
  end

  defp weekend_invalid?(:tahoe, checkin, checkout) do
    if Date.compare(checkout, checkin) == :lt do
      false
    else
      reservation_dates = Date.range(checkin, checkout) |> Enum.to_list()

      has_saturday? =
        Enum.any?(reservation_dates, &(Date.day_of_week(&1, :monday) == 6))

      has_sunday? =
        Enum.any?(reservation_dates, &(Date.day_of_week(&1, :monday) == 7))

      has_saturday? and not has_sunday?
    end
  end

  defp weekend_invalid?(_property, _checkin, _checkout), do: false

  defp availability_message(%{booking_mode: :room}),
    do: "Your room is not available starting on this date"

  defp availability_message(%{booking_mode: :buyout}),
    do: "The property is not available starting on this date"

  defp availability_message(_),
    do: "The property is not available starting on this date"

  defp availability_error_message(:blackout_conflict),
    do: "The selected dates overlap with a blackout period"

  defp availability_error_message(:property_unavailable),
    do: "The selected dates or guest count are not available"

  defp availability_error_message(:room_unavailable),
    do: "Your room is not available for the selected dates"

  defp availability_error_message(:property_buyout_active),
    do: "The property has an active buyout for the selected dates"

  defp availability_error_message(:rooms_already_booked),
    do: "Rooms are already booked for the selected dates"

  defp availability_error_message(_), do: "The selected dates are not available"

  defp blackout_on_date?(property, date) do
    Bookings.has_blackout?(property, date, Date.add(date, 1))
  end

  defp buyout_on_date?(property, date) do
    alias Ysc.Bookings.PropertyInventory

    Repo.exists?(
      from pi in PropertyInventory,
        where: pi.property == ^property,
        where: pi.day == ^date,
        where: pi.buyout_held == true or pi.buyout_booked == true
    )
  end

  defp max_nights_for_checkin(booking, checkin_date) do
    season = Season.for_date(booking.property, checkin_date)
    Season.get_max_nights(season, booking.property)
  end

  defp min_date(left, right) do
    if Date.compare(left, right) == :gt, do: right, else: left
  end

  defp today_pst do
    DateTime.now!(@cabin_timezone) |> DateTime.to_date()
  rescue
    _ -> Date.utc_today()
  end
end

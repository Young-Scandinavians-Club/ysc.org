defmodule YscWeb.Api.BookingsJSON do
  @moduledoc """
  JSON rendering for booking API responses.
  """

  alias YscWeb.UserAvatar

  def index(%{bookings: bookings}) do
    %{data: Enum.map(bookings, &booking/1)}
  end

  def calendar(%{
        bookings: bookings,
        start_date: start_date,
        end_date: end_date
      }) do
    grouped =
      bookings
      |> Enum.flat_map(fn booking ->
        dates_in_range(
          booking.checkin_date,
          booking.checkout_date,
          start_date,
          end_date
        )
        |> Enum.map(fn date -> {Date.to_iso8601(date), booking} end)
      end)
      |> Enum.group_by(&elem(&1, 0), &booking(elem(&1, 1)))

    %{
      data: grouped,
      start_date: Date.to_iso8601(start_date),
      end_date: Date.to_iso8601(end_date)
    }
  end

  defp booking(b) do
    %{
      id: to_string(b.id),
      reference_id: b.reference_id,
      property: b.property,
      status: b.status,
      checkin_date: Date.to_iso8601(b.checkin_date),
      checkout_date: Date.to_iso8601(b.checkout_date),
      guests_count: b.guests_count,
      children_count: b.children_count,
      checked_in: b.checked_in || false,
      booking_mode: b.booking_mode,
      member: member(b.user),
      rooms: rooms(b.rooms),
      guests: guests(b.booking_guests),
      check_ins: check_ins(b.check_ins)
    }
  end

  defp member(nil), do: nil

  defp member(user) do
    %{
      id: to_string(user.id),
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      avatar_url:
        UserAvatar.url(
          Ysc.Avatars.resolve_user_avatar_url(user),
          user.id,
          user.most_connected_country
        )
    }
  end

  defp rooms(rooms) when is_list(rooms) do
    Enum.map(rooms, fn room ->
      %{
        id: to_string(room.id),
        name: room.name
      }
    end)
  end

  defp rooms(_), do: []

  defp guests(guests) when is_list(guests) do
    Enum.map(guests, fn guest ->
      %{
        id: to_string(guest.id),
        first_name: guest.first_name,
        last_name: guest.last_name,
        is_primary: guest.is_booking_user || false
      }
    end)
  end

  defp guests(_), do: []

  defp check_ins(check_ins) when is_list(check_ins) do
    Enum.map(check_ins, fn ci ->
      %{
        id: to_string(ci.id),
        checked_in_at:
          ci.checked_in_at && DateTime.to_iso8601(ci.checked_in_at),
        rules_agreed: ci.rules_agreed,
        vehicles: vehicles(ci)
      }
    end)
  end

  defp check_ins(_), do: []

  defp vehicles(%{check_in_vehicles: vehicles}) when is_list(vehicles) do
    Enum.map(vehicles, &vehicle/1)
  end

  defp vehicles(_), do: []

  defp vehicle(v) do
    %{
      id: to_string(v.id),
      type: v.type,
      color: v.color,
      make: v.make
    }
  end

  defp dates_in_range(checkin, checkout, range_start, range_end) do
    effective_start =
      if Date.compare(checkin, range_start) == :lt,
        do: range_start,
        else: checkin

    effective_end =
      if Date.compare(checkout, range_end) == :gt, do: range_end, else: checkout

    if Date.compare(effective_start, effective_end) in [:lt, :eq] do
      Date.range(effective_start, effective_end) |> Enum.to_list()
    else
      []
    end
  end
end

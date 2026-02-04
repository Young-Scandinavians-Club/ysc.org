defmodule YscWeb.TahoeStayingWithLive do
  use YscWeb, :live_view
  use YscNative, :live_view

  alias Ysc.Bookings

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    start_date = Date.add(today, -2)
    end_date = Date.add(today, 14)

    # Generate calendar dates
    calendar_dates = Date.range(start_date, end_date) |> Enum.to_list()

    # Fetch rooms for Tahoe property
    rooms =
      Bookings.list_rooms(:tahoe)
      |> Enum.filter(& &1.is_active)
      |> Enum.sort_by(& &1.name)

    # Fetch bookings for Tahoe property in date range
    bookings =
      Bookings.list_bookings(:tahoe, start_date, end_date,
        preload: [:rooms, :user, check_ins: :check_in_vehicles]
      )
      |> Enum.filter(fn booking ->
        # Only include room bookings (not buyout bookings)
        booking.status != :canceled &&
          booking.status != :refunded &&
          Ecto.assoc_loaded?(booking.rooms) && booking.rooms != []
      end)

    # Group bookings by room
    bookings_by_room =
      bookings
      |> Enum.reduce(%{}, fn booking, acc ->
        Enum.reduce(booking.rooms, acc, fn room, room_acc ->
          booking_data = %{
            id: booking.id,
            user_name: format_user_name(booking.user),
            checkin_date: booking.checkin_date,
            checkout_date: booking.checkout_date,
            checked_in: booking.checked_in || false,
            car_info: format_car_info(booking.check_ins),
            guests_count: booking.guests_count || 1,
            children_count: booking.children_count || 0
          }

          Map.update(room_acc, room.id, [booking_data], fn existing ->
            [booking_data | existing]
          end)
        end)
      end)

    # Format data for Swift component
    calendar_data_json =
      format_calendar_data(
        rooms,
        calendar_dates,
        bookings_by_room,
        today,
        start_date,
        end_date
      )

    # Format reservations data for table (flatten bookings with room names)
    reservations_data_json = format_reservations_data(bookings, rooms)

    # Ensure we have valid JSON
    if calendar_data_json == nil || calendar_data_json == "" do
      require Logger

      Logger.error(
        "[TahoeStayingWithLive] Failed to generate calendar_data_json"
      )
    end

    # Format date range for display
    date_range_text = format_date_range_text(start_date, end_date)

    socket =
      socket
      |> assign(:calendar_data_json, calendar_data_json)
      |> assign(:reservations_data_json, reservations_data_json)
      # Default to calendar tab
      |> assign(:tab, "1")
      |> assign(:date_range_text, date_range_text)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    # Parse URI to get current path and send to SwiftUI
    parsed_uri = URI.parse(uri)
    current_path = parsed_uri.path || "/"

    # Send current path to SwiftUI via push_event
    socket =
      socket
      |> Phoenix.LiveView.push_event("current_path", %{path: current_path})

    # Restore tab state from query params
    tab = Map.get(params, "tab", socket.assigns.tab || "1")
    socket = assign(socket, :tab, tab)

    {:noreply, socket}
  end

  @impl true
  def handle_event("tab-changed", %{"selection" => tab}, socket) do
    # Only update if tab actually changed
    if tab != socket.assigns.tab do
      # Update URL with the new tab (handle_params will update the assign)
      socket =
        socket
        |> push_patch(
          to: ~p"/bookings/tahoe/staying-with?tab=#{tab}",
          replace: true
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp format_user_name(user) do
    cond do
      user.first_name && user.last_name ->
        "#{user.first_name} #{user.last_name}"

      user.first_name ->
        user.first_name

      user.last_name ->
        user.last_name

      user.email ->
        user.email

      true ->
        "Guest"
    end
  end

  defp format_car_info(check_ins) when is_list(check_ins) do
    check_ins
    |> Enum.filter(fn check_in ->
      Ecto.assoc_loaded?(check_in.check_in_vehicles) &&
        check_in.check_in_vehicles != []
    end)
    |> Enum.flat_map(fn check_in ->
      Enum.map(check_in.check_in_vehicles, fn vehicle ->
        parts = [vehicle.make, vehicle.type, vehicle.color]
        parts = Enum.filter(parts, &(&1 && &1 != ""))
        Enum.join(parts, " ")
      end)
    end)
    |> case do
      [] -> nil
      [car_info] -> car_info
      car_infos -> Enum.join(car_infos, ", ")
    end
  end

  defp format_car_info(_), do: nil

  defp format_calendar_data(
         rooms,
         calendar_dates,
         bookings_by_room,
         today,
         start_date,
         end_date
       ) do
    # Convert dates to ISO8601 strings
    date_to_string = fn date -> Date.to_iso8601(date) end

    # Format rooms - convert ULID to string for JSON
    formatted_rooms =
      Enum.map(rooms, fn room ->
        %{
          id: to_string(room.id),
          name: room.name
        }
      end)

    # Format calendar dates
    formatted_dates = Enum.map(calendar_dates, date_to_string)

    # Format bookings by room - convert ULID room_id to string
    formatted_bookings_by_room =
      bookings_by_room
      |> Enum.map(fn {room_id, bookings} ->
        formatted_bookings =
          Enum.map(bookings, fn booking ->
            %{
              id: to_string(booking.id),
              userName: booking.user_name,
              checkinDate: date_to_string.(booking.checkin_date),
              checkoutDate: date_to_string.(booking.checkout_date),
              checkedIn: booking.checked_in,
              carInfo: booking.car_info,
              guestsCount: booking.guests_count,
              childrenCount: booking.children_count
            }
          end)

        # Convert room_id (ULID) to string for map key
        room_id_str =
          if is_binary(room_id), do: room_id, else: to_string(room_id)

        {room_id_str, formatted_bookings}
      end)
      |> Map.new()

    # Build the data structure
    calendar_data = %{
      rooms: formatted_rooms,
      calendarDates: formatted_dates,
      bookingsByRoom: formatted_bookings_by_room,
      today: date_to_string.(today),
      calendarStartDate: date_to_string.(start_date),
      calendarEndDate: date_to_string.(end_date)
    }

    # Encode to JSON
    Jason.encode!(calendar_data)
  end

  defp format_reservations_data(bookings, rooms) do
    # Create a map of room_id -> room_name for quick lookup
    room_map =
      rooms
      |> Enum.map(fn room -> {room.id, room.name} end)
      |> Map.new()

    # Flatten bookings - each booking can have multiple rooms, so create a row per room
    reservations =
      bookings
      |> Enum.flat_map(fn booking ->
        # Get room names for this booking
        room_names =
          booking.rooms
          |> Enum.map(fn room -> Map.get(room_map, room.id, "Unknown") end)
          |> Enum.sort()
          |> Enum.join(", ")

        # Create one reservation entry per booking (with all rooms listed)
        [
          %{
            id: to_string(booking.id),
            userName: format_user_name(booking.user),
            roomNames: room_names,
            checkinDate: Date.to_iso8601(booking.checkin_date),
            checkoutDate: Date.to_iso8601(booking.checkout_date),
            checkedIn: booking.checked_in || false,
            carInfo: format_car_info(booking.check_ins),
            guestsCount: booking.guests_count || 1,
            childrenCount: booking.children_count || 0
          }
        ]
      end)
      |> Enum.sort_by(& &1.checkinDate)

    # Build the data structure
    reservations_data = %{
      reservations: reservations
    }

    # Encode to JSON
    Jason.encode!(reservations_data)
  end

  defp format_date_range_text(start_date, end_date) do
    # Format: "MMMM dd - MMMM dd, yyyy" (e.g., "January 08 - January 22, 2025")
    start_str = Calendar.strftime(start_date, "%B %d")
    end_str = Calendar.strftime(end_date, "%B %d, %Y")
    "#{start_str} - #{end_str}"
  end
end

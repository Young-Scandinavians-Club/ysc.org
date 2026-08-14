defmodule Ysc.Bookings.PricingHelpers do
  @moduledoc """
  Shared helper functions for booking price calculations.

  Provides utilities for:
  - Checking if price calculation is ready
  - Calculating prices for different booking modes
  - Handling price breakdowns
  - Returning consistent socket assigns
  """

  alias Ysc.Bookings
  alias Ysc.Bookings.Entitlements
  import Phoenix.Component, only: [assign: 2]

  @doc """
  Checks if the socket has all required information to calculate a price.

  ## Parameters
  - `socket`: The LiveView socket
  - `property`: The property type (:tahoe or :clear_lake)

  ## Returns
  - `true` if ready to calculate price
  - `false` otherwise
  """
  def ready_for_price_calculation?(socket, _property) do
    checkin_date = Map.get(socket.assigns, :checkin_date)
    checkout_date = Map.get(socket.assigns, :checkout_date)
    has_dates = !is_nil(checkin_date) && !is_nil(checkout_date)

    if has_dates do
      booking_mode = Map.get(socket.assigns, :selected_booking_mode)

      case booking_mode do
        :buyout ->
          true

        :room ->
          # For Tahoe room bookings, need at least one room selected
          # Check both single room selection and multiple room selection
          selected_room_id = Map.get(socket.assigns, :selected_room_id)
          selected_room_ids = Map.get(socket.assigns, :selected_room_ids)

          !is_nil(selected_room_id) ||
            (!is_nil(selected_room_ids) && is_list(selected_room_ids) &&
               selected_room_ids != [])

        :day ->
          # For Clear Lake day bookings, need guests count
          guests_count = Map.get(socket.assigns, :guests_count)
          !is_nil(guests_count) && is_integer(guests_count) && guests_count > 0

        _ ->
          false
      end
    else
      false
    end
  end

  @doc """
  Calculates the booking price and returns a function that updates the socket.

  Handles different booking modes:
  - `:buyout` - Full cabin buyout
  - `:room` - Individual room(s) booking (Tahoe)
  - `:day` - Per guest per day booking (Clear Lake)

  ## Parameters
  - `socket`: The LiveView socket
  - `property`: The property type (:tahoe or :clear_lake)
  - `opts`: Optional keyword list with:
    - `parse_guests_fn`: Function to parse guests count (default: identity)
    - `parse_children_fn`: Function to parse children count (default: identity)
    - `can_select_multiple_rooms_fn`: Function to check if multiple rooms allowed (default: always false)

  ## Returns
  - Updated socket with `calculated_price`, `price_breakdown`, and `price_error` assigns
  """
  def calculate_price_if_ready(socket, property, opts \\ []) do
    if ready_for_price_calculation?(socket, property) do
      parse_guests_fn =
        Keyword.get(opts, :parse_guests_fn, &Function.identity/1)

      parse_children_fn =
        Keyword.get(opts, :parse_children_fn, &Function.identity/1)

      can_select_multiple_rooms_fn =
        Keyword.get(opts, :can_select_multiple_rooms_fn, fn _ -> false end)

      guests_count = parse_guests_fn.(Map.get(socket.assigns, :guests_count, 1))

      children_count =
        parse_children_fn.(Map.get(socket.assigns, :children_count, 0))

      case socket.assigns.selected_booking_mode do
        :buyout ->
          calculate_buyout_price(socket, property, guests_count, children_count)

        :room ->
          calculate_room_price(
            socket,
            property,
            guests_count,
            children_count,
            can_select_multiple_rooms_fn
          )

        :day ->
          calculate_day_price(socket, property, guests_count)

        _ ->
          assign_error(socket, "Invalid booking mode")
      end
    else
      assign(socket,
        calculated_price: nil,
        price_breakdown: nil,
        price_error: nil
      )
    end
  end

  # Calculate price for buyout mode
  @dialyzer {:nowarn_function, calculate_buyout_price: 4}
  defp calculate_buyout_price(socket, property, guests_count, children_count) do
    case Bookings.calculate_booking_price(
           property,
           socket.assigns.checkin_date,
           socket.assigns.checkout_date,
           :buyout,
           guests_count: guests_count,
           children_count: children_count,
           seasons: Map.get(socket.assigns, :seasons)
         ) do
      {:ok, base_price, base_breakdown} ->
        {socket, calculated_price, price_breakdown} =
          apply_entitlement_discount_to_preview(
            socket,
            property,
            :buyout,
            base_price,
            Map.merge(base_breakdown, %{
              guests_count: guests_count,
              children_count: children_count
            }),
            guests_count: guests_count,
            children_count: children_count,
            room_ids: []
          )

        assign(socket,
          calculated_price: calculated_price,
          price_breakdown: price_breakdown,
          price_error: nil
        )

      {:error, reason} ->
        assign_error(socket, "Unable to calculate price: #{inspect(reason)}")
    end
  end

  # Calculate price for room mode (Tahoe)
  @dialyzer {:nowarn_function, calculate_room_price: 5}
  defp calculate_room_price(
         socket,
         property,
         guests_count,
         children_count,
         can_select_multiple_rooms_fn
       ) do
    room_ids = get_selected_room_ids(socket, can_select_multiple_rooms_fn)

    if room_ids == [] do
      assign_error(socket, "Please select at least one room")
    else
      room_count = length(room_ids)

      billable_people =
        calculate_billable_people(
          socket,
          room_ids,
          guests_count,
          children_count
        )

      case Bookings.calculate_booking_price(
             property,
             socket.assigns.checkin_date,
             socket.assigns.checkout_date,
             :room,
             room_id: List.first(room_ids),
             guests_count: billable_people,
             children_count: children_count,
             use_actual_guests: true
           ) do
        {:ok, base_price, base_breakdown} ->
          # Ensure billable_people is set correctly in the breakdown
          # This is important for display - it should reflect the minimum occupancy calculation
          # Check if minimum occupancy pricing is being applied (billable_people > actual guests_count)
          using_minimum_pricing = billable_people > guests_count

          merged_breakdown =
            base_breakdown
            |> Map.merge(%{
              room_count: room_count,
              guests_count: guests_count,
              billable_people: billable_people,
              children_count: children_count,
              using_minimum_pricing: using_minimum_pricing
            })
            # Explicitly set billable_people to ensure it's not overridden
            |> Map.put(:billable_people, billable_people)
            |> Map.put(:using_minimum_pricing, using_minimum_pricing)

          {socket, calculated_price, price_breakdown} =
            apply_entitlement_discount_to_preview(
              socket,
              property,
              :room,
              base_price,
              merged_breakdown,
              guests_count: billable_people,
              children_count: children_count,
              room_ids: room_ids
            )

          assign(socket,
            calculated_price: calculated_price,
            price_breakdown: price_breakdown,
            price_error: nil
          )

        {:error, reason} ->
          assign_error(socket, "Unable to calculate price: #{inspect(reason)}")
      end
    end
  end

  # Calculate price for day mode (Clear Lake)
  @dialyzer {:nowarn_function, calculate_day_price: 3}
  defp calculate_day_price(socket, property, guests_count) do
    case Bookings.calculate_booking_price(
           property,
           socket.assigns.checkin_date,
           socket.assigns.checkout_date,
           :day,
           guests_count: guests_count,
           seasons: Map.get(socket.assigns, :seasons)
         ) do
      {:ok, base_price, base_breakdown} ->
        {socket, calculated_price, price_breakdown} =
          apply_entitlement_discount_to_preview(
            socket,
            property,
            :day,
            base_price,
            Map.merge(base_breakdown, %{
              guests_count: guests_count
            }),
            guests_count: guests_count,
            children_count: 0,
            room_ids: []
          )

        assign(socket,
          calculated_price: calculated_price,
          price_breakdown: price_breakdown,
          price_error: nil
        )

      {:error, reason} ->
        assign_error(socket, "Unable to calculate price: #{inspect(reason)}")
    end
  end

  @doc """
  Clears cached entitlement hold/user lookups so the next price preview refetches.
  """
  def invalidate_entitlement_pricing_cache(socket) do
    assign(socket, entitlement_pricing_context: nil)
  end

  # Helper to assign error state
  defp assign_error(socket, error_message) do
    assign(socket,
      calculated_price: nil,
      price_breakdown: nil,
      price_error: error_message
    )
  end

  defp apply_entitlement_discount_to_preview(
         socket,
         property,
         booking_mode,
         gross,
         breakdown,
         opts
       ) do
    user = socket.assigns[:current_user]

    if user do
      {socket, pricing_context} =
        ensure_entitlement_pricing_context(socket, user.id)

      {final_total, _items, subtotal, discount, ent_id} =
        Entitlements.apply_best_entitlement(
          user.id,
          property,
          booking_mode,
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          gross,
          %{},
          Keyword.merge(opts, pricing_context: pricing_context)
        )

      bd =
        Map.merge(breakdown, %{
          entitlement_subtotal: subtotal,
          entitlement_discount: discount,
          applied_entitlement_id: ent_id
        })

      {socket, final_total, bd}
    else
      {socket, gross, breakdown}
    end
  end

  defp ensure_entitlement_pricing_context(socket, user_id) do
    exclude_booking_id =
      Map.get(socket.assigns, :booking_id) ||
        Map.get(socket.assigns, :hold_booking_id)

    case socket.assigns[:entitlement_pricing_context] do
      %{
        user_id: ^user_id,
        exclude_booking_id: ^exclude_booking_id
      } = pricing_context ->
        {socket, pricing_context}

      _ ->
        pricing_context =
          Entitlements.pricing_context(user_id,
            exclude_booking_id: exclude_booking_id
          )

        {assign(socket, entitlement_pricing_context: pricing_context),
         pricing_context}
    end
  end

  defp get_selected_room_ids(socket, can_select_multiple_rooms_fn) do
    if can_select_multiple_rooms_fn.(socket.assigns) do
      socket.assigns.selected_room_ids || []
    else
      if socket.assigns.selected_room_id,
        do: [socket.assigns.selected_room_id],
        else: []
    end
  end

  defp calculate_billable_people(socket, room_ids, guests_count, children_count) do
    room_count = length(room_ids)

    if room_count > 1 do
      calculate_billable_people_multiple_rooms(
        socket,
        room_ids,
        guests_count,
        children_count
      )
    else
      calculate_billable_people_single_room(
        socket,
        List.first(room_ids),
        guests_count,
        children_count
      )
    end
  end

  defp calculate_billable_people_multiple_rooms(
         socket,
         room_ids,
         guests_count,
         children_count
       ) do
    rooms_by_id = rooms_by_id(socket, room_ids)

    room_minimums =
      room_ids
      |> Enum.map(fn room_id ->
        case lookup_room(rooms_by_id, room_id) do
          nil -> 1
          r -> Map.get(r, :min_billable_occupancy) || 1
        end
      end)

    total_min_occupancy =
      if Enum.empty?(room_minimums), do: 1, else: Enum.sum(room_minimums)

    total_people = guests_count + children_count

    if total_people >= total_min_occupancy do
      guests_count
    else
      min_adults_needed = max(0, total_min_occupancy - children_count)
      max(guests_count, min_adults_needed)
    end
  end

  defp calculate_billable_people_single_room(
         socket,
         room_id,
         guests_count,
         children_count
       ) do
    rooms_by_id = rooms_by_id(socket, [room_id])

    case lookup_room(rooms_by_id, room_id) do
      nil ->
        guests_count

      room ->
        min_occupancy = room.min_billable_occupancy || 1
        min_adults_needed = max(0, min_occupancy - children_count)
        max(guests_count, min_adults_needed)
    end
  end

  defp rooms_by_id(socket, room_ids) do
    available_rooms = socket.assigns[:available_rooms] || []

    available_by_id =
      Enum.reduce(available_rooms, %{}, fn room, acc ->
        acc
        |> Map.put(room.id, room)
        |> Map.put(to_string(room.id), room)
      end)

    missing_ids =
      room_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reject(fn room_id ->
        Map.has_key?(available_by_id, room_id) or
          Map.has_key?(available_by_id, to_string(room_id))
      end)

    fetched_by_id =
      case Bookings.list_rooms_by_ids(missing_ids) do
        [] ->
          %{}

        rooms ->
          Enum.reduce(rooms, %{}, fn room, acc ->
            acc
            |> Map.put(room.id, room)
            |> Map.put(to_string(room.id), room)
          end)
      end

    Map.merge(available_by_id, fetched_by_id)
  end

  defp lookup_room(rooms_by_id, room_id) do
    Map.get(rooms_by_id, room_id) || Map.get(rooms_by_id, to_string(room_id))
  end
end

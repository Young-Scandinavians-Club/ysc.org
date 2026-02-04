defmodule Ysc.Bookings.BookingLocker do
  @moduledoc """
  Provides atomic booking operations with proper locking to prevent race conditions.

  This module ensures that inventory availability checks and booking creation happen
  atomically within a single database transaction with proper row-level locking.

  ## Booking Flows

  ### A) Buyout (Tahoe summer or Clear Lake, when allowed)
  - Locks property_inventory rows for all days
  - Ensures: buyout_* false AND (for Tahoe) no room_inventory held/booked
  - Marks buyout_held = true, creates booking in :hold
  - After payment → flip to buyout_booked = true and set booking :complete
  - On failure/expiry → reset buyout_held = false, set booking :expired|:canceled

  ### B) Tahoe per-room
  - Locks room_inventory for the target room across the range
  - Locks property_inventory to check buyout flags
  - Ensures room not held/booked and property no buyout
  - Sets held = true on room_inventory; creates booking :hold
  - Confirm → booked = true (clear held)
  - Release → clear held

  ### C) Clear Lake per-guest
  - Locks property_inventory for all days
  - Ensures buyout flags false and capacity_booked + capacity_held + guests <= capacity_total
  - Increments capacity_held; creates booking :hold
  - Confirm → decrement held, increment booked
  - Release → decrement held
  """

  import Ecto.Query, warn: false
  import RetryOn, only: [retry_on_stale: 2]
  require Logger

  alias Ysc.Repo

  alias Ysc.Bookings.{
    Booking,
    PropertyInventory,
    RoomInventory,
    Room
  }

  alias Ysc.Bookings

  @hold_duration_minutes 30

  # Default capacity per property (can be overridden by season policy)
  @default_capacity_clear_lake 12
  # Tahoe uses room-level inventory, not property capacity
  @default_capacity_tahoe 0

  @doc """
  Atomically creates a buyout booking with proper inventory locking.

  Uses optimistic locking with automatic retry on stale errors.

  ## Parameters:
  - `user_id`: The user making the booking
  - `property`: The property (:tahoe or :clear_lake)
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `guests_count`: Number of guests
  - `opts`: Additional options (e.g., `hold_duration_minutes`)

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure (including `:stale_inventory` if retries exhausted)
  """
  def create_buyout_booking(
        user_id,
        property,
        checkin_date,
        checkout_date,
        guests_count,
        opts \\ []
      ) do
    # Use retry_on_stale to handle optimistic locking conflicts
    # This will automatically retry if Ecto.StaleEntryError is raised
    retry_on_stale(
      fn attempt ->
        if attempt > 1 do
          Logger.info("Retrying buyout booking after stale error",
            user_id: user_id,
            property: property,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            attempt: attempt
          )
        end

        do_create_buyout_booking(
          user_id,
          property,
          checkin_date,
          checkout_date,
          guests_count,
          opts
        )
      end,
      max_attempts: 3,
      delay_ms: 100
    )
  end

  defp do_create_buyout_booking(
         user_id,
         property,
         checkin_date,
         checkout_date,
         guests_count,
         opts
       ) do
    hold_duration =
      Keyword.get(opts, :hold_duration_minutes, @hold_duration_minutes)

    hold_expires_at = DateTime.add(DateTime.utc_now(), hold_duration, :minute)

    Repo.transaction(fn ->
      days =
        Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      # Ensure property_inventory rows exist
      ensure_property_inventory_for_days(property, days)

      # Fetch property_inventory rows for all days (optimistic locking - no FOR UPDATE)
      prop_inv = fetch_property_inventory(property, checkin_date, checkout_date)

      # Validate buyout availability
      validate_buyout_availability(
        property,
        checkin_date,
        checkout_date,
        prop_inv
      )

      # Update all property_inventory rows using optimistic locking
      update_property_inventory_for_buyout(prop_inv, property)

      # Calculate pricing
      {total_price, pricing_items} =
        calculate_buyout_pricing(
          property,
          checkin_date,
          checkout_date,
          guests_count
        )

      # Create booking in :hold
      booking =
        create_buyout_booking_hold(
          user_id,
          property,
          checkin_date,
          checkout_date,
          guests_count,
          hold_expires_at,
          total_price,
          pricing_items
        )

      booking
    end)
    |> case do
      {:ok, booking} ->
        # Emit telemetry event for booking creation
        :telemetry.execute(
          [:ysc, :bookings, :booking_created],
          %{count: 1},
          %{
            booking_id: booking.id,
            property: to_string(booking.property),
            booking_mode: to_string(booking.booking_mode),
            user_id: user_id
          }
        )

        {:ok, booking}

      error ->
        error
    end
  end

  defp ensure_property_inventory_for_days(property, days) do
    for day <- days do
      capacity_total = get_property_capacity_for_date(property, day)
      ensure_property_inventory_row(property, day, capacity_total)
    end
  end

  defp fetch_property_inventory(property, checkin_date, checkout_date) do
    Repo.all(
      from pi in PropertyInventory,
        where:
          pi.property == ^property and pi.day >= ^checkin_date and
            pi.day < ^checkout_date
    )
  end

  defp validate_buyout_availability(
         property,
         checkin_date,
         checkout_date,
         prop_inv
       ) do
    # If Tahoe has rooms, check room activity
    if property == :tahoe do
      validate_tahoe_rooms_available(property, checkin_date, checkout_date)
    end

    # Validate no blackout overlap
    if Bookings.has_blackout?(property, checkin_date, checkout_date) do
      Repo.rollback({:error, :blackout_conflict})
    end

    # Validate no buyout held/booked and no per-guest counts (Clear Lake)
    invalid_days =
      Enum.filter(prop_inv, fn pi ->
        pi.buyout_held == true or
          pi.buyout_booked == true or
          (property == :clear_lake and
             (pi.capacity_held > 0 or pi.capacity_booked > 0))
      end)

    if invalid_days != [] do
      Repo.rollback({:error, :property_unavailable})
    end
  end

  defp validate_tahoe_rooms_available(property, checkin_date, checkout_date) do
    room_inv =
      Repo.all(
        from ri in RoomInventory,
          join: r in Room,
          on: ri.room_id == r.id,
          where:
            r.property == ^property and ri.day >= ^checkin_date and
              ri.day < ^checkout_date
      )

    # Validate no held/booked rooms for any day
    blocked_days =
      Enum.filter(room_inv, fn ri -> ri.held == true or ri.booked == true end)

    if blocked_days != [] do
      Repo.rollback({:error, :rooms_already_booked})
    end
  end

  defp update_property_inventory_for_buyout(prop_inv, property) do
    # IMPORTANT: We must update ALL rows or the booking fails (no partial bookings)
    # For composite primary keys, we manually check lock_version in the WHERE clause
    # AND include availability checks to ensure optimistic locking works correctly
    update_results =
      Enum.map(prop_inv, fn pi ->
        # Use update_all with explicit lock_version check AND availability validation
        # This ensures optimistic locking works correctly - if lock_version changed or
        # availability changed, the update will affect 0 rows
        {count, _} =
          Repo.update_all(
            from(pi2 in PropertyInventory,
              where:
                pi2.property == type(^property, Ysc.Bookings.BookingProperty) and
                  pi2.day == ^pi.day and
                  pi2.lock_version == ^pi.lock_version and
                  pi2.buyout_held == false and pi2.buyout_booked == false and
                  (type(^property, Ysc.Bookings.BookingProperty) != :clear_lake or
                     (pi2.capacity_held == 0 and pi2.capacity_booked == 0))
            ),
            set: [
              buyout_held: true,
              lock_version: pi.lock_version + 1,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        if count == 1 do
          {:ok, :updated}
        else
          {:error, :stale_inventory}
        end
      end)

    # Check if all updates succeeded
    failed_updates = Enum.filter(update_results, &match?({:error, _}, &1))

    if failed_updates != [] do
      # At least one update failed - this means another transaction modified the inventory
      # Raise Ecto.StaleEntryError so retry_on_stale can catch it and retry
      raise Ecto.StaleEntryError, struct: List.first(prop_inv), action: :update
    end
  end

  defp calculate_buyout_pricing(
         property,
         checkin_date,
         checkout_date,
         guests_count
       ) do
    case Bookings.calculate_booking_price(
           property,
           checkin_date,
           checkout_date,
           :buyout,
           guests_count: guests_count,
           children_count: 0
         ) do
      {:ok, total, _breakdown} ->
        nights = Date.diff(checkout_date, checkin_date)

        price_per_night =
          if nights > 0, do: Money.div(total, nights) |> elem(1), else: total

        items = %{
          "type" => "buyout",
          "nights" => nights,
          "price_per_night" => %{
            "amount" => Decimal.to_string(price_per_night.amount),
            "currency" => to_string(price_per_night.currency)
          },
          "total" => %{
            "amount" => Decimal.to_string(total.amount),
            "currency" => to_string(total.currency)
          }
        }

        {total, items}

      {:error, _reason} ->
        {nil, nil}
    end
  end

  defp create_buyout_booking_hold(
         user_id,
         property,
         checkin_date,
         checkout_date,
         guests_count,
         hold_expires_at,
         total_price,
         pricing_items
       ) do
    attrs = %{
      property: property,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      booking_mode: :buyout,
      guests_count: guests_count,
      user_id: user_id,
      status: :hold,
      hold_expires_at: hold_expires_at,
      total_price: total_price,
      pricing_items: pricing_items
    }

    case %Booking{}
         |> Booking.changeset(attrs, skip_validation: true)
         |> Repo.insert() do
      {:ok, booking} ->
        booking

      {:error, changeset} ->
        Repo.rollback({:error, changeset})
    end
  end

  @doc """
  Atomically creates a booking with one or more rooms with proper inventory locking.

  ## Parameters:
  - `user_id`: The user making the booking
  - `room_ids`: List of room IDs to book (can be single room or multiple), or a single room_id (binary)
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `guests_count`: Number of guests
  - `opts`: Additional options (e.g., `hold_duration_minutes`, `children_count`)

  ## Returns:
  - `{:ok, %Booking{}}` on success (with rooms preloaded)
  - `{:error, reason}` on failure

  ## Notes:
  - All rooms must be available for the booking to succeed
  - Creates a single booking with multiple rooms (many-to-many relationship)
  - All rooms are locked atomically in a single transaction
  """
  def create_room_booking(
        user_id,
        room_ids,
        checkin_date,
        checkout_date,
        guests_count,
        opts \\ []
      )

  def create_room_booking(
        user_id,
        room_ids,
        checkin_date,
        checkout_date,
        guests_count,
        opts
      )
      when is_list(room_ids) do
    retry_on_stale(
      fn attempt ->
        if attempt > 1 do
          Logger.info("Retrying room booking after stale error",
            user_id: user_id,
            room_ids: room_ids,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            attempt: attempt
          )
        end

        do_create_room_booking(
          user_id,
          room_ids,
          checkin_date,
          checkout_date,
          guests_count,
          opts
        )
      end,
      max_attempts: 3,
      delay_ms: 100
    )
  end

  # Backward compatibility: single room_id as string/binary
  def create_room_booking(
        user_id,
        room_id,
        checkin_date,
        checkout_date,
        guests_count,
        opts
      )
      when is_binary(room_id) do
    create_room_booking(
      user_id,
      [room_id],
      checkin_date,
      checkout_date,
      guests_count,
      opts
    )
  end

  defp do_create_room_booking(
         user_id,
         room_ids,
         checkin_date,
         checkout_date,
         guests_count,
         opts
       )
       when is_list(room_ids) do
    children_count = Keyword.get(opts, :children_count, 0)

    hold_duration =
      Keyword.get(opts, :hold_duration_minutes, @hold_duration_minutes)

    hold_expires_at = DateTime.add(DateTime.utc_now(), hold_duration, :minute)

    if room_ids == [] do
      {:error, :no_rooms_provided}
    else
      Repo.transaction(fn ->
        days =
          Date.range(checkin_date, Date.add(checkout_date, -1))
          |> Enum.to_list()

        # Get all rooms to determine property (must all be same property)
        rooms = fetch_and_validate_rooms(room_ids)
        property = rooms |> List.first() |> Map.get(:property)

        # Ensure inventory rows exist
        ensure_room_booking_inventory(property, room_ids, days)

        # Fetch inventory rows (optimistic locking - no FOR UPDATE)
        room_inv = fetch_room_inventory(room_ids, checkin_date, checkout_date)

        prop_inv =
          fetch_property_inventory(property, checkin_date, checkout_date)

        # Validate availability
        validate_room_booking_availability(prop_inv, room_inv)

        # Update all room_inventory rows using optimistic locking
        update_room_inventory_for_booking(room_inv)

        # Calculate pricing for all rooms combined
        case calculate_room_booking_pricing(
               rooms,
               checkin_date,
               checkout_date,
               guests_count,
               children_count
             ) do
          {total_price, pricing_items}
          when not is_nil(total_price) and not is_nil(pricing_items) ->
            # Create booking :hold with all rooms
            hold_params = %{
              user_id: user_id,
              property: property,
              checkin_date: checkin_date,
              checkout_date: checkout_date,
              guests_count: guests_count,
              children_count: children_count,
              hold_expires_at: hold_expires_at,
              total_price: total_price,
              pricing_items: pricing_items,
              rooms: rooms
            }

            create_room_booking_hold(hold_params)

          {nil, _} ->
            {:error, :pricing_calculation_failed}

          {_, nil} ->
            {:error, :pricing_calculation_failed}
        end
      end)
      |> case do
        {:ok, %Booking{} = booking} ->
          # Emit telemetry event for booking creation
          :telemetry.execute(
            [:ysc, :bookings, :booking_created],
            %{count: 1},
            %{
              booking_id: booking.id,
              property: to_string(booking.property),
              booking_mode: "room",
              user_id: user_id
            }
          )

          {:ok, booking}

        {:ok, {:error, reason}} ->
          {:error, reason}

        error ->
          error
      end
    end
  end

  defp fetch_and_validate_rooms(room_ids) do
    # Batch load all rooms in a single query to avoid N+1
    rooms =
      from(r in Room, where: r.id in ^room_ids)
      |> Repo.all()

    # Verify all requested rooms were found (matching Repo.get! behavior)
    if length(rooms) != length(room_ids) do
      found_ids = Enum.map(rooms, & &1.id)
      missing_ids = room_ids -- found_ids
      Repo.rollback({:error, {:rooms_not_found, missing_ids}})
    end

    # Verify all rooms are from the same property
    property = rooms |> List.first() |> Map.get(:property)

    if Enum.any?(rooms, &(&1.property != property)) do
      Repo.rollback({:error, :rooms_must_be_same_property})
    end

    rooms
  end

  defp ensure_room_booking_inventory(property, room_ids, days) do
    # Ensure property_inventory rows exist (for buyout check)
    for day <- days do
      capacity_total = get_property_capacity_for_date(property, day)
      ensure_property_inventory_row(property, day, capacity_total)
    end

    # Ensure room_inventory rows exist for all rooms
    for day <- days, room_id <- room_ids do
      ensure_room_inventory_row(room_id, day)
    end
  end

  defp fetch_room_inventory(room_ids, checkin_date, checkout_date) do
    Repo.all(
      from ri in RoomInventory,
        where:
          ri.room_id in ^room_ids and ri.day >= ^checkin_date and
            ri.day < ^checkout_date
    )
  end

  defp validate_room_booking_availability(prop_inv, room_inv) do
    # Check buyout flags
    buyout_blocked =
      Enum.any?(prop_inv, fn pi ->
        pi.buyout_held == true or pi.buyout_booked == true
      end)

    if buyout_blocked do
      Repo.rollback({:error, :property_buyout_active})
    end

    # Check all rooms are available
    room_blocked =
      Enum.any?(room_inv, fn ri -> ri.held == true or ri.booked == true end)

    if room_blocked do
      Repo.rollback({:error, :room_unavailable})
    end
  end

  defp update_room_inventory_for_booking(room_inv) do
    # IMPORTANT: We must update ALL rows or the booking fails (no partial bookings)
    # For composite primary keys, we manually check lock_version in the WHERE clause
    # AND include availability checks to ensure optimistic locking works correctly
    update_results =
      Enum.map(room_inv, fn ri ->
        # Use update_all with explicit lock_version check AND availability validation
        # This ensures optimistic locking works correctly - if lock_version changed or
        # availability changed, the update will affect 0 rows
        {count, _} =
          Repo.update_all(
            from(ri2 in RoomInventory,
              where:
                ri2.room_id == ^ri.room_id and ri2.day == ^ri.day and
                  ri2.lock_version == ^ri.lock_version and
                  ri2.held == false and ri2.booked == false
            ),
            set: [
              held: true,
              lock_version: ri.lock_version + 1,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        if count == 1 do
          {:ok, :updated}
        else
          {:error, :stale_inventory}
        end
      end)

    # Check if all updates succeeded
    failed_updates = Enum.filter(update_results, &match?({:error, _}, &1))

    if failed_updates != [] do
      # At least one update failed - this means another transaction modified the inventory
      # Raise Ecto.StaleEntryError so retry_on_stale can catch it and retry
      raise Ecto.StaleEntryError, struct: List.first(room_inv), action: :update
    end
  end

  defp calculate_room_booking_pricing(
         rooms,
         checkin_date,
         checkout_date,
         guests_count,
         children_count
       ) do
    case calculate_multi_room_price(
           rooms,
           checkin_date,
           checkout_date,
           guests_count,
           children_count
         ) do
      {:ok, total, items} ->
        {total, items}

      {:error, _reason} ->
        {nil, nil}

      nil ->
        # Handle case where calculate_multi_room_price returns nil
        # (e.g., when no pricing rules are found)
        {nil, nil}
    end
  end

  defp create_room_booking_hold(params) do
    attrs = %{
      property: params.property,
      checkin_date: params.checkin_date,
      checkout_date: params.checkout_date,
      booking_mode: :room,
      guests_count: params.guests_count,
      children_count: params.children_count,
      user_id: params.user_id,
      status: :hold,
      hold_expires_at: params.hold_expires_at,
      total_price: params.total_price,
      pricing_items: params.pricing_items
    }

    case %Booking{}
         |> Booking.changeset(attrs, rooms: params.rooms, skip_validation: true)
         |> Repo.insert() do
      {:ok, booking} ->
        # Preload rooms for return
        Repo.preload(booking, :rooms)

      {:error, changeset} ->
        Repo.rollback({:error, changeset})
    end
  end

  # Helper to calculate price for multiple rooms
  defp calculate_multi_room_price(
         rooms,
         checkin_date,
         checkout_date,
         guests_count,
         children_count
       ) do
    nights = Date.diff(checkout_date, checkin_date)
    property = rooms |> List.first() |> Map.get(:property)

    results =
      Enum.reduce(rooms, {:ok, Money.new(:USD, 0), []}, fn room, acc ->
        process_room_pricing(
          acc,
          room,
          property,
          checkin_date,
          checkout_date,
          guests_count,
          children_count,
          nights
        )
      end)

    case results do
      {:ok, _total, _items} ->
        build_combined_pricing_items(
          results,
          nights,
          guests_count,
          children_count
        )

      error ->
        error
    end
  end

  defp process_room_pricing(
         acc,
         room,
         property,
         checkin_date,
         checkout_date,
         guests_count,
         children_count,
         nights
       ) do
    case acc do
      {:ok, total_acc, items_acc} ->
        actual_total_acc = normalize_money_struct(total_acc)

        case Bookings.calculate_booking_price(
               property,
               checkin_date,
               checkout_date,
               :room,
               room_id: room.id,
               guests_count: guests_count,
               children_count: children_count
             ) do
          {:ok, room_total, breakdown} ->
            add_room_to_pricing(
              actual_total_acc,
              items_acc,
              room,
              room_total,
              breakdown,
              nights,
              guests_count,
              children_count
            )

          error ->
            error
        end

      error ->
        error
    end
  end

  defp normalize_money_struct(total_acc) do
    case total_acc do
      {:ok, money} when is_struct(money, Money) -> money
      %Money{} = money -> money
      _ -> Money.new(:USD, 0)
    end
  end

  defp add_room_to_pricing(
         actual_total_acc,
         items_acc,
         room,
         room_total,
         breakdown,
         nights,
         guests_count,
         children_count
       ) do
    room_items =
      build_room_pricing_items(
        room,
        room_total,
        nights,
        guests_count,
        children_count,
        breakdown
      )

    case Money.add(actual_total_acc, room_total) do
      {:ok, new_total} ->
        {:ok, new_total, [room_items | items_acc]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_combined_pricing_items(
         results,
         nights,
         guests_count,
         children_count
       ) do
    case results do
      {:ok, total, items} ->
        combined_items = %{
          "type" => "room",
          "rooms" => Enum.reverse(items),
          "nights" => nights,
          "guests_count" => guests_count,
          "children_count" => children_count,
          "total" => %{
            "amount" => Decimal.to_string(total.amount),
            "currency" => to_string(total.currency)
          }
        }

        {:ok, total, combined_items}

      error ->
        error
    end
  end

  @doc """
  Atomically creates a per-guest booking (Clear Lake) with proper inventory locking.

  ## Parameters:
  - `user_id`: The user making the booking
  - `property`: The property (should be :clear_lake)
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `guests_count`: Number of guests
  - `opts`: Additional options (e.g., `hold_duration_minutes`)

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def create_per_guest_booking(
        user_id,
        property,
        checkin_date,
        checkout_date,
        guests_count,
        opts \\ []
      ) do
    retry_on_stale(
      fn attempt ->
        if attempt > 1 do
          Logger.info("Retrying per-guest booking after stale error",
            user_id: user_id,
            property: property,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            attempt: attempt
          )
        end

        do_create_per_guest_booking(
          user_id,
          property,
          checkin_date,
          checkout_date,
          guests_count,
          opts
        )
      end,
      max_attempts: 3,
      delay_ms: 100
    )
  end

  defp do_create_per_guest_booking(
         user_id,
         property,
         checkin_date,
         checkout_date,
         guests_count,
         opts
       ) do
    hold_duration =
      Keyword.get(opts, :hold_duration_minutes, @hold_duration_minutes)

    hold_expires_at = DateTime.add(DateTime.utc_now(), hold_duration, :minute)

    Repo.transaction(fn ->
      days =
        Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      # Ensure property_inventory rows exist with capacity_total = season cap (e.g., 12)
      ensure_property_inventory_for_days(property, days)

      # Fetch property_inventory rows (optimistic locking - no FOR UPDATE)
      prop_inv = fetch_property_inventory(property, checkin_date, checkout_date)

      # Validate per-guest availability
      validate_per_guest_availability(
        property,
        checkin_date,
        checkout_date,
        prop_inv,
        guests_count
      )

      # Increment capacity_held using optimistic locking
      update_property_inventory_for_per_guest(prop_inv, property, guests_count)

      # Calculate pricing
      {total_price, pricing_items} =
        calculate_per_guest_pricing(
          property,
          checkin_date,
          checkout_date,
          guests_count
        )

      # Create booking :hold
      booking =
        create_per_guest_booking_hold(
          user_id,
          property,
          checkin_date,
          checkout_date,
          guests_count,
          hold_expires_at,
          total_price,
          pricing_items
        )

      booking
    end)
    |> case do
      {:ok, booking} ->
        # Emit telemetry event for booking creation
        :telemetry.execute(
          [:ysc, :bookings, :booking_created],
          %{count: 1},
          %{
            booking_id: booking.id,
            property: to_string(property),
            booking_mode: "day",
            user_id: user_id
          }
        )

        {:ok, booking}

      error ->
        error
    end
  end

  defp validate_per_guest_availability(
         property,
         checkin_date,
         checkout_date,
         prop_inv,
         guests_count
       ) do
    # Validate no blackout overlap
    if Bookings.has_blackout?(property, checkin_date, checkout_date) do
      Repo.rollback({:error, :blackout_conflict})
    end

    # Validate for each day: buyout flags false and capacity_booked + capacity_held + guests <= capacity_total
    invalid_days =
      Enum.filter(prop_inv, fn pi ->
        pi.buyout_held == true or
          pi.buyout_booked == true or
          pi.capacity_booked + pi.capacity_held + guests_count >
            pi.capacity_total
      end)

    if invalid_days != [] do
      Repo.rollback({:error, :insufficient_capacity})
    end
  end

  defp update_property_inventory_for_per_guest(prop_inv, property, guests_count) do
    # IMPORTANT: We must update ALL rows or the booking fails (no partial bookings)
    # For composite primary keys, we manually check lock_version in the WHERE clause
    # AND include availability checks to ensure optimistic locking works correctly
    update_results =
      Enum.map(prop_inv, fn pi ->
        # Use update_all with explicit lock_version check AND availability validation
        # This ensures optimistic locking works correctly - if lock_version changed or
        # capacity changed, the update will affect 0 rows
        {count, _} =
          Repo.update_all(
            from(pi2 in PropertyInventory,
              where:
                pi2.property == ^property and pi2.day == ^pi.day and
                  pi2.lock_version == ^pi.lock_version and
                  pi2.buyout_held == false and pi2.buyout_booked == false and
                  pi2.capacity_booked + pi2.capacity_held + ^guests_count <=
                    pi2.capacity_total
            ),
            set: [
              capacity_held: pi.capacity_held + guests_count,
              lock_version: pi.lock_version + 1,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        if count == 1 do
          {:ok, :updated}
        else
          {:error, :stale_inventory}
        end
      end)

    # Check if all updates succeeded
    failed_updates = Enum.filter(update_results, &match?({:error, _}, &1))

    if failed_updates != [] do
      # At least one update failed - this means another transaction modified the inventory
      # Raise Ecto.StaleEntryError so retry_on_stale can catch it and retry
      raise Ecto.StaleEntryError, struct: List.first(prop_inv), action: :update
    end
  end

  defp calculate_per_guest_pricing(
         property,
         checkin_date,
         checkout_date,
         guests_count
       ) do
    case Bookings.calculate_booking_price(
           property,
           checkin_date,
           checkout_date,
           :day,
           guests_count: guests_count,
           children_count: 0
         ) do
      {:ok, total, _breakdown} ->
        nights = Date.diff(checkout_date, checkin_date)

        price_per_guest_per_night =
          if nights > 0 and guests_count > 0 do
            Money.div(total, nights * guests_count) |> elem(1)
          else
            Money.new(:USD, 0)
          end

        items = %{
          "type" => "per_guest",
          "nights" => nights,
          "guests_count" => guests_count,
          "price_per_guest_per_night" => %{
            "amount" => Decimal.to_string(price_per_guest_per_night.amount),
            "currency" => to_string(price_per_guest_per_night.currency)
          },
          "total" => %{
            "amount" => Decimal.to_string(total.amount),
            "currency" => to_string(total.currency)
          }
        }

        {total, items}

      {:error, _reason} ->
        {nil, nil}
    end
  end

  defp create_per_guest_booking_hold(
         user_id,
         property,
         checkin_date,
         checkout_date,
         guests_count,
         hold_expires_at,
         total_price,
         pricing_items
       ) do
    attrs = %{
      property: property,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      booking_mode: :day,
      guests_count: guests_count,
      user_id: user_id,
      status: :hold,
      hold_expires_at: hold_expires_at,
      total_price: total_price,
      pricing_items: pricing_items
    }

    case %Booking{}
         |> Booking.changeset(attrs, skip_validation: true)
         |> Repo.insert() do
      {:ok, booking} ->
        booking

      {:error, changeset} ->
        Repo.rollback({:error, changeset})
    end
  end

  @doc """
  Confirms a booking (moves from :hold to :complete) and updates inventory accordingly.

  ## Parameters:
  - `booking_id`: The booking to confirm

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def confirm_booking(booking_id) do
    Repo.transaction(fn ->
      booking = Repo.get!(Booking, booking_id) |> Repo.preload(:rooms)

      # Make this function idempotent - if booking is already confirmed, return success
      # This handles the race condition where multiple processes (redirect + webhook/polling)
      # might try to confirm the same booking after payment succeeds
      if booking.status == :complete do
        Logger.info(
          "Booking already confirmed, returning existing booking (idempotent)",
          booking_id: booking.id
        )

        # Return the already-confirmed booking
        booking
      else
        # Booking must be in :hold status to proceed with confirmation
        if booking.status != :hold do
          Repo.rollback({:error, :invalid_status})
        end

        # Continue with normal confirmation flow below
      end

      case booking.booking_mode do
        :buyout ->
          # Flip to buyout_booked = true
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and
                    pi.day < ^booking.checkout_date
              ),
              set: [
                buyout_held: false,
                buyout_booked: true,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end

        :room ->
          # Set booked = true, clear held for all rooms
          room_ids = Enum.map(booking.rooms, & &1.id)

          if room_ids != [] do
            {count, _} =
              Repo.update_all(
                from(ri in RoomInventory,
                  where:
                    ri.room_id in ^room_ids and
                      ri.day >= ^booking.checkin_date and
                      ri.day < ^booking.checkout_date
                ),
                set: [
                  held: false,
                  booked: true,
                  updated_at: DateTime.truncate(DateTime.utc_now(), :second)
                ]
              )

            if count == 0 do
              Repo.rollback({:error, :inventory_update_failed})
            end
          end

        :day ->
          # Decrement held, increment booked
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and
                    pi.day < ^booking.checkout_date
              ),
              inc: [
                capacity_booked: booking.guests_count,
                capacity_held: -booking.guests_count
              ],
              set: [updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end
      end

      # Update booking status
      # Pass existing rooms to avoid Ecto thinking we're removing them
      case booking
           |> Booking.changeset(%{status: :complete, hold_expires_at: nil},
             rooms: booking.rooms,
             skip_validation: true
           )
           |> Repo.update() do
        {:ok, updated_booking} ->
          updated_booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
    |> case do
      {:ok, confirmed_booking} ->
        # Emit telemetry event for booking payment/confirmation
        :telemetry.execute(
          [:ysc, :bookings, :payment_processed],
          %{count: 1},
          %{
            booking_id: confirmed_booking.id,
            property: to_string(confirmed_booking.property),
            booking_mode: to_string(confirmed_booking.booking_mode),
            user_id: confirmed_booking.user_id,
            status: "success"
          }
        )

        # After successful confirmation, cancel all other hold bookings for the same property and user
        # This frees up any inventory that was accidentally left pending
        # Do this outside the transaction to avoid nested transaction issues
        cancel_other_hold_bookings(
          confirmed_booking.property,
          confirmed_booking.user_id,
          confirmed_booking.id
        )

        # Send booking confirmation email
        send_booking_confirmation_email(confirmed_booking)

        # Schedule check-in reminder email (3 days before check-in at 8:00 AM PST)
        schedule_checkin_reminder(confirmed_booking)

        # Schedule checkout reminder email (evening before checkout at 6:00 PM PST)
        schedule_checkout_reminder(confirmed_booking)

        {:ok, confirmed_booking}

      error ->
        error
    end
  end

  @doc """
  Creates and confirms a booking directly (for admin use).

  This bypasses the normal hold → payment → confirm flow and directly:
  1. Creates the booking with :complete status
  2. Updates inventory to mark as booked
  3. Sends confirmation email to the user
  4. Schedules check-in and checkout reminders

  ## Parameters:
  - `attrs`: Booking attributes (user_id, property, checkin_date, checkout_date, guests_count, booking_mode, etc.)
  - `opts`: Additional options:
    - `:rooms` - List of Room structs to associate with the booking
    - `:skip_email` - If true, doesn't send confirmation email (default: false)
    - `:skip_reminders` - If true, doesn't schedule reminders (default: false)

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def create_admin_booking(attrs, opts \\ []) do
    rooms = Keyword.get(opts, :rooms, [])
    skip_email = Keyword.get(opts, :skip_email, false)
    skip_reminders = Keyword.get(opts, :skip_reminders, false)

    # Ensure status is :complete for admin bookings
    attrs = Map.put(attrs, :status, :complete)

    Repo.transaction(fn ->
      # Create the booking
      changeset =
        %Booking{}
        |> Booking.changeset(attrs, rooms: rooms, skip_validation: true)

      case Repo.insert(changeset) do
        {:ok, booking} ->
          # Reload with associations
          booking = Repo.preload(booking, [:rooms, :user])

          # Update inventory based on booking mode
          update_inventory_for_admin_booking(booking)

          booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
    |> case do
      {:ok, booking} ->
        # Send confirmation email (outside transaction)
        unless skip_email do
          send_booking_confirmation_email(booking)
        end

        # Schedule reminders (outside transaction)
        unless skip_reminders do
          schedule_checkin_reminder(booking)
          schedule_checkout_reminder(booking)
        end

        {:ok, booking}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Updates inventory to mark dates as booked for an admin-created booking
  defp update_inventory_for_admin_booking(booking) do
    case booking.booking_mode do
      :buyout ->
        # Set buyout_booked = true for all days
        {count, _} =
          Repo.update_all(
            from(pi in PropertyInventory,
              where:
                pi.property == ^booking.property and
                  pi.day >= ^booking.checkin_date and
                  pi.day < ^booking.checkout_date
            ),
            set: [
              buyout_booked: true,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        # Ensure inventory rows exist first if count is 0
        if count == 0 do
          ensure_inventory_exists_and_book(booking)
        else
          :ok
        end

      :room ->
        room_ids = Enum.map(booking.rooms, & &1.id)

        if room_ids != [] do
          {count, _} =
            Repo.update_all(
              from(ri in RoomInventory,
                where:
                  ri.room_id in ^room_ids and
                    ri.day >= ^booking.checkin_date and
                    ri.day < ^booking.checkout_date
              ),
              set: [
                booked: true,
                held: false,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          # Ensure inventory rows exist first if count is 0
          if count == 0 do
            ensure_room_inventory_exists_and_book(booking, room_ids)
          else
            :ok
          end
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  # Ensures property inventory rows exist for the date range and marks as booked
  defp ensure_inventory_exists_and_book(booking) do
    dates =
      Date.range(booking.checkin_date, Date.add(booking.checkout_date, -1))

    Enum.each(dates, fn date ->
      Repo.insert(
        %PropertyInventory{
          property: booking.property,
          day: date,
          buyout_booked: true,
          buyout_held: false,
          capacity_total:
            if(booking.property == :clear_lake,
              do: @default_capacity_clear_lake,
              else: @default_capacity_tahoe
            ),
          capacity_held: 0,
          capacity_booked: 0
        },
        on_conflict: {:replace, [:buyout_booked, :updated_at]},
        conflict_target: [:property, :day]
      )
    end)

    :ok
  end

  # Ensures room inventory rows exist for the date range and marks as booked
  defp ensure_room_inventory_exists_and_book(booking, room_ids) do
    dates =
      Date.range(booking.checkin_date, Date.add(booking.checkout_date, -1))

    for room_id <- room_ids, date <- dates do
      Repo.insert(
        %RoomInventory{
          room_id: room_id,
          day: date,
          booked: true,
          held: false
        },
        on_conflict: {:replace, [:booked, :held, :updated_at]},
        conflict_target: [:room_id, :day]
      )
    end

    :ok
  end

  defp schedule_checkin_reminder(booking) do
    require Logger

    try do
      YscWeb.Workers.BookingCheckinReminderWorker.schedule_reminder(
        booking.id,
        booking.checkin_date
      )

      Logger.info("Scheduled check-in reminder email",
        booking_id: booking.id,
        checkin_date: booking.checkin_date
      )
    rescue
      error ->
        Logger.error("Failed to schedule check-in reminder",
          booking_id: booking.id,
          error: Exception.message(error)
        )
    end
  end

  defp schedule_checkout_reminder(booking) do
    require Logger

    try do
      YscWeb.Workers.BookingCheckoutReminderWorker.schedule_reminder(
        booking.id,
        booking.checkout_date
      )

      Logger.info("Scheduled checkout reminder email",
        booking_id: booking.id,
        checkout_date: booking.checkout_date
      )
    rescue
      error ->
        Logger.error("Failed to schedule checkout reminder",
          booking_id: booking.id,
          error: Exception.message(error)
        )
    end
  end

  defp send_booking_confirmation_email(booking) do
    require Logger

    try do
      # Reload booking with associations
      booking =
        Repo.get(Ysc.Bookings.Booking, booking.id)
        |> Repo.preload([:user, :rooms])

      if booking && booking.user do
        # Prepare email data
        email_data =
          YscWeb.Emails.BookingConfirmation.prepare_email_data(booking)

        # Generate idempotency key
        idempotency_key = "booking_confirmation_#{booking.id}"

        # Schedule email
        result =
          YscWeb.Emails.Notifier.schedule_email(
            booking.user.email,
            idempotency_key,
            YscWeb.Emails.BookingConfirmation.get_subject(),
            "booking_confirmation",
            email_data,
            "",
            booking.user_id
          )

        case result do
          %Oban.Job{} = job ->
            Logger.info("Booking confirmation email scheduled successfully",
              booking_id: booking.id,
              user_id: booking.user_id,
              user_email: booking.user.email,
              job_id: job.id
            )

          {:error, reason} ->
            Logger.error("Failed to schedule booking confirmation email",
              booking_id: booking.id,
              user_id: booking.user_id,
              error: reason
            )
        end
      else
        Logger.warning(
          "Skipping booking confirmation email - missing booking or user",
          booking_id: booking && booking.id
        )
      end
    rescue
      error ->
        Logger.error("Failed to send booking confirmation email",
          booking_id: booking && booking.id,
          error: inspect(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  # Helper to cancel all other hold bookings for the same property and user
  defp cancel_other_hold_bookings(property, user_id, exclude_booking_id) do
    # Find all other hold bookings for the same property and user
    other_hold_bookings =
      Repo.all(
        from b in Booking,
          where: b.property == ^property,
          where: b.user_id == ^user_id,
          where: b.status == :hold,
          where: b.id != ^exclude_booking_id
      )

    # Release each hold booking
    Enum.each(other_hold_bookings, fn hold_booking ->
      case release_hold(hold_booking.id) do
        {:ok, _} ->
          # Successfully released
          :ok

        {:error, reason} ->
          # Log error but don't fail the main operation
          require Logger

          Logger.warning(
            "Failed to release hold booking #{hold_booking.id} when confirming booking #{exclude_booking_id}: #{inspect(reason)}"
          )
      end
    end)
  end

  @doc """
  Releases a hold (cancels a :hold booking) and updates inventory accordingly.

  ## Parameters:
  - `booking_id`: The booking to release

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def release_hold(booking_id) do
    require Logger

    Repo.transaction(fn ->
      booking = Repo.get!(Booking, booking_id) |> Repo.preload(:rooms)

      if booking.status != :hold do
        Repo.rollback({:error, :invalid_status})
      end

      # Cancel PaymentIntent in Stripe if it exists (search by metadata)
      cancel_booking_payment_intent(booking)

      case booking.booking_mode do
        :buyout ->
          # Reset buyout_held = false
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and
                    pi.day < ^booking.checkout_date
              ),
              set: [
                buyout_held: false,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end

        :room ->
          # Clear held for all rooms
          room_ids = Enum.map(booking.rooms, & &1.id)

          if room_ids != [] do
            {count, _} =
              Repo.update_all(
                from(ri in RoomInventory,
                  where:
                    ri.room_id in ^room_ids and
                      ri.day >= ^booking.checkin_date and
                      ri.day < ^booking.checkout_date
                ),
                set: [
                  held: false,
                  updated_at: DateTime.truncate(DateTime.utc_now(), :second)
                ]
              )

            if count == 0 do
              Repo.rollback({:error, :inventory_update_failed})
            end
          end

        :day ->
          # Decrement held
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and
                    pi.day < ^booking.checkout_date
              ),
              inc: [capacity_held: -booking.guests_count],
              set: [updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end
      end

      # Update booking status to canceled
      # Pass existing rooms to avoid Ecto thinking we're removing them
      case booking
           |> Booking.changeset(%{status: :canceled, hold_expires_at: nil},
             rooms: booking.rooms,
             skip_validation: true
           )
           |> Repo.update() do
        {:ok, updated_booking} ->
          updated_booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
  end

  # Helper function to cancel PaymentIntent for a booking by searching Stripe metadata
  # Note: This searches recent PaymentIntents since bookings don't store payment_intent_id.
  # For better performance, consider storing payment_intent_id in the booking schema.
  defp cancel_booking_payment_intent(booking) do
    require Logger

    # Search for recent PaymentIntents (last 100) with this booking_id in metadata
    # Since bookings expire after 30 minutes, we only need to check recent PaymentIntents
    case Stripe.PaymentIntent.list(%{
           limit: 100,
           expand: ["data.metadata"]
         }) do
      {:ok, %{data: payment_intents}} ->
        # Find PaymentIntent with matching booking_id in metadata
        matching_intent =
          Enum.find(payment_intents, fn pi ->
            case pi.metadata do
              %{"booking_id" => booking_id} when is_binary(booking_id) ->
                booking_id == booking.id

              _ ->
                false
            end
          end)

        if matching_intent do
          # Only cancel if it's still in a cancelable state
          cancelable_statuses = [
            "requires_payment_method",
            "requires_confirmation",
            "requires_action"
          ]

          if matching_intent.status in cancelable_statuses do
            case Ysc.Tickets.StripeService.cancel_payment_intent(
                   matching_intent.id
                 ) do
              :ok ->
                Logger.info("Canceled PaymentIntent for expired booking",
                  booking_id: booking.id,
                  payment_intent_id: matching_intent.id
                )

              {:error, reason} ->
                Logger.warning(
                  "Failed to cancel PaymentIntent for expired booking (continuing anyway)",
                  booking_id: booking.id,
                  payment_intent_id: matching_intent.id,
                  error: reason
                )
            end
          else
            Logger.debug("PaymentIntent already in non-cancelable state",
              booking_id: booking.id,
              payment_intent_id: matching_intent.id,
              status: matching_intent.status
            )
          end
        else
          Logger.debug(
            "No PaymentIntent found for expired booking (may have been canceled already)",
            booking_id: booking.id
          )
        end

      {:error, error} ->
        Logger.warning(
          "Failed to search for PaymentIntent for expired booking (continuing anyway)",
          booking_id: booking.id,
          error: inspect(error)
        )
    end
  end

  @doc """
  Cancels a complete booking and frees up inventory.

  This is the reverse of confirm_booking - it releases booked inventory
  and updates the booking status to :canceled.

  ## Parameters:
  - `booking_id`: The booking to cancel

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def cancel_complete_booking(booking_id) do
    Repo.transaction(fn ->
      booking = Repo.get!(Booking, booking_id) |> Repo.preload(:rooms)

      if booking.status != :complete do
        Repo.rollback({:error, :invalid_status})
      end

      case booking.booking_mode do
        :buyout ->
          # Reset buyout_booked = false
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and
                    pi.day < ^booking.checkout_date
              ),
              set: [
                buyout_booked: false,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end

        :room ->
          # Clear booked for all rooms
          room_ids = Enum.map(booking.rooms, & &1.id)

          if room_ids != [] do
            {count, _} =
              Repo.update_all(
                from(ri in RoomInventory,
                  where:
                    ri.room_id in ^room_ids and
                      ri.day >= ^booking.checkin_date and
                      ri.day < ^booking.checkout_date
                ),
                set: [
                  booked: false,
                  updated_at: DateTime.truncate(DateTime.utc_now(), :second)
                ]
              )

            if count == 0 do
              Repo.rollback({:error, :inventory_update_failed})
            end
          end

        :day ->
          # Decrement booked
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and
                    pi.day < ^booking.checkout_date
              ),
              inc: [capacity_booked: -booking.guests_count],
              set: [updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end
      end

      # Update booking status to canceled
      # Pass existing rooms to avoid Ecto thinking we're removing them
      case booking
           |> Booking.changeset(%{status: :canceled, hold_expires_at: nil},
             rooms: booking.rooms,
             skip_validation: true
           )
           |> Repo.update() do
        {:ok, updated_booking} ->
          updated_booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
  end

  @doc """
  Marks a complete booking as refunded and optionally releases inventory.

  This is similar to cancel_complete_booking but sets the status to :refunded
  instead of :canceled, making it clear the booking was refunded.

  ## Parameters:
  - `booking_id`: The booking to mark as refunded
  - `release_inventory`: If true, releases the inventory (dates/rooms become available)

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def refund_complete_booking(booking_id, release_inventory \\ true) do
    Repo.transaction(fn ->
      booking = Repo.get!(Booking, booking_id) |> Repo.preload(:rooms)

      if booking.status != :complete do
        Repo.rollback({:error, :invalid_status})
      end

      # Release inventory if requested
      if release_inventory do
        case booking.booking_mode do
          :buyout ->
            # Reset buyout_booked = false
            {count, _} =
              Repo.update_all(
                from(pi in PropertyInventory,
                  where:
                    pi.property == ^booking.property and
                      pi.day >= ^booking.checkin_date and
                      pi.day < ^booking.checkout_date
                ),
                set: [
                  buyout_booked: false,
                  updated_at: DateTime.truncate(DateTime.utc_now(), :second)
                ]
              )

            if count == 0 do
              Repo.rollback({:error, :inventory_update_failed})
            end

          :room ->
            # Clear booked for all rooms
            room_ids = Enum.map(booking.rooms, & &1.id)

            if room_ids != [] do
              {count, _} =
                Repo.update_all(
                  from(ri in RoomInventory,
                    where:
                      ri.room_id in ^room_ids and
                        ri.day >= ^booking.checkin_date and
                        ri.day < ^booking.checkout_date
                  ),
                  set: [
                    booked: false,
                    updated_at: DateTime.truncate(DateTime.utc_now(), :second)
                  ]
                )

              if count == 0 do
                Repo.rollback({:error, :inventory_update_failed})
              end
            end

          :day ->
            # Decrement booked
            {count, _} =
              Repo.update_all(
                from(pi in PropertyInventory,
                  where:
                    pi.property == ^booking.property and
                      pi.day >= ^booking.checkin_date and
                      pi.day < ^booking.checkout_date
                ),
                inc: [capacity_booked: -booking.guests_count],
                set: [
                  updated_at: DateTime.truncate(DateTime.utc_now(), :second)
                ]
              )

            if count == 0 do
              Repo.rollback({:error, :inventory_update_failed})
            end
        end
      end

      # Update booking status to refunded
      # Pass existing rooms to avoid Ecto thinking we're removing them
      case booking
           |> Booking.changeset(%{status: :refunded, hold_expires_at: nil},
             rooms: booking.rooms,
             skip_validation: true
           )
           |> Repo.update() do
        {:ok, updated_booking} ->
          updated_booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
  end

  ## Private Functions

  defp ensure_property_inventory_row(property, day, capacity_total) do
    Repo.insert_all(
      PropertyInventory,
      [
        %{
          property: property,
          day: day,
          capacity_total: capacity_total,
          capacity_held: 0,
          capacity_booked: 0,
          buyout_held: false,
          buyout_booked: false,
          updated_at: DateTime.truncate(DateTime.utc_now(), :second)
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:property, :day]
    )
  end

  defp ensure_room_inventory_row(room_id, day) do
    Repo.insert_all(
      RoomInventory,
      [
        %{
          room_id: room_id,
          day: day,
          held: false,
          booked: false,
          updated_at: DateTime.truncate(DateTime.utc_now(), :second)
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:room_id, :day]
    )
  end

  defp build_room_pricing_items(
         room,
         total,
         nights,
         guests_count,
         children_count,
         breakdown
       ) do
    # For room bookings, create a JSON-safe structure with string keys
    # Convert breakdown map (with atom keys) to string keys if provided
    base_item = %{
      "type" => "room",
      "room_id" => room.id,
      "room_name" => room.name,
      "nights" => nights,
      "guests_count" => guests_count,
      "children_count" => children_count,
      "total" => %{
        "amount" => Decimal.to_string(total.amount),
        "currency" => to_string(total.currency)
      }
    }

    # If breakdown is provided, convert atom keys to string keys and merge
    if breakdown && is_map(breakdown) do
      breakdown_string_keys =
        breakdown
        |> Enum.map(fn
          {key, value} when is_atom(key) ->
            {to_string(key), convert_money_to_map(value)}

          {key, value} ->
            {key, convert_money_to_map(value)}
        end)
        |> Enum.into(%{})

      Map.merge(base_item, breakdown_string_keys)
    else
      base_item
    end
  end

  # Helper to convert Money structs to maps for JSON encoding
  defp convert_money_to_map(%Money{} = money) do
    %{
      "amount" => Decimal.to_string(money.amount),
      "currency" => to_string(money.currency)
    }
  end

  defp convert_money_to_map(value)
       when is_integer(value) or is_float(value) or is_binary(value) do
    value
  end

  defp convert_money_to_map(value) when is_map(value) do
    Enum.map(value, fn {k, v} -> {k, convert_money_to_map(v)} end)
    |> Enum.into(%{})
  end

  defp convert_money_to_map(value), do: value

  defp get_property_capacity_for_date(property, _date) do
    # NOTE: Get from season policy if available
    # For now, use defaults
    case property do
      :clear_lake -> @default_capacity_clear_lake
      :tahoe -> @default_capacity_tahoe
      _ -> 0
    end
  end
end

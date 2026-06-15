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
  import Ecto.Changeset, only: [put_change: 3]
  import RetryOn, only: [retry_on_stale: 2]
  require Ysc.Logging

  alias Ysc.Repo

  alias Ysc.Bookings.{
    Booking,
    Entitlements,
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
          Ysc.Logging.info("Retrying buyout booking after stale error",
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
      case calculate_buyout_pricing(
             property,
             checkin_date,
             checkout_date,
             guests_count
           ) do
        {base_total, base_items}
        when not is_nil(base_total) and not is_nil(base_items) ->
          {total_price, pricing_items, subtotal, discount, ent_id} =
            Entitlements.apply_best_entitlement(
              user_id,
              property,
              :buyout,
              checkin_date,
              checkout_date,
              base_total,
              base_items,
              guests_count: guests_count,
              children_count: 0,
              room_ids: []
            )

          create_buyout_booking_hold(%{
            user_id: user_id,
            property: property,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: guests_count,
            hold_expires_at: hold_expires_at,
            total_price: total_price,
            pricing_items: pricing_items,
            subtotal_price: subtotal,
            discount_total: discount,
            applied_booking_entitlement_id: ent_id
          })

        _ ->
          Repo.rollback(:pricing_calculation_failed)
      end
    end)
    |> case do
      {:ok, {:error, reason}} ->
        {:error, reason}

      {:ok, %Booking{} = booking} ->
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

      {:error, :pricing_calculation_failed} ->
        {:error, :pricing_calculation_failed}

      error ->
        error
    end
    |> invalidate_availability_cache()
  end

  defp ensure_property_inventory_for_days(property, days) do
    for day <- days do
      capacity_total = get_property_capacity_for_date(property, day)
      ensure_property_inventory_row(property, day, capacity_total)
    end
  end

  defp day_property_inventory_stay_days(booking) do
    booking.checkin_date
    |> Date.range(Date.add(booking.checkout_date, -1))
    |> Enum.to_list()
  end

  defp day_property_inventory_query(booking) do
    from(pi in PropertyInventory,
      where:
        pi.property == ^booking.property and
          pi.day >= ^booking.checkin_date and
          pi.day < ^booking.checkout_date
    )
  end

  defp update_all_day_property_inventory!(booking, updates, opts) do
    query = day_property_inventory_query(booking)
    retry_updates = Keyword.fetch!(opts, :retry_updates)

    {count, _} = Repo.update_all(query, updates)

    if count == 0 do
      ensure_property_inventory_for_days(
        booking.property,
        day_property_inventory_stay_days(booking)
      )

      {count, _} = Repo.update_all(query, retry_updates)

      if count == 0 do
        Repo.rollback({:error, :inventory_update_failed})
      end
    end
  end

  defp release_day_held_capacity_for_stay!(booking) do
    ensure_property_inventory_for_days(
      booking.property,
      day_property_inventory_stay_days(booking)
    )

    updated_at = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      from(pi in day_property_inventory_query(booking),
        where: pi.capacity_held >= ^booking.guests_count
      )
      |> Repo.update_all(
        inc: [capacity_held: -booking.guests_count],
        set: [updated_at: updated_at]
      )

    if count == 0 do
      Repo.rollback({:error, :inventory_update_failed})
    end
  end

  defp release_day_booked_capacity_for_stay!(booking) do
    ensure_property_inventory_for_days(
      booking.property,
      day_property_inventory_stay_days(booking)
    )

    updated_at = DateTime.truncate(DateTime.utc_now(), :second)

    from(pi in day_property_inventory_query(booking),
      where: pi.capacity_booked >= ^booking.guests_count
    )
    |> Repo.update_all(
      inc: [capacity_booked: -booking.guests_count],
      set: [updated_at: updated_at]
    )

    :ok
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

  defp create_buyout_booking_hold(%{} = a) do
    attrs =
      a
      |> Map.take([
        :user_id,
        :property,
        :checkin_date,
        :checkout_date,
        :guests_count,
        :hold_expires_at,
        :total_price,
        :pricing_items
      ])
      |> Map.merge(%{
        booking_mode: :buyout,
        status: :hold
      })

    changeset =
      %Booking{}
      |> Booking.changeset(attrs, skip_validation: true)
      |> put_change(:subtotal_price, a[:subtotal_price])
      |> put_change(:discount_total, a[:discount_total])
      |> put_change(
        :applied_booking_entitlement_id,
        a[:applied_booking_entitlement_id]
      )

    case Repo.insert_with_reference_retry(changeset, Booking) do
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
          Ysc.Logging.info("Retrying room booking after stale error",
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
          {base_total, base_items}
          when not is_nil(base_total) and not is_nil(base_items) ->
            room_ids = Enum.map(rooms, & &1.id)

            {total_price, pricing_items, subtotal, discount, ent_id} =
              Entitlements.apply_best_entitlement(
                user_id,
                property,
                :room,
                checkin_date,
                checkout_date,
                base_total,
                base_items,
                guests_count: guests_count,
                children_count: children_count,
                room_ids: room_ids
              )

            pricing_extras = %{
              subtotal_price: subtotal,
              discount_total: discount,
              applied_booking_entitlement_id: ent_id
            }

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
              pricing_extras: pricing_extras,
              rooms: rooms
            }

            create_room_booking_hold(hold_params)

          {nil, _} ->
            Repo.rollback(:pricing_calculation_failed)
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

        {:error, :pricing_calculation_failed} ->
          {:error, :pricing_calculation_failed}

        error ->
          error
      end
      |> invalidate_availability_cache()
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
    end
  end

  defp create_room_booking_hold(params) do
    extras = Map.get(params, :pricing_extras, %{})

    attrs =
      %{
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

    changeset =
      %Booking{}
      |> Booking.changeset(attrs, rooms: params.rooms, skip_validation: true)
      |> put_change(:subtotal_price, extras[:subtotal_price])
      |> put_change(:discount_total, extras[:discount_total])
      |> put_change(
        :applied_booking_entitlement_id,
        extras[:applied_booking_entitlement_id]
      )

    case Repo.insert_with_reference_retry(changeset, Booking) do
      {:ok, booking} ->
        # Preload rooms for return
        Repo.preload(booking, :rooms)

      {:error, changeset} ->
        Repo.rollback({:error, changeset})
    end
  end

  # Helper to calculate price for multiple rooms.
  # Per-person-per-night pricing is independent of room count — only total guest
  # count matters. We therefore calculate once using the first room, which matches
  # exactly what the checkout page charges. The old approach called
  # calculate_booking_price once per room with the full guests_count and summed
  # the results, incorrectly multiplying the price by the number of rooms.
  defp calculate_multi_room_price(
         rooms,
         checkin_date,
         checkout_date,
         guests_count,
         children_count
       ) do
    nights = Date.diff(checkout_date, checkin_date)
    property = rooms |> List.first() |> Map.get(:property)
    first_room = List.first(rooms)

    case Bookings.calculate_booking_price(
           property,
           checkin_date,
           checkout_date,
           :room,
           room_id: first_room.id,
           guests_count: guests_count,
           children_count: children_count
         ) do
      {:ok, total, breakdown} ->
        room_items =
          Enum.map(rooms, fn room ->
            build_room_pricing_items(
              room,
              total,
              nights,
              guests_count,
              children_count,
              breakdown
            )
          end)

        combined_items = %{
          "type" => "room",
          "rooms" => room_items,
          "nights" => nights,
          "guests_count" => guests_count,
          "children_count" => children_count,
          "total" => %{
            "amount" => Decimal.to_string(total.amount),
            "currency" => to_string(total.currency)
          }
        }

        {:ok, total, combined_items}

      {:error, reason} ->
        {:error, reason}
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
          Ysc.Logging.info("Retrying per-guest booking after stale error",
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
      case calculate_per_guest_pricing(
             property,
             checkin_date,
             checkout_date,
             guests_count
           ) do
        {base_total, base_items}
        when not is_nil(base_total) and not is_nil(base_items) ->
          {total_price, pricing_items, subtotal, discount, ent_id} =
            Entitlements.apply_best_entitlement(
              user_id,
              property,
              :day,
              checkin_date,
              checkout_date,
              base_total,
              base_items,
              guests_count: guests_count,
              children_count: 0,
              room_ids: []
            )

          create_per_guest_booking_hold(%{
            user_id: user_id,
            property: property,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: guests_count,
            hold_expires_at: hold_expires_at,
            total_price: total_price,
            pricing_items: pricing_items,
            subtotal_price: subtotal,
            discount_total: discount,
            applied_booking_entitlement_id: ent_id
          })

        _ ->
          Repo.rollback(:pricing_calculation_failed)
      end
    end)
    |> case do
      {:ok, {:error, reason}} ->
        {:error, reason}

      {:ok, %Booking{} = booking} ->
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

      {:error, :pricing_calculation_failed} ->
        {:error, :pricing_calculation_failed}

      error ->
        error
    end
    |> invalidate_availability_cache()
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

  defp create_per_guest_booking_hold(%{} = a) do
    attrs =
      a
      |> Map.take([
        :user_id,
        :property,
        :checkin_date,
        :checkout_date,
        :guests_count,
        :hold_expires_at,
        :total_price,
        :pricing_items
      ])
      |> Map.merge(%{
        booking_mode: :day,
        status: :hold
      })

    changeset =
      %Booking{}
      |> Booking.changeset(attrs, skip_validation: true)
      |> put_change(:subtotal_price, a[:subtotal_price])
      |> put_change(:discount_total, a[:discount_total])
      |> put_change(
        :applied_booking_entitlement_id,
        a[:applied_booking_entitlement_id]
      )

    case Repo.insert_with_reference_retry(changeset, Booking) do
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

      # Make this function idempotent - if booking is already confirmed, short-circuit
      # the entire transaction (including inventory updates) and signal to the caller
      # that no side-effects should be triggered again.
      if booking.status == :complete do
        Ysc.Logging.info(
          "Booking already confirmed, skipping re-confirmation (idempotent)",
          booking_id: booking.id
        )

        Repo.rollback({:already_confirmed, booking})
      end

      # Booking must be in :hold status to proceed with confirmation
      if booking.status != :hold do
        Repo.rollback({:error, :invalid_status})
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
          updated_at = DateTime.truncate(DateTime.utc_now(), :second)

          update_all_day_property_inventory!(
            booking,
            [
              inc: [
                capacity_booked: booking.guests_count,
                capacity_held: -booking.guests_count
              ],
              set: [updated_at: updated_at]
            ],
            retry_updates: [
              set: [
                capacity_booked: booking.guests_count,
                capacity_held: 0,
                updated_at: updated_at
              ]
            ]
          )
      end

      # Update booking status
      # Pass existing rooms to avoid Ecto thinking we're removing them
      case booking
           |> Booking.changeset(
             %{
               status: :complete,
               hold_expires_at: nil
             },
             rooms: booking.rooms,
             skip_validation: true
           )
           |> Repo.update() do
        {:ok, updated_booking} ->
          if updated_booking.applied_booking_entitlement_id do
            _ =
              Entitlements.lock_entitlement_for_consume(
                updated_booking.applied_booking_entitlement_id
              )

            case Entitlements.consume_for_booking!(
                   updated_booking.applied_booking_entitlement_id,
                   updated_booking.id
                 ) do
              :ok ->
                updated_booking

              {:error, reason} ->
                Repo.rollback({:error, reason})
            end
          else
            updated_booking
          end

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

        invalidate_availability_cache({:ok, confirmed_booking})

      # Booking was already confirmed by a prior call - return success without
      # re-triggering emails, SMS, or re-scheduling reminders.
      {:error, {:already_confirmed, booking}} ->
        Ysc.Logging.info(
          "confirm_booking: booking was already confirmed, no side-effects triggered",
          booking_id: booking.id
        )

        {:ok, booking}

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

      case Repo.insert_with_reference_retry(changeset, Booking) do
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
    |> invalidate_availability_cache()
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

      :day ->
        {count, _} =
          Repo.update_all(
            day_property_inventory_query(booking),
            inc: [capacity_booked: booking.guests_count],
            set: [updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
          )

        if count == 0 do
          ensure_day_inventory_exists_and_book(booking)
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp ensure_day_inventory_exists_and_book(booking) do
    dates =
      Date.range(booking.checkin_date, Date.add(booking.checkout_date, -1))

    Enum.each(dates, fn date ->
      capacity_total = get_property_capacity_for_date(booking.property, date)

      Repo.insert(
        %PropertyInventory{
          property: booking.property,
          day: date,
          buyout_booked: false,
          buyout_held: false,
          capacity_total: capacity_total,
          capacity_held: 0,
          capacity_booked: booking.guests_count
        },
        on_conflict: {:replace, [:capacity_booked, :updated_at]},
        conflict_target: [:property, :day]
      )
    end)

    :ok
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
    require Ysc.Logging

    try do
      YscWeb.Workers.BookingCheckinReminderWorker.schedule_reminder(
        booking.id,
        booking.checkin_date
      )

      Ysc.Logging.info("Scheduled check-in reminder email",
        booking_id: booking.id,
        checkin_date: booking.checkin_date
      )
    rescue
      error ->
        Ysc.Logging.error("Failed to schedule check-in reminder",
          booking_id: booking.id,
          error: Exception.message(error)
        )
    end
  end

  defp schedule_checkout_reminder(booking) do
    require Ysc.Logging

    try do
      YscWeb.Workers.BookingCheckoutReminderWorker.schedule_reminder(
        booking.id,
        booking.checkout_date
      )

      Ysc.Logging.info("Scheduled checkout reminder email",
        booking_id: booking.id,
        checkout_date: booking.checkout_date
      )
    rescue
      error ->
        Ysc.Logging.error("Failed to schedule checkout reminder",
          booking_id: booking.id,
          error: Exception.message(error)
        )
    end
  end

  defp send_booking_confirmation_email(booking) do
    require Ysc.Logging

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
            booking.user_id,
            Ysc.EmailConfig.booking_reply_to(booking.property)
          )

        case result do
          %Oban.Job{} = job ->
            Ysc.Logging.info(
              "Booking confirmation email scheduled successfully",
              booking_id: booking.id,
              user_id: booking.user_id,
              user_email: booking.user.email,
              job_id: job.id
            )

          {:error, reason} ->
            Ysc.Logging.error("Failed to schedule booking confirmation email",
              booking_id: booking.id,
              user_id: booking.user_id,
              error: reason
            )
        end
      else
        Ysc.Logging.warning(
          "Skipping booking confirmation email - missing booking or user",
          booking_id: booking && booking.id
        )
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send booking confirmation email",
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
          require Ysc.Logging

          Ysc.Logging.warning(
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
    require Ysc.Logging

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
          release_day_held_capacity_for_stay!(booking)
      end

      # Update booking status to canceled
      # Pass existing rooms to avoid Ecto thinking we're removing them
      case booking
           |> Booking.changeset(
             %{
               status: :canceled,
               hold_expires_at: nil
             },
             rooms: booking.rooms,
             skip_validation: true
           )
           |> put_change(:applied_booking_entitlement_id, nil)
           |> put_change(:subtotal_price, nil)
           |> put_change(:discount_total, nil)
           |> Repo.update() do
        {:ok, updated_booking} ->
          updated_booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
    |> invalidate_availability_cache()
  end

  defp stripe_payment_intent_module do
    Application.get_env(
      :ysc,
      :stripe_payment_intent_module,
      Stripe.PaymentIntent
    )
  end

  # Helper function to cancel PaymentIntent for a booking by searching Stripe metadata
  # Note: This searches recent PaymentIntents since bookings don't store payment_intent_id.
  # For better performance, consider storing payment_intent_id in the booking schema.
  defp cancel_booking_payment_intent(booking) do
    require Ysc.Logging

    # Search for recent PaymentIntents (last 100) with this booking_id in metadata
    # Since bookings expire after 30 minutes, we only need to check recent PaymentIntents
    case stripe_payment_intent_module().list(%{
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
                Ysc.Logging.info("Canceled PaymentIntent for expired booking",
                  booking_id: booking.id,
                  payment_intent_id: matching_intent.id
                )

              {:error, reason} ->
                Ysc.Logging.warning(
                  "Failed to cancel PaymentIntent for expired booking (continuing anyway)",
                  booking_id: booking.id,
                  payment_intent_id: matching_intent.id,
                  error: reason
                )
            end
          else
            Ysc.Logging.debug("PaymentIntent already in non-cancelable state",
              booking_id: booking.id,
              payment_intent_id: matching_intent.id,
              status: matching_intent.status
            )
          end
        else
          Ysc.Logging.debug(
            "No PaymentIntent found for expired booking (may have been canceled already)",
            booking_id: booking.id
          )
        end

      {:error, error} ->
        Ysc.Logging.warning(
          "Failed to search for PaymentIntent for expired booking (continuing anyway)",
          booking_id: booking.id,
          error: inspect(error)
        )
    end
  end

  @doc """
  Places a short-lived hold on inventory for newly selected dates during modification payment.

  Holds only calendar days that are not already part of the current stay, plus any
  additional per-guest capacity needed on overlapping days.
  """
  def place_modification_hold(booking, attrs, opts \\ []) do
    hold_minutes =
      Keyword.get(opts, :hold_duration_minutes, @hold_duration_minutes)

    retry_on_stale(
      fn _attempt ->
        result =
          Repo.transaction(fn ->
            booking =
              Repo.get!(Booking, booking.id)
              |> Repo.preload(:rooms)

            if booking.status != :complete do
              Repo.rollback({:error, :invalid_status})
            end

            release_modification_hold_inventory!(booking)

            case Bookings.validate_modification_availability(booking, attrs) do
              :ok -> :ok
              {:error, reason} -> Repo.rollback({:error, reason})
            end

            hold_data = compute_modification_hold_data(booking, attrs)

            if modification_hold_needed?(hold_data) do
              hold_modification_inventory!(booking, attrs, hold_data)
            end

            expires_at =
              DateTime.utc_now()
              |> DateTime.add(hold_minutes, :minute)
              |> DateTime.truncate(:second)

            hold_attrs =
              encode_modification_hold_attrs(booking, attrs, hold_data, opts)

            case booking
                 |> Booking.changeset(
                   %{
                     modification_hold_expires_at: expires_at,
                     modification_hold_attrs: hold_attrs
                   },
                   skip_validation: true
                 )
                 |> Repo.update() do
              {:ok, updated_booking} -> updated_booking
              {:error, changeset} -> Repo.rollback({:error, changeset})
            end
          end)

        invalidate_availability_cache(result)
      end,
      max_attempts: 3,
      delay_ms: 100
    )
  end

  @doc """
  Releases a modification payment hold without applying the modification.

  By default clears stored hold attrs (user cancelled). Pass `clear_attrs: false`
  when the hold timed out but a Stripe payment may still complete — attrs are
  needed to apply the modification on redirect return.
  """
  def release_modification_hold(booking_id, opts \\ []) do
    clear_attrs = Keyword.get(opts, :clear_attrs, true)

    retry_on_stale(
      fn _attempt ->
        result =
          Repo.transaction(fn ->
            booking =
              Repo.get!(Booking, booking_id)
              |> Repo.preload(:rooms)

            release_modification_hold_inventory!(booking)

            hold_attrs =
              if clear_attrs, do: nil, else: booking.modification_hold_attrs

            case booking
                 |> Booking.changeset(
                   %{
                     modification_hold_expires_at: nil,
                     modification_hold_attrs: hold_attrs
                   },
                   skip_validation: true
                 )
                 |> Repo.update() do
              {:ok, updated_booking} -> updated_booking
              {:error, changeset} -> Repo.rollback({:error, changeset})
            end
          end)

        invalidate_availability_cache(result)
      end,
      max_attempts: 3,
      delay_ms: 100
    )
  end

  @doc """
  Modifies a complete booking's dates and guest counts with inventory reconciliation.

  Releases inventory for the old stay, books inventory for the new stay, recalculates
  pricing, and sets `refund_forfeited_at` on first modification.

  ## Parameters
  - `booking`: The booking to modify (must be `:complete`)
  - `attrs`: Map with `:checkin_date`, `:checkout_date`, `:guests_count`, optional `:children_count`
  - `opts`: Optional `:previous_details` map for modification email

  ## Returns
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def modify_complete_booking(booking, attrs, opts \\ []) do
    retry_on_stale(
      fn attempt ->
        if attempt > 1 do
          Ysc.Logging.info(
            "Retrying modify_complete_booking due to stale inventory",
            booking_id: booking.id,
            attempt: attempt
          )
        end

        do_modify_complete_booking(booking, attrs, opts)
      end,
      max_attempts: 3,
      delay_ms: 100
    )
  end

  defp do_modify_complete_booking(booking, attrs, opts) do
    previous_details = Keyword.get(opts, :previous_details)

    previous_details =
      previous_details ||
        %{
          checkin_date: booking.checkin_date,
          checkout_date: booking.checkout_date,
          guests_count: booking.guests_count,
          children_count: booking.children_count || 0,
          total_price: booking.total_price
        }

    result =
      Repo.transaction(fn ->
        booking =
          Repo.get!(Booking, booking.id)
          |> Repo.preload([:rooms, :user])

        if booking.status != :complete do
          Repo.rollback({:error, :invalid_status})
        end

        new_checkin = Map.get(attrs, :checkin_date, booking.checkin_date)
        new_checkout = Map.get(attrs, :checkout_date, booking.checkout_date)
        new_guests = Map.get(attrs, :guests_count, booking.guests_count)

        new_children =
          Map.get(attrs, :children_count, booking.children_count || 0)

        parsed_attrs = %{
          checkin_date: new_checkin,
          checkout_date: new_checkout,
          guests_count: new_guests,
          children_count: new_children
        }

        if modification_unchanged?(
             booking,
             new_checkin,
             new_checkout,
             new_guests,
             new_children
           ) do
          Repo.rollback({:error, :no_changes})
        end

        if Bookings.has_blackout?(booking.property, new_checkin, new_checkout) do
          Repo.rollback({:error, :blackout_conflict})
        end

        case Bookings.validate_modification_availability(booking, parsed_attrs) do
          :ok -> :ok
          {:error, reason} -> Repo.rollback({:error, reason})
        end

        user = booking.user || Repo.get!(Ysc.Accounts.User, booking.user_id)

        changeset =
          booking
          |> Booking.changeset(parsed_attrs, rooms: booking.rooms, user: user)

        if not changeset.valid? do
          Repo.rollback({:error, changeset})
        end

        hold_context = modification_hold_context(booking)

        release_booked_inventory!(booking)

        updated_for_inventory = %{
          booking
          | checkin_date: new_checkin,
            checkout_date: new_checkout,
            guests_count: new_guests,
            children_count: new_children
        }

        book_inventory_for_complete!(updated_for_inventory, hold_context)

        case Bookings.calculate_modification_pricing(updated_for_inventory) do
          {:ok, priced} ->
            refund_forfeited_at =
              booking.refund_forfeited_at ||
                DateTime.utc_now() |> DateTime.truncate(:second)

            update_attrs = %{
              checkin_date: new_checkin,
              checkout_date: new_checkout,
              guests_count: new_guests,
              children_count: new_children,
              total_price: priced.total,
              subtotal_price: priced.subtotal,
              discount_total: priced.discount,
              pricing_items: priced.pricing_items,
              modification_hold_expires_at: nil,
              modification_hold_attrs: nil
            }

            case booking
                 |> Booking.changeset(update_attrs,
                   rooms: booking.rooms,
                   skip_validation: true
                 )
                 |> put_change(:subtotal_price, priced.subtotal)
                 |> put_change(:discount_total, priced.discount)
                 |> put_change(:refund_forfeited_at, refund_forfeited_at)
                 |> Repo.update() do
              {:ok, updated_booking} ->
                Repo.preload(updated_booking, [:rooms, :user])

              {:error, changeset} ->
                Repo.rollback({:error, changeset})
            end

          {:error, reason} ->
            Repo.rollback({:error, reason})
        end
      end)

    case result do
      {:ok, updated_booking} ->
        reschedule_booking_reminders(updated_booking)
        send_booking_modification_email(updated_booking, previous_details)
        invalidate_availability_cache({:ok, updated_booking})
        {:ok, updated_booking}

      error ->
        invalidate_availability_cache(error)
    end
  end

  defp modification_unchanged?(booking, checkin, checkout, guests, children) do
    booking.checkin_date == checkin and booking.checkout_date == checkout and
      booking.guests_count == guests and
      (booking.children_count || 0) == children
  end

  def modification_hold_active?(%Booking{} = booking) do
    case modification_hold_context(booking) do
      %{active: true} -> true
      _ -> false
    end
  end

  def modification_hold_context(%Booking{} = booking) do
    now = DateTime.utc_now()

    cond do
      is_nil(booking.modification_hold_expires_at) ->
        %{active: false}

      DateTime.compare(booking.modification_hold_expires_at, now) != :gt ->
        %{active: false}

      is_nil(booking.modification_hold_attrs) ->
        %{active: false}

      true ->
        attrs = booking.modification_hold_attrs

        %{
          active: true,
          checkin_date: parse_hold_date!(attrs["checkin_date"]),
          checkout_date: parse_hold_date!(attrs["checkout_date"]),
          guests_count: attrs["guests_count"],
          children_count: Map.get(attrs, "children_count", 0),
          held_days:
            (Map.get(attrs, "held_days") || [])
            |> Enum.map(&parse_hold_date!/1)
            |> MapSet.new(),
          overlap_extra_guests: parse_overlap_extra_guests(attrs)
        }
    end
  end

  def modification_hold_matches?(booking, attrs) do
    case modification_hold_context(booking) do
      %{active: false} ->
        false

      hold ->
        hold.checkin_date == attrs.checkin_date and
          hold.checkout_date == attrs.checkout_date and
          hold.guests_count == attrs.guests_count and
          hold.children_count == (attrs.children_count || 0)
    end
  end

  defp parse_hold_date!(date) when is_binary(date), do: Date.from_iso8601!(date)
  defp parse_hold_date!(%Date{} = date), do: date

  defp parse_overlap_extra_guests(attrs) do
    (Map.get(attrs, "overlap_extra_guests") || %{})
    |> Enum.map(fn {day, count} ->
      {parse_hold_date!(day), count}
    end)
    |> Map.new()
  end

  defp encode_modification_hold_attrs(booking, attrs, hold_data, opts) do
    overlap_extra_guests =
      hold_data.overlap_extra_guests
      |> Enum.map(fn {day, count} -> {Date.to_iso8601(day), count} end)
      |> Map.new()

    base = %{
      "checkin_date" => Date.to_iso8601(attrs.checkin_date),
      "checkout_date" => Date.to_iso8601(attrs.checkout_date),
      "guests_count" => attrs.guests_count,
      "children_count" => attrs.children_count || 0,
      "held_days" => Enum.map(hold_data.held_days, &Date.to_iso8601/1),
      "overlap_extra_guests" => overlap_extra_guests,
      "booking_mode" => Atom.to_string(booking.booking_mode)
    }

    case Keyword.get(opts, :guest_params) do
      guest_params when is_map(guest_params) and map_size(guest_params) > 0 ->
        Map.put(base, "guest_params", guest_params)

      _ ->
        base
    end
  end

  defp compute_modification_hold_data(booking, attrs) do
    old_days =
      modification_stay_days(booking.checkin_date, booking.checkout_date)

    new_days = modification_stay_days(attrs.checkin_date, attrs.checkout_date)

    held_days =
      new_days
      |> MapSet.difference(old_days)
      |> MapSet.to_list()
      |> Enum.sort()

    overlap_days = MapSet.intersection(old_days, new_days)

    overlap_extra_guests =
      if booking.booking_mode == :day and
           attrs.guests_count > booking.guests_count do
        extra = attrs.guests_count - booking.guests_count

        overlap_days
        |> MapSet.to_list()
        |> Map.new(fn day -> {day, extra} end)
      else
        %{}
      end

    %{
      held_days: held_days,
      overlap_extra_guests: overlap_extra_guests
    }
  end

  defp modification_hold_needed?(%{
         held_days: held_days,
         overlap_extra_guests: overlap
       }) do
    held_days != [] or overlap != %{}
  end

  defp modification_stay_days(checkin, checkout) do
    checkin
    |> Date.range(Date.add(checkout, -1))
    |> MapSet.new()
  end

  defp hold_modification_inventory!(booking, attrs, hold_data) do
    if hold_data.held_days != [] do
      ensure_property_inventory_for_days(booking.property, hold_data.held_days)

      case booking.booking_mode do
        :buyout ->
          hold_buyout_days!(booking.property, hold_data.held_days)

        :room ->
          room_ids = Enum.map(booking.rooms, & &1.id)

          ensure_room_booking_inventory(
            booking.property,
            room_ids,
            hold_data.held_days
          )

          hold_room_days!(room_ids, hold_data.held_days)

        :day ->
          hold_day_capacity!(
            booking.property,
            hold_data.held_days,
            attrs.guests_count
          )
      end
    end

    if hold_data.overlap_extra_guests != %{} do
      for day <- Map.keys(hold_data.overlap_extra_guests) do
        ensure_property_inventory_row(
          booking.property,
          day,
          get_property_capacity_for_date(booking.property, day)
        )
      end

      hold_day_capacity!(
        booking.property,
        Map.keys(hold_data.overlap_extra_guests),
        nil,
        hold_data.overlap_extra_guests
      )
    end

    :ok
  end

  defp hold_buyout_days!(property, days) do
    prop_inv =
      Repo.all(
        from pi in PropertyInventory,
          where: pi.property == ^property and pi.day in ^days
      )

    if length(prop_inv) != length(days) do
      Repo.rollback({:error, :property_unavailable})
    end

    update_property_inventory_for_buyout(prop_inv, property)
  end

  defp hold_room_days!(room_ids, days) do
    room_inv =
      Repo.all(
        from ri in RoomInventory,
          where: ri.room_id in ^room_ids and ri.day in ^days
      )

    expected = length(room_ids) * length(days)

    if length(room_inv) != expected do
      Repo.rollback({:error, :room_unavailable})
    end

    update_room_inventory_for_booking(room_inv)
  end

  defp hold_day_capacity!(property, days, guests_count, overlap_extra \\ nil) do
    prop_inv =
      Repo.all(
        from pi in PropertyInventory,
          where: pi.property == ^property and pi.day in ^days
      )

    if length(prop_inv) != length(days) do
      Repo.rollback({:error, :property_unavailable})
    end

    update_results =
      Enum.map(prop_inv, fn pi ->
        guests_to_hold =
          cond do
            overlap_extra -> Map.get(overlap_extra, pi.day)
            guests_count -> guests_count
            true -> nil
          end

        if is_nil(guests_to_hold) or guests_to_hold <= 0 do
          {:ok, :skipped}
        else
          {count, _} =
            Repo.update_all(
              from(pi2 in PropertyInventory,
                where:
                  pi2.property == ^property and pi2.day == ^pi.day and
                    pi2.lock_version == ^pi.lock_version and
                    pi2.buyout_held == false and pi2.buyout_booked == false and
                    pi2.capacity_booked + pi2.capacity_held + ^guests_to_hold <=
                      pi2.capacity_total
              ),
              set: [
                capacity_held: pi.capacity_held + guests_to_hold,
                lock_version: pi.lock_version + 1,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
        end
      end)

    if Enum.any?(update_results, &match?({:error, _}, &1)) do
      raise_stale_inventory!(List.first(prop_inv))
    end
  end

  defp release_modification_hold_inventory!(booking) do
    case decode_modification_hold_attrs(booking.modification_hold_attrs) do
      nil ->
        :ok

      hold_attrs ->
        release_modification_hold_inventory_for_attrs!(booking, hold_attrs)
    end
  end

  defp decode_modification_hold_attrs(nil), do: nil

  defp decode_modification_hold_attrs(attrs) do
    held_days =
      (Map.get(attrs, "held_days") || [])
      |> Enum.map(&parse_hold_date!/1)

    overlap_extra_guests = parse_overlap_extra_guests(attrs)

    if held_days == [] and overlap_extra_guests == %{} do
      nil
    else
      %{
        held_days: held_days,
        overlap_extra_guests: overlap_extra_guests,
        guests_count: Map.get(attrs, "guests_count", 0)
      }
    end
  end

  defp release_modification_hold_inventory_for_attrs!(booking, hold_attrs) do
    guests_count = Map.get(hold_attrs, :guests_count, booking.guests_count)

    case booking.booking_mode do
      :buyout ->
        release_buyout_held_days!(booking.property, hold_attrs.held_days)

      :room ->
        room_ids = Enum.map(booking.rooms, & &1.id)
        release_room_held_days!(room_ids, hold_attrs.held_days)

      :day ->
        if hold_attrs.held_days != [] do
          release_day_held_days!(
            booking.property,
            hold_attrs.held_days,
            guests_count
          )
        end

        if hold_attrs.overlap_extra_guests != %{} do
          release_day_overlap_extra!(
            booking.property,
            hold_attrs.overlap_extra_guests
          )
        end
    end

    :ok
  end

  defp release_buyout_held_days!(_property, days) when days == [], do: :ok

  defp release_buyout_held_days!(property, days) do
    prop_inv =
      Repo.all(
        from pi in PropertyInventory,
          where:
            pi.property == ^property and pi.day in ^days and
              pi.buyout_held == true
      )

    update_results =
      Enum.map(prop_inv, fn pi ->
        {count, _} =
          Repo.update_all(
            from(pi2 in PropertyInventory,
              where:
                pi2.property == ^property and pi2.day == ^pi.day and
                  pi2.lock_version == ^pi.lock_version and
                  pi2.buyout_held == true
            ),
            set: [
              buyout_held: false,
              lock_version: pi.lock_version + 1,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
      end)

    if Enum.any?(update_results, &match?({:error, _}, &1)) do
      raise_stale_inventory!(List.first(prop_inv))
    end
  end

  defp release_room_held_days!(room_ids, days)
       when days == [] or room_ids == [], do: :ok

  defp release_room_held_days!(room_ids, days) do
    room_inv =
      Repo.all(
        from ri in RoomInventory,
          where: ri.room_id in ^room_ids and ri.day in ^days and ri.held == true
      )

    update_results =
      Enum.map(room_inv, fn ri ->
        {count, _} =
          Repo.update_all(
            from(ri2 in RoomInventory,
              where:
                ri2.room_id == ^ri.room_id and ri2.day == ^ri.day and
                  ri2.lock_version == ^ri.lock_version and ri2.held == true
            ),
            set: [
              held: false,
              lock_version: ri.lock_version + 1,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
      end)

    if Enum.any?(update_results, &match?({:error, _}, &1)) do
      raise_stale_inventory!(List.first(room_inv))
    end
  end

  defp release_day_held_days!(property, days, guests_count) do
    prop_inv =
      Repo.all(
        from pi in PropertyInventory,
          where:
            pi.property == ^property and pi.day in ^days and
              pi.capacity_held >= ^guests_count
      )

    update_results =
      Enum.map(prop_inv, fn pi ->
        {count, _} =
          Repo.update_all(
            from(pi2 in PropertyInventory,
              where:
                pi2.property == ^property and pi2.day == ^pi.day and
                  pi2.lock_version == ^pi.lock_version and
                  pi2.capacity_held >= ^guests_count
            ),
            set: [
              capacity_held: pi.capacity_held - guests_count,
              lock_version: pi.lock_version + 1,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
      end)

    if Enum.any?(update_results, &match?({:error, _}, &1)) do
      raise_stale_inventory!(List.first(prop_inv))
    end
  end

  defp release_day_overlap_extra!(property, overlap_extra_guests) do
    days = Map.keys(overlap_extra_guests)

    prop_inv =
      Repo.all(
        from pi in PropertyInventory,
          where: pi.property == ^property and pi.day in ^days
      )

    update_results =
      Enum.map(prop_inv, fn pi ->
        extra = Map.get(overlap_extra_guests, pi.day, 0)

        if extra <= 0 or pi.capacity_held < extra do
          {:error, :stale_inventory}
        else
          {count, _} =
            Repo.update_all(
              from(pi2 in PropertyInventory,
                where:
                  pi2.property == ^property and pi2.day == ^pi.day and
                    pi2.lock_version == ^pi.lock_version and
                    pi2.capacity_held >= ^extra
              ),
              set: [
                capacity_held: pi.capacity_held - extra,
                lock_version: pi.lock_version + 1,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
        end
      end)

    if Enum.any?(update_results, &match?({:error, _}, &1)) do
      raise_stale_inventory!(List.first(prop_inv))
    end
  end

  defp release_booked_inventory!(booking) do
    days =
      booking.checkin_date
      |> Date.range(Date.add(booking.checkout_date, -1))
      |> Enum.to_list()

    case booking.booking_mode do
      :buyout ->
        prop_inv =
          Repo.all(
            from pi in PropertyInventory,
              where:
                pi.property == ^booking.property and pi.day in ^days and
                  pi.buyout_booked == true
          )

        if length(prop_inv) != length(days) do
          Repo.rollback({:error, :inventory_update_failed})
        end

        release_buyout_booked_days!(booking.property, prop_inv)

      :room ->
        room_ids = Enum.map(booking.rooms, & &1.id)

        if room_ids != [] do
          room_inv =
            Repo.all(
              from ri in RoomInventory,
                where:
                  ri.room_id in ^room_ids and ri.day in ^days and
                    ri.booked == true
            )

          expected = length(room_ids) * length(days)

          if length(room_inv) != expected do
            Repo.rollback({:error, :inventory_update_failed})
          end

          release_room_booked_days!(room_inv)
        end

      :day ->
        if length(days) !=
             length(fetch_property_inventory_days(booking.property, days)) do
          ensure_property_inventory_for_days(booking.property, days)
        end

        prop_inv =
          Repo.all(
            from pi in PropertyInventory,
              where:
                pi.property == ^booking.property and pi.day in ^days and
                  pi.capacity_booked >= ^booking.guests_count
          )

        if length(prop_inv) != length(days) do
          Repo.rollback({:error, :inventory_update_failed})
        end

        release_day_booked_days!(
          booking.property,
          prop_inv,
          booking.guests_count
        )
    end
  end

  defp release_buyout_booked_days!(property, prop_inv) do
    update_results =
      Enum.map(prop_inv, fn pi ->
        {count, _} =
          Repo.update_all(
            from(pi2 in PropertyInventory,
              where:
                pi2.property == ^property and pi2.day == ^pi.day and
                  pi2.lock_version == ^pi.lock_version and
                  pi2.buyout_booked == true
            ),
            set: [
              buyout_booked: false,
              lock_version: pi.lock_version + 1,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
      end)

    if Enum.any?(update_results, &match?({:error, _}, &1)) do
      raise_stale_inventory!(List.first(prop_inv))
    end
  end

  defp release_room_booked_days!(room_inv) do
    update_results =
      Enum.map(room_inv, fn ri ->
        {count, _} =
          Repo.update_all(
            from(ri2 in RoomInventory,
              where:
                ri2.room_id == ^ri.room_id and ri2.day == ^ri.day and
                  ri2.lock_version == ^ri.lock_version and ri2.booked == true
            ),
            set: [
              booked: false,
              lock_version: ri.lock_version + 1,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
      end)

    if Enum.any?(update_results, &match?({:error, _}, &1)) do
      raise_stale_inventory!(List.first(room_inv))
    end
  end

  defp release_day_booked_days!(property, prop_inv, guests_count) do
    update_results =
      Enum.map(prop_inv, fn pi ->
        {count, _} =
          Repo.update_all(
            from(pi2 in PropertyInventory,
              where:
                pi2.property == ^property and pi2.day == ^pi.day and
                  pi2.lock_version == ^pi.lock_version and
                  pi2.capacity_booked >= ^guests_count
            ),
            set: [
              capacity_booked: pi.capacity_booked - guests_count,
              lock_version: pi.lock_version + 1,
              updated_at: DateTime.truncate(DateTime.utc_now(), :second)
            ]
          )

        if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
      end)

    if Enum.any?(update_results, &match?({:error, _}, &1)) do
      raise_stale_inventory!(List.first(prop_inv))
    end
  end

  defp book_inventory_for_complete!(booking, hold_context) do
    days =
      booking.checkin_date
      |> Date.range(Date.add(booking.checkout_date, -1))
      |> Enum.to_list()

    held_days =
      case hold_context do
        %{active: true, held_days: held_days} ->
          held_days |> MapSet.to_list() |> MapSet.new()

        _ ->
          MapSet.new()
      end

    overlap_extra_guests =
      case hold_context do
        %{active: true, overlap_extra_guests: overlap} -> overlap
        _ -> %{}
      end

    case booking.booking_mode do
      :buyout ->
        book_buyout_days!(booking, days, held_days)

      :room ->
        room_ids = Enum.map(booking.rooms, & &1.id)

        if room_ids != [] do
          book_room_days!(booking, room_ids, days, held_days)
        else
          :ok
        end

      :day ->
        book_day_capacity!(booking, days, held_days, overlap_extra_guests)
    end
  end

  @dialyzer {:nowarn_function, book_buyout_days!: 3}
  defp book_buyout_days!(booking, days, held_days) do
    prop_inv =
      Repo.all(
        from pi in PropertyInventory,
          where: pi.property == ^booking.property and pi.day in ^days
      )

    if length(prop_inv) != length(days) do
      ensure_inventory_exists_and_book(booking)
    else
      update_results =
        Enum.map(prop_inv, fn pi ->
          from_held = MapSet.member?(held_days, pi.day)

          query =
            if from_held do
              from(pi2 in PropertyInventory,
                where:
                  pi2.property == ^booking.property and pi2.day == ^pi.day and
                    pi2.lock_version == ^pi.lock_version and
                    pi2.buyout_held == true
              )
            else
              from(pi2 in PropertyInventory,
                where:
                  pi2.property == ^booking.property and pi2.day == ^pi.day and
                    pi2.lock_version == ^pi.lock_version and
                    pi2.buyout_held == false and
                    pi2.buyout_booked == false and
                    (type(^booking.property, Ysc.Bookings.BookingProperty) !=
                       :clear_lake or
                       (pi2.capacity_held == 0 and pi2.capacity_booked == 0))
              )
            end

          {count, _} =
            Repo.update_all(
              query,
              set: [
                buyout_booked: true,
                buyout_held: false,
                lock_version: pi.lock_version + 1,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
        end)

      if Enum.any?(update_results, &match?({:error, _}, &1)) do
        raise_stale_inventory!(List.first(prop_inv))
      end
    end
  end

  @dialyzer {:nowarn_function, book_room_days!: 4}
  defp book_room_days!(booking, room_ids, days, held_days) do
    room_inv =
      Repo.all(
        from ri in RoomInventory,
          where: ri.room_id in ^room_ids and ri.day in ^days
      )

    expected = length(room_ids) * length(days)

    if length(room_inv) != expected do
      ensure_room_inventory_exists_and_book(booking, room_ids)
    else
      update_results =
        Enum.map(room_inv, fn ri ->
          from_held = MapSet.member?(held_days, ri.day)

          query =
            if from_held do
              from(ri2 in RoomInventory,
                where:
                  ri2.room_id == ^ri.room_id and ri2.day == ^ri.day and
                    ri2.lock_version == ^ri.lock_version and ri2.held == true
              )
            else
              from(ri2 in RoomInventory,
                where:
                  ri2.room_id == ^ri.room_id and ri2.day == ^ri.day and
                    ri2.lock_version == ^ri.lock_version and ri2.held == false and
                    ri2.booked == false
              )
            end

          {count, _} =
            Repo.update_all(
              query,
              set: [
                booked: true,
                held: false,
                lock_version: ri.lock_version + 1,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
        end)

      if Enum.any?(update_results, &match?({:error, _}, &1)) do
        raise_stale_inventory!(List.first(room_inv))
      end
    end
  end

  @dialyzer {:nowarn_function, book_day_capacity!: 4}
  defp book_day_capacity!(booking, days, held_days, overlap_extra_guests) do
    if length(days) !=
         length(fetch_property_inventory_days(booking.property, days)) do
      ensure_property_inventory_for_days(booking.property, days)
    end

    prop_inv = fetch_property_inventory_days(booking.property, days)

    if length(prop_inv) != length(days) do
      Repo.rollback({:error, :inventory_update_failed})
    end

    update_results =
      Enum.map(prop_inv, fn pi ->
        from_held = MapSet.member?(held_days, pi.day)
        overlap_extra = Map.get(overlap_extra_guests, pi.day, 0)

        cond do
          from_held ->
            {count, _} =
              Repo.update_all(
                from(pi2 in PropertyInventory,
                  where:
                    pi2.property == ^booking.property and pi2.day == ^pi.day and
                      pi2.lock_version == ^pi.lock_version and
                      pi2.capacity_held >= ^booking.guests_count
                ),
                set: [
                  capacity_booked: pi.capacity_booked + booking.guests_count,
                  capacity_held: pi.capacity_held - booking.guests_count,
                  lock_version: pi.lock_version + 1,
                  updated_at: DateTime.truncate(DateTime.utc_now(), :second)
                ]
              )

            if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}

          overlap_extra > 0 ->
            {count, _} =
              Repo.update_all(
                from(pi2 in PropertyInventory,
                  where:
                    pi2.property == ^booking.property and pi2.day == ^pi.day and
                      pi2.lock_version == ^pi.lock_version and
                      pi2.capacity_held >= ^overlap_extra and
                      pi2.capacity_booked + pi2.capacity_held - ^overlap_extra +
                        ^booking.guests_count <= pi2.capacity_total
                ),
                set: [
                  capacity_booked: pi.capacity_booked + booking.guests_count,
                  capacity_held: pi.capacity_held - overlap_extra,
                  lock_version: pi.lock_version + 1,
                  updated_at: DateTime.truncate(DateTime.utc_now(), :second)
                ]
              )

            if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}

          true ->
            {count, _} =
              Repo.update_all(
                from(pi2 in PropertyInventory,
                  where:
                    pi2.property == ^booking.property and pi2.day == ^pi.day and
                      pi2.lock_version == ^pi.lock_version and
                      pi2.buyout_held == false and pi2.buyout_booked == false and
                      pi2.capacity_booked + pi2.capacity_held +
                        ^booking.guests_count <=
                        pi2.capacity_total
                ),
                set: [
                  capacity_booked: pi.capacity_booked + booking.guests_count,
                  lock_version: pi.lock_version + 1,
                  updated_at: DateTime.truncate(DateTime.utc_now(), :second)
                ]
              )

            if count == 1, do: {:ok, :updated}, else: {:error, :stale_inventory}
        end
      end)

    if Enum.any?(update_results, &match?({:error, _}, &1)) do
      raise_stale_inventory!(List.first(prop_inv))
    end
  end

  defp raise_stale_inventory!(struct) do
    raise Ecto.StaleEntryError, struct: struct, action: :update
  end

  defp fetch_property_inventory_days(property, days) do
    Repo.all(
      from pi in PropertyInventory,
        where: pi.property == ^property and pi.day in ^days
    )
  end

  defp reschedule_booking_reminders(booking) do
    import Ecto.Query

    reminder_workers = [
      "YscWeb.Workers.BookingCheckinReminderWorker",
      "YscWeb.Workers.BookingCheckoutReminderWorker"
    ]

    _ =
      from(j in Oban.Job,
        where: j.worker in ^reminder_workers,
        where: fragment("?->>'booking_id' = ?", j.args, ^booking.id),
        where: j.state in ["available", "scheduled", "retryable"]
      )
      |> Repo.update_all(
        set: [
          state: "cancelled",
          cancelled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        ]
      )

    schedule_checkin_reminder(booking)
    schedule_checkout_reminder(booking)
  end

  defp send_booking_modification_email(booking, previous_details) do
    require Ysc.Logging

    try do
      booking =
        Repo.get(Booking, booking.id)
        |> Repo.preload([:user, :rooms])

      if booking && booking.user do
        email_data =
          YscWeb.Emails.BookingModificationConfirmation.prepare_email_data(
            booking,
            previous_details
          )

        modified_at_unix =
          (booking.updated_at || DateTime.utc_now())
          |> DateTime.truncate(:second)
          |> DateTime.to_unix()

        idempotency_key =
          "booking_modification_#{booking.id}_#{modified_at_unix}"

        result =
          YscWeb.Emails.Notifier.schedule_email(
            booking.user.email,
            idempotency_key,
            YscWeb.Emails.BookingModificationConfirmation.get_subject(),
            "booking_modification_confirmation",
            email_data,
            "",
            booking.user_id,
            Ysc.EmailConfig.booking_reply_to(booking.property)
          )

        case result do
          %Oban.Job{} = job ->
            Ysc.Logging.info(
              "Booking modification email scheduled successfully",
              booking_id: booking.id,
              job_id: job.id
            )

          {:error, reason} ->
            Ysc.Logging.error(
              "Failed to schedule booking modification email",
              booking_id: booking.id,
              error: reason
            )
        end
      end
    rescue
      error ->
        Ysc.Logging.error(
          "Failed to send booking modification email",
          booking_id: booking.id,
          error: Exception.message(error)
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
          release_day_booked_capacity_for_stay!(booking)
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
    |> invalidate_availability_cache()
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
            release_day_booked_capacity_for_stay!(booking)
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
    |> invalidate_availability_cache()
  end

  ## Private Functions

  defp invalidate_availability_cache({:ok, _} = result) do
    Ysc.Bookings.AvailabilityCache.invalidate()
    result
  end

  defp invalidate_availability_cache(result), do: result

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

  @dialyzer {:nowarn_function, build_room_pricing_items: 6}
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

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    property = :tahoe
    checkin_date = Fixtures.today()
    checkout_date = Date.add(checkin_date, 3)

    from(pi in PropertyInventory,
      where:
        pi.property == ^property and
          pi.day >= ^checkin_date and
          pi.day < ^checkout_date
    )
  end
end

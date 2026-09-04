defmodule Ysc.Bookings.ModificationDateAvailability do
  @moduledoc """
  Builds calendar constraints for member booking modifications.

  Generates date tooltip maps used by the date range picker to disable dates
  that would violate booking policy or availability for the existing booking.
  """

  import Ecto.Query, warn: false

  alias Ysc.Bookings

  alias Ysc.Bookings.{
    Booking,
    BookingLocker,
    BookingValidator,
    PropertyInventory,
    Room,
    RoomInventory,
    Season,
    SeasonHelpers
  }

  alias Ysc.Repo

  @cabin_timezone "America/Los_Angeles"

  defmodule Snapshot do
    @moduledoc false
    defstruct [
      :booking,
      :old_days,
      :hold,
      :blackouts,
      :property_by_day,
      :room_by_key,
      :tahoe_rooms_by_day,
      :room_conflicts
    ]
  end

  @doc """
  Returns calendar bounds and metadata for a booking modification picker.
  """
  def calendar_context(%Booking{} = booking) do
    booking = Repo.preload(booking, :rooms)
    today = today_pst()
    seasons = Bookings.list_seasons(booking.property)

    calendar_bounds(booking, today, seasons)
  end

  @doc """
  Lightweight calendar bounds for the initial static render before WebSocket connect.

  Avoids `list_seasons/1` and other database reads; replaced with `calendar_context/1`
  when async change data loads.
  """
  def calendar_placeholder(%Booking{} = booking) do
    today = today_pst()

    calendar_bounds(
      booking,
      today,
      [],
      max_date: Date.add(today, 365),
      max_nights: 365
    )
  end

  defp calendar_bounds(booking, today, seasons, opts \\ []) do
    max_date =
      Keyword.get_lazy(opts, :max_date, fn ->
        SeasonHelpers.calculate_max_booking_date(
          booking.property,
          today,
          seasons
        )
      end)

    max_nights =
      Keyword.get_lazy(opts, :max_nights, fn ->
        max_nights_for_checkin(booking, booking.checkin_date, seasons)
      end)

    %{
      today: today,
      seasons: seasons,
      min_date: today,
      max_date: max_date,
      max_nights: max_nights
    }
  end

  @doc """
  Builds an availability snapshot sized for validating proposed modification dates.

  Uses batched inventory, blackout, and booking-conflict queries instead of
  per-day `room_available?/4` checks during `prepare_modification/2`.
  """
  def build_snapshot_for_modification(%Booking{} = booking, checkin, checkout) do
    %{today: today, seasons: seasons, min_date: cal_min, max_date: cal_max} =
      calendar_context(booking)

    min_date =
      [cal_min, booking.checkin_date, checkin]
      |> Enum.min(Date)

    max_date =
      [cal_max, booking.checkout_date, checkout]
      |> Enum.max(Date)

    build_availability_snapshot(booking, min_date, max_date, today, seasons)
  end

  @doc """
  Returns `:ok` or `{:error, reason}` for proposed modification dates.

  Pass a prebuilt `Snapshot` from `build_snapshot_for_modification/3` or
  `build_availability_snapshot/5` to avoid rebuilding inventory data.
  """
  def validate_modification_dates(%Snapshot{} = snapshot, checkin, checkout) do
    snapshot = refresh_snapshot_hold(snapshot)

    case modification_availability_error(snapshot, checkin, checkout) do
      nil -> :ok
      reason -> {:error, reason}
    end
  end

  def validate_modification_dates(%Booking{} = booking, checkin, checkout) do
    booking
    |> build_snapshot_for_modification(checkin, checkout)
    |> validate_modification_dates(checkin, checkout)
  end

  @doc false
  def refresh_snapshot_hold(%Snapshot{booking: booking} = snapshot) do
    %{snapshot | hold: BookingLocker.modification_hold_context(booking)}
  end

  @doc """
  Prefetches blackout, inventory, and room-conflict data for a calendar range.

  Pass the returned snapshot to `checkin_date_tooltips/6` and
  `checkout_date_tooltips/6` to avoid repeated database queries while building
  tooltip maps.
  """
  def build_availability_snapshot(
        %Booking{} = booking,
        min_date,
        max_date,
        _today,
        seasons
      ) do
    booking = Repo.preload(booking, :rooms)
    hold = BookingLocker.modification_hold_context(booking)

    old_days =
      modification_date_range(booking.checkin_date, booking.checkout_date)

    query_end =
      Date.add(max_date, max_property_nights(booking.property, seasons))

    days = Date.range(min_date, query_end) |> Enum.to_list()
    room_ids = Enum.map(booking.rooms, & &1.id)

    property_rows =
      Repo.all(
        from pi in PropertyInventory,
          where: pi.property == ^booking.property and pi.day in ^days
      )

    property_by_day = Map.new(property_rows, &{&1.day, &1})

    room_by_key =
      if room_ids == [] do
        %{}
      else
        booking.property
        |> load_room_inventory(room_ids, days)
        |> Map.new(fn ri -> {{ri.room_id, ri.day}, ri} end)
      end

    tahoe_rooms_by_day =
      if booking.property == :tahoe do
        load_tahoe_room_inventory(days)
      else
        %{}
      end

    %Snapshot{
      booking: booking,
      old_days: old_days,
      hold: hold,
      blackouts:
        Bookings.get_overlapping_blackouts(
          booking.property,
          min_date,
          query_end
        ),
      property_by_day: property_by_day,
      room_by_key: room_by_key,
      tahoe_rooms_by_day: tahoe_rooms_by_day,
      room_conflicts:
        load_room_conflicts(booking, room_ids, min_date, query_end)
    }
  end

  @doc """
  Returns a map of ISO date strings to unavailability messages for check-in dates.
  """
  def checkin_date_tooltips(
        booking,
        min_date,
        max_date,
        today,
        seasons,
        snapshot \\ nil
      )

  def checkin_date_tooltips(
        %Booking{} = booking,
        min_date,
        max_date,
        today,
        seasons,
        nil
      ) do
    snapshot =
      build_availability_snapshot(booking, min_date, max_date, today, seasons)

    checkin_date_tooltips(
      booking,
      min_date,
      max_date,
      today,
      seasons,
      snapshot
    )
  end

  def checkin_date_tooltips(
        _booking,
        min_date,
        max_date,
        today,
        seasons,
        %Snapshot{} = snapshot
      ) do
    Date.range(min_date, max_date)
    |> Enum.reduce(%{}, fn date, acc ->
      case checkin_unavailability_reason(
             snapshot,
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
        booking,
        checkin_date,
        max_date,
        today,
        seasons,
        snapshot \\ nil
      )

  def checkout_date_tooltips(
        %Booking{} = booking,
        checkin_date,
        max_date,
        today,
        seasons,
        nil
      ) do
    min_date = today

    snapshot =
      build_availability_snapshot(booking, min_date, max_date, today, seasons)

    checkout_date_tooltips(
      booking,
      checkin_date,
      max_date,
      today,
      seasons,
      snapshot
    )
  end

  def checkout_date_tooltips(
        _booking,
        checkin_date,
        max_date,
        today,
        seasons,
        %Snapshot{} = snapshot
      ) do
    if is_nil(checkin_date) or Date.compare(checkin_date, max_date) == :gt do
      %{}
    else
      booking = snapshot.booking
      max_nights = max_nights_for_checkin(booking, checkin_date, seasons)
      latest_checkout = min_date(Date.add(checkin_date, max_nights), max_date)
      first_checkout = Date.add(checkin_date, 1)

      if Date.compare(first_checkout, latest_checkout) == :gt do
        %{}
      else
        Date.range(first_checkout, latest_checkout)
        |> Enum.reduce(%{}, fn checkout, acc ->
          case checkout_unavailability_reason(
                 snapshot,
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
         snapshot,
         date,
         min_date,
         max_date,
         today,
         seasons
       ) do
    booking = snapshot.booking

    cond do
      Date.compare(date, min_date) == :lt ->
        "Past dates cannot be booked"

      Date.compare(date, max_date) == :gt ->
        "Bookings are not open for this date yet"

      not SeasonHelpers.date_selectable?(booking.property, date, today, seasons) ->
        "Bookings for this season are not yet open"

      blackout_on_date?(snapshot, date) ->
        "This date is unavailable"

      buyout_on_date?(snapshot, date) and booking.booking_mode == :room ->
        "The entire cabin is already booked on this date"

      not has_valid_checkout?(snapshot, date, max_date, today, seasons) ->
        availability_message(booking)

      true ->
        nil
    end
  end

  defp checkout_unavailability_reason(
         snapshot,
         checkin,
         checkout,
         today,
         seasons
       ) do
    booking = snapshot.booking

    cond do
      not SeasonHelpers.date_selectable?(
        booking.property,
        checkout,
        today,
        seasons
      ) ->
        "Bookings for this season are not yet open"

      weekend_message =
          weekend_unavailability_message(booking.property, checkin, checkout) ->
        weekend_message

      buyout_winter_blocked?(booking, checkin, checkout, seasons) ->
        "Booking the entire cabin isn't available for winter nights in this stay"

      true ->
        case modification_availability_error(snapshot, checkin, checkout) do
          nil -> nil
          reason -> availability_error_message(reason)
        end
    end
  end

  defp has_valid_checkout?(snapshot, checkin, max_date, today, seasons) do
    booking = snapshot.booking
    max_nights = max_nights_for_checkin(booking, checkin, seasons)
    latest_checkout = min_date(Date.add(checkin, max_nights), max_date)
    first_checkout = Date.add(checkin, 1)

    if Date.compare(first_checkout, latest_checkout) == :gt do
      false
    else
      Enum.any?(Date.range(first_checkout, latest_checkout), fn checkout ->
        is_nil(
          weekend_unavailability_message(booking.property, checkin, checkout)
        ) and
          not buyout_winter_blocked?(booking, checkin, checkout, seasons) and
          is_nil(modification_availability_error(snapshot, checkin, checkout)) and
          SeasonHelpers.date_selectable?(
            booking.property,
            checkout,
            today,
            seasons
          )
      end)
    end
  end

  defp buyout_winter_blocked?(
         %{booking_mode: :buyout, property: :tahoe},
         checkin,
         checkout,
         seasons
       )
       when is_list(seasons) do
    not Season.buyout_allowed_for_stay?(seasons, checkin, checkout)
  end

  defp buyout_winter_blocked?(_booking, _checkin, _checkout, _seasons),
    do: false

  defp modification_availability_error(
         %Snapshot{} = snapshot,
         checkin,
         checkout
       ) do
    booking = snapshot.booking
    new_guests = booking.guests_count
    new_days = modification_date_range(checkin, checkout)

    availability_result =
      case booking.booking_mode do
        :buyout ->
          validate_buyout_modification(snapshot, new_days)

        :room ->
          validate_room_modification(snapshot, checkin, checkout)

        :day ->
          validate_day_modification(snapshot, new_days, new_guests)

        _ ->
          {:error, :invalid_booking_mode}
      end

    case availability_result do
      :ok ->
        if blackout_conflict?(snapshot, checkin, checkout) do
          :blackout_conflict
        else
          nil
        end

      {:error, reason} ->
        reason
    end
  end

  defp validate_buyout_modification(snapshot, new_days) do
    booking = snapshot.booking
    held_days = held_days(snapshot.hold)

    unavailable? =
      new_days
      |> MapSet.to_list()
      |> Enum.map(&Map.get(snapshot.property_by_day, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.any?(fn pi ->
        day_in_old = MapSet.member?(snapshot.old_days, pi.day)
        our_hold = MapSet.member?(held_days, pi.day)

        blocked_buyout =
          not day_in_old and
            (pi.buyout_booked == true or
               (pi.buyout_held == true and not our_hold))

        blocked_capacity =
          booking.property == :clear_lake and not day_in_old and
            (pi.capacity_held > 0 or pi.capacity_booked > 0) and
            not our_hold

        blocked_buyout or blocked_capacity
      end)

    cond do
      unavailable? ->
        {:error, :property_unavailable}

      booking.property == :tahoe ->
        blocked_rooms =
          Enum.any?(MapSet.to_list(new_days), fn day ->
            room_rows = Map.get(snapshot.tahoe_rooms_by_day, day, [])

            Enum.any?(room_rows, fn ri ->
              not MapSet.member?(snapshot.old_days, ri.day) and
                (ri.held == true or ri.booked == true) and
                not MapSet.member?(held_days, ri.day)
            end)
          end)

        if blocked_rooms, do: {:error, :rooms_already_booked}, else: :ok

      true ->
        :ok
    end
  end

  defp validate_room_modification(snapshot, checkin, checkout) do
    cond do
      inactive_room_assigned?(snapshot.booking) ->
        {:error, :room_unavailable}

      blackout_conflict?(snapshot, checkin, checkout) ->
        {:error, :blackout_conflict}

      buyout_active?(snapshot, checkin, checkout) ->
        {:error, :property_buyout_active}

      room_unavailable?(snapshot, checkin, checkout) ->
        {:error, :room_unavailable}

      true ->
        :ok
    end
  end

  defp validate_day_modification(snapshot, new_days, new_guests) do
    held_days = held_days(snapshot.hold)
    overlap_extra = overlap_extra(snapshot.hold)

    unavailable? =
      Enum.any?(MapSet.to_list(new_days), fn day ->
        pi = Map.get(snapshot.property_by_day, day)

        # Missing inventory rows mean the night has never been held/booked —
        # treat as available, matching buyout modification and new Clear Lake booking.
        if is_nil(pi) do
          false
        else
          released_guests =
            if MapSet.member?(snapshot.old_days, day),
              do: snapshot.booking.guests_count,
              else: 0

          our_overlap_extra = Map.get(overlap_extra, day, 0)

          our_new_day_hold =
            if MapSet.member?(held_days, day), do: new_guests, else: 0

          available =
            pi.capacity_total - pi.capacity_booked - pi.capacity_held +
              released_guests + our_overlap_extra + our_new_day_hold

          new_guests > available
        end
      end)

    if unavailable?, do: {:error, :property_unavailable}, else: :ok
  end

  defp inactive_room_assigned?(%Booking{rooms: rooms}) when is_list(rooms) do
    Enum.any?(rooms, &(Map.get(&1, :is_active) == false))
  end

  defp inactive_room_assigned?(_), do: false

  defp room_unavailable?(snapshot, checkin, checkout) do
    held_days = held_days(snapshot.hold)

    snapshot.booking.rooms
    |> Enum.map(& &1.id)
    |> Enum.any?(fn room_id ->
      checkin
      |> Date.range(Date.add(checkout, -1))
      |> Enum.any?(fn day ->
        not MapSet.member?(snapshot.old_days, day) and
          not MapSet.member?(held_days, day) and
          room_blocked_on_day?(snapshot, room_id, day)
      end)
    end)
  end

  defp room_blocked_on_day?(snapshot, room_id, day) do
    checkout = Date.add(day, 1)

    room_conflict_on_day?(snapshot.room_conflicts, room_id, day) or
      buyout_active?(snapshot, day, checkout) or
      blackout_conflict?(snapshot, day, checkout)
  end

  defp room_conflict_on_day?(conflicts, room_id, day) do
    Enum.any?(conflicts, fn {id, checkin, checkout} ->
      id == room_id and
        Date.compare(checkin, Date.add(day, 1)) == :lt and
        Date.compare(checkout, day) == :gt
    end)
  end

  defp buyout_active?(snapshot, checkin, checkout) do
    if Date.compare(checkout, checkin) != :gt do
      false
    else
      checkin
      |> Date.range(Date.add(checkout, -1))
      |> Enum.any?(fn day ->
        case Map.get(snapshot.property_by_day, day) do
          %{buyout_held: true} -> true
          %{buyout_booked: true} -> true
          _ -> false
        end
      end)
    end
  end

  defp blackout_on_date?(snapshot, date) do
    blackout_conflict?(snapshot, date, Date.add(date, 1))
  end

  defp blackout_conflict?(snapshot, checkin, checkout) do
    Enum.any?(snapshot.blackouts, fn blackout ->
      cond do
        checkout == blackout.start_date ->
          false

        checkin == blackout.end_date ->
          false

        Date.compare(checkin, blackout.end_date) == :lt &&
            Date.compare(checkout, blackout.start_date) == :gt ->
          true

        true ->
          false
      end
    end)
  end

  defp buyout_on_date?(snapshot, date) do
    case Map.get(snapshot.property_by_day, date) do
      %{buyout_held: true} -> true
      %{buyout_booked: true} -> true
      _ -> false
    end
  end

  defp held_days(%{active: true, held_days: held_days}), do: held_days
  defp held_days(_), do: MapSet.new()

  defp overlap_extra(%{active: true, overlap_extra_guests: overlap}),
    do: overlap

  defp overlap_extra(_), do: %{}

  defp modification_date_range(checkin, checkout) do
    checkin
    |> Date.range(Date.add(checkout, -1))
    |> MapSet.new()
  end

  defp load_room_inventory(property, room_ids, days) do
    Repo.all(
      from ri in RoomInventory,
        join: r in Room,
        on: ri.room_id == r.id,
        where: r.property == ^property,
        where: ri.room_id in ^room_ids,
        where: ri.day in ^days
    )
  end

  defp load_tahoe_room_inventory(days) do
    Repo.all(
      from ri in RoomInventory,
        join: r in Room,
        on: ri.room_id == r.id,
        where: r.property == :tahoe,
        where: ri.day in ^days
    )
    |> Enum.group_by(& &1.day)
  end

  defp load_room_conflicts(booking, room_ids, start_date, end_date) do
    if room_ids == [] do
      []
    else
      room_ids_binary = Enum.map(room_ids, &ulid_to_binary/1)

      Repo.all(
        from b in Booking,
          join: br in "booking_rooms",
          on: br.booking_id == b.id,
          where: fragment("? = ANY(?)", br.room_id, ^room_ids_binary),
          where: b.status in [:hold, :complete],
          where: b.id != ^booking.id,
          where: b.checkin_date < ^end_date and b.checkout_date > ^start_date,
          select: {type(br.room_id, Ecto.ULID), b.checkin_date, b.checkout_date}
      )
    end
  end

  defp ulid_to_binary(ulid) do
    case Ecto.ULID.dump(ulid) do
      {:ok, binary} -> binary
      _ -> ulid
    end
  end

  defp max_property_nights(property, seasons) do
    seasons
    |> Enum.map(&Season.get_max_nights(&1, property))
    |> Enum.max(fn -> 4 end)
  end

  # Matches BookingValidator: any stay that includes Saturday must span the
  # full weekend (check-in Friday or earlier, checkout Sunday or later).
  defp weekend_unavailability_message(:tahoe, checkin, checkout) do
    if Date.compare(checkout, checkin) == :lt do
      nil
    else
      reservation_dates = Date.range(checkin, checkout) |> Enum.to_list()

      has_saturday? =
        Enum.any?(reservation_dates, &(Date.day_of_week(&1, :monday) == 6))

      if has_saturday? do
        has_friday? =
          Enum.any?(reservation_dates, &(Date.day_of_week(&1, :monday) == 5))

        has_sunday? =
          Enum.any?(reservation_dates, &(Date.day_of_week(&1, :monday) == 7))

        cond do
          has_friday? and has_sunday? ->
            nil

          not has_friday? ->
            BookingValidator.saturday_requires_friday_start_message()

          true ->
            BookingValidator.saturday_requires_sunday_message()
        end
      else
        nil
      end
    end
  end

  defp weekend_unavailability_message(_property, _checkin, _checkout), do: nil

  defp availability_message(%{booking_mode: :room}),
    do: "Your room is not available starting on this date"

  defp availability_message(%{booking_mode: :buyout}),
    do: "The cabin is not available starting on this date"

  defp availability_message(_),
    do: "The cabin is not available starting on this date"

  defp availability_error_message(:blackout_conflict),
    do:
      "These dates aren't available for booking. They may be reserved for maintenance or a club event. Please choose different dates, or contact info@ysc.org if you have questions."

  defp availability_error_message(:property_unavailable),
    do: "The selected dates or guest count are not available"

  defp availability_error_message(:room_unavailable),
    do: "Your room is not available for the selected dates"

  defp availability_error_message(:property_buyout_active),
    do: "The entire cabin is already booked for those dates"

  defp availability_error_message(:rooms_already_booked),
    do: "Rooms are already booked for the selected dates"

  defp availability_error_message(_), do: "The selected dates are not available"

  defp max_nights_for_checkin(booking, checkin_date, seasons) do
    season =
      case seasons do
        [_ | _] -> Season.find_season_for_date(seasons, checkin_date)
        _ -> Season.for_date(booking.property, checkin_date)
      end

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

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    property = :tahoe
    min_date = Fixtures.today()
    max_date = Date.add(min_date, 30)
    days = Date.range(min_date, max_date) |> Enum.to_list()

    from(pi in PropertyInventory,
      where: pi.property == ^property and pi.day in ^days
    )
  end
end

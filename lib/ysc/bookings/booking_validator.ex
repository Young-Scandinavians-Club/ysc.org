defmodule Ysc.Bookings.BookingValidator do
  @moduledoc """
  Validates bookings according to property-specific rules.

  ## Tahoe Rules:
  - Winter: Only individual rooms
  - Summer: Individual rooms OR full buyout
  - If booking contains Saturday, must also reserve Sunday (full weekend)
  - Only one active booking per user at a time (all seasons)
  - Exception: Family/Lifetime members can have up to 2 bookings in the same time period (overlapping dates)
  - Maximum 4 nights per booking
  - Family membership: Up to 2 rooms in same time period (same or overlapping dates)
  - Single membership: Only 1 room per booking

  ## Clear Lake Rules:
  - Book by number of guests (not rooms)
  - Priced per guest per day
  - Maximum 12 guests per day
  - Option for "full buyout"
  """
  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Bookings.{Booking, Season, PropertyInventory}
  alias Ysc.Accounts.User
  alias Ysc.Subscriptions

  @max_guests_clear_lake 12

  @doc """
  Validates a booking changeset according to all business rules.

  ## Options
  - `:skip_validation` - If true, skips all business rule validations (useful for admin-created bookings)
  """
  def validate(changeset, opts \\ []) do
    # Skip all validation if requested (for admin-created bookings)
    if opts[:skip_validation] do
      changeset
    else
      user = opts[:user] || get_user_from_changeset(changeset)
      property = Ecto.Changeset.get_field(changeset, :property)

      changeset
      |> validate_booking_mode(property)
      |> validate_advance_booking_limit(property)
      |> validate_weekend_requirement()
      |> validate_max_nights()
      |> validate_single_active_booking(user, property)
      |> validate_buyout_no_active_bookings(user, property)
      |> validate_membership_room_limits(user, property)
      |> validate_clear_lake_guest_limits(property)
      |> validate_room_capacity()
    end
  end

  # Tahoe: During winter, only individual rooms; during summer, rooms or buyout
  defp validate_booking_mode(changeset, :tahoe) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    booking_mode = Ecto.Changeset.get_field(changeset, :booking_mode)
    rooms = Ecto.Changeset.get_field(changeset, :rooms) || []
    has_rooms = is_list(rooms) && rooms != []

    if checkin_date do
      season = Season.for_date(:tahoe, checkin_date)

      cond do
        is_nil(season) ->
          changeset

        season.name == "Winter" ->
          # Winter: only rooms allowed (no buyouts)
          validate_winter_booking_mode(changeset, has_rooms, booking_mode)

        season.name == "Summer" ->
          # Summer: rooms or buyout allowed - validation passes if either rooms are set or booking_mode is buyout
          changeset

        true ->
          changeset
      end
    else
      changeset
    end
  end

  defp validate_booking_mode(changeset, _property), do: changeset

  # Validate advance booking limit based on season's configurable days
  # Uses cross-season logic: checks the season for checkin_date and next season's limits
  defp validate_advance_booking_limit(changeset, property)
       when property in [:tahoe, :clear_lake] do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)

    if checkin_date && checkout_date do
      alias Ysc.Bookings.SeasonHelpers

      validation_errors =
        SeasonHelpers.validate_advance_booking_limit(
          property,
          checkin_date,
          checkout_date
        )

      if Map.has_key?(validation_errors, :advance_booking_limit) do
        Ecto.Changeset.add_error(
          changeset,
          :checkin_date,
          validation_errors.advance_booking_limit
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_advance_booking_limit(changeset, _property), do: changeset

  # If booking contains Saturday, must also reserve Sunday
  defp validate_weekend_requirement(changeset) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    property = Ecto.Changeset.get_field(changeset, :property)

    if checkin_date && checkout_date && property == :tahoe do
      # The range of nights stayed is from checkin to the day before checkout
      # (checkout date is when you leave, not a night you stay)
      last_night = Date.add(checkout_date, -1)
      stay_nights = Date.range(checkin_date, last_night) |> Enum.to_list()

      has_saturday =
        Enum.any?(stay_nights, fn date ->
          day_of_week(date) == 6
        end)

      if has_saturday do
        # Check if Sunday is included as a stay night
        validate_sunday_included(changeset, stay_nights)
      else
        changeset
      end
    else
      changeset
    end
  end

  # Maximum nights validation based on season configuration
  defp validate_max_nights(changeset) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    property = Ecto.Changeset.get_field(changeset, :property)

    if checkin_date && checkout_date && property do
      nights = Date.diff(checkout_date, checkin_date)

      # Get max nights from season for check-in date
      max_nights =
        if checkin_date do
          season = Season.for_date(property, checkin_date)
          Season.get_max_nights(season, property)
        else
          # Fallback to property defaults
          get_default_max_nights(property)
        end

      if nights > max_nights do
        Ecto.Changeset.add_error(
          changeset,
          :checkout_date,
          "Maximum #{max_nights} nights allowed per booking"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  # Only one active booking per user at a time (all seasons)
  # Exception: Family/Lifetime members can have up to 2 bookings in the same time period
  defp validate_single_active_booking(changeset, user, :tahoe) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    booking_id = Ecto.Changeset.get_field(changeset, :id)
    user_id = Ecto.Changeset.get_field(changeset, :user_id) || (user && user.id)

    if checkin_date && checkout_date && user_id && not is_nil(user) do
      # Get primary user for membership type check (sub-accounts use primary's membership)
      primary_user = get_primary_user_for_booking(user)
      membership_type = get_membership_type(primary_user)

      # Get all family member user IDs
      family_user_ids = Ysc.Accounts.get_family_group_user_ids(primary_user)

      # Family and lifetime members can have up to 2 bookings in the same time period
      # Single members can only have 1 active booking at a time (any dates)
      if membership_type in [:family, :lifetime] do
        # For family/lifetime: Check for overlapping bookings, max 2 total (1 existing + 1 new)
        overlapping_query =
          from b in Booking,
            where: b.user_id in ^family_user_ids,
            where: b.property == :tahoe,
            where: b.status == :complete,
            where:
              fragment(
                "? < ? AND ? > ?",
                b.checkin_date,
                ^checkout_date,
                b.checkout_date,
                ^checkin_date
              )

        overlapping_query =
          if booking_id do
            from b in overlapping_query, where: b.id != ^booking_id
          else
            overlapping_query
          end

        overlapping_count = Repo.aggregate(overlapping_query, :count, :id)

        if overlapping_count > 1 do
          error_message =
            build_overlapping_booking_error_message(membership_type)

          Ecto.Changeset.add_error(
            changeset,
            :checkin_date,
            error_message
          )
        else
          changeset
        end
      else
        # For single members: Check for ANY active/future bookings, max 1 total
        today = Date.utc_today()

        active_bookings_query =
          from b in Booking,
            where: b.user_id in ^family_user_ids,
            where: b.property == :tahoe,
            where: b.status == :complete,
            where: b.checkout_date >= ^today

        active_bookings_query =
          if booking_id do
            from b in active_bookings_query, where: b.id != ^booking_id
          else
            active_bookings_query
          end

        active_count = Repo.aggregate(active_bookings_query, :count, :id)

        if active_count > 0 do
          error_message =
            build_overlapping_booking_error_message(membership_type)

          Ecto.Changeset.add_error(
            changeset,
            :user_id,
            error_message
          )
        else
          changeset
        end
      end
    else
      changeset
    end
  end

  defp validate_single_active_booking(changeset, _user, _property),
    do: changeset

  # Prevent buyout bookings if user has any active or future bookings
  defp validate_buyout_no_active_bookings(changeset, user, :tahoe) do
    booking_mode = Ecto.Changeset.get_field(changeset, :booking_mode)
    user_id = Ecto.Changeset.get_field(changeset, :user_id) || (user && user.id)

    if booking_mode == :buyout && user_id && not is_nil(user) do
      # Get primary user for family group check
      primary_user = get_primary_user_for_booking(user)
      family_user_ids = Ysc.Accounts.get_family_group_user_ids(primary_user)
      today = Date.utc_today()

      # Check for any active bookings (status = :complete) with checkout_date >= today
      has_active_booking =
        Repo.exists?(
          from b in Booking,
            where: b.user_id in ^family_user_ids,
            where: b.property == :tahoe,
            where: b.status == :complete,
            where: b.checkout_date >= ^today
        )

      if has_active_booking do
        Ecto.Changeset.add_error(
          changeset,
          :booking_mode,
          "You cannot book a full buyout while you have an active or future reservation. Please complete or cancel your existing reservation first."
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_buyout_no_active_bookings(changeset, _user, _property),
    do: changeset

  defp get_primary_user_for_booking(user) do
    if Ysc.Accounts.sub_account?(user) do
      Ysc.Accounts.get_primary_user(user) || user
    else
      user
    end
  end

  # Membership-based room limits: Family = 2 rooms, Single = 1 room
  # Family memberships can book 2 rooms with overlapping dates (same timeframe)
  # Limits apply across the entire family group
  defp validate_membership_room_limits(changeset, user, :tahoe) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    user_id = Ecto.Changeset.get_field(changeset, :user_id) || (user && user.id)
    booking_id = Ecto.Changeset.get_field(changeset, :id)

    if checkin_date && checkout_date && user_id && not is_nil(user) do
      # Get primary user for membership type check (sub-accounts use primary's membership)
      primary_user = get_primary_user_for_booking(user)
      membership_type = get_membership_type(primary_user)

      # Get all family member user IDs
      family_user_ids = Ysc.Accounts.get_family_group_user_ids(primary_user)

      max_rooms =
        case membership_type do
          :family -> 2
          :lifetime -> 2
          _ -> 1
        end

      # For family memberships, check for overlapping dates (same timeframe)
      # For single memberships, check for exact same dates
      # Count the actual number of rooms (not bookings) in overlapping time period
      # Only count active bookings (status = :complete)
      # Check across ALL family members
      base_query =
        if membership_type in [:family, :lifetime] do
          # Family: Allow overlapping dates (same timeframe)
          from b in Booking,
            join: br in "booking_rooms",
            on: br.booking_id == b.id,
            where: b.user_id in ^family_user_ids,
            where: b.property == :tahoe,
            where: b.status == :complete,
            where:
              fragment(
                "? < ? AND ? > ?",
                b.checkin_date,
                ^checkout_date,
                b.checkout_date,
                ^checkin_date
              )
        else
          # Single: Only exact same dates
          from b in Booking,
            join: br in "booking_rooms",
            on: br.booking_id == b.id,
            where: b.user_id in ^family_user_ids,
            where: b.property == :tahoe,
            where: b.status == :complete,
            where: b.checkin_date == ^checkin_date,
            where: b.checkout_date == ^checkout_date
        end

      room_count_query =
        if booking_id do
          from [b, br] in base_query,
            where: b.id != ^booking_id,
            select: count(br.id)
        else
          from [b, br] in base_query,
            select: count(br.id)
        end

      existing_room_count = Repo.one(room_count_query) || 0

      # Also count rooms being booked in the current changeset
      current_rooms =
        case Ecto.Changeset.get_change(changeset, :rooms) do
          nil -> []
          rooms when is_list(rooms) -> rooms
        end

      new_room_count = length(current_rooms)
      total_rooms = existing_room_count + new_room_count

      if total_rooms > max_rooms do
        error_message =
          build_room_limit_error_message(membership_type, max_rooms)

        Ecto.Changeset.add_error(
          changeset,
          :rooms,
          error_message
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_membership_room_limits(changeset, _user, _property),
    do: changeset

  # Clear Lake: Maximum 12 guests per day
  defp validate_clear_lake_guest_limits(changeset, :clear_lake) do
    guests_count = Ecto.Changeset.get_field(changeset, :guests_count)
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    booking_mode = Ecto.Changeset.get_field(changeset, :booking_mode)

    if guests_count && checkin_date && checkout_date && booking_mode != :buyout do
      if guests_count > @max_guests_clear_lake do
        Ecto.Changeset.add_error(
          changeset,
          :guests_count,
          "Maximum #{@max_guests_clear_lake} guests allowed per day for Clear Lake"
        )
      else
        # Check daily guest limits across all bookings
        # Exclude checkout_date from the range since checkout is at 11:00 AM
        # and check-in is at 15:00 (3 PM), allowing same-day turnarounds
        # This matches the logic in get_clear_lake_daily_availability
        date_range =
          if Date.compare(checkout_date, checkin_date) == :gt do
            Date.range(checkin_date, Date.add(checkout_date, -1))
            |> Enum.to_list()
          else
            []
          end

        booking_id = Ecto.Changeset.get_field(changeset, :id)

        date_range
        |> Enum.reduce(changeset, fn date, acc ->
          # Count existing guests for this date (excluding current booking if updating)
          # Only count completed bookings - hold bookings are tracked via capacity_held
          # This matches the calendar logic which only shows completed bookings
          existing_guests_query =
            from b in Booking,
              where: b.property == :clear_lake,
              where: b.checkin_date <= ^date,
              where: b.checkout_date > ^date,
              where: b.booking_mode != :buyout,
              where: b.status == :complete,
              select: fragment("COALESCE(SUM(?), 0)", b.guests_count)

          existing_guests_query =
            if booking_id do
              from b in existing_guests_query, where: b.id != ^booking_id
            else
              existing_guests_query
            end

          existing_guests = Repo.one(existing_guests_query) || 0

          # Also get capacity_held from PropertyInventory to account for hold bookings
          capacity_held =
            from(pi in PropertyInventory,
              where: pi.property == :clear_lake,
              where: pi.day == ^date,
              select: pi.capacity_held
            )
            |> Repo.one() || 0

          total_guests = existing_guests + capacity_held + guests_count

          if total_guests > @max_guests_clear_lake do
            Ecto.Changeset.add_error(
              acc,
              :guests_count,
              "Maximum #{@max_guests_clear_lake} guests per day exceeded. #{existing_guests + capacity_held} guests already booked on #{date}."
            )
          else
            acc
          end
        end)
      end
    else
      changeset
    end
  end

  defp validate_clear_lake_guest_limits(changeset, _property), do: changeset

  # Validate room capacity (guests_count <= sum of room capacities for all rooms)
  defp validate_room_capacity(changeset) do
    rooms = Ecto.Changeset.get_field(changeset, :rooms) || []
    guests_count = Ecto.Changeset.get_field(changeset, :guests_count)

    if rooms != [] && guests_count do
      # For multiple rooms, sum the capacities
      total_capacity =
        Enum.reduce(rooms, 0, fn room, acc ->
          room_capacity = if is_struct(room), do: room.capacity_max, else: 0
          acc + room_capacity
        end)

      if total_capacity > 0 && guests_count > total_capacity do
        room_names =
          Enum.map_join(rooms, ", ", fn room ->
            if is_struct(room), do: room.name, else: "Unknown"
          end)

        Ecto.Changeset.add_error(
          changeset,
          :guests_count,
          "Total room capacity is #{total_capacity} guests, but #{guests_count} guests requested (#{room_names})"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  # Helper functions

  defp get_user_from_changeset(changeset) do
    user_id = Ecto.Changeset.get_field(changeset, :user_id)

    if user_id do
      Repo.get(User, user_id) |> Repo.preload(:subscriptions)
    else
      nil
    end
  end

  defp get_membership_type(user) do
    # Check for lifetime membership first
    if Ysc.Accounts.has_lifetime_membership?(user) do
      :lifetime
    else
      # Get active subscriptions
      subscriptions =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Ysc.Subscriptions.list_subscriptions(user)

          subscriptions when is_list(subscriptions) ->
            subscriptions

          _ ->
            []
        end

      active_subscriptions =
        Enum.filter(subscriptions, fn sub ->
          Subscriptions.valid?(sub)
        end)

      case active_subscriptions do
        [] ->
          :none

        [subscription | _] ->
          get_membership_type_from_subscription(subscription)

        multiple ->
          most_expensive = get_most_expensive_subscription(multiple)
          get_membership_type_from_subscription(most_expensive)
      end
    end
  end

  defp get_membership_type_from_subscription(subscription) do
    subscription = Repo.preload(subscription, :subscription_items)

    case subscription.subscription_items do
      [item | _] ->
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        case Enum.find(
               membership_plans,
               &(&1.stripe_price_id == item.stripe_price_id)
             ) do
          %{id: id} -> id
          _ -> :none
        end

      _ ->
        :none
    end
  end

  defp get_most_expensive_subscription(subscriptions) do
    membership_plans = Application.get_env(:ysc, :membership_plans, [])

    price_to_amount =
      Map.new(membership_plans, fn plan ->
        {plan.stripe_price_id, plan.amount}
      end)

    Enum.max_by(subscriptions, fn subscription ->
      subscription = Repo.preload(subscription, :subscription_items)

      case subscription.subscription_items do
        [item | _] -> Map.get(price_to_amount, item.stripe_price_id, 0)
        _ -> 0
      end
    end)
  end

  defp day_of_week(date) do
    # Returns 1-7 where 1 = Monday, 6 = Saturday, 7 = Sunday
    Date.day_of_week(date, :monday)
  end

  defp validate_winter_booking_mode(changeset, has_rooms, booking_mode) do
    if !has_rooms or booking_mode == :buyout do
      Ecto.Changeset.add_error(
        changeset,
        :booking_mode,
        "Winter season only allows individual room bookings, not buyouts"
      )
    else
      changeset
    end
  end

  defp validate_sunday_included(changeset, date_range) do
    # Check if Sunday is included
    has_sunday =
      Enum.any?(date_range, fn date ->
        day_of_week(date) == 7
      end)

    if has_sunday do
      changeset
    else
      Ecto.Changeset.add_error(
        changeset,
        :checkout_date,
        "Bookings containing Saturday must also include Sunday (full weekend required)"
      )
    end
  end

  defp get_default_max_nights(property) do
    case property do
      :tahoe -> 4
      :clear_lake -> 30
      _ -> 4
    end
  end

  defp build_overlapping_booking_error_message(membership_type) do
    if membership_type in [:family, :lifetime] do
      "Your family can only have up to 2 bookings in the same time period. Please complete your existing booking first or book within the same time period as your existing booking."
    else
      "You can only have one active booking at a time. Please complete your existing booking first."
    end
  end

  defp build_room_limit_error_message(membership_type, max_rooms) do
    if membership_type in [:family, :lifetime] do
      "Your family membership allows maximum #{max_rooms} room(s) in the same time period"
    else
      "#{String.capitalize("#{membership_type}")} membership allows maximum #{max_rooms} room(s) in the same time period"
    end
  end
end

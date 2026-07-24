defmodule Ysc.Bookings.BookingValidator do
  @moduledoc """
  Validates bookings according to property-specific rules.

  ## Tahoe Rules:
  - Winter nights: individual rooms only (buyout cannot occupy any Winter night)
  - Non-winter nights: individual rooms OR full buyout
  - Saturday check-in must be a one-night stay checking out Sunday; any other stay
    that includes Saturday must also include Sunday
  - Only one active booking per user at a time (all seasons)
  - Exception: Family/Couple members can have up to 2 bookings in the same time period (overlapping dates)
  - Max nights come from the check-in season configuration (Tahoe default 4)
  - Family membership: Up to 2 rooms in same time period (same or overlapping dates)
  - Single membership: Only 1 room per booking

  ## Clear Lake Rules:
  - Book by number of guests (not rooms)
  - Priced per guest per day
  - No limit on the number of guests per day for "A la carte" (day) bookings
  - Option for "full buyout"
  """
  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Bookings.{Booking, Season}
  alias Ysc.Accounts.User
  alias Ysc.Subscriptions

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

  # Tahoe: Winter nights are rooms-only; buyout must not occupy any winter night
  defp validate_booking_mode(changeset, :tahoe) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    booking_mode = Ecto.Changeset.get_field(changeset, :booking_mode)
    rooms = Ecto.Changeset.get_field(changeset, :rooms) || []
    has_rooms = is_list(rooms) && rooms != []

    cond do
      is_nil(checkin_date) ->
        changeset

      booking_mode == :buyout or not has_rooms ->
        buyout_ok? =
          if checkout_date do
            Season.buyout_allowed_for_stay?(
              :tahoe,
              checkin_date,
              checkout_date
            )
          else
            Season.buyout_allowed_on_date?(:tahoe, checkin_date)
          end

        if buyout_ok? do
          changeset
        else
          validate_winter_booking_mode(changeset, has_rooms, booking_mode)
        end

      true ->
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

  # Tahoe weekend rules:
  # - Saturday check-in must be a one-night stay checking out Sunday
  # - Any other stay that includes Saturday must also include Sunday
  defp validate_weekend_requirement(changeset) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    property = Ecto.Changeset.get_field(changeset, :property)

    if checkin_date && checkout_date && property == :tahoe &&
         Date.compare(checkout_date, checkin_date) != :lt do
      if day_of_week(checkin_date) == 6 do
        validate_saturday_checkin_one_night(
          changeset,
          checkin_date,
          checkout_date
        )
      else
        reservation_dates =
          Date.range(checkin_date, checkout_date) |> Enum.to_list()

        has_saturday =
          Enum.any?(reservation_dates, fn date ->
            day_of_week(date) == 6
          end)

        if has_saturday do
          validate_sunday_included(changeset, reservation_dates)
        else
          changeset
        end
      end
    else
      changeset
    end
  end

  defp validate_saturday_checkin_one_night(
         changeset,
         checkin_date,
         checkout_date
       ) do
    one_night_to_sunday? =
      Date.diff(checkout_date, checkin_date) == 1 &&
        day_of_week(checkout_date) == 7

    if one_night_to_sunday? do
      changeset
    else
      Ecto.Changeset.add_error(
        changeset,
        :checkout_date,
        "Check-ins on Saturday must check out on Sunday (one-night stay only)"
      )
    end
  end

  # Maximum nights validation based on season configuration
  @dialyzer {:nowarn_function, validate_max_nights: 1}
  defp validate_max_nights(changeset) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    property = Ecto.Changeset.get_field(changeset, :property)

    if checkin_date && checkout_date && property do
      nights = Date.diff(checkout_date, checkin_date)

      # Get max nights from season for check-in date
      season = Season.for_date(property, checkin_date)
      max_nights = Season.get_max_nights(season, property)

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
        today = Ysc.Bookings.SeasonHelpers.cabin_today()

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
    booking_id = Ecto.Changeset.get_field(changeset, :id)
    user_id = Ecto.Changeset.get_field(changeset, :user_id) || (user && user.id)

    if booking_mode == :buyout && user_id && not is_nil(user) do
      # Get primary user for family group check
      primary_user = get_primary_user_for_booking(user)
      family_user_ids = Ysc.Accounts.get_family_group_user_ids(primary_user)
      today = Ysc.Bookings.SeasonHelpers.cabin_today()

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

      has_active_booking = Repo.exists?(active_bookings_query)

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

  # Clear Lake: A la carte (day) bookings have no guest cap — pass through unchanged.
  defp validate_clear_lake_guest_limits(changeset, _property), do: changeset

  # Validate room capacity (adults + children <= sum of room capacities for all rooms)
  defp validate_room_capacity(changeset) do
    rooms = Ecto.Changeset.get_field(changeset, :rooms) || []
    guests_count = Ecto.Changeset.get_field(changeset, :guests_count)
    children_count = Ecto.Changeset.get_field(changeset, :children_count) || 0

    if rooms != [] && guests_count do
      # For multiple rooms, sum the capacities
      total_capacity =
        Enum.reduce(rooms, 0, fn room, acc ->
          room_capacity = if is_struct(room), do: room.capacity_max, else: 0
          acc + room_capacity
        end)

      total_people = guests_count + children_count

      if total_capacity > 0 && total_people > total_capacity do
        room_names =
          Enum.map_join(rooms, ", ", fn room ->
            if is_struct(room), do: room.name, else: "Unknown"
          end)

        error_field =
          if guests_count > total_capacity,
            do: :guests_count,
            else: :children_count

        error_message =
          if children_count > 0 do
            "Total room capacity is #{total_capacity} guests, but #{total_people} requested (#{guests_count} adults, #{children_count} children) (#{room_names})"
          else
            "Total room capacity is #{total_capacity} guests, but #{total_people} guests requested (#{room_names})"
          end

        Ecto.Changeset.add_error(changeset, error_field, error_message)
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
      end
    end
  end

  @dialyzer {:nowarn_function, get_membership_type_from_subscription: 1}
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

  defp day_of_week(date) do
    # Returns 1-7 where 1 = Monday, 6 = Saturday, 7 = Sunday
    Date.day_of_week(date, :monday)
  end

  defp validate_winter_booking_mode(changeset, has_rooms, booking_mode) do
    if !has_rooms or booking_mode == :buyout do
      Ecto.Changeset.add_error(
        changeset,
        :booking_mode,
        "Entire-cabin rentals are not available for winter nights in this stay"
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

  defp build_overlapping_booking_error_message(membership_type) do
    if membership_type in [:family, :lifetime] do
      "Your family can only have 2 cabin bookings at the same time. You already have 2 reservations during these dates — cancel or complete one before booking again."
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

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    family_user_ids = [Fixtures.ulid()]
    checkin_date = Fixtures.today()
    checkout_date = Date.add(checkin_date, 3)

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
        ),
      select: count(br.id)
  end
end

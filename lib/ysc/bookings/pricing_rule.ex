defmodule Ysc.Bookings.PricingRule do
  @moduledoc """
  PricingRule schema and changesets.

  Defines pricing rules with hierarchical specificity:
  - Most specific: room_id (applies to one room)
  - Medium: room_category_id (applies to all rooms in a category)
  - Least specific: property + season (default fallback)

  The system uses "most-specific wins" lookup logic.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "pricing_rules" do
    # Price amount (stored as Money)
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD

    # Children price amount (optional, stored as Money)
    field :children_amount, Money.Ecto.Composite.Type, default_currency: :USD

    # Booking mode (room, day, buyout)
    field :booking_mode, Ysc.Bookings.BookingMode

    # Price unit (per_person_per_night, per_guest_per_day, buyout_fixed)
    field :price_unit, Ysc.Bookings.PriceUnit

    # Hierarchical specificity (most specific first):
    # 1. room_id - applies to specific room
    # 2. room_category_id - applies to category
    # 3. property + season - default fallback
    belongs_to :room, Ysc.Bookings.Room, foreign_key: :room_id, references: :id

    belongs_to :room_category, Ysc.Bookings.RoomCategory,
      foreign_key: :room_category_id,
      references: :id

    field :property, Ysc.Bookings.BookingProperty

    belongs_to :season, Ysc.Bookings.Season,
      foreign_key: :season_id,
      references: :id

    timestamps()
  end

  @doc """
  Creates a changeset for the PricingRule schema.
  """
  def changeset(pricing_rule, attrs \\ %{}) do
    pricing_rule
    |> cast(attrs, [
      :amount,
      :children_amount,
      :booking_mode,
      :price_unit,
      :room_id,
      :room_category_id,
      :property,
      :season_id
    ])
    |> validate_required([
      :amount,
      :booking_mode,
      :price_unit
    ])
    |> validate_money(:amount)
    |> validate_money(:children_amount)
    |> validate_specificity()
    |> validate_room_and_category()
    |> unique_constraint(
      [
        :room_id,
        :room_category_id,
        :property,
        :season_id,
        :booking_mode,
        :price_unit
      ],
      name: :uq_pricing_rules_specificity
    )
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:room_category_id)
    |> foreign_key_constraint(:season_id)
  end

  # Custom validation for money field
  defp validate_money(changeset, field) do
    validate_change(changeset, field, fn _field, value ->
      case value do
        %Money{currency: :USD} = money when money.amount >= 0 ->
          []

        %Money{currency: currency} when currency != :USD ->
          [{field, "must be in USD"}]

        %Money{amount: amount} when amount < 0 ->
          [{field, "must be greater than or equal to 0"}]

        nil ->
          []

        _ ->
          [{field, "invalid money format"}]
      end
    end)
  end

  # Validates that at least one of room_id, room_category_id, or property is set
  defp validate_specificity(changeset) do
    room_id = get_field(changeset, :room_id)
    room_category_id = get_field(changeset, :room_category_id)
    property = get_field(changeset, :property)

    if room_id || room_category_id || property do
      changeset
    else
      add_error(
        changeset,
        :base,
        "must specify at least one of: room_id, room_category_id, or property"
      )
    end
  end

  # Validates that if room_id is set, room_category_id should not conflict
  defp validate_room_and_category(changeset) do
    room_id = get_field(changeset, :room_id)
    room_category_id = get_field(changeset, :room_category_id)

    # If room_id is set, ensure the room's category matches room_category_id (if both set)
    if room_id && room_category_id do
      # This could be enhanced to check the room's actual category
      # For now, we allow it but warn that room-level rules take precedence
      changeset
    else
      changeset
    end
  end

  @doc """
  Finds the most specific pricing rule for the given criteria.

  Returns the rule matching with highest specificity:
  1. room_id (most specific)
  2. room_category_id (medium)
  3. property + season (least specific)

  ## Parameters
  - `property`: Property to search for
  - `season_id`: Season ID (optional)
  - `room_id`: Room ID (optional, for room-specific pricing)
  - `room_category_id`: Room category ID (optional, for category pricing)
  - `booking_mode`: Booking mode (room, day, buyout)
  - `price_unit`: Price unit to search for

  ## Returns
  - `%PricingRule{}` if found
  - `nil` if not found
  """
  def find_most_specific(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit
      ) do
    alias Ysc.Bookings.PricingRuleCache
    require Logger

    Logger.debug(
      "[PricingRule] find_most_specific called. " <>
        "Property: #{property}, Season ID: #{inspect(season_id)}, " <>
        "Room ID: #{inspect(room_id)}, Room Category ID: #{inspect(room_category_id)}, " <>
        "Booking Mode: #{booking_mode}, Price Unit: #{price_unit}"
    )

    # Use cache which will handle DB lookup on miss
    PricingRuleCache.get(
      property,
      season_id,
      room_id,
      room_category_id,
      booking_mode,
      price_unit
    )
  end

  # Internal function that actually queries the database (called by cache on miss)
  def find_most_specific_db(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit
      ) do
    alias Ysc.Bookings.PricingRule
    require Logger

    base_query = build_base_query(property, booking_mode, price_unit)
    query = apply_season_filter(base_query, season_id)
    query = apply_room_category_filters(query, room_id, room_category_id)
    query = apply_ordering(query)

    result = Ysc.Repo.one(query)

    if result do
      Logger.debug(
        "[PricingRule] Found pricing rule: ID=#{result.id}, " <>
          "Amount=#{inspect(result.amount)}, " <>
          "Room ID=#{inspect(result.room_id)}, " <>
          "Category ID=#{inspect(result.room_category_id)}, " <>
          "Season ID=#{inspect(result.season_id)}"
      )
    else
      Logger.debug(
        "[PricingRule] No pricing rule found matching criteria. " <>
          "Checking if any rules exist for property #{property}..."
      )

      # Check if any pricing rules exist at all for this property
      count_query =
        from pr in PricingRule,
          where: pr.property == ^property or is_nil(pr.property),
          select: count(pr.id)

      total_count = Ysc.Repo.one(count_query)

      Logger.debug(
        "[PricingRule] Total pricing rules for property #{property}: #{total_count}"
      )

      # Check rules matching booking_mode and price_unit
      matching_count_query =
        from pr in PricingRule,
          where: pr.booking_mode == ^booking_mode,
          where: pr.price_unit == ^price_unit,
          where: pr.property == ^property or is_nil(pr.property),
          select: count(pr.id)

      matching_count = Ysc.Repo.one(matching_count_query)

      Logger.debug(
        "[PricingRule] Pricing rules matching booking_mode=#{booking_mode}, " <>
          "price_unit=#{price_unit}, property=#{property}: #{matching_count}"
      )
    end

    result
  end

  defp build_base_query(property, booking_mode, price_unit) do
    alias Ysc.Bookings.PricingRule

    from pr in PricingRule,
      where: pr.booking_mode == ^booking_mode,
      where: pr.price_unit == ^price_unit,
      where: pr.property == ^property or is_nil(pr.property)
  end

  defp apply_season_filter(base_query, season_id) do
    if season_id do
      from pr in base_query,
        where: is_nil(pr.season_id) or pr.season_id == ^season_id
    else
      from pr in base_query, where: is_nil(pr.season_id)
    end
  end

  defp apply_room_category_filters(query, room_id, room_category_id) do
    cond do
      room_id ->
        # Most specific: room_id match
        from pr in query,
          where: pr.room_id == ^room_id

      room_category_id ->
        # Medium specificity: category match (no room_id set)
        from pr in query,
          where: is_nil(pr.room_id) and pr.room_category_id == ^room_category_id

      true ->
        # Least specific: property only (no room_id or category_id)
        from pr in query,
          where: is_nil(pr.room_id) and is_nil(pr.room_category_id)
    end
  end

  defp build_children_base_query(property, booking_mode, price_unit) do
    alias Ysc.Bookings.PricingRule

    from pr in PricingRule,
      where: pr.booking_mode == ^booking_mode,
      where: pr.price_unit == ^price_unit,
      where: pr.property == ^property or is_nil(pr.property),
      where: not is_nil(pr.children_amount)
  end

  defp apply_ordering(query) do
    # Order by specificity (room_id > category_id > season_id)
    from pr in query,
      order_by: [
        desc: fragment("CASE WHEN ? IS NOT NULL THEN 1 ELSE 0 END", pr.room_id),
        desc:
          fragment(
            "CASE WHEN ? IS NOT NULL THEN 1 ELSE 0 END",
            pr.room_category_id
          ),
        desc:
          fragment("CASE WHEN ? IS NOT NULL THEN 1 ELSE 0 END", pr.season_id)
      ],
      limit: 1
  end

  @doc """
  Finds the most specific children pricing rule for the given criteria.

  Uses the same hierarchy as `find_most_specific/6` but looks for rules
  that have a `children_amount` set. Falls back through the hierarchy:
  1. room_id (most specific)
  2. room_category_id (medium)
  3. property + season (least specific)

  If no children pricing rule is found, returns `nil`.

  ## Parameters
  - `property`: Property to search for
  - `season_id`: Season ID (optional)
  - `room_id`: Room ID (optional, for room-specific pricing)
  - `room_category_id`: Room category ID (optional, for category pricing)
  - `booking_mode`: Booking mode (room, day, buyout)
  - `price_unit`: Price unit to search for

  ## Returns
  - `%PricingRule{}` if found with children_amount set
  - `nil` if not found
  """
  def find_children_pricing_rule(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit
      ) do
    alias Ysc.Bookings.PricingRuleCache
    require Logger

    Logger.debug(
      "[PricingRule] find_children_pricing_rule called. " <>
        "Property: #{property}, Season ID: #{inspect(season_id)}, " <>
        "Room ID: #{inspect(room_id)}, Room Category ID: #{inspect(room_category_id)}, " <>
        "Booking Mode: #{booking_mode}, Price Unit: #{price_unit}"
    )

    # Use cache which will handle DB lookup on miss
    PricingRuleCache.get_children(
      property,
      season_id,
      room_id,
      room_category_id,
      booking_mode,
      price_unit
    )
  end

  # Internal function that actually queries the database (called by cache on miss)
  def find_children_pricing_rule_db(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit
      ) do
    require Logger

    Logger.debug(
      "[PricingRule] find_children_pricing_rule_db called. " <>
        "Property: #{property}, Season ID: #{inspect(season_id)}, " <>
        "Room ID: #{inspect(room_id)}, Room Category ID: #{inspect(room_category_id)}, " <>
        "Booking Mode: #{booking_mode}, Price Unit: #{price_unit}"
    )

    base_query = build_children_base_query(property, booking_mode, price_unit)
    query = apply_season_filter(base_query, season_id)
    query = apply_room_category_filters(query, room_id, room_category_id)
    query = apply_ordering(query)

    result = Ysc.Repo.one(query)

    if result do
      Logger.debug(
        "[PricingRule] Found children pricing rule: ID=#{result.id}, " <>
          "Children Amount=#{inspect(result.children_amount)}, " <>
          "Room ID=#{inspect(result.room_id)}, " <>
          "Category ID=#{inspect(result.room_category_id)}, " <>
          "Season ID=#{inspect(result.season_id)}"
      )
    else
      Logger.debug(
        "[PricingRule] No children pricing rule found matching criteria."
      )
    end

    result
  end
end

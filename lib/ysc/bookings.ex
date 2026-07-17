defmodule Ysc.Bookings do
  @moduledoc """
  Context module for managing bookings, seasons, rooms, and pricing rules.

  ## Booking Rules

  - **Check-in Time**: 3:00 PM (15:00)
  - **Check-out Time**: 11:00 AM (11:00)

  These times allow same-day turnarounds: a booking ending on a date
  (check-out at 11 AM) can be followed by another booking starting on the same
  date (check-in at 3 PM), with a 4-hour gap for cleaning/preparation.

  Example:
  - Booking 1: Nov 1 - Nov 3 (checks out Nov 3 at 11 AM)
  - Booking 2: Nov 3 - Nov 5 (checks in Nov 3 at 3 PM)
  - These bookings do NOT overlap and can both be accepted.
  """
  import Ecto.Query, warn: false
  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Repo
  alias Stripe
  alias Ysc.Ledgers
  alias Ysc.Stripe.PaymentIntentHelpers

  alias Ysc.Bookings.{
    Season,
    SeasonCache,
    PricingRule,
    Room,
    RoomCategory,
    Blackout,
    Booking,
    BookingGuest,
    BookingLocker,
    DoorCode,
    RefundPolicy,
    RefundPolicyRule,
    PendingRefund,
    PropertyInventory,
    CheckIn,
    CheckInVehicle,
    CheckInBooking
  }

  # Check-in and check-out times
  @checkin_time ~T[15:00:00]
  @checkout_time ~T[11:00:00]

  @doc """
  Returns `:ok` when `user` may create or pay for a cabin booking.

  Mirrors the booking LiveViews' UI eligibility checks: account must be
  `:active` and the user (or their primary account) must have active membership.
  """
  def ensure_user_may_book(%Accounts.User{} = user) do
    cond do
      user.state != :active ->
        {:error, :application_pending_approval}

      not Accounts.has_active_membership?(user) ->
        {:error, :membership_required}

      true ->
        :ok
    end
  end

  ## Seasons

  @doc """
  Lists all seasons, optionally filtered by property.

  Uses cache when filtering by property for better performance.
  """
  def list_seasons(property \\ nil) do
    if property do
      # Check if season cache is enabled (disabled in tests to avoid race conditions)
      cache_enabled = Application.get_env(:ysc, :season_cache_enabled, true)

      if cache_enabled do
        # Use cache for property-specific lookups
        SeasonCache.get_all_for_property(property)
      else
        # Query directly when cache is disabled
        Season.list_all_for_property_db(property)
      end
    else
      # For all seasons, query directly (less common, no cache needed)
      query = from s in Season, order_by: [asc: s.property, asc: s.name]
      Repo.all(query)
    end
  end

  @doc """
  Gets a single season.
  """
  def get_season!(id) do
    Repo.get!(Season, id)
  end

  @doc """
  Creates a season.
  """
  def create_season(attrs \\ %{}) do
    result =
      %Season{}
      |> Season.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _season} ->
        # Invalidate season cache
        Ysc.Bookings.SeasonCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Updates a season.
  """
  def update_season(%Season{} = season, attrs) do
    result =
      season
      |> Season.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _season} ->
        # Invalidate season cache
        Ysc.Bookings.SeasonCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Deletes a season.
  """
  def delete_season(%Season{} = season) do
    result = Repo.delete(season)

    case result do
      {:ok, _season} ->
        # Invalidate season cache
        Ysc.Bookings.SeasonCache.invalidate()
        result

      _ ->
        result
    end
  end

  ## Pricing Rules

  @doc """
  Lists all pricing rules, with preloaded associations.

  Optionally filters by `property` so admin views can load only the active
  property's rules instead of fetching every rule and filtering in memory.
  """
  def list_pricing_rules(property \\ nil) do
    query =
      from(pr in PricingRule,
        order_by: [asc: pr.property, asc: pr.booking_mode, asc: pr.price_unit],
        preload: [:room, :room_category, :season]
      )

    query =
      if property do
        from pr in query, where: pr.property == ^property
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single pricing rule.
  """
  def get_pricing_rule!(id) do
    Repo.get!(PricingRule, id)
    |> Repo.preload([:room, :room_category, :season])
  end

  @doc """
  Creates a pricing rule.
  """
  def create_pricing_rule(attrs \\ %{}) do
    result =
      %PricingRule{}
      |> PricingRule.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _pricing_rule} ->
        # Invalidate pricing rule cache
        Ysc.Bookings.PricingRuleCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Updates a pricing rule.
  """
  def update_pricing_rule(%PricingRule{} = pricing_rule, attrs) do
    result =
      pricing_rule
      |> PricingRule.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _pricing_rule} ->
        # Invalidate pricing rule cache
        Ysc.Bookings.PricingRuleCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Deletes a pricing rule.
  """
  def delete_pricing_rule(%PricingRule{} = pricing_rule) do
    result = Repo.delete(pricing_rule)

    case result do
      {:ok, _pricing_rule} ->
        # Invalidate pricing rule cache
        Ysc.Bookings.PricingRuleCache.invalidate()
        result

      _ ->
        result
    end
  end

  ## Rooms

  @doc """
  Lists all rooms, optionally filtered by property.
  """
  def list_rooms(property \\ nil) do
    if property do
      Ysc.Bookings.RoomsListCache.list(property)
    else
      list_rooms_from_db(property)
    end
  end

  def list_rooms_from_db(property \\ nil) do
    query =
      from r in Room,
        order_by: [asc: r.property, asc: r.name],
        preload: [:room_category, :image]

    query =
      if property do
        from r in query, where: r.property == ^property
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single room.
  """
  def get_room!(id) do
    Repo.get!(Room, id)
    |> Repo.preload([:room_category, :image])
  end

  @doc """
  Fetches rooms by ID in a single query.

  Used for pricing helpers when selected room IDs are not yet in
  `available_rooms` — avoids one `get_room!/1` call per room.
  """
  def list_rooms_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      []
    else
      from(r in Room, where: r.id in ^ids)
      |> Repo.all()
    end
  end

  @doc """
  Creates a room.
  """
  def create_room(attrs \\ %{}) do
    result =
      %Room{}
      |> Room.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _} -> Ysc.Bookings.RoomsListCache.invalidate()
      _ -> :ok
    end

    result
  end

  @doc """
  Updates a room.
  """
  def update_room(%Room{} = room, attrs) do
    result =
      room
      |> Room.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _} -> Ysc.Bookings.RoomsListCache.invalidate()
      _ -> :ok
    end

    result
  end

  @doc """
  Deletes a room.
  """
  def delete_room(%Room{} = room) do
    result = Repo.delete(room)

    case result do
      {:ok, _} -> Ysc.Bookings.RoomsListCache.invalidate()
      _ -> :ok
    end

    result
  end

  ## Room Categories

  @doc """
  Lists all room categories.
  """
  def list_room_categories do
    Repo.all(from rc in RoomCategory, order_by: [asc: rc.name])
  end

  ## Bookings

  @doc """
  Lists all bookings, optionally filtered by property and date range.

  A booking is included if it overlaps with the date range, meaning:
  - The booking's check-in date is <= end_date
  - The booking's checkout date is >= start_date

  ## Parameters
  - `property`: Optional atom property filter (e.g., `:tahoe`, `:clear_lake`)
  - `start_date`: Optional start date for filtering (inclusive)
  - `end_date`: Optional end date for filtering (inclusive)

  ## Examples
      # Get all bookings for Tahoe
      list_bookings(:tahoe)

      # Get bookings for Tahoe in November 2025
      list_bookings(:tahoe, ~D[2025-11-01], ~D[2025-11-30])

      # Get all bookings in a date range across all properties
      list_bookings(nil, ~D[2025-11-01], ~D[2025-11-30])
  """
  def list_bookings(
        property \\ nil,
        start_date \\ nil,
        end_date \\ nil,
        opts \\ []
      ) do
    preloads = Keyword.get(opts, :preload, [:rooms, :user])

    query =
      from b in Booking, order_by: [asc: b.checkin_date], preload: ^preloads

    query =
      if property do
        from b in query, where: b.property == ^property
      else
        query
      end

    query =
      if start_date && end_date do
        from b in query,
          where:
            fragment(
              "(? <= ? AND ? >= ?)",
              b.checkin_date,
              ^end_date,
              b.checkout_date,
              ^start_date
            )
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Lists bookings with pagination, filtering, and search support.

  Supports fuzzy search by user name, email, or booking reference.
  Supports date range filtering by booking dates.
  """
  def list_paginated_bookings(params) do
    # Extract date range filters if present
    {date_range_filters, other_params} = extract_date_range_filters(params)
    # Extract property filter if present
    {property_filter, other_params} = extract_property_filter(other_params)

    base_query =
      from(b in Booking,
        preload: [:user, rooms: :room_category]
      )

    # Apply property filter
    base_query =
      if property_filter do
        from b in base_query, where: b.property == ^property_filter
      else
        base_query
      end

    # Apply date range filters
    base_query =
      if date_range_filters[:filter_start_date] &&
           date_range_filters[:filter_end_date] do
        from b in base_query,
          where:
            fragment(
              "(? <= ? AND ? >= ?)",
              b.checkin_date,
              ^date_range_filters[:filter_end_date],
              b.checkout_date,
              ^date_range_filters[:filter_start_date]
            )
      else
        base_query
      end

    case Flop.validate_and_run(base_query, other_params, for: Booking) do
      {:ok, {bookings, meta}} ->
        {:ok, {bookings, meta}}

      error ->
        error
    end
  end

  def list_paginated_bookings(params, nil), do: list_paginated_bookings(params)

  def list_paginated_bookings(params, search_term) when search_term == "",
    do: list_paginated_bookings(params)

  @spec list_paginated_bookings(
          %{
            optional(:__struct__) => Flop,
            optional(atom() | binary()) => any()
          },
          any()
        ) :: {:error, Flop.Meta.t()} | {:ok, {list(), Flop.Meta.t()}}
  def list_paginated_bookings(params, search_term) do
    # Extract date range filters if present
    {date_range_filters, other_params} = extract_date_range_filters(params)
    # Extract property filter if present
    {property_filter, other_params} = extract_property_filter(other_params)

    base_query = fuzzy_search_booking(search_term)

    # Apply property filter
    base_query =
      if property_filter do
        from b in base_query, where: b.property == ^property_filter
      else
        base_query
      end

    # Apply date range filters
    base_query =
      if date_range_filters[:filter_start_date] &&
           date_range_filters[:filter_end_date] do
        from b in base_query,
          where:
            fragment(
              "(? <= ? AND ? >= ?)",
              b.checkin_date,
              ^date_range_filters[:filter_end_date],
              b.checkout_date,
              ^date_range_filters[:filter_start_date]
            )
      else
        base_query
      end

    case Flop.validate_and_run(base_query, other_params, for: Booking) do
      {:ok, {bookings, meta}} ->
        {:ok, {bookings, meta}}

      error ->
        error
    end
  end

  @doc """
  Lists paginated bookings for a specific user with Flop.
  """
  def list_user_bookings_paginated(user_id, params) do
    base_query =
      from(b in Booking,
        where: b.user_id == ^user_id,
        preload: [:user, rooms: :room_category]
      )

    case Flop.validate_and_run(base_query, params, for: Booking) do
      {:ok, {bookings, meta}} ->
        {:ok, {bookings, meta}}

      error ->
        error
    end
  end

  defp fuzzy_search_booking(search_term) do
    search_like = "%#{search_term}%"

    from(b in Booking,
      left_join: u in assoc(b, :user),
      where:
        fragment("SIMILARITY(?, ?) > 0.2", u.email, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term) or
          ilike(b.reference_id, ^search_like),
      preload: [:user, rooms: :room_category]
    )
  end

  defp extract_property_filter(params) do
    if params["filter"] && params["filter"]["property"] do
      property_str = params["filter"]["property"]
      property_atom = String.to_existing_atom(property_str)
      filtered_params = delete_in(params, ["filter", "property"])
      {property_atom, filtered_params}
    else
      {nil, params}
    end
  end

  defp extract_date_range_filters(params) do
    filter_start_date =
      if params["filter"] && params["filter"]["filter_start_date"] do
        case Date.from_iso8601(params["filter"]["filter_start_date"]) do
          {:ok, date} -> date
          _ -> nil
        end
      else
        nil
      end

    filter_end_date =
      if params["filter"] && params["filter"]["filter_end_date"] do
        case Date.from_iso8601(params["filter"]["filter_end_date"]) do
          {:ok, date} -> date
          _ -> nil
        end
      else
        nil
      end

    filtered_params =
      params
      |> delete_in(["filter", "filter_start_date"])
      |> delete_in(["filter", "filter_end_date"])

    {%{filter_start_date: filter_start_date, filter_end_date: filter_end_date},
     filtered_params}
  end

  defp delete_in(map, [key | rest]) when is_map(map) do
    case rest do
      [] ->
        Map.delete(map, key)

      [next_key | remaining] ->
        delete_nested_key(map, key, next_key, remaining)
    end
  end

  defp delete_in(map, _), do: map

  defp delete_nested_key(map, key, next_key, remaining) do
    if is_map(map[key]) do
      Map.update(map, key, %{}, fn nested_map ->
        delete_in(nested_map, [next_key | remaining])
      end)
    else
      map
    end
  end

  @doc """
  Gets a single booking.
  """
  def get_booking!(id) do
    Repo.get!(Booking, id)
    |> Repo.preload([
      {:booking_guests,
       from(bg in BookingGuest, order_by: [asc: bg.order_index])},
      :rooms,
      :user
    ])
  end

  @doc """
  Gets a booking with associations needed for admin view and edit modals.

  Loads everything in one preload pass instead of `get_booking!/1` followed by
  a second `Repo.preload/2`.
  """
  def get_booking_for_admin_view!(id) do
    Repo.get!(Booking, id)
    |> Repo.preload([
      {:booking_guests,
       from(bg in BookingGuest, order_by: [asc: bg.order_index])},
      rooms: :room_category,
      user: :current_avatar,
      check_ins: :check_in_vehicles
    ])
  end

  @doc """
  Gets a booking by reference_id.
  """
  def get_booking_by_reference_id(reference_id) do
    booking =
      from(b in Booking,
        where: b.reference_id == ^reference_id,
        preload: [:rooms, :user]
      )
      |> Repo.one()

    if booking do
      booking
      |> Repo.preload([
        {:booking_guests,
         from(bg in BookingGuest, order_by: [asc: bg.order_index])}
      ])
    else
      nil
    end
  end

  @doc """
  Creates a booking.
  """
  def create_booking(attrs \\ %{}) do
    result =
      %Booking{}
      |> Booking.changeset(attrs)
      |> Repo.insert()

    invalidate_availability_caches(result)
    result
  end

  @doc """
  Updates a booking.
  """
  def update_booking(%Booking{} = booking, attrs, opts \\ []) do
    result =
      booking
      |> Booking.changeset(attrs, opts)
      |> Repo.update()

    invalidate_availability_caches(result)
    result
  end

  @doc """
  Returns the total amount paid for a booking across all recorded Stripe payments.
  """
  def get_booking_total_paid_amount(booking) do
    import Ecto.Query

    entries =
      from(e in Ysc.Ledgers.LedgerEntry,
        join: a in Ysc.Ledgers.LedgerAccount,
        on: e.account_id == a.id,
        where: e.related_entity_type == ^:booking,
        where: e.related_entity_id == ^booking.id,
        where: e.debit_credit == "debit",
        where: a.name == "stripe_account",
        select: e.amount
      )
      |> Repo.all()

    case entries do
      [] ->
        if booking.total_price do
          {:ok, booking.total_price}
        else
          {:error, :payment_not_found}
        end

      amounts ->
        total =
          Enum.reduce(amounts, Money.new(0, :USD), fn amount, acc ->
            case Money.add(acc, amount) do
              {:ok, sum} -> sum
              {:error, _} -> acc
            end
          end)

        {:ok, total}
    end
  end

  @doc """
  Validates a proposed booking modification and returns pricing preview without persisting.
  """
  def prepare_modification(%Booking{} = booking, attrs, opts \\ []) do
    booking =
      if modification_preload_needed?(booking) do
        Repo.preload(booking, [:rooms, :user])
      else
        booking
      end

    with :ok <- validate_modification_eligible(booking),
         {:ok, parsed} <- parse_modification_attrs(booking, attrs),
         :ok <- validate_modification_checkin_not_past(parsed),
         :ok <- ensure_modification_changed(booking, parsed),
         {:ok, user} <- fetch_modification_user(booking),
         {:ok, _} <- validate_modification_changeset(booking, parsed, user),
         :ok <- maybe_validate_modification_availability(booking, parsed, opts),
         {:ok, priced} <-
           calculate_modification_pricing(
             build_preview_booking(booking, parsed)
           ),
         {:ok, amount_paid} <- modification_amount_paid(booking, opts) do
      previous_total = booking.total_price || Money.new(0, :USD)

      {:ok,
       %{
         new_total: priced.total,
         previous_total: previous_total,
         amount_paid: amount_paid,
         delta: modification_delta(previous_total, priced.total),
         breakdown: priced.breakdown,
         attrs: parsed
       }}
    end
  end

  defp modification_delta(previous_total, new_total) do
    case Money.sub(new_total, previous_total) do
      {:ok, delta} ->
        if Money.negative?(delta), do: Money.new(0, :USD), else: delta

      {:error, _} ->
        Money.new(0, :USD)
    end
  end

  @doc """
  Applies a booking modification after optional payment verification.
  """
  def apply_modification(%Booking{} = booking, attrs, opts \\ []) do
    booking = Repo.get!(Booking, booking.id) |> Repo.preload([:rooms, :user])
    attrs = attrs_for_paid_modification_apply(booking, attrs, opts)
    prepare_opts = prepare_modification_opts_for_apply(opts)

    with :ok <- validate_modification_eligible(booking),
         {:ok, parsed} <- parse_modification_attrs(booking, attrs),
         {:ok, preview} <- prepare_modification(booking, attrs, prepare_opts),
         :ok <- verify_modification_payment(preview, booking, opts),
         :ok <-
           ensure_modification_hold_for_apply(booking, parsed, preview, opts) do
      previous_details = %{
        checkin_date: booking.checkin_date,
        checkout_date: booking.checkout_date,
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0,
        total_price: booking.total_price,
        additional_payment:
          if(Money.positive?(preview.delta), do: preview.delta, else: nil)
      }

      case BookingLocker.modify_complete_booking(
             booking,
             parsed,
             previous_details: previous_details
           ) do
        {:ok, updated_booking} = result ->
          case record_modification_payment_if_needed(
                 updated_booking,
                 preview,
                 opts
               ) do
            :ok ->
              result

            {:error, reason} ->
              require Ysc.Logging

              Ysc.Logging.error(
                "Booking modification applied but payment ledger write failed",
                booking_id: updated_booking.id,
                error: reason
              )

              {:error, {:ledger_payment_failed, reason}}
          end

        other ->
          other
      end
    end
  end

  defp record_modification_payment_if_needed(booking, %{delta: delta}, opts) do
    if Money.positive?(delta) do
      case Keyword.get(opts, :payment_intent_id) do
        nil ->
          {:error, :payment_required}

        payment_intent_id ->
          record_modification_ledger_payment(booking, payment_intent_id, delta)
      end
    else
      :ok
    end
  end

  @doc """
  Idempotently records a modification payment in the ledger when the booking
  already reflects the change but the payment intent is not yet recorded.

  Used to recover from ledger write failures after `apply_modification/3`
  commits inventory and date changes.
  """
  def ensure_modification_ledger_recorded(
        %Booking{} = booking,
        payment_intent_id
      ) do
    booking = Repo.get!(Booking, booking.id) |> Repo.preload([:rooms, :user])

    if modification_ledger_recorded?(booking.id, payment_intent_id) do
      :ok
    else
      with {:ok, amount} <-
             modification_payment_amount_from_intent(
               payment_intent_id,
               booking.id,
               booking.user_id
             ),
           true <- modification_payment_balance_due?(booking, amount) do
        record_modification_ledger_payment(booking, payment_intent_id, amount)
      else
        false -> {:error, :modification_not_applied}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc false
  def modification_ledger_recorded?(booking_id, payment_intent_id) do
    case Ledgers.get_payment_by_external_id(payment_intent_id) do
      nil ->
        false

      payment ->
        from(e in Ysc.Ledgers.LedgerEntry,
          where: e.payment_id == ^payment.id,
          where: e.related_entity_type == ^:booking,
          where: e.related_entity_id == ^booking_id,
          limit: 1
        )
        |> Repo.exists?()
    end
  end

  @doc false
  def sync_hold_checkout_pricing(%Booking{status: :hold} = booking, attrs)
      when is_map(attrs) do
    total_price = Map.fetch!(attrs, :total_price)

    changeset =
      booking
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:total_price, total_price)
      |> put_optional_checkout_money(:subtotal_price, attrs[:subtotal_price])
      |> put_optional_checkout_money(:discount_total, attrs[:discount_total])

    Repo.update(changeset)
  end

  def sync_hold_checkout_pricing(%Booking{}, _attrs),
    do: {:error, :invalid_status}

  @doc false
  def sync_hold_pricing_from_calculation(%Booking{} = booking) do
    case calculate_modification_pricing(booking) do
      {:ok, priced} ->
        sync_hold_checkout_pricing(booking, %{
          total_price: priced.total,
          subtotal_price: priced.subtotal,
          discount_total: priced.discount
        })

      {:error, _} = error ->
        error
    end
  end

  @doc false
  def maybe_sync_hold_pricing_from_calculation(%Booking{status: :hold} = booking) do
    sync_hold_pricing_from_calculation(booking)
  end

  def maybe_sync_hold_pricing_from_calculation(%Booking{} = booking) do
    {:ok, booking}
  end

  defp put_optional_checkout_money(changeset, field, %Money{} = value) do
    Ecto.Changeset.put_change(changeset, field, value)
  end

  defp put_optional_checkout_money(changeset, _field, _), do: changeset

  @doc false
  def verify_booking_payment_intent(payment_intent, %Booking{} = booking) do
    metadata = payment_intent.metadata || %{}

    metadata_booking_id =
      Map.get(metadata, "booking_id") || Map.get(metadata, :booking_id)

    metadata_user_id =
      Map.get(metadata, "user_id") || Map.get(metadata, :user_id)

    modification_flag =
      Map.get(metadata, "modification") || Map.get(metadata, :modification)

    expected_cents = Ysc.MoneyHelper.money_to_cents(booking.total_price)

    cond do
      payment_intent.status != "succeeded" ->
        {:error, :payment_not_succeeded}

      modification_flag in ["true", true] ->
        {:error, :payment_metadata_mismatch}

      to_string(metadata_booking_id || "") != to_string(booking.id) ->
        {:error, :payment_metadata_mismatch}

      to_string(metadata_user_id || "") != to_string(booking.user_id) ->
        {:error, :payment_metadata_mismatch}

      payment_intent.amount != expected_cents ->
        {:error, :payment_amount_mismatch}

      payment_intent_recorded_for_other_booking?(payment_intent.id, booking.id) ->
        {:error, :payment_already_used}

      true ->
        :ok
    end
  end

  @doc false
  def verify_modification_redirect_payment_intent(
        payment_intent,
        %Booking{} = booking
      ) do
    metadata = payment_intent.metadata || %{}

    metadata_booking_id =
      Map.get(metadata, "booking_id") || Map.get(metadata, :booking_id)

    metadata_user_id =
      Map.get(metadata, "user_id") || Map.get(metadata, :user_id)

    modification_flag =
      Map.get(metadata, "modification") || Map.get(metadata, :modification)

    cond do
      payment_intent.status != "succeeded" ->
        {:error, :payment_not_succeeded}

      booking.status != :complete ->
        {:error, :payment_metadata_mismatch}

      modification_flag not in ["true", true] ->
        {:error, :payment_metadata_mismatch}

      to_string(metadata_booking_id || "") != to_string(booking.id) ->
        {:error, :payment_metadata_mismatch}

      to_string(metadata_user_id || "") != to_string(booking.user_id) ->
        {:error, :payment_metadata_mismatch}

      true ->
        :ok
    end
  end

  defp payment_intent_recorded_for_other_booking?(payment_intent_id, booking_id) do
    case Ledgers.get_payment_by_external_id(payment_intent_id) do
      nil ->
        false

      _payment ->
        not modification_ledger_recorded?(booking_id, payment_intent_id)
    end
  end

  defp modification_payment_amount_from_intent(
         payment_intent_id,
         booking_id,
         user_id
       ) do
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{}) do
      {:ok, %{status: "succeeded"} = payment_intent} ->
        metadata = payment_intent.metadata || %{}

        metadata_booking_id =
          Map.get(metadata, "booking_id") || Map.get(metadata, :booking_id)

        metadata_user_id =
          Map.get(metadata, "user_id") || Map.get(metadata, :user_id)

        modification_flag =
          Map.get(metadata, "modification") || Map.get(metadata, :modification)

        cond do
          modification_flag not in ["true", true] ->
            {:error, :payment_metadata_mismatch}

          to_string(metadata_booking_id || "") != to_string(booking_id) ->
            {:error, :payment_metadata_mismatch}

          to_string(metadata_user_id || "") != to_string(user_id) ->
            {:error, :payment_metadata_mismatch}

          true ->
            {:ok, Ysc.MoneyHelper.cents_to_money(payment_intent.amount, :USD)}
        end

      {:ok, _} ->
        {:error, :payment_not_succeeded}

      {:error, reason} ->
        {:error, {:payment_verification_failed, reason}}
    end
  end

  defp modification_payment_balance_due?(%Booking{} = booking, amount) do
    recorded_total = sum_booking_stripe_payment_entries(booking.id)

    case Money.sub(booking.total_price, recorded_total) do
      {:ok, remaining} ->
        Money.positive?(amount) and Money.cmp(remaining, amount) == 0

      {:error, _} ->
        false
    end
  end

  defp sum_booking_stripe_payment_entries(booking_id) do
    from(e in Ysc.Ledgers.LedgerEntry,
      join: a in Ysc.Ledgers.LedgerAccount,
      on: e.account_id == a.id,
      where: e.related_entity_type == ^:booking,
      where: e.related_entity_id == ^booking_id,
      where: e.debit_credit == "debit",
      where: a.name == "stripe_account",
      where: not is_nil(e.payment_id)
    )
    |> Repo.all()
    |> Enum.reduce(Money.new(0, :USD), fn entry, acc ->
      case Money.add(acc, entry.amount) do
        {:ok, sum} -> sum
        {:error, _} -> acc
      end
    end)
  end

  defp record_modification_ledger_payment(booking, payment_intent_id, amount) do
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{
           expand: ["payment_method", "latest_charge"]
         }) do
      {:ok, payment_intent} ->
        stripe_fee =
          payment_intent
          |> Ysc.Stripe.WebhookHandler.extract_stripe_fee_from_payment_intent()
          |> normalize_stripe_fee()

        attrs = %{
          user_id: booking.user_id,
          amount: amount,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: payment_intent.id,
          stripe_fee: stripe_fee,
          description: "Booking modification - #{booking.reference_id}",
          property: booking.property,
          payment_method_id: nil
        }

        case Ledgers.process_payment(attrs) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, {:payment_verification_failed, reason}}
    end
  end

  defp validate_modification_eligible(booking) do
    if booking.status == :complete do
      :ok
    else
      {:error, :invalid_status}
    end
  end

  @doc """
  Places a short-lived inventory hold while the member completes modification payment.
  """
  def place_modification_hold(%Booking{} = booking, attrs, opts \\ []) do
    booking
    |> Ysc.Bookings.BookingLocker.place_modification_hold(attrs, opts)
    |> unwrap_transaction_rollback_error()
  end

  @doc """
  Releases a modification payment hold without applying the modification.
  """
  def release_modification_hold(booking_id, opts \\ []) do
    booking_id
    |> Ysc.Bookings.BookingLocker.release_modification_hold(opts)
    |> unwrap_transaction_rollback_error()
  end

  defp unwrap_transaction_rollback_error({:error, {:error, reason}}),
    do: {:error, reason}

  defp unwrap_transaction_rollback_error(result), do: result

  @doc """
  Returns modification form params stored on an active payment hold, if any.

  Accepts a `%Booking{}` (from `modification_hold_attrs`) or a parsed attrs map
  (string or atom keys, dates as binaries or `%Date{}`).
  """
  def modification_hold_form_params(%Booking{modification_hold_attrs: attrs})
      when is_map(attrs) do
    modification_attrs_to_form_params(attrs)
  end

  def modification_hold_form_params(attrs)
      when is_map(attrs) and not is_struct(attrs, Booking) do
    modification_attrs_to_form_params(attrs)
  end

  def modification_hold_form_params(_), do: nil

  defp modification_attrs_to_form_params(attrs) do
    checkin = Map.get(attrs, "checkin_date") || Map.get(attrs, :checkin_date)
    checkout = Map.get(attrs, "checkout_date") || Map.get(attrs, :checkout_date)

    with {:ok, checkin_str} <- normalize_modification_form_date(checkin),
         {:ok, checkout_str} <- normalize_modification_form_date(checkout) do
      guests = Map.get(attrs, "guests_count") || Map.get(attrs, :guests_count)

      children =
        Map.get(attrs, "children_count") || Map.get(attrs, :children_count, 0)

      %{
        "checkin_date" => checkin_str,
        "checkout_date" => checkout_str,
        "guests_count" => to_string(guests),
        "children_count" => to_string(children)
      }
    else
      :error -> nil
    end
  end

  defp normalize_modification_form_date(%Date{} = date),
    do: {:ok, Date.to_iso8601(date)}

  defp normalize_modification_form_date(date) when is_binary(date),
    do: {:ok, date}

  defp normalize_modification_form_date(_), do: :error

  defp maybe_validate_modification_availability(booking, parsed, opts) do
    if Keyword.get(opts, :skip_availability_check) do
      :ok
    else
      validate_modification_availability(booking, parsed, opts)
    end
  end

  defp attrs_for_paid_modification_apply(booking, attrs, opts) do
    if Keyword.get(opts, :payment_intent_id) do
      modification_hold_form_params(booking) ||
        modification_hold_form_params(attrs) ||
        attrs
    else
      attrs
    end
  end

  defp modification_preload_needed?(booking) do
    not (Ecto.assoc_loaded?(booking.rooms) and Ecto.assoc_loaded?(booking.user))
  end

  defp modification_amount_paid(booking, opts) do
    case Keyword.get(opts, :amount_paid) do
      %Money{} = amount -> {:ok, amount}
      _ -> get_booking_total_paid_amount(booking)
    end
  end

  defp prepare_modification_opts_for_apply(opts) do
    if Keyword.get(opts, :payment_intent_id) do
      Keyword.put(opts, :skip_availability_check, true)
    else
      opts
    end
  end

  defp validate_modification_checkin_not_past(parsed) do
    today_pst = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

    if Date.compare(parsed.checkin_date, today_pst) == :lt do
      {:error, :checkin_in_past}
    else
      :ok
    end
  end

  defp parse_modification_attrs(booking, attrs) do
    with {:ok, checkin} <-
           parse_modification_date(attrs, :checkin_date, booking.checkin_date),
         {:ok, checkout} <-
           parse_modification_date(attrs, :checkout_date, booking.checkout_date),
         {:ok, guests} <-
           parse_modification_integer(
             attrs,
             "guests_count",
             booking.guests_count
           ),
         {:ok, children} <-
           parse_modification_integer(
             attrs,
             "children_count",
             booking.children_count || 0
           ) do
      {:ok,
       %{
         checkin_date: checkin,
         checkout_date: checkout,
         guests_count: guests,
         children_count: children
       }}
    end
  end

  defp parse_modification_date(attrs, key, default) do
    string_key = Atom.to_string(key)

    value =
      Map.get(attrs, key) ||
        Map.get(attrs, string_key) ||
        default

    case value do
      %Date{} = date ->
        {:ok, date}

      date when is_binary(date) ->
        case Date.from_iso8601(date) do
          {:ok, parsed} ->
            {:ok, parsed}

          {:error, _} ->
            case DateTime.from_iso8601(date) do
              {:ok, datetime, _} -> {:ok, DateTime.to_date(datetime)}
              _ -> {:error, :invalid_date}
            end
        end

      _ ->
        {:error, :invalid_date}
    end
  end

  defp parse_modification_integer(attrs, key, default) do
    value =
      Map.get(attrs, key) ||
        Map.get(attrs, String.to_existing_atom(key), default)

    case value do
      n when is_integer(n) and n >= 0 ->
        {:ok, n}

      n when is_binary(n) ->
        case Integer.parse(n) do
          {parsed, _} when parsed >= 0 -> {:ok, parsed}
          _ -> {:error, :invalid_guest_count}
        end

      _ ->
        {:error, :invalid_guest_count}
    end
  rescue
    ArgumentError -> {:error, :invalid_guest_count}
  end

  defp ensure_modification_changed(booking, parsed) do
    if booking.checkin_date == parsed.checkin_date and
         booking.checkout_date == parsed.checkout_date and
         booking.guests_count == parsed.guests_count and
         (booking.children_count || 0) == parsed.children_count do
      {:error, :no_changes}
    else
      :ok
    end
  end

  defp fetch_modification_user(booking) do
    case booking.user || Repo.get(Ysc.Accounts.User, booking.user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Validates that proposed modification dates and guest counts are available.

  Uses batched availability snapshots (see `ModificationDateAvailability`) instead
  of per-day `room_available?/4` queries. Pass `availability_snapshot:` in `opts`
  when the caller already built a snapshot for the change-reservation calendar.
  """
  def validate_modification_availability(
        %Booking{} = booking,
        parsed,
        opts \\ []
      ) do
    snapshot =
      Keyword.get_lazy(opts, :availability_snapshot, fn ->
        Ysc.Bookings.ModificationDateAvailability.build_snapshot_for_modification(
          booking,
          parsed.checkin_date,
          parsed.checkout_date
        )
      end)

    Ysc.Bookings.ModificationDateAvailability.validate_modification_dates(
      snapshot,
      parsed.checkin_date,
      parsed.checkout_date
    )
  end

  defp validate_modification_changeset(booking, parsed, user) do
    changeset =
      booking
      |> Booking.changeset(
        %{
          checkin_date: parsed.checkin_date,
          checkout_date: parsed.checkout_date,
          guests_count: parsed.guests_count,
          children_count: parsed.children_count
        },
        rooms: booking.rooms,
        user: user
      )

    if changeset.valid? do
      {:ok, changeset}
    else
      {:error, changeset}
    end
  end

  defp build_preview_booking(booking, parsed) do
    %{
      booking
      | checkin_date: parsed.checkin_date,
        checkout_date: parsed.checkout_date,
        guests_count: parsed.guests_count,
        children_count: parsed.children_count
    }
  end

  defp verify_modification_payment(%{delta: delta}, booking, opts) do
    if Money.positive?(delta) do
      case Keyword.get(opts, :payment_intent_id) do
        nil ->
          {:error, :payment_required}

        payment_intent_id ->
          verify_modification_payment_intent(
            payment_intent_id,
            delta,
            booking.id,
            booking.user_id
          )
      end
    else
      :ok
    end
  end

  defp ensure_modification_hold_for_apply(
         booking,
         parsed,
         %{delta: delta},
         opts
       ) do
    if Money.positive?(delta) do
      booking = Repo.get!(Booking, booking.id)

      hold_ok? =
        Ysc.Bookings.BookingLocker.modification_hold_active?(booking) and
          Ysc.Bookings.BookingLocker.modification_hold_matches?(booking, parsed)

      cond do
        hold_ok? ->
          :ok

        Keyword.get(opts, :payment_intent_id) ->
          case place_modification_hold(booking, parsed) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end

        true ->
          {:error, :modification_hold_expired}
      end
    else
      :ok
    end
  end

  defp verify_modification_payment_intent(
         payment_intent_id,
         expected_delta,
         booking_id,
         user_id
       ) do
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{}) do
      {:ok, %{status: "succeeded"} = payment_intent} ->
        expected_cents = Ysc.MoneyHelper.money_to_cents(expected_delta)
        metadata = payment_intent.metadata || %{}

        metadata_booking_id =
          Map.get(metadata, "booking_id") || Map.get(metadata, :booking_id)

        metadata_user_id =
          Map.get(metadata, "user_id") || Map.get(metadata, :user_id)

        modification_flag =
          Map.get(metadata, "modification") || Map.get(metadata, :modification)

        cond do
          modification_flag not in ["true", true] ->
            {:error, :payment_metadata_mismatch}

          to_string(metadata_booking_id || "") != to_string(booking_id) ->
            {:error, :payment_metadata_mismatch}

          to_string(metadata_user_id || "") != to_string(user_id) ->
            {:error, :payment_metadata_mismatch}

          payment_intent.amount != expected_cents ->
            {:error, :payment_amount_mismatch}

          true ->
            :ok
        end

      {:ok, _} ->
        {:error, :payment_not_succeeded}

      {:error, reason} ->
        {:error, {:payment_verification_failed, reason}}
    end
  end

  @doc """
  Calculates pricing for a booking modification using locked entitlements.
  """
  def calculate_modification_pricing(%Booking{} = booking) do
    alias Ysc.Bookings.Entitlements

    booking = Repo.preload(booking, :rooms)
    nights = Date.diff(booking.checkout_date, booking.checkin_date)

    room_opts = fn ->
      room_ids =
        if Ecto.assoc_loaded?(booking.rooms) && booking.rooms != [] do
          Enum.map(booking.rooms, & &1.id)
        else
          []
        end

      [
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0,
        room_ids: room_ids
      ]
    end

    base_result =
      case booking.booking_mode do
        :buyout ->
          calculate_booking_price(
            booking.property,
            booking.checkin_date,
            booking.checkout_date,
            :buyout,
            guests_count: booking.guests_count,
            children_count: 0
          )

        :room ->
          room_ids =
            if booking.rooms != [],
              do: Enum.map(booking.rooms, & &1.id),
              else: []

          if room_ids == [] do
            {:error, :rooms_required}
          else
            calculate_booking_price(
              booking.property,
              booking.checkin_date,
              booking.checkout_date,
              :room,
              room_id: List.first(room_ids),
              guests_count: booking.guests_count,
              children_count: booking.children_count || 0
            )
          end

        :day ->
          calculate_booking_price(
            booking.property,
            booking.checkin_date,
            booking.checkout_date,
            :day,
            guests_count: booking.guests_count,
            children_count: 0
          )

        _ ->
          {:error, :invalid_booking_mode}
      end

    with {:ok, base_total, breakdown} <- base_result,
         {:ok, priced} <-
           Entitlements.price_with_locked_entitlement(
             booking,
             base_total,
             booking.booking_mode,
             room_opts.()
           ) do
      pricing_items =
        build_modification_pricing_items(booking, priced, breakdown, nights)

      {:ok,
       %{
         total: priced.total,
         subtotal: priced.subtotal,
         discount: priced.discount,
         pricing_items: pricing_items,
         breakdown: Map.merge(breakdown, %{nights: nights})
       }}
    end
  end

  defp build_modification_pricing_items(booking, priced, breakdown, nights) do
    total_map = %{
      "amount" => Decimal.to_string(priced.total.amount),
      "currency" => to_string(priced.total.currency)
    }

    case booking.booking_mode do
      :room ->
        %{
          "type" => "room",
          "nights" => nights,
          "guests_count" => booking.guests_count,
          "children_count" => booking.children_count || 0,
          "total" => total_map,
          "entitlement_discount" => money_map(priced.discount),
          "entitlement_subtotal" => money_map(priced.subtotal)
        }

      :day ->
        %{
          "type" => "per_guest",
          "nights" => nights,
          "guests_count" => booking.guests_count,
          "total" => total_map
        }

      :buyout ->
        price_per_night_map =
          case Map.get(breakdown, :price_per_night) ||
                 Map.get(breakdown, "price_per_night") do
            %Money{} = money -> money_map(money)
            other -> other
          end

        %{
          "type" => "buyout",
          "nights" => nights,
          "guests_count" => booking.guests_count,
          "price_per_night" => price_per_night_map,
          "subtotal" => money_map(priced.subtotal),
          "total" => total_map
        }
    end
  end

  defp money_map(%Money{} = money) do
    %{
      "amount" => Decimal.to_string(money.amount),
      "currency" => to_string(money.currency)
    }
  end

  defp money_map(_), do: nil

  defp normalize_stripe_fee(%Money{} = fee), do: fee
  defp normalize_stripe_fee(_), do: Money.new(0, :USD)

  @doc """
  Deletes a booking.
  """
  def delete_booking(%Booking{} = booking) do
    result = Repo.delete(booking)
    invalidate_availability_caches(result)
    result
  end

  ## Booking Guests

  @doc """
  Lists all guests for a booking, ordered by order_index.
  """
  def list_booking_guests(booking_id) do
    from(bg in BookingGuest,
      where: bg.booking_id == ^booking_id,
      order_by: [asc: bg.order_index]
    )
    |> Repo.all()
  end

  @doc """
  Creates multiple booking guests atomically.
  """
  def create_booking_guests(booking_id, guests_attrs)
      when is_list(guests_attrs) do
    import Ecto.Multi

    multi =
      Enum.reduce(guests_attrs, new(), fn {index, guest_attrs}, acc ->
        # Convert atom keys to string keys to avoid mixed key errors
        guest_attrs_string_keys =
          Enum.reduce(guest_attrs, %{}, fn
            {key, value}, acc_map when is_atom(key) ->
              Map.put(acc_map, Atom.to_string(key), value)

            {key, value}, acc_map ->
              Map.put(acc_map, key, value)
          end)

        guest_attrs_with_booking =
          Map.merge(guest_attrs_string_keys, %{
            "booking_id" => booking_id,
            "order_index" => index
          })

        changeset =
          BookingGuest.changeset(%BookingGuest{}, guest_attrs_with_booking)

        insert(acc, {:guest, index}, changeset)
      end)

    case Repo.transaction(multi) do
      {:ok, results} ->
        guests = Enum.map(results, fn {_key, guest} -> guest end)
        {:ok, guests}

      {:error, _key, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes all guests for a booking.
  """
  def delete_booking_guests(booking_id) do
    from(bg in BookingGuest, where: bg.booking_id == ^booking_id)
    |> Repo.delete_all()
  end

  ## Check-ins

  @doc """
  Validates that bookings are eligible for property check-in.

  Requires confirmed (`:complete`) status, an active stay window in PST
  (check-in date reached and checkout not yet passed), and that the booking
  has not already been marked checked in.
  """
  def validate_bookings_for_check_in(bookings) when is_list(bookings) do
    today_pst = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

    Enum.reduce_while(bookings, :ok, fn booking, :ok ->
      case check_in_eligibility_error(booking, today_pst) do
        nil -> {:cont, :ok}
        message -> {:halt, {:error, message}}
      end
    end)
  end

  defp check_in_eligibility_error(%Booking{} = booking, today_pst) do
    label = booking_check_in_label(booking)

    cond do
      booking.status != :complete ->
        "booking #{label} is not confirmed (status: #{booking.status})"

      booking.checked_in ->
        "booking #{label} is already checked in"

      Date.compare(booking.checkin_date, today_pst) == :gt ->
        "booking #{label} is not yet active (check-in: #{booking.checkin_date})"

      Date.compare(booking.checkout_date, today_pst) != :gt ->
        "booking #{label} has already ended (checkout: #{booking.checkout_date})"

      true ->
        nil
    end
  end

  defp booking_check_in_label(%Booking{reference_id: ref})
       when is_binary(ref) and ref != "",
       do: ref

  defp booking_check_in_label(%Booking{id: id}), do: to_string(id)

  @doc """
  Creates a check-in with associated bookings and vehicles.
  """
  @dialyzer {:nowarn_function, create_check_in: 1}
  def create_check_in(attrs \\ %{}) do
    import Ecto.Multi

    bookings = Map.get(attrs, :bookings, []) || []
    vehicles = Map.get(attrs, :vehicles, []) || []

    check_in_attrs =
      attrs
      |> Map.drop([:bookings, :vehicles])
      |> Map.put(:checked_in_at, DateTime.utc_now())

    multi =
      new()
      |> insert(:check_in, CheckIn.changeset(%CheckIn{}, check_in_attrs))
      |> insert_check_in_bookings(bookings)
      |> insert_check_in_vehicles(vehicles)
      |> mark_bookings_checked_in(bookings)

    case Repo.transaction(multi) do
      {:ok, %{check_in: check_in}} ->
        check_in =
          Repo.preload(check_in, [:bookings, :check_in_vehicles])

        {:ok, check_in}

      {:error, _key, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp insert_check_in_bookings(multi, []) do
    multi
  end

  defp insert_check_in_bookings(multi, bookings) when is_list(bookings) do
    import Ecto.Multi

    Enum.reduce(bookings, multi, fn booking, acc ->
      insert(acc, {:check_in_booking, booking.id}, fn %{check_in: check_in} ->
        %CheckInBooking{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:check_in_id, check_in.id)
        |> Ecto.Changeset.put_change(:booking_id, booking.id)
      end)
    end)
  end

  defp insert_check_in_vehicles(multi, []) do
    multi
  end

  defp insert_check_in_vehicles(multi, vehicles) when is_list(vehicles) do
    import Ecto.Multi

    Enum.with_index(vehicles)
    |> Enum.reduce(multi, fn {vehicle_attrs, index}, acc ->
      insert(acc, {:vehicle, index}, fn %{check_in: check_in} ->
        CheckInVehicle.changeset(
          %CheckInVehicle{},
          Map.merge(vehicle_attrs, %{"check_in_id" => check_in.id})
        )
      end)
    end)
  end

  defp mark_bookings_checked_in(multi, []) do
    multi
  end

  defp mark_bookings_checked_in(multi, bookings) when is_list(bookings) do
    # Extract booking IDs
    booking_ids = Enum.map(bookings, & &1.id)

    # Use update_all to directly update the database without touching relations
    Ecto.Multi.run(multi, :mark_bookings_checked_in, fn repo, _changes ->
      {count, _} =
        from(b in Booking, where: b.id in ^booking_ids)
        |> repo.update_all(set: [checked_in: true])

      {:ok, count}
    end)
  end

  @doc """
  Gets a single check-in with preloaded associations.
  """
  def get_check_in!(id) do
    Repo.get!(CheckIn, id)
    |> Repo.preload([:bookings, :check_in_vehicles])
  end

  @doc """
  Lists all check-ins for a specific booking.
  """
  def list_check_ins_by_booking(booking_id) do
    from(ci in CheckIn,
      join: cib in CheckInBooking,
      on: ci.id == cib.check_in_id,
      where: cib.booking_id == ^booking_id,
      order_by: [desc: ci.checked_in_at],
      preload: [:bookings, :check_in_vehicles]
    )
    |> Repo.all()
  end

  @doc """
  Searches bookings by the booking owner's last name (case-insensitive).
  Returns bookings that are active today (in PST) and belong to a user with matching last name.
  Filters by the specified property.

  A booking is considered active if:
  - checkin_date <= today (PST)
  - checkout_date > today (PST)

  ## Parameters
  - `last_name`: The last name to search for (case-insensitive)
  - `property`: The property to filter by (:tahoe or :clear_lake)
  """
  def search_bookings_by_last_name(last_name, property)
      when is_binary(last_name) and is_atom(property) do
    # Normalize input to lowercase for case-insensitive comparison
    normalized_last_name = String.downcase(String.trim(last_name))

    if normalized_last_name == "" do
      []
    else
      # Get today's date in PST timezone
      today_pst = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

      bookings =
        from(b in Booking,
          join: u in assoc(b, :user),
          # Case-insensitive comparison: convert database value to lowercase
          where:
            b.property == ^property and
              b.checkin_date <= ^today_pst and
              b.checkout_date > ^today_pst and
              fragment(
                "LOWER(?) = LOWER(?)",
                u.last_name,
                ^normalized_last_name
              ),
          order_by: [desc: b.checkin_date],
          preload: [:rooms, {:user, :current_avatar}]
        )
        |> Repo.all()

      Repo.preload(bookings, [
        {:booking_guests,
         from(bg in BookingGuest, order_by: [asc: bg.order_index])},
        check_ins: :check_in_vehicles
      ])
    end
  end

  @doc """
  Marks a booking as checked in.
  """
  def mark_booking_checked_in(booking_id) do
    booking = Repo.get!(Booking, booking_id) |> Repo.preload(:rooms)

    booking
    |> Booking.changeset(%{checked_in: true})
    |> Repo.update()
  end

  ## Blackouts

  @doc """
  Lists all blackouts, optionally filtered by property and date range.

  A blackout is included if it overlaps with the date range, meaning:
  - The blackout's start_date is <= end_date
  - The blackout's end_date is >= start_date

  ## Parameters
  - `property`: Optional atom property filter (e.g., `:tahoe`, `:clear_lake`)
  - `start_date`: Optional start date for filtering (inclusive)
  - `end_date`: Optional end date for filtering (inclusive)

  ## Examples
      # Get all blackouts for Tahoe
      list_blackouts(:tahoe)

      # Get blackouts for Tahoe in November 2025
      list_blackouts(:tahoe, ~D[2025-11-01], ~D[2025-11-30])

      # Get all blackouts in a date range across all properties
      list_blackouts(nil, ~D[2025-11-01], ~D[2025-11-30])
  """
  def list_blackouts(property \\ nil, start_date \\ nil, end_date \\ nil) do
    if property && start_date && end_date do
      Ysc.Bookings.BlackoutListCache.list(property, start_date, end_date)
    else
      list_blackouts_from_db(property, start_date, end_date)
    end
  end

  def list_blackouts_from_db(
        property \\ nil,
        start_date \\ nil,
        end_date \\ nil
      ) do
    query = from b in Blackout, order_by: [asc: b.property, asc: b.start_date]

    query =
      if property do
        from b in query, where: b.property == ^property
      else
        query
      end

    query =
      if start_date && end_date do
        from b in query,
          where:
            fragment(
              "(? <= ? AND ? >= ?)",
              b.start_date,
              ^end_date,
              b.end_date,
              ^start_date
            )
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single blackout.
  """
  def get_blackout!(id) do
    Repo.get!(Blackout, id)
  end

  @doc """
  Creates a blackout.
  """
  def create_blackout(attrs \\ %{}) do
    result =
      %Blackout{}
      |> Blackout.changeset(attrs)
      |> Repo.insert()

    invalidate_blackout_caches(result)
    result
  end

  @doc """
  Updates a blackout.
  """
  def update_blackout(%Blackout{} = blackout, attrs) do
    result =
      blackout
      |> Blackout.changeset(attrs)
      |> Repo.update()

    invalidate_blackout_caches(result)
    result
  end

  @doc """
  Deletes a blackout.
  """
  def delete_blackout(%Blackout{} = blackout) do
    result = Repo.delete(blackout)
    invalidate_blackout_caches(result)
    result
  end

  defp invalidate_availability_caches({:ok, _}) do
    Ysc.Bookings.AvailabilityCache.invalidate()
    :ok
  end

  defp invalidate_availability_caches(_), do: :ok

  defp invalidate_blackout_caches({:ok, _}) do
    Ysc.Bookings.BlackoutListCache.invalidate()
    :ok
  end

  defp invalidate_blackout_caches(_), do: :ok

  @doc """
  Checks if a blackout overlaps with a booking date range, accounting for check-in/check-out times.

  Since check-out is at 11 AM and check-in is at 3 PM, a blackout and booking can share the
  same date if one ends and the other starts on that date.

  ## Parameters
  - `property`: The property to check
  - `checkin_date`: Booking check-in date
  - `checkout_date`: Booking check-out date

  ## Returns
  - `true` if there's a blackout conflict
  - `false` if there's no conflict

  ## Examples
      # Blackout Jan 9-12, Booking Jan 7-9: No conflict (checkout at 11 AM, blackout starts at 3 PM)
      iex> Ysc.Bookings.has_blackout?(:tahoe, ~D[2025-01-07], ~D[2025-01-09])
      false

      # Blackout Jan 9-12, Booking Jan 9-10: Conflict (check-in at 3 PM conflicts with blackout)
      iex> Ysc.Bookings.has_blackout?(:tahoe, ~D[2025-01-09], ~D[2025-01-10])
      true
  """
  def has_blackout?(property, checkin_date, checkout_date)
      when is_atom(property) do
    # Get all blackouts that might overlap
    blackouts = get_overlapping_blackouts(property, checkin_date, checkout_date)

    # Check if any blackout actually conflicts, accounting for check-in/checkout times
    Enum.any?(blackouts, fn blackout ->
      # A blackout conflicts with a booking if:
      # 1. The booking's check-in date is before the blackout's end date
      #    AND the booking's checkout date is after the blackout's start date
      # 2. BUT we need to account for same-day turnarounds:
      #    - If booking checkout is on blackout start date: No conflict (11 AM checkout vs 3 PM blackout start)
      #    - If booking checkin is on blackout end date: No conflict (3 PM checkin vs 11 AM blackout end)

      cond do
        # Same-day turnarounds: no conflict
        checkout_date == blackout.start_date ->
          false

        checkin_date == blackout.end_date ->
          false

        # Otherwise, check for standard overlap
        # Conflict occurs if: checkin < blackout_end AND checkout > blackout_start
        Date.compare(checkin_date, blackout.end_date) == :lt &&
            Date.compare(checkout_date, blackout.start_date) == :gt ->
          true

        true ->
          false
      end
    end)
  end

  @doc """
  Gets all blackouts that overlap with a date range for a property.
  """
  def get_overlapping_blackouts(property, start_date, end_date)
      when is_atom(property) do
    Ysc.Bookings.BlackoutListCache.list(property, start_date, end_date)
  end

  def get_overlapping_blackouts_from_db(property, start_date, end_date)
      when is_atom(property) do
    from(b in Blackout,
      where: b.property == ^property,
      where:
        fragment(
          "(? <= ? AND ? >= ?)",
          b.start_date,
          ^end_date,
          b.end_date,
          ^start_date
        ),
      order_by: [asc: b.start_date]
    )
    |> Repo.all()
  end

  ## Booking Availability

  @doc """
  Checks if two booking date ranges overlap, accounting for check-in/check-out times.

  Since check-out is at 11 AM and check-in is at 3 PM, bookings can share the
  same date if one ends and the other starts on that date.

  ## Parameters
  - `checkin_date1`, `checkout_date1`: First booking's dates
  - `checkin_date2`, `checkout_date2`: Second booking's dates

  ## Returns
  - `true` if the bookings overlap (conflict)
  - `false` if they don't overlap (can coexist)

  ## Examples
      iex> Ysc.Bookings.bookings_overlap?(~D[2025-11-01], ~D[2025-11-03], ~D[2025-11-03], ~D[2025-11-05])
      false
      # First booking ends Nov 3 at 11 AM, second starts Nov 3 at 3 PM - no overlap

      iex> Ysc.Bookings.bookings_overlap?(~D[2025-11-01], ~D[2025-11-04], ~D[2025-11-03], ~D[2025-11-05])
      true
      # First booking includes Nov 3 and Nov 4, second includes Nov 3 and Nov 4 - overlap

      iex> Ysc.Bookings.bookings_overlap?(~D[2025-11-01], ~D[2025-11-02], ~D[2025-11-02], ~D[2025-11-03])
      false
      # First ends Nov 2 at 11 AM, second starts Nov 2 at 3 PM - no overlap
  """
  def bookings_overlap?(
        checkin_date1,
        checkout_date1,
        checkin_date2,
        checkout_date2
      ) do
    # Bookings overlap if:
    # 1. The first booking's check-in date is before the second's checkout date
    #    AND the first booking's checkout date is after the second's check-in date
    # 2. BUT we need to account for same-day turnarounds:
    #    - If one booking ends on date X and another starts on date X, they don't overlap
    #    - So we exclude the case where checkout_date1 == checkin_date2
    #    - And we exclude the case where checkout_date2 == checkin_date1

    cond do
      # Same-day turnarounds: if one ends and the other starts on the same date, no overlap
      checkout_date1 == checkin_date2 ->
        false

      checkout_date2 == checkin_date1 ->
        false

      # Otherwise, check for standard overlap
      # Overlap occurs if: checkin1 < checkout2 AND checkout1 > checkin2
      Date.compare(checkin_date1, checkout_date2) == :lt &&
          Date.compare(checkout_date1, checkin_date2) == :gt ->
        true

      true ->
        false
    end
  end

  @doc """
  Returns whether any hold or complete bookings conflict with a date range.

  Uses strict overlap semantics (same-day turnarounds are allowed), matching
  `bookings_overlap?/4` and Tahoe buyout validation.
  """
  def has_conflicting_bookings?(
        property,
        checkin_date,
        checkout_date,
        opts \\ []
      ) do
    property
    |> conflicting_bookings_query(checkin_date, checkout_date, opts)
    |> Repo.exists?()
  end

  @doc false
  def conflicting_bookings_query(
        property,
        checkin_date,
        checkout_date,
        opts \\ []
      ) do
    statuses = Keyword.get(opts, :statuses, [:hold, :complete])

    from b in Booking,
      where: b.property == ^property,
      where: b.status in ^statuses,
      where:
        fragment(
          "? < ? AND ? > ?",
          b.checkin_date,
          ^checkout_date,
          b.checkout_date,
          ^checkin_date
        )
  end

  @doc """
  Gets the check-in time (3:00 PM).
  """
  def checkin_time, do: @checkin_time

  @doc """
  Gets the check-out time (11:00 AM).
  """
  def checkout_time, do: @checkout_time

  @doc """
  Checks if a room is available for the given date range.

  A room is available if:
  - There are no existing bookings that overlap with the date range
  - There are no blackouts for the property that overlap with the date range
  - The room is active

  ## Parameters
  - `room_id`: The room to check
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `exclude_booking_id`: Optional booking ID to exclude from the check (for updates)

  ## Returns
  - `true` if available
  - `false` if not available
  """
  def room_available?(
        room_id,
        checkin_date,
        checkout_date,
        exclude_booking_id \\ nil
      ) do
    room = get_room!(room_id)

    if room.is_active do
      # Check for overlapping bookings using the booking_rooms join table
      # ULIDs are stored as binary UUIDs in PostgreSQL, but have different string representations
      # We need to compare the binary UUID column with the ULID string
      # Since ULIDs are binary-compatible with UUIDs, we can use the room's ID directly
      # and let Ecto handle the conversion by using type/2 to specify binary_id
      overlapping_bookings_query =
        from b in Booking,
          join: br in "booking_rooms",
          on: br.booking_id == b.id,
          where: br.room_id == type(^room.id, Ecto.ULID),
          where:
            fragment(
              "(? < ? AND ? > ?)",
              b.checkin_date,
              ^checkout_date,
              b.checkout_date,
              ^checkin_date
            ),
          where: b.status in [:hold, :complete]

      overlapping_bookings_query =
        if exclude_booking_id do
          from b in overlapping_bookings_query,
            where: b.id != ^exclude_booking_id
        else
          overlapping_bookings_query
        end

      has_overlapping_bookings = Repo.exists?(overlapping_bookings_query)

      # Check for property buyout
      # If there is a buyout, no rooms are available
      has_buyout =
        Repo.exists?(
          from pi in PropertyInventory,
            where: pi.property == ^room.property,
            where: pi.day >= ^checkin_date and pi.day < ^checkout_date,
            where: pi.buyout_held == true or pi.buyout_booked == true
        )

      if has_overlapping_bookings or has_buyout do
        false
      else
        # Check for blackouts
        not has_blackout?(room.property, checkin_date, checkout_date)
      end
    else
      false
    end
  end

  @doc """
  Gets available rooms for a property and date range.

  Returns a list of rooms that are available for the given dates.
  """
  def get_available_rooms(property, checkin_date, checkout_date) do
    list_rooms(property)
    |> Enum.filter(fn room ->
      room_available?(room.id, checkin_date, checkout_date)
    end)
  end

  @doc """
  Batch checks availability for multiple rooms at once.

  Returns a MapSet of room IDs that are available for the given dates.
  This is much more efficient than calling room_available? for each room individually.

  ## Parameters
  - `room_ids`: List of room IDs to check
  - `property`: The property
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date

  ## Returns
  - `MapSet` of available room IDs
  """
  def batch_check_room_availability(
        room_ids,
        property,
        checkin_date,
        checkout_date
      ) do
    if Enum.empty?(room_ids) do
      MapSet.new()
    else
      # Get all active rooms (Room.id is ULID type, so Ecto handles conversion automatically)
      active_room_ids =
        from(r in Room,
          where: r.id in ^room_ids,
          where: r.property == ^property,
          where: r.is_active == true,
          select: r.id
        )
        |> Repo.all()
        |> MapSet.new()

      # Convert room_ids to binary format for comparison with booking_rooms.room_id (which is binary)
      room_ids_binary =
        room_ids
        |> Enum.map(&convert_room_id_to_binary/1)

      # Check for overlapping bookings for all rooms at once
      # booking_rooms.room_id is stored as binary UUID, so we use the binary format
      # Use fragment with ANY to properly handle the binary array
      booked_room_ids_binary =
        from(b in Booking,
          join: br in "booking_rooms",
          on: br.booking_id == b.id,
          where:
            fragment(
              "? = ANY(?)",
              br.room_id,
              ^room_ids_binary
            ),
          where:
            fragment(
              "(? < ? AND ? > ?)",
              b.checkin_date,
              ^checkout_date,
              b.checkout_date,
              ^checkin_date
            ),
          where: b.status in [:hold, :complete],
          select: br.room_id,
          distinct: true
        )
        |> Repo.all()
        |> MapSet.new()

      # Convert active_room_ids to binary for comparison with booked_room_ids_binary
      active_room_ids_binary =
        active_room_ids
        |> Enum.map(&convert_room_id_to_binary/1)
        |> MapSet.new()

      # Available rooms = active rooms (binary) - booked rooms (binary)
      available_room_ids_binary =
        MapSet.difference(active_room_ids_binary, booked_room_ids_binary)

      # Convert back to ULID strings by matching with original room_ids
      # We can do this by finding which room_ids (when converted to binary) match the available binary IDs
      available_room_ids =
        room_ids
        |> Enum.filter(fn room_id ->
          room_available?(room_id, available_room_ids_binary)
        end)
        |> MapSet.new()

      # Check for property buyout (if buyout exists, no rooms are available)
      has_buyout =
        Repo.exists?(
          from(pi in PropertyInventory,
            where: pi.property == ^property,
            where: pi.day >= ^checkin_date and pi.day < ^checkout_date,
            where: pi.buyout_held == true or pi.buyout_booked == true
          )
        )

      # Check for blackouts
      has_blackout = has_blackout?(property, checkin_date, checkout_date)

      if has_buyout or has_blackout do
        # If buyout or blackout exists, no rooms are available
        MapSet.new()
      else
        # available_room_ids was already calculated above
        available_room_ids
      end
    end
  end

  @doc """
  Calculates the total price for a booking.

  ## Parameters
  - `property`: The property (:tahoe or :clear_lake)
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `booking_mode`: Booking mode (:room, :day, or :buyout)
  - `opts`: Optional keyword list with:
    - `:room_id` - Optional room ID (for room bookings)
    - `:guests_count` - Number of guests/people (default: 1)
    - `:children_count` - Number of children (default: 0)
    - `:exclude_booking_id` - Optional booking ID to exclude (for updates)
    - `:use_actual_guests` - Whether to use actual guests count (default: false)

  ## Returns
  - `{:ok, %Money{}}` with the total price
  - `{:error, reason}` if pricing cannot be calculated
  """
  def calculate_booking_price(
        property,
        checkin_date,
        checkout_date,
        booking_mode,
        opts \\ []
      ) do
    params = %{
      property: property,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      booking_mode: booking_mode,
      room_id: Keyword.get(opts, :room_id),
      guests_count: Keyword.get(opts, :guests_count, 1),
      children_count: Keyword.get(opts, :children_count, 0),
      use_actual_guests: Keyword.get(opts, :use_actual_guests, false)
    }

    calculate_booking_price_impl(params)
  end

  defp calculate_booking_price_impl(params) do
    with {:ok, nights} <-
           validate_booking_dates(params.checkin_date, params.checkout_date),
         {:ok, _} <- validate_booking_mode(params.booking_mode, params.room_id) do
      case params.booking_mode do
        :buyout ->
          calculate_buyout_price(
            params.property,
            params.checkin_date,
            params.checkout_date,
            nights
          )

        :room ->
          calculate_room_price(
            params.property,
            params.checkin_date,
            params.checkout_date,
            params.room_id,
            params.guests_count,
            params.children_count,
            nights,
            params.use_actual_guests
          )

        :day ->
          calculate_day_price(
            params.property,
            params.checkin_date,
            params.checkout_date,
            params.guests_count,
            nights
          )

        _ ->
          {:error, :invalid_booking_mode}
      end
    end
  end

  defp validate_booking_dates(checkin_date, checkout_date) do
    cond do
      not is_struct(checkin_date, Date) ->
        Ysc.Logging.error(
          "[Bookings] calculate_booking_price: invalid checkin_date: #{inspect(checkin_date)}"
        )

        {:error, :invalid_checkin_date}

      not is_struct(checkout_date, Date) ->
        Ysc.Logging.error(
          "[Bookings] calculate_booking_price: invalid checkout_date: #{inspect(checkout_date)}"
        )

        {:error, :invalid_checkout_date}

      true ->
        nights = Date.diff(checkout_date, checkin_date)

        if nights <= 0 do
          {:error, :invalid_date_range}
        else
          {:ok, nights}
        end
    end
  end

  defp validate_booking_mode(:room, nil), do: {:error, :room_id_required}
  defp validate_booking_mode(_booking_mode, _room_id), do: {:ok, :valid}

  defp calculate_buyout_price(property, checkin_date, checkout_date, _nights) do
    # For buyouts, we need to check the season for each night
    # and sum up the prices
    date_range =
      Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

    {total, price_per_night} =
      Enum.reduce(date_range, {Money.new(:USD, 0), nil}, fn date,
                                                            {acc, price_acc} ->
        season = Season.for_date(property, date)
        season_id = if season, do: season.id, else: nil

        pricing_rule =
          PricingRule.find_most_specific(
            property,
            season_id,
            nil,
            nil,
            :buyout,
            :buyout_fixed
          )

        if pricing_rule do
          # Capture price per night if not yet captured
          new_price_acc = price_acc || pricing_rule.amount
          add_pricing_rule_amount(acc, pricing_rule.amount, new_price_acc)
        else
          {acc, price_acc}
        end
      end)

    nights = length(date_range)

    breakdown = %{
      nights: nights,
      price_per_night: price_per_night
    }

    {:ok, total, breakdown}
  end

  defp calculate_room_price(
         property,
         checkin_date,
         checkout_date,
         room_id,
         guests_count,
         children_count,
         nights,
         use_actual_guests
       ) do
    # Basic validation
    case validate_room_price_params(
           property,
           checkin_date,
           checkout_date,
           guests_count,
           children_count
         ) do
      :ok ->
        calculate_room_price_impl(
          property,
          checkin_date,
          checkout_date,
          room_id,
          guests_count,
          children_count,
          nights,
          use_actual_guests
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_room_price_params(
         property,
         _checkin_date,
         _checkout_date,
         guests_count,
         children_count
       ) do
    # Dates and range are validated in calculate_booking_price_impl/1 via
    # validate_booking_dates/2 before calculate_room_price/8 is called.
    with :ok <- validate_property(property),
         :ok <- validate_guests_count(guests_count) do
      validate_children_count(children_count)
    end
  end

  defp validate_property(property) when is_atom(property), do: :ok
  defp validate_property(_), do: {:error, :invalid_property}

  defp validate_guests_count(guests_count)
       when is_integer(guests_count) and guests_count > 0,
       do: :ok

  defp validate_guests_count(_), do: {:error, :invalid_guests_count}

  defp validate_children_count(children_count)
       when is_integer(children_count) and children_count >= 0,
       do: :ok

  defp validate_children_count(_), do: {:error, :invalid_children_count}

  defp calculate_room_price_impl(
         property,
         checkin_date,
         checkout_date,
         room_id,
         guests_count,
         children_count,
         _nights,
         use_actual_guests
       ) do
    room = get_room!(room_id)

    # For multiple rooms, use actual guests_count; for single room, use billable_people (capped by capacity)
    billable_people =
      calculate_billable_people(use_actual_guests, room, guests_count)

    if is_nil(billable_people) or billable_people <= 0 do
      {:error, :invalid_guests_count}
    else
      date_range =
        Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      {total, base_total, children_total, adult_price_per_night,
       children_price_per_night, found_pricing_rules} =
        calculate_room_price_for_date_range(
          date_range,
          property,
          room_id,
          room.room_category_id,
          billable_people,
          children_count
        )

      if found_pricing_rules do
        price_result_params = %{
          date_range: date_range,
          total: total,
          base_total: base_total,
          children_total: children_total,
          adult_price_per_night: adult_price_per_night,
          children_price_per_night: children_price_per_night,
          billable_people: billable_people,
          guests_count: guests_count,
          children_count: children_count
        }

        build_room_price_result(price_result_params)
      else
        {:error, :no_pricing_rules_found}
      end
    end
  end

  defp calculate_billable_people(use_actual_guests, room, guests_count) do
    if use_actual_guests do
      guests_count
    else
      Room.billable_people(room, guests_count) || guests_count
    end
  end

  defp calculate_room_price_for_date_range(
         date_range,
         property,
         room_id,
         room_category_id,
         billable_people,
         children_count
       ) do
    Enum.reduce(
      date_range,
      {Money.new(:USD, 0), Money.new(:USD, 0), Money.new(:USD, 0), nil, nil,
       false},
      fn date,
         {acc, base_acc, children_acc, adult_price, children_price, found_any} ->
        calculate_room_price_for_date(
          date,
          property,
          room_id,
          room_category_id,
          billable_people,
          children_count,
          {acc, base_acc, children_acc, adult_price, children_price, found_any}
        )
      end
    )
  end

  defp calculate_room_price_for_date(
         date,
         property,
         room_id,
         room_category_id,
         billable_people,
         children_count,
         {acc, base_acc, children_acc, adult_price, children_price, found_any}
       ) do
    season = Season.for_date(property, date)
    season_id = if season, do: season.id, else: nil

    pricing_rule =
      find_pricing_rule_for_room(property, season_id, room_id, room_category_id)

    if pricing_rule do
      process_pricing_rule_for_date(
        pricing_rule,
        property,
        season_id,
        room_id,
        room_category_id,
        billable_people,
        children_count,
        {acc, base_acc, children_acc, adult_price, children_price, found_any}
      )
    else
      {acc, base_acc, children_acc, adult_price, children_price, found_any}
    end
  end

  defp find_pricing_rule_for_room(
         property,
         season_id,
         room_id,
         room_category_id
       ) do
    # Fallback hierarchy (room mode only — never falls back to buyout pricing):
    # 1. Room-specific rule
    # 2. Category-level rule
    PricingRule.find_most_specific(
      property,
      season_id,
      room_id,
      room_category_id,
      :room,
      :per_person_per_night
    ) ||
      PricingRule.find_most_specific(
        property,
        season_id,
        nil,
        room_category_id,
        :room,
        :per_person_per_night
      ) ||
      PricingRule.find_most_specific(
        property,
        season_id,
        nil,
        nil,
        :room,
        :per_person_per_night
      )
  end

  defp process_pricing_rule_for_date(
         pricing_rule,
         property,
         season_id,
         room_id,
         room_category_id,
         billable_people,
         children_count,
         {acc, base_acc, children_acc, adult_price, children_price, _found_any}
       ) do
    # Store per-person-per-night price (use first one found)
    adult_price = adult_price || pricing_rule.amount

    # Calculate base price
    {:ok, base_price} = Money.mult(pricing_rule.amount, billable_people)

    # Look up children pricing rule using same hierarchy
    children_price_per_person =
      find_children_pricing(property, season_id, room_id, room_category_id)

    # Store children price per night (use first one found)
    children_price = children_price || children_price_per_person

    # Add children pricing for Tahoe
    children_price_for_night =
      calculate_children_price_for_night(
        property,
        children_count,
        children_price_per_person
      )

    {:ok, night_total} = Money.add(base_price, children_price_for_night)
    {:ok, new_total} = Money.add(acc, night_total)
    {:ok, new_base_total} = Money.add(base_acc, base_price)

    {:ok, new_children_total} =
      Money.add(children_acc, children_price_for_night)

    {new_total, new_base_total, new_children_total, adult_price, children_price,
     true}
  end

  defp find_children_pricing(property, season_id, room_id, room_category_id) do
    # Falls back to $25 if no children pricing rule found
    children_pricing_rule =
      PricingRule.find_children_pricing_rule(
        property,
        season_id,
        room_id,
        room_category_id,
        :room,
        :per_person_per_night
      ) ||
        PricingRule.find_children_pricing_rule(
          property,
          season_id,
          nil,
          room_category_id,
          :room,
          :per_person_per_night
        ) ||
        PricingRule.find_children_pricing_rule(
          property,
          season_id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

    # Use children_amount from rule if found, otherwise fallback to $25
    if children_pricing_rule && children_pricing_rule.children_amount do
      children_pricing_rule.children_amount
    else
      Money.new(:USD, 25)
    end
  end

  defp calculate_children_price_for_night(
         property,
         children_count,
         children_price_per_person
       ) do
    if property == :tahoe && children_count > 0 do
      {:ok, price} = Money.mult(children_price_per_person, children_count)
      price
    else
      Money.new(:USD, 0)
    end
  end

  defp build_room_price_result(params) do
    nights = length(params.date_range)

    base_per_night = calculate_per_night_price(params.base_total, nights)

    children_per_night =
      calculate_per_night_price(params.children_total, nights)

    # Ensure children_price_per_night has a fallback value
    children_price_per_night =
      params.children_price_per_night || Money.new(:USD, 25)

    {:ok, params.total,
     %{
       base: params.base_total,
       children: params.children_total,
       base_per_night: base_per_night,
       children_per_night: children_per_night,
       nights: nights,
       billable_people: params.billable_people,
       guests_count: params.guests_count,
       children_count: params.children_count,
       adult_price_per_night: params.adult_price_per_night,
       children_price_per_night: children_price_per_night
     }}
  end

  defp calculate_per_night_price(total, nights) do
    if nights > 0 do
      {:ok, price} = Money.div(total, nights)
      price
    else
      Money.new(:USD, 0)
    end
  end

  defp calculate_day_price(
         property,
         checkin_date,
         _checkout_date,
         guests_count,
         nights
       ) do
    # For day bookings, price is per guest per day
    # Clear Lake uses this model

    # Determine season for checkin date to find correct pricing rule
    # This is important because pricing rules might be season-specific (e.g., Summer only)
    season = Season.for_date(property, checkin_date)
    season_id = if season, do: season.id, else: nil

    pricing_rule =
      PricingRule.find_most_specific(
        property,
        season_id,
        nil,
        nil,
        :day,
        :per_guest_per_day
      )

    if pricing_rule do
      total_days = nights
      total_guests = guests_count

      case Money.mult(pricing_rule.amount, total_days * total_guests) do
        {:ok, total} ->
          breakdown = %{
            nights: nights,
            guests_count: guests_count,
            price_per_guest_per_night: pricing_rule.amount
          }

          {:ok, total, breakdown}
      end
    else
      {:error, :pricing_rule_not_found}
    end
  end

  ## Door Codes

  @doc """
  Gets the currently active door code for a property.
  Returns nil if no active code exists.
  """
  def get_active_door_code(property) do
    from(dc in DoorCode,
      where: dc.property == ^property,
      where: is_nil(dc.active_to),
      order_by: [desc: dc.active_from],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists all door codes for a property, ordered by most recent first.
  """
  def list_door_codes(property) do
    from(dc in DoorCode,
      where: dc.property == ^property,
      order_by: [desc: dc.active_from, desc: dc.inserted_at],
      limit: 10
    )
    |> Repo.all()
  end

  @doc """
  Gets the last 3 door codes (excluding the current one if it matches) for a property.
  Used to check for code reuse warnings.
  """
  def get_recent_door_codes(property, exclude_code \\ nil) do
    query =
      from(dc in DoorCode,
        where: dc.property == ^property,
        order_by: [desc: dc.active_from, desc: dc.inserted_at],
        limit: 3
      )

    query =
      if exclude_code do
        from(dc in query, where: dc.code != ^exclude_code)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Creates a new door code and invalidates all previous codes for the property.

  Sets active_from to the current datetime and active_to to nil (making it active).
  Sets active_to to the current datetime for all other door codes for this property.
  """
  def create_door_code(attrs \\ %{}) do
    property = attrs[:property] || attrs["property"]
    code = attrs[:code] || attrs["code"]

    if is_nil(property) or is_nil(code) do
      {:error, :invalid_attributes}
    else
      case Repo.transaction(fn ->
             now = DateTime.utc_now()

             # Invalidate all previous door codes for this property
             from(dc in DoorCode,
               where: dc.property == ^property,
               where: is_nil(dc.active_to)
             )
             |> Repo.update_all(set: [active_to: now])

             # Create the new door code - normalize all keys to strings
             door_code_attrs =
               attrs
               |> Enum.map(fn
                 {k, v} when is_atom(k) -> {Atom.to_string(k), v}
                 {k, v} -> {k, v}
               end)
               |> Enum.into(%{})
               |> Map.put("active_from", now)
               |> Map.put("active_to", nil)
               |> Map.put("property", property)
               |> Map.put("code", code)

             case %DoorCode{}
                  |> DoorCode.changeset(door_code_attrs)
                  |> Repo.insert() do
               {:ok, door_code} ->
                 door_code

               {:error, changeset} ->
                 Repo.rollback(changeset)
             end
           end) do
        {:ok, door_code} ->
          {:ok, door_code}

        {:error, changeset} ->
          {:error, changeset}

        error ->
          error
      end
    end
  end

  @doc """
  Gets a single door code.
  """
  def get_door_code!(id) do
    Repo.get!(DoorCode, id)
  end

  ## Refund Policies

  @doc """
  Lists all refund policies, optionally filtered by property and booking mode.
  """
  def list_refund_policies(property \\ nil, booking_mode \\ nil) do
    query =
      from rp in RefundPolicy,
        order_by: [asc: rp.property, asc: rp.booking_mode]

    query =
      if property do
        from rp in query, where: rp.property == ^property
      else
        query
      end

    query =
      if booking_mode do
        from rp in query, where: rp.booking_mode == ^booking_mode
      else
        query
      end

    # Preload rules with ordering in a single query to avoid N+1
    policies =
      query
      |> Repo.all()
      |> Repo.preload(
        rules:
          from(r in RefundPolicyRule,
            order_by: [desc: r.days_before_checkin, asc: r.priority]
          )
      )

    policies
  end

  @doc """
  Gets a single refund policy.
  """
  def get_refund_policy!(id) do
    Repo.get!(RefundPolicy, id)
    |> Repo.preload(:rules)
  end

  @doc """
  Gets the active refund policy for a property and booking mode.
  Returns nil if no active policy exists.

  Uses cache for improved performance.
  """
  def get_active_refund_policy(property, booking_mode) do
    alias Ysc.Bookings.RefundPolicyCache
    RefundPolicyCache.get_active(property, booking_mode)
  end

  @doc """
  Gets the active refund policy directly from the database, bypassing cache.
  Useful for seed scripts and migrations where the cache may not be initialized.
  """
  def get_active_refund_policy_db(property, booking_mode) do
    import Ecto.Query
    alias Ysc.Bookings.{RefundPolicy, RefundPolicyRule}

    policy =
      from(rp in RefundPolicy,
        where: rp.property == ^property,
        where: rp.booking_mode == ^booking_mode,
        where: rp.is_active == true,
        order_by: [desc: rp.inserted_at, desc: rp.id],
        limit: 1
      )
      |> Repo.one()

    if policy do
      # Load rules ordered by days_before_checkin descending
      rules =
        from(r in RefundPolicyRule,
          where: r.refund_policy_id == ^policy.id
        )
        |> RefundPolicyRule.ordered_by_days()
        |> Repo.all()

      %{policy | rules: rules}
    else
      nil
    end
  end

  @doc """
  Creates a refund policy.
  """
  def create_refund_policy(attrs \\ %{}) do
    result =
      %RefundPolicy{}
      |> RefundPolicy.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _refund_policy} ->
        # Invalidate refund policy cache
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Creates a refund policy (bang version).
  """
  def create_refund_policy!(attrs \\ %{}) do
    result =
      %RefundPolicy{}
      |> RefundPolicy.changeset(attrs)
      |> Repo.insert!()

    # Invalidate refund policy cache
    Ysc.Bookings.RefundPolicyCache.invalidate()
    result
  end

  @doc """
  Updates a refund policy.
  """
  def update_refund_policy(%RefundPolicy{} = refund_policy, attrs) do
    result =
      refund_policy
      |> RefundPolicy.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _refund_policy} ->
        # Invalidate refund policy cache
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Deletes a refund policy.
  """
  def delete_refund_policy(%RefundPolicy{} = refund_policy) do
    result = Repo.delete(refund_policy)

    case result do
      {:ok, _refund_policy} ->
        # Invalidate refund policy cache
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  ## Refund Policy Rules

  @doc """
  Lists all rules for a refund policy, ordered by days_before_checkin descending.
  """
  def list_refund_policy_rules(refund_policy_id) do
    from(r in RefundPolicyRule,
      where: r.refund_policy_id == ^refund_policy_id
    )
    |> RefundPolicyRule.ordered_by_days()
    |> Repo.all()
  end

  @doc """
  Gets a single refund policy rule.
  """
  def get_refund_policy_rule!(id) do
    Repo.get!(RefundPolicyRule, id)
  end

  @doc """
  Creates a refund policy rule.
  """
  def create_refund_policy_rule(attrs \\ %{}) do
    result =
      %RefundPolicyRule{}
      |> RefundPolicyRule.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _refund_policy_rule} ->
        # Invalidate refund policy cache (rules are part of the policy)
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Creates a refund policy rule (bang version).
  """
  def create_refund_policy_rule!(attrs \\ %{}) do
    result =
      %RefundPolicyRule{}
      |> RefundPolicyRule.changeset(attrs)
      |> Repo.insert!()

    # Invalidate refund policy cache (rules are part of the policy)
    Ysc.Bookings.RefundPolicyCache.invalidate()
    result
  end

  @doc """
  Updates a refund policy rule.
  """
  def update_refund_policy_rule(%RefundPolicyRule{} = refund_policy_rule, attrs) do
    result =
      refund_policy_rule
      |> RefundPolicyRule.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _refund_policy_rule} ->
        # Invalidate refund policy cache (rules are part of the policy)
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Deletes a refund policy rule.
  """
  def delete_refund_policy_rule(%RefundPolicyRule{} = refund_policy_rule) do
    result = Repo.delete(refund_policy_rule)

    case result do
      {:ok, _refund_policy_rule} ->
        # Invalidate refund policy cache (rules are part of the policy)
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  ## Refund Calculation

  @doc """
  Calculates the refund amount for a booking based on the cancellation date and refund policy.

  ## Parameters
  - `booking`: The booking to calculate refund for
  - `cancellation_date`: The date the booking is being cancelled (defaults to today)

  ## Returns
  - `{:ok, refund_amount, applied_rule}` if a policy exists and calculation succeeds
  - `{:ok, full_refund, nil}` if no policy exists (full refund by default)
  - `{:error, reason}` if calculation fails

  ## Examples
      iex> booking = %Booking{property: :tahoe, booking_mode: :buyout, checkin_date: ~D[2025-12-01]}
      iex> calculate_refund(booking, ~D[2025-11-10])
      {:ok, %Money{amount: 500, currency: :USD}, %RefundPolicyRule{}}
  """
  def calculate_refund(
        booking,
        cancellation_date \\ Date.utc_today(),
        opts \\ []
      ) do
    if booking.refund_forfeited_at do
      {:ok, Money.new(0, :USD), nil}
    else
      calculate_refund_from_policy(booking, cancellation_date, opts)
    end
  end

  defp calculate_refund_from_policy(
         booking,
         cancellation_date,
         opts
       ) do
    policy = get_active_refund_policy(booking.property, booking.booking_mode)

    days_before_checkin = Date.diff(booking.checkin_date, cancellation_date)

    if days_before_checkin < 0 do
      # Cancellation is after check-in date - no refund (regardless of policy)
      {:ok, Money.new(0, :USD), nil}
    else
      if is_nil(policy) or is_nil(policy.rules) or Enum.empty?(policy.rules) do
        # No policy exists - default to full refund
        {:ok, nil, nil}
      else
        # Find the most restrictive rule that applies
        # Rules are ordered by days_before_checkin DESC, so we need to find
        # the rule with the smallest days_before_checkin where cancellation_days <= rule.days_before_checkin
        # This means we want the LAST rule in the list that matches (most restrictive)
        matching_rules =
          Enum.filter(policy.rules, fn rule ->
            days_before_checkin <= rule.days_before_checkin
          end)

        applied_rule =
          if Enum.empty?(matching_rules) do
            nil
          else
            # Get the rule with the smallest days_before_checkin (most restrictive)
            Enum.min_by(matching_rules, fn rule -> rule.days_before_checkin end)
          end

        if applied_rule do
          # Get the original payment amount for this booking
          original_amount_result =
            case Keyword.get(opts, :original_amount) do
              %Money{} = amount -> {:ok, amount}
              _ -> get_booking_payment_amount(booking)
            end

          case original_amount_result do
            {:ok, original_amount} ->
              refund_percentage =
                Decimal.to_float(applied_rule.refund_percentage)

              refund_amount =
                calculate_refund_amount(original_amount, refund_percentage)

              {:ok, refund_amount, applied_rule}

            {:error, reason} ->
              {:error, reason}
          end
        else
          # No rule applies - default to full refund
          {:ok, nil, nil}
        end
      end
    end
  end

  @doc """
  Gets the payment amount for a booking by looking up ledger entries.
  """
  def get_booking_payment_amount(booking) do
    import Ecto.Query

    # Find ledger entries for this booking
    # Payment entries are debit entries to stripe_account
    entry =
      from(e in Ysc.Ledgers.LedgerEntry,
        join: a in Ysc.Ledgers.LedgerAccount,
        on: e.account_id == a.id,
        where: e.related_entity_type == ^:booking,
        where: e.related_entity_id == ^booking.id,
        where: e.debit_credit == "debit",
        where: a.name == "stripe_account",
        order_by: [desc: e.inserted_at],
        limit: 1
      )
      |> Repo.one()

    if entry do
      {:ok, entry.amount}
    else
      {:error, :payment_not_found}
    end
  end

  defp calculate_refund_amount(original_amount, refund_percentage)
       when is_float(refund_percentage) do
    # Convert percentage to decimal (e.g., 50.0 -> 0.5)
    multiplier = Decimal.from_float(refund_percentage / 100.0)

    case Money.mult(original_amount, multiplier) do
      {:ok, refund_amount} -> refund_amount
    end
  end

  @doc """
  Cancels a booking and processes the refund according to the refund policy.

  If the refund is 100% (full refund), it processes immediately.
  If the refund is less than 100% (partial refund), it creates a pending refund
  that requires admin review.

  ## Parameters
  - `booking`: The booking to cancel
  - `cancellation_date`: Optional cancellation date (defaults to today)
  - `reason`: Optional cancellation reason

  ## Returns
  - `{:ok, booking, refund_amount, refund_transaction_or_pending_refund}` if successful
  - `{:error, reason}` if cancellation fails

  ## Examples
      iex> cancel_booking(booking, ~D[2025-11-10], "User requested cancellation")
      {:ok, %Booking{}, %Money{}, %LedgerTransaction{}}
  """
  def cancel_booking(
        booking,
        cancellation_date \\ Date.utc_today(),
        reason \\ nil
      ) do
    alias Ysc.Bookings.{BookingLocker, PendingRefund}

    # First, always cancel the booking and free up inventory
    cancel_result =
      case booking.status do
        :hold ->
          BookingLocker.release_hold(booking.id)

        :complete ->
          BookingLocker.cancel_complete_booking(booking.id)

        _ ->
          # Booking already canceled or in invalid state
          {:error, :invalid_status}
      end

    case cancel_result do
      {:ok, canceled_booking} ->
        # Get the original payment for this booking first
        case get_booking_payment(canceled_booking) do
          {:ok, payment} ->
            # Calculate refund amount
            case calculate_refund(canceled_booking, cancellation_date) do
              {:ok, refund_amount, applied_rule} ->
                # If refund_amount is nil, it means full refund (no policy)
                # In that case, use the full payment amount
                actual_refund_amount =
                  if is_nil(refund_amount) do
                    payment.amount
                  else
                    refund_amount
                  end

                # Process refund if amount > 0
                if actual_refund_amount && Money.positive?(actual_refund_amount) do
                  # Only process refund immediately if NO policy rule was applied (full refund outside policy)
                  # If ANY policy rule applies (even if it results in 100% refund), create pending refund for admin review
                  if is_nil(applied_rule) do
                    # No policy rule applied - full refund, process immediately
                    refund_reason =
                      "Booking cancellation: #{reason || "No reason provided"}. Full refund (no policy applied)."

                    # Get the payment intent ID from the payment
                    payment_intent_id = payment.external_payment_id

                    if payment_intent_id && payment.external_provider == :stripe do
                      # Convert refund amount to cents for Stripe
                      refund_amount_cents =
                        Ysc.MoneyHelper.money_to_cents(actual_refund_amount)

                      if refund_amount_cents < 1 do
                        {:error,
                         {:refund_failed,
                          "Refund amount must be at least $0.01 (Stripe minimum)."}}
                      else
                        case create_stripe_refund(
                               payment_intent_id,
                               refund_amount_cents,
                               refund_reason
                             ) do
                          {:ok, stripe_refund} ->
                            # Refund created in Stripe - ledger will be updated via webhook
                            # Send cancellation confirmation to user
                            send_booking_cancellation_confirmation_email(
                              canceled_booking,
                              payment,
                              actual_refund_amount,
                              false,
                              reason
                            )

                            # Send cancellation notifications to cabin master and treasurer
                            send_booking_cancellation_notifications(
                              canceled_booking,
                              payment,
                              nil,
                              reason
                            )

                            # Return the refund ID so we can track it
                            {:ok, canceled_booking, actual_refund_amount,
                             stripe_refund.id}

                          {:error, reason} ->
                            {:error, {:refund_failed, reason}}
                        end
                      end
                    else
                      {:error,
                       {:refund_failed,
                        "Payment does not have a valid Stripe payment intent ID"}}
                    end
                  else
                    # Policy rule applied (partial refund, full refund via policy, or $0) - create pending refund for admin review
                    applied_rule_days = applied_rule.days_before_checkin

                    applied_rule_percentage = applied_rule.refund_percentage

                    pending_refund_attrs = %{
                      booking_id: canceled_booking.id,
                      payment_id: payment.id,
                      policy_refund_amount: actual_refund_amount,
                      status: :pending,
                      cancellation_reason: reason,
                      applied_rule_days_before_checkin: applied_rule_days,
                      applied_rule_refund_percentage: applied_rule_percentage
                    }

                    case %PendingRefund{}
                         |> PendingRefund.changeset(pending_refund_attrs)
                         |> Repo.insert() do
                      {:ok, pending_refund} ->
                        # Send pending refund email (this also serves as cancellation confirmation)
                        send_booking_refund_pending_email(
                          pending_refund,
                          canceled_booking,
                          payment
                        )

                        # Send cancellation notifications to cabin master and treasurer
                        send_booking_cancellation_notifications(
                          canceled_booking,
                          payment,
                          pending_refund,
                          reason
                        )

                        {:ok, canceled_booking, actual_refund_amount,
                         pending_refund}

                      {:error, changeset} ->
                        {:error, {:pending_refund_failed, changeset}}
                    end
                  end
                else
                  # No refund (0% or nil) - check if a policy rule was applied
                  if applied_rule do
                    # Policy rule applied resulting in $0 refund - create pending refund for admin review
                    pending_refund_attrs = %{
                      booking_id: canceled_booking.id,
                      payment_id: payment.id,
                      policy_refund_amount: Money.new(0, :USD),
                      status: :pending,
                      cancellation_reason: reason,
                      applied_rule_days_before_checkin:
                        applied_rule.days_before_checkin,
                      applied_rule_refund_percentage:
                        applied_rule.refund_percentage
                    }

                    case %PendingRefund{}
                         |> PendingRefund.changeset(pending_refund_attrs)
                         |> Repo.insert() do
                      {:ok, pending_refund} ->
                        # Send pending refund email (this also serves as cancellation confirmation)
                        send_booking_refund_pending_email(
                          pending_refund,
                          canceled_booking,
                          payment
                        )

                        # Send cancellation notifications to cabin master and treasurer
                        send_booking_cancellation_notifications(
                          canceled_booking,
                          payment,
                          pending_refund,
                          reason
                        )

                        {:ok, canceled_booking, Money.new(0, :USD),
                         pending_refund}

                      {:error, changeset} ->
                        {:error, {:pending_refund_failed, changeset}}
                    end
                  else
                    # No refund and no policy rule applied
                    # Send cancellation confirmation to user
                    send_booking_cancellation_confirmation_email(
                      canceled_booking,
                      payment,
                      Money.new(0, :USD),
                      false,
                      reason
                    )

                    # Send cancellation notifications to cabin master and treasurer
                    send_booking_cancellation_notifications(
                      canceled_booking,
                      payment,
                      nil,
                      reason
                    )

                    {:ok, canceled_booking, Money.new(0, :USD), nil}
                  end
                end

              {:error, reason} ->
                {:error, {:calculation_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:payment_not_found, reason}}
        end

      {:error, reason} ->
        {:error, {:cancellation_failed, reason}}
    end
  end

  @doc """
  Gets the payment for a booking by looking up ledger entries.

  Returns `{:ok, payment}` if found, or `{:error, :payment_not_found}` if not found.
  """
  def get_booking_payment(booking) do
    import Ecto.Query

    # Find the payment via ledger entries
    # Payment entries are debit entries to stripe_account
    entry =
      from(e in Ysc.Ledgers.LedgerEntry,
        join: a in Ysc.Ledgers.LedgerAccount,
        on: e.account_id == a.id,
        where: e.related_entity_type == ^:booking,
        where: e.related_entity_id == ^booking.id,
        where: e.debit_credit == "debit",
        where: a.name == "stripe_account",
        preload: [payment: :payment_method],
        order_by: [desc: e.inserted_at],
        limit: 1
      )
      |> Repo.one()

    if entry && entry.payment do
      {:ok, entry.payment}
    else
      {:error, :payment_not_found}
    end
  end

  @doc """
  Gets daily availability information for Clear Lake property.

  Returns a map where keys are dates (as Date structs) and values are maps with:
  - `day_bookings_count`: Number of guests already booked for day bookings
  - `spots_available`: Number of spots remaining vs 12 (informational, not used as a cap)
  - `has_buyout`: Whether there's a buyout booking on this date
  - `is_blacked_out`: Whether the date is in a blackout period
  - `can_book_day`: Whether day bookings are possible (not blacked out and no buyout)
  - `can_book_buyout`: Whether buyout is possible (not blacked out and no day bookings)

  ## Parameters
  - `start_date`: Start date of the range to check
  - `end_date`: End date of the range to check

  ## Returns
  A map of dates to availability information.
  """
  def get_clear_lake_daily_availability(start_date, end_date) do
    Ysc.Bookings.AvailabilityCache.get_clear_lake_daily_availability(
      start_date,
      end_date
    )
  end

  def get_clear_lake_daily_availability_from_db(start_date, end_date) do
    date_range = Date.range(start_date, end_date) |> Enum.to_list()

    # Get all bookings that overlap with the date range OR have checkout/checkin dates in the range
    # We need to expand the query to include bookings that checkout on start_date or checkin on end_date
    # to properly detect changeover days
    # Only preload what we need - we don't need user data for availability calculation
    # Only count :complete bookings here - :hold bookings are tracked via capacity_held in PropertyInventory
    # This prevents double-counting since capacity_held is the source of truth for held capacity
    # Expand the date range by 1 day on each side to capture all relevant checkouts and checkins
    expanded_start = Date.add(start_date, -1)
    expanded_end = Date.add(end_date, 1)

    all_bookings =
      list_bookings(:clear_lake, expanded_start, expanded_end,
        preload: [:rooms]
      )

    bookings =
      Enum.filter(all_bookings, fn booking ->
        booking.status == :complete
      end)

    # Get all blackouts that overlap with the date range
    blackouts = get_overlapping_blackouts(:clear_lake, start_date, end_date)

    # Create a set of blacked out dates
    # Use MapSet.union to efficiently combine date ranges without creating intermediate lists
    blacked_out_dates =
      blackouts
      |> Enum.reduce(MapSet.new(), fn blackout, acc ->
        blackout_dates =
          Date.range(blackout.start_date, blackout.end_date)
          |> Enum.reduce(MapSet.new(), fn date, set -> MapSet.put(set, date) end)

        MapSet.union(acc, blackout_dates)
      end)

    # Initialize availability map
    availability =
      date_range
      |> Enum.map(fn date ->
        {date,
         %{
           day_bookings_count: 0,
           has_buyout: false,
           has_checkout: false,
           has_checkin: false
         }}
      end)
      |> Map.new()

    # Process bookings to count guests per day and check for buyouts
    # Note: Exclude checkout_date from the range since checkout is at 11:00 AM
    # and check-in is at 15:00 (3 PM), allowing same-day turnarounds
    availability =
      bookings
      |> Enum.reduce(availability, fn booking, acc ->
        # Track checkout and checkin dates for changeover day detection
        # Only track if the date is in the availability map (within the displayed range)
        acc =
          if Map.has_key?(acc, booking.checkout_date) do
            Map.update!(acc, booking.checkout_date, fn info ->
              %{info | has_checkout: true}
            end)
          else
            acc
          end

        acc =
          if Map.has_key?(acc, booking.checkin_date) do
            Map.update!(acc, booking.checkin_date, fn info ->
              %{info | has_checkin: true}
            end)
          else
            acc
          end

        # Only count dates from checkin_date to checkout_date - 1
        # The checkout_date itself is not occupied since guests leave at 11 AM
        # Use Date.range directly without converting to list for better performance
        if Date.compare(booking.checkout_date, booking.checkin_date) == :gt do
          # Exclude checkout_date - only count nights actually stayed
          booking_date_range =
            Date.range(
              booking.checkin_date,
              Date.add(booking.checkout_date, -1)
            )

          booking_date_range
          |> Enum.reduce(acc, fn date, date_acc ->
            if Map.has_key?(date_acc, date) do
              case booking.booking_mode do
                :day ->
                  # Only count :complete bookings here
                  # :hold bookings are tracked separately via capacity_held in PropertyInventory
                  current_count = date_acc[date].day_bookings_count

                  Map.put(date_acc, date, %{
                    date_acc[date]
                    | day_bookings_count: current_count + booking.guests_count
                  })

                :buyout ->
                  # Only count :complete buyout bookings here
                  # :hold buyout bookings are tracked via buyout_held in PropertyInventory
                  Map.put(date_acc, date, %{date_acc[date] | has_buyout: true})

                _ ->
                  date_acc
              end
            else
              date_acc
            end
          end)
        else
          # Edge case: same day check-in/check-out (shouldn't happen, but handle gracefully)
          acc
        end
      end)

    # Get capacity_held and buyout_held from PropertyInventory for each date to account for hold bookings
    # This ensures we account for :hold bookings that haven't been confirmed yet
    held_inventory_by_date =
      from(pi in PropertyInventory,
        where: pi.property == :clear_lake,
        where: pi.day >= ^start_date and pi.day <= ^end_date,
        select:
          {pi.day,
           %{capacity_held: pi.capacity_held, buyout_held: pi.buyout_held}}
      )
      |> Repo.all()
      |> Map.new()

    # Finalize availability information for each date
    availability
    |> Enum.map(fn {date, info} ->
      is_blacked_out = MapSet.member?(blacked_out_dates, date)

      # Account for both confirmed bookings and held capacity from PropertyInventory
      # This ensures we count :hold bookings that may not be in the bookings query
      held_inventory =
        Map.get(held_inventory_by_date, date, %{
          capacity_held: 0,
          buyout_held: false
        })

      capacity_held = held_inventory.capacity_held
      buyout_held = held_inventory.buyout_held

      # Total occupied includes both confirmed bookings and held capacity
      total_occupied = info.day_bookings_count + capacity_held
      spots_available = max(0, 12 - total_occupied)

      # Day bookings can be made if:
      # - Not blacked out
      # - No buyout (confirmed or held)
      # There is no cap on the number of guests for a la carte bookings
      can_book_day =
        not is_blacked_out and not info.has_buyout and
          not buyout_held

      # Buyout can only be booked if:
      # - Not blacked out
      # - No buyout already on that day (confirmed or held)
      # - No day bookings (shared/per person) on that day (day_bookings_count must be 0)
      # - No held capacity (capacity_held > 0 means there are :hold day bookings)
      can_book_buyout =
        not is_blacked_out and not info.has_buyout and not buyout_held and
          info.day_bookings_count == 0 and capacity_held == 0

      is_changeover = info.has_checkout && info.has_checkin

      {
        date,
        %{
          day_bookings_count: info.day_bookings_count,
          spots_available: spots_available,
          has_buyout: info.has_buyout,
          is_blacked_out: is_blacked_out,
          can_book_day: can_book_day,
          can_book_buyout: can_book_buyout,
          has_checkout: info.has_checkout,
          has_checkin: info.has_checkin,
          is_changeover_day: is_changeover
        }
      }
    end)
    |> Map.new()
  end

  @doc """
  Gets daily availability information for Tahoe property.

  Returns a map where keys are dates (as Date structs) and values are maps with:
  - `has_room_booking`: Whether there's any room booking on this date
  - `has_buyout`: Whether there's a buyout booking on this date
  - `is_blacked_out`: Whether the date is in a blackout period
  - `can_book_buyout`: Whether buyout is possible (not blacked out and no room bookings)
  - `can_book_room`: Whether room bookings are possible (not blacked out and no buyout)

  ## Parameters
  - `start_date`: Start date of the range to check
  - `end_date`: End date of the range to check

  ## Returns
  A map of dates to availability information.
  """
  def get_tahoe_daily_availability(start_date, end_date) do
    date_range = Date.range(start_date, end_date) |> Enum.to_list()

    # Get all bookings that overlap with the date range
    # Expand the date range by 1 day on each side to capture all relevant checkouts and checkins
    expanded_start = Date.add(start_date, -1)
    expanded_end = Date.add(end_date, 1)

    all_bookings =
      list_bookings(:tahoe, expanded_start, expanded_end, preload: [:rooms])

    bookings =
      Enum.filter(all_bookings, fn booking ->
        booking.status in [:hold, :complete]
      end)

    # Get all blackouts that overlap with the date range
    # Expand the range to include blackouts that might affect changeover days
    expanded_blackout_start = Date.add(start_date, -1)
    expanded_blackout_end = Date.add(end_date, 1)

    blackouts =
      get_overlapping_blackouts(
        :tahoe,
        expanded_blackout_start,
        expanded_blackout_end
      )

    # Create a set of blacked out dates
    # Blackouts block:
    # - The afternoon (check-in time) of start_date
    # - The morning (checkout time) of end_date
    # - All full days in between
    # The calendar component handles morning/afternoon split based on whether dates are blacked out
    blacked_out_dates =
      blackouts
      |> Enum.reduce(MapSet.new(), fn blackout, acc ->
        # Include all dates from start_date to end_date
        # The calendar will show:
        # - start_date as check-in day (afternoon blocked) if start_date is blacked out
        # - end_date as check-out day (morning blocked) if end_date is blacked out
        # - All dates in between as fully blocked
        blackout_dates =
          Date.range(blackout.start_date, blackout.end_date)
          |> Enum.reduce(MapSet.new(), fn date, set -> MapSet.put(set, date) end)

        MapSet.union(acc, blackout_dates)
      end)

    # Initialize availability map
    availability =
      date_range
      |> Enum.map(fn date ->
        {date, %{has_room_booking: false, has_buyout: false}}
      end)
      |> Map.new()

    # Process bookings to check for room bookings and buyouts
    # Note: Exclude checkout_date from the range since checkout is at 11:00 AM
    # and check-in is at 15:00 (3 PM), allowing same-day turnarounds
    availability =
      bookings
      |> Enum.reduce(availability, fn booking, acc ->
        # Only count dates from checkin_date to checkout_date - 1
        # The checkout_date itself is not occupied since guests leave at 11 AM
        if Date.compare(booking.checkout_date, booking.checkin_date) == :gt do
          # Exclude checkout_date - only count nights actually stayed
          booking_date_range =
            Date.range(
              booking.checkin_date,
              Date.add(booking.checkout_date, -1)
            )

          booking_date_range
          |> Enum.reduce(acc, fn date, date_acc ->
            if Map.has_key?(date_acc, date) do
              case booking.booking_mode do
                :room ->
                  # Any room booking makes buyout unavailable
                  Map.put(date_acc, date, %{
                    date_acc[date]
                    | has_room_booking: true
                  })

                :buyout ->
                  # Buyout makes everything unavailable
                  Map.put(date_acc, date, %{date_acc[date] | has_buyout: true})

                _ ->
                  date_acc
              end
            else
              date_acc
            end
          end)
        else
          # Edge case: same day check-in/check-out (shouldn't happen, but handle gracefully)
          acc
        end
      end)

    # Get buyout_held from PropertyInventory for each date to account for hold bookings
    held_inventory_by_date =
      from(pi in PropertyInventory,
        where: pi.property == :tahoe,
        where: pi.day >= ^start_date and pi.day <= ^end_date,
        select: {pi.day, %{buyout_held: pi.buyout_held}}
      )
      |> Repo.all()
      |> Map.new()

    # Check for held room bookings - these are bookings with :hold status
    # We already have them in the bookings list, so filter and extract dates
    held_room_dates =
      bookings
      |> Enum.filter(fn booking ->
        booking.status == :hold && booking.booking_mode == :room
      end)
      |> Enum.flat_map(fn booking ->
        if Date.compare(booking.checkout_date, booking.checkin_date) == :gt do
          Date.range(booking.checkin_date, Date.add(booking.checkout_date, -1))
          |> Enum.to_list()
        else
          []
        end
      end)
      |> MapSet.new()

    # Finalize availability information for each date
    availability
    |> Enum.map(fn {date, info} ->
      is_blacked_out = MapSet.member?(blacked_out_dates, date)

      # Check for held buyout
      held_inventory =
        Map.get(held_inventory_by_date, date, %{buyout_held: false})

      buyout_held = held_inventory.buyout_held

      # Check if there's a held room booking on this date
      has_held_room_booking = MapSet.member?(held_room_dates, date)

      # Room bookings can be made if:
      # - Not blacked out
      # - No buyout (confirmed or held)
      # - No room bookings don't block other room bookings (they can coexist)
      can_book_room =
        not is_blacked_out and not info.has_buyout and not buyout_held

      # Buyout can only be booked if:
      # - Not blacked out
      # - No buyout already on that day (confirmed or held)
      # - No room bookings (confirmed or held) on that day
      can_book_buyout =
        not is_blacked_out and not info.has_buyout and not buyout_held and
          not info.has_room_booking and not has_held_room_booking

      {
        date,
        %{
          has_room_booking: info.has_room_booking || has_held_room_booking,
          has_buyout: info.has_buyout || buyout_held,
          is_blacked_out: is_blacked_out,
          can_book_room: can_book_room,
          can_book_buyout: can_book_buyout
        }
      }
    end)
    |> Map.new()
  end

  @doc """
  Lists all pending refunds that require admin review.
  """
  def list_pending_refunds do
    import Ecto.Query

    from(pr in PendingRefund,
      where: pr.status == :pending,
      order_by: [asc: pr.inserted_at],
      preload: [:booking, :payment]
    )
    |> Repo.all()
  end

  @doc """
  Returns pending refund counts for the admin dashboard: total and per property.
  """
  def pending_refunds_dashboard_summary do
    counts =
      from(pr in PendingRefund,
        join: b in assoc(pr, :booking),
        where: pr.status == :pending,
        group_by: b.property,
        select: {b.property, count(pr.id)}
      )
      |> Repo.all()
      |> Map.new()

    tahoe = Map.get(counts, :tahoe, 0)
    clear_lake = Map.get(counts, :clear_lake, 0)

    %{
      total: tahoe + clear_lake,
      tahoe: tahoe,
      clear_lake: clear_lake
    }
  end

  @doc """
  Gets a pending refund by ID with all associations preloaded.
  """
  def get_pending_refund!(id) do
    import Ecto.Query

    from(pr in PendingRefund,
      where: pr.id == ^id,
      preload: [:booking, :payment, :reviewed_by]
    )
    |> Repo.one!()
  end

  @doc """
  Approves and processes a pending refund.

  The admin can specify a different refund amount than the policy amount.
  If no admin_refund_amount is provided, the policy_refund_amount is used.

  ## Parameters
  - `pending_refund`: The pending refund to approve
  - `admin_refund_amount`: Optional custom refund amount (defaults to policy amount)
  - `admin_notes`: Optional notes from the admin
  - `reviewed_by`: The admin user approving the refund

  ## Returns
  - `{:ok, pending_refund, stripe_refund_id}` if successful. When the approved
    amount rounds to **zero** cents, Stripe is not called and the third value is
    `nil` (ledger refund records are not created).
  - `{:error, :invalid_refund_amount}` when the approved amount is negative.
  - `{:error, reason}` if processing fails
  """
  def approve_pending_refund(
        pending_refund,
        admin_refund_amount \\ nil,
        admin_notes \\ nil,
        reviewed_by
      ) do
    alias Ysc.MoneyHelper

    pending_refund = Repo.get!(PendingRefund, pending_refund.id)

    # Use admin amount if provided, otherwise use policy amount (rounded to USD cents)
    refund_amount = admin_refund_amount || pending_refund.policy_refund_amount

    refund_amount =
      case Money.round(refund_amount) do
        %Money{} = rounded -> rounded
        {:error, _} -> refund_amount
      end

    refund_reason =
      if admin_notes do
        "Booking cancellation refund (admin approved): #{admin_notes}. Policy amount: #{MoneyHelper.format_money!(pending_refund.policy_refund_amount)}, Refunded amount: #{MoneyHelper.format_money!(refund_amount)}."
      else
        "Booking cancellation refund (admin approved). Policy amount: #{MoneyHelper.format_money!(pending_refund.policy_refund_amount)}, Refunded amount: #{MoneyHelper.format_money!(refund_amount)}."
      end

    # Get the payment to find the payment intent ID
    payment = Repo.get!(Ysc.Ledgers.Payment, pending_refund.payment_id)

    if payment.external_payment_id && payment.external_provider == :stripe do
      refund_amount_cents = Ysc.MoneyHelper.money_to_cents(refund_amount)

      cond do
        refund_amount_cents < 0 ->
          Ysc.Logging.error(
            "Negative pending refund amount rejected",
            pending_refund_id: pending_refund.id,
            payment_id: payment.id,
            refund_amount_cents: refund_amount_cents
          )

          {:error, :invalid_refund_amount}

        refund_amount_cents == 0 ->
          if pending_refund.status != :pending do
            {:error,
             {:refund_failed, "Pending refund is not awaiting approval"}}
          else
            # Policy or admin amount is $0.00 — approve administratively; no Stripe charge-back.
            Ysc.Logging.info(
              "Pending refund approved with no Stripe refund (zero approved amount)",
              pending_refund_id: pending_refund.id,
              payment_id: payment.id
            )

            updated_pending_refund =
              pending_refund
              |> PendingRefund.changeset(%{
                status: :approved,
                admin_refund_amount: refund_amount,
                admin_notes: admin_notes,
                reviewed_by_id: reviewed_by.id,
                reviewed_at: DateTime.utc_now()
              })
              |> Repo.update!()

            {:ok, updated_pending_refund, nil}
          end

        true ->
          approve_pending_refund_with_stripe(
            pending_refund,
            payment,
            refund_amount,
            refund_amount_cents,
            refund_reason,
            admin_notes,
            reviewed_by
          )
      end
    else
      {:error,
       {:refund_failed,
        "Payment does not have a valid Stripe payment intent ID"}}
    end
  end

  defp approve_pending_refund_with_stripe(
         pending_refund,
         payment,
         refund_amount,
         refund_amount_cents,
         refund_reason,
         admin_notes,
         reviewed_by
       ) do
    pending_refund = Repo.get!(PendingRefund, pending_refund.id)

    case pending_refund.status do
      :approved ->
        {:ok, pending_refund,
         latest_stripe_refund_external_id_for_payment(payment.id)}

      :pending ->
        case claim_pending_refund_processing(pending_refund.id) do
          {:claimed, pr} ->
            finalize_stripe_pending_refund_approval(
              pr,
              payment,
              refund_amount,
              refund_amount_cents,
              refund_reason,
              admin_notes,
              reviewed_by
            )

          {:skipped, pr} ->
            case pr.status do
              :approved ->
                {:ok, pr,
                 latest_stripe_refund_external_id_for_payment(payment.id)}

              :processing ->
                finalize_stripe_pending_refund_approval(
                  pr,
                  payment,
                  refund_amount,
                  refund_amount_cents,
                  refund_reason,
                  admin_notes,
                  reviewed_by
                )

              :pending ->
                {:error,
                 {:refund_failed,
                  "Could not claim pending refund for processing"}}

              _ ->
                {:error, {:refund_failed, "Invalid pending refund status"}}
            end
        end

      :processing ->
        finalize_stripe_pending_refund_approval(
          pending_refund,
          payment,
          refund_amount,
          refund_amount_cents,
          refund_reason,
          admin_notes,
          reviewed_by
        )

      _ ->
        {:error, {:refund_failed, "Pending refund is not awaiting approval"}}
    end
  end

  defp claim_pending_refund_processing(pending_refund_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _} =
      from(pr in PendingRefund,
        where: pr.id == ^pending_refund_id and pr.status == :pending
      )
      |> Repo.update_all(set: [status: :processing, updated_at: now])

    pr = Repo.get!(PendingRefund, pending_refund_id)

    if count == 1 do
      {:claimed, pr}
    else
      {:skipped, pr}
    end
  end

  defp reset_pending_refund_after_stripe_failure(pending_refund_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(pr in PendingRefund,
        where: pr.id == ^pending_refund_id and pr.status == :processing
      ),
      set: [status: :pending, updated_at: now]
    )
  end

  defp finalize_stripe_pending_refund_approval(
         pending_refund,
         payment,
         refund_amount,
         refund_amount_cents,
         refund_reason,
         admin_notes,
         reviewed_by
       ) do
    pending_refund = Repo.get!(PendingRefund, pending_refund.id)

    cond do
      pending_refund.status == :approved ->
        {:ok, pending_refund,
         latest_stripe_refund_external_id_for_payment(payment.id)}

      pending_refund.status != :processing ->
        {:error, {:refund_failed, "Pending refund is not in processing state"}}

      true ->
        idempotency_key = "approve_pending_refund_#{pending_refund.id}"

        case create_stripe_refund(
               payment.external_payment_id,
               refund_amount_cents,
               refund_reason,
               idempotency_key: idempotency_key
             ) do
          {:ok, stripe_refund} ->
            ledger_result =
              Ledgers.process_refund(%{
                payment_id: payment.id,
                refund_amount: refund_amount,
                reason: refund_reason,
                external_refund_id: stripe_refund.id
              })

            changes =
              PendingRefund.changeset(pending_refund, %{
                status: :approved,
                admin_refund_amount: refund_amount,
                admin_notes: admin_notes,
                reviewed_by_id: reviewed_by.id,
                reviewed_at: DateTime.utc_now()
              })

            case Repo.update(changes) do
              {:ok, updated_pending_refund} ->
                log_ledger_result(
                  ledger_result,
                  pending_refund,
                  payment,
                  stripe_refund
                )

                {:ok, updated_pending_refund, stripe_refund.id}

              {:error, _} ->
                reloaded = Repo.get!(PendingRefund, pending_refund.id)

                if reloaded.status == :approved do
                  log_ledger_result(
                    ledger_result,
                    pending_refund,
                    payment,
                    stripe_refund
                  )

                  {:ok, reloaded, stripe_refund.id}
                else
                  {:error,
                   {:refund_failed,
                    "Could not finalize approved pending refund"}}
                end
            end

          {:error, reason} ->
            _ = reset_pending_refund_after_stripe_failure(pending_refund.id)
            {:error, {:refund_failed, reason}}
        end
    end
  end

  defp latest_stripe_refund_external_id_for_payment(payment_id) do
    from(r in Ysc.Ledgers.Refund,
      where: r.payment_id == ^payment_id,
      where: r.external_provider == :stripe,
      where: not is_nil(r.external_refund_id),
      order_by: [desc: r.inserted_at],
      limit: 1,
      select: r.external_refund_id
    )
    |> Repo.one()
  end

  @doc """
  Rejects a pending refund.

  ## Parameters
  - `pending_refund`: The pending refund to reject
  - `admin_notes`: Optional notes explaining why the refund was rejected
  - `reviewed_by`: The admin user rejecting the refund

  ## Returns
  - `{:ok, pending_refund}` if successful
  - `{:error, reason}` if update fails
  """
  def reject_pending_refund(pending_refund, admin_notes \\ nil, reviewed_by) do
    pending_refund
    |> PendingRefund.changeset(%{
      status: :rejected,
      admin_notes: admin_notes,
      reviewed_by_id: reviewed_by.id,
      reviewed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  defp send_booking_refund_pending_email(pending_refund, booking, payment) do
    require Ysc.Logging

    try do
      # Reload associations
      booking =
        Repo.get(Ysc.Bookings.Booking, booking.id) |> Repo.preload(:user)

      payment = Ysc.Ledgers.get_payment_with_associations(payment.id)

      if booking && booking.user && payment do
        # Prepare email data
        email_data =
          YscWeb.Emails.BookingRefundPending.prepare_email_data(
            pending_refund,
            booking,
            payment
          )

        # Generate idempotency key
        idempotency_key = "booking_refund_pending_#{pending_refund.id}"

        # Schedule email
        result =
          YscWeb.Emails.Notifier.schedule_email(
            booking.user.email,
            idempotency_key,
            YscWeb.Emails.BookingRefundPending.get_subject(),
            "booking_refund_pending",
            email_data,
            "",
            booking.user_id,
            Ysc.EmailConfig.booking_reply_to(booking.property)
          )

        case result do
          %Oban.Job{} = job ->
            Ysc.Logging.info(
              "Booking refund pending email scheduled successfully",
              pending_refund_id: pending_refund.id,
              booking_id: booking.id,
              user_id: booking.user_id,
              user_email: booking.user.email,
              job_id: job.id
            )

          {:error, reason} ->
            Ysc.Logging.error("Failed to schedule booking refund pending email",
              pending_refund_id: pending_refund.id,
              booking_id: booking.id,
              user_id: booking.user_id,
              error: reason
            )
        end
      else
        Ysc.Logging.warning(
          "Skipping booking refund pending email - missing associations",
          pending_refund_id: pending_refund.id,
          booking_id: booking && booking.id,
          payment_id: payment && payment.id
        )
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send booking refund pending email",
          pending_refund_id: pending_refund.id,
          booking_id: booking && booking.id,
          error: inspect(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  defp send_booking_cancellation_notifications(
         booking,
         payment,
         pending_refund,
         reason
       ) do
    require Ysc.Logging
    import Ecto.Query

    try do
      # Reload booking with user association
      booking =
        Repo.get(Ysc.Bookings.Booking, booking.id) |> Repo.preload(:user)

      if booking && booking.user do
        # Get cabin master for the property
        cabin_master_position =
          case booking.property do
            :tahoe -> "tahoe_cabin_master"
            :clear_lake -> "clear_lake_cabin_master"
            _ -> nil
          end

        cabin_master =
          if cabin_master_position do
            from(u in Ysc.Accounts.User,
              where:
                u.board_position == ^cabin_master_position and
                  u.state == :active,
              limit: 1
            )
            |> Repo.one()
          else
            nil
          end

        # Get treasurer
        treasurer =
          from(u in Ysc.Accounts.User,
            where: u.board_position == "treasurer" and u.state == :active,
            limit: 1
          )
          |> Repo.one()

        # Send email to cabin master if found
        if cabin_master && cabin_master.email do
          send_cabin_master_cancellation_email(
            cabin_master,
            booking,
            payment,
            pending_refund,
            reason
          )
        else
          Ysc.Logging.warning("No cabin master found for property",
            property: booking.property,
            booking_id: booking.id
          )
        end

        # Send email to treasurer if found
        if treasurer && treasurer.email do
          send_treasurer_cancellation_email(
            treasurer,
            booking,
            payment,
            pending_refund,
            reason
          )
        else
          Ysc.Logging.warning("No treasurer found",
            booking_id: booking.id
          )
        end
      else
        Ysc.Logging.warning(
          "Skipping cancellation notification emails - missing booking or user",
          booking_id: booking && booking.id
        )
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send cancellation notification emails",
          booking_id: booking && booking.id,
          error: inspect(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  defp send_cabin_master_cancellation_email(
         cabin_master,
         booking,
         payment,
         pending_refund,
         reason
       ) do
    require Ysc.Logging

    try do
      # Prepare email data
      email_data =
        YscWeb.Emails.BookingCancellationCabinMasterNotification.prepare_email_data(
          booking,
          payment,
          pending_refund,
          reason
        )

      # Determine if review is required
      requires_review = not is_nil(pending_refund)

      # Generate idempotency key
      idempotency_key =
        "booking_cancellation_cabin_master_#{booking.id}_#{DateTime.utc_now() |> DateTime.to_unix()}"

      # Schedule email
      result =
        YscWeb.Emails.Notifier.schedule_email(
          cabin_master.email,
          idempotency_key,
          YscWeb.Emails.BookingCancellationCabinMasterNotification.get_subject(
            requires_review
          ),
          "booking_cancellation_cabin_master_notification",
          email_data,
          "",
          cabin_master.id,
          Ysc.EmailConfig.booking_reply_to(booking.property)
        )

      case result do
        %Oban.Job{} = job ->
          Ysc.Logging.info(
            "Cabin master cancellation email scheduled successfully",
            booking_id: booking.id,
            cabin_master_id: cabin_master.id,
            cabin_master_email: cabin_master.email,
            job_id: job.id
          )

        {:error, reason} ->
          Ysc.Logging.error(
            "Failed to schedule cabin master cancellation email",
            booking_id: booking.id,
            cabin_master_id: cabin_master.id,
            error: reason
          )
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send cabin master cancellation email",
          booking_id: booking.id,
          cabin_master_id: cabin_master.id,
          error: inspect(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  defp send_treasurer_cancellation_email(
         treasurer,
         booking,
         payment,
         pending_refund,
         reason
       ) do
    require Ysc.Logging

    try do
      # Prepare email data
      email_data =
        YscWeb.Emails.BookingCancellationTreasurerNotification.prepare_email_data(
          booking,
          payment,
          pending_refund,
          reason
        )

      # Determine if review is required
      requires_review = not is_nil(pending_refund)

      # Generate idempotency key
      idempotency_key =
        "booking_cancellation_treasurer_#{booking.id}_#{DateTime.utc_now() |> DateTime.to_unix()}"

      # Schedule email
      result =
        YscWeb.Emails.Notifier.schedule_email(
          treasurer.email,
          idempotency_key,
          YscWeb.Emails.BookingCancellationTreasurerNotification.get_subject(
            requires_review
          ),
          "booking_cancellation_treasurer_notification",
          email_data,
          "",
          treasurer.id,
          Ysc.EmailConfig.booking_reply_to(booking.property)
        )

      case result do
        %Oban.Job{} = job ->
          Ysc.Logging.info(
            "Treasurer cancellation email scheduled successfully",
            booking_id: booking.id,
            treasurer_id: treasurer.id,
            treasurer_email: treasurer.email,
            job_id: job.id
          )

        {:error, reason} ->
          Ysc.Logging.error("Failed to schedule treasurer cancellation email",
            booking_id: booking.id,
            treasurer_id: treasurer.id,
            error: reason
          )
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send treasurer cancellation email",
          booking_id: booking.id,
          treasurer_id: treasurer.id,
          error: inspect(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  defp send_booking_cancellation_confirmation_email(
         booking,
         payment,
         refund_amount,
         is_pending_refund,
         reason
       ) do
    require Ysc.Logging

    try do
      # Reload booking with user association
      booking =
        Repo.get(Ysc.Bookings.Booking, booking.id) |> Repo.preload(:user)

      if booking && booking.user && booking.user.email do
        # Prepare email data
        email_data =
          YscWeb.Emails.BookingCancellationConfirmation.prepare_email_data(
            booking,
            payment,
            refund_amount,
            is_pending_refund,
            reason
          )

        # Generate idempotency key
        idempotency_key =
          "booking_cancellation_confirmation_#{booking.id}_#{DateTime.utc_now() |> DateTime.to_unix()}"

        # Schedule email
        result =
          YscWeb.Emails.Notifier.schedule_email(
            booking.user.email,
            idempotency_key,
            YscWeb.Emails.BookingCancellationConfirmation.get_subject(),
            "booking_cancellation_confirmation",
            email_data,
            "",
            booking.user_id,
            Ysc.EmailConfig.booking_reply_to(booking.property)
          )

        case result do
          %Oban.Job{} = job ->
            Ysc.Logging.info(
              "Booking cancellation confirmation email scheduled successfully",
              booking_id: booking.id,
              user_id: booking.user_id,
              user_email: booking.user.email,
              job_id: job.id
            )

          {:error, reason} ->
            Ysc.Logging.error(
              "Failed to schedule booking cancellation confirmation email",
              booking_id: booking.id,
              user_id: booking.user_id,
              error: reason
            )
        end
      else
        Ysc.Logging.warning(
          "Skipping booking cancellation confirmation email - missing booking or user",
          booking_id: booking && booking.id
        )
      end
    rescue
      error ->
        Ysc.Logging.error(
          "Failed to send booking cancellation confirmation email",
          booking_id: booking && booking.id,
          error: inspect(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  ## Private Functions

  @doc """
  Creates a refund in Stripe for a payment intent (public version for admin use).

  ## Parameters
  - `payment_intent_id`: The Stripe payment intent ID
  - `amount_cents`: The refund amount in cents
  - `reason`: Reason for the refund

  ## Returns
  - `{:ok, %Stripe.Refund{}}` on success
  - `{:error, reason}` on failure
  """
  def create_stripe_refund_for_admin(payment_intent_id, amount_cents, reason) do
    create_stripe_refund(payment_intent_id, amount_cents, reason)
  end

  # Creates a refund in Stripe for a payment intent.
  #
  # ## Parameters
  # - `payment_intent_id`: The Stripe payment intent ID
  # - `amount_cents`: The refund amount in cents
  # - `reason`: Reason for the refund
  #
  # ## Returns
  # - `{:ok, %Stripe.Refund{}}` on success
  # - `{:error, reason}` on failure
  defp create_stripe_refund(payment_intent_id, amount_cents, reason, opts \\ []) do
    require Ysc.Logging

    # First, retrieve the payment intent to get the charge ID
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{
           expand: ["latest_charge"]
         }) do
      {:ok, payment_intent} ->
        charge_id = PaymentIntentHelpers.charge_id(payment_intent)

        if charge_id do
          # Extract metadata from payment intent for refund metadata
          user_id = payment_intent.metadata["user_id"]

          booking_id =
            payment_intent.metadata["booking_id"] ||
              payment_intent.metadata["ticket_order_id"]

          # Create refund using the charge ID
          refund_params = %{
            charge: charge_id,
            amount: amount_cents,
            reason: "requested_by_customer",
            metadata: %{
              reason: reason,
              payment_intent_id: payment_intent_id,
              user_id: user_id,
              booking_id: booking_id
            }
          }

          handle_stripe_refund_creation(
            refund_params,
            payment_intent_id,
            amount_cents,
            opts
          )
        else
          Ysc.Logging.error("No charge found in payment intent",
            payment_intent_id: payment_intent_id
          )

          {:error, "No charge found for payment intent"}
        end

      {:error, %Stripe.Error{} = error} ->
        Ysc.Logging.warning("Failed to retrieve payment intent for refund",
          payment_intent_id: payment_intent_id,
          error: error.message
        )

        {:error, "Failed to retrieve payment intent: #{error.message}"}

      {:error, reason} ->
        Ysc.Logging.warning("Failed to retrieve payment intent for refund",
          payment_intent_id: payment_intent_id,
          error: inspect(reason)
        )

        {:error, "Failed to retrieve payment intent"}
    end
  end

  defp room_available?(room_id, available_room_ids_binary) do
    case Ecto.ULID.dump(room_id) do
      {:ok, binary} -> MapSet.member?(available_room_ids_binary, binary)
      _ -> false
    end
  end

  defp convert_room_id_to_binary(room_id) do
    case Ecto.ULID.dump(room_id) do
      {:ok, binary} -> binary
      _ -> room_id
    end
  end

  defp add_pricing_rule_amount(acc, amount, new_price_acc) do
    case Money.add(acc, amount) do
      {:ok, new_total} -> {new_total, new_price_acc}
      {:error, _} -> {acc, new_price_acc}
    end
  end

  defp log_ledger_result(ledger_result, pending_refund, payment, stripe_refund) do
    case ledger_result do
      {:ok, _} ->
        Ysc.Logging.info("Refund processed successfully in ledger",
          pending_refund_id: pending_refund.id,
          payment_id: payment.id,
          stripe_refund_id: stripe_refund.id
        )

      {:error, {:already_processed, _, _}} ->
        # Refund was already processed (likely by webhook) - this is fine
        Ysc.Logging.info("Refund already processed in ledger (idempotency)",
          pending_refund_id: pending_refund.id,
          payment_id: payment.id,
          stripe_refund_id: stripe_refund.id
        )

      {:error, reason} ->
        # Log error but don't fail - refund was created in Stripe
        Ysc.Logging.warning(
          "Failed to process refund in ledger (refund created in Stripe)",
          pending_refund_id: pending_refund.id,
          payment_id: payment.id,
          stripe_refund_id: stripe_refund.id,
          error: inspect(reason)
        )
    end
  end

  @dialyzer {:nowarn_function, handle_stripe_refund_creation: 4}
  defp handle_stripe_refund_creation(
         refund_params,
         payment_intent_id,
         amount_cents,
         opts
       ) do
    idempotency_key = Keyword.get(opts, :idempotency_key)

    if Ysc.Env.test?() do
      refund = %Stripe.Refund{
        id: "re_test_#{idempotency_key || payment_intent_id}"
      }

      Ysc.Logging.info("Stripe refund created successfully (test stub)",
        refund_id: refund.id,
        payment_intent_id: payment_intent_id,
        amount_cents: amount_cents
      )

      {:ok, refund}
    else
      stripe_opts =
        case idempotency_key do
          nil -> []
          key -> [idempotency_key: key]
        end

      case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             Stripe.Refund.create(refund_params, stripe_opts)
           end) do
        {:ok, refund} ->
          Ysc.Logging.info("Stripe refund created successfully",
            refund_id: refund.id,
            payment_intent_id: payment_intent_id,
            amount_cents: amount_cents
          )

          {:ok, refund}

        {:error, %Stripe.Error{} = error} ->
          Ysc.Logging.warning("Stripe refund creation failed",
            payment_intent_id: payment_intent_id,
            error: error.message
          )

          {:error, error.message}

        {:error, reason} ->
          Ysc.Logging.warning("Stripe refund creation failed",
            payment_intent_id: payment_intent_id,
            error: inspect(reason)
          )

          {:error, "Failed to create refund in Stripe"}
      end
    end
  end

  @doc false
  def ci_query_explain_query do
    from(b in Booking,
      preload: [:user, rooms: :room_category, check_ins: :check_in_vehicles],
      limit: 50
    )
  end

  @doc false
  def ci_query_explain_conflicting_bookings_query do
    conflicting_bookings_query(
      :tahoe,
      Ysc.Ci.QueryExplain.Fixtures.today(),
      Date.add(Ysc.Ci.QueryExplain.Fixtures.today(), 3)
    )
  end
end

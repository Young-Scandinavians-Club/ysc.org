defmodule Ysc.Accounts.MembershipCache do
  @moduledoc """
  In-memory cache for user membership data to improve performance.

  Caches membership status and membership type per user with a short TTL (5 minutes).
  This reduces database queries when users interact with the UI.
  """

  import Ecto.Query, warn: false
  require Ysc.Logging
  alias Ysc.Accounts
  alias Ysc.Accounts.User
  alias Ysc.Customers
  alias Ysc.Repo
  alias Ysc.Subscriptions

  @cache_name :ysc_cache
  @cache_prefix "membership:"
  # Distinguishes a stored `nil` membership from a Cachex miss (`{:ok, nil}`).
  @cached_tag :cached
  # 5 minutes in milliseconds
  @default_ttl 5 * 60 * 1000

  @doc """
  Gets the active membership for a user from cache or fetches from database and caches it.

  Returns the membership struct (lifetime map or subscription) or nil.
  """
  def get_active_membership(user) when is_nil(user), do: nil

  def get_active_membership(user) do
    get_active_membership(user, validate: true)
  end

  @doc """
  Like `get_active_membership/1`, with optional `:validate` (default `true`).

  When `validate: true`, cache hits are checked with `Subscriptions.valid?/1`
  against the cached struct (status and period dates) so every authenticated
  page load does not re-fetch the subscription row. Mutations invalidate this
  cache; TTL covers missed invalidations.

  When `validate: false`, returns cached membership without that check. Pair
  with `batch_validate_subscription_ids/1` for hot paths that load many users
  at once.
  """
  def get_active_membership(user, opts) when is_list(opts) do
    validate? = Keyword.get(opts, :validate, true)
    cache_key = build_cache_key(user.id, "active")

    case read_wrapped(cache_key) do
      :miss ->
        membership = get_active_membership_db(user)
        cache_with_ttl(cache_key, membership)
        membership

      {:hit, membership} ->
        if !validate? or membership_valid?(membership) do
          membership
        else
          invalidate_user(user.id)
          membership = get_active_membership_db(user)
          cache_with_ttl(cache_key, membership)
          membership
        end
    end
  end

  @doc """
  True when `Cachex.get/2` for the active-membership key is a real hit.

  Cachex returns `{:ok, nil}` for both a missing key and a stored `nil`, so
  entries are wrapped as `{:cached, value}`. Session auth uses this to skip
  subscription preloads for members *and* non-members.
  """
  def active_membership_cache_hit?({:ok, {@cached_tag, _value}}), do: true
  def active_membership_cache_hit?({:ok, nil}), do: false
  def active_membership_cache_hit?({:ok, _legacy}), do: true
  def active_membership_cache_hit?(_), do: false

  @doc """
  Gets the membership plan type for a user from cache or fetches from database and caches it.

  Returns the plan ID as an atom (`:lifetime`, `:single`, `:family`, etc.) or `nil`.
  """
  def get_membership_plan_type(user) when is_nil(user), do: nil

  def get_membership_plan_type(user) do
    cache_key = build_cache_key(user.id, "plan_type")

    case read_wrapped(cache_key) do
      :miss ->
        membership = get_active_membership(user)
        plan_type = get_membership_plan_type_from_membership(membership)
        cache_with_ttl(cache_key, plan_type)
        plan_type

      {:hit, plan_type} ->
        plan_type
    end
  end

  @doc """
  Gets both membership status and plan type for a user from cache.

  Returns a tuple `{membership, plan_type}` where:
  - `membership` is the active membership struct or nil
  - `plan_type` is the plan type atom or nil
  """
  def get_membership_data(user) when is_nil(user), do: {nil, nil}

  def get_membership_data(user) do
    membership = get_active_membership(user)
    plan_type = get_membership_plan_type_from_membership(membership)
    {membership, plan_type}
  end

  @doc """
  Returns `{membership, plan_type}` tuples keyed by user id.

  Cache misses are loaded in one subscriptions query (plus a preload of
  items) instead of one `Customers.subscriptions/1` per user. Cached
  subscriptions are then re-validated in a single query.
  """
  def batch_membership_data_for_users(users) when is_list(users) do
    lookups =
      Enum.map(users, fn user ->
        {user, read_wrapped(build_cache_key(user.id, "active"))}
      end)

    uncached_users =
      Enum.flat_map(lookups, fn
        {user, :miss} -> [user]
        _ -> []
      end)

    fetched_by_id = fetch_and_cache_memberships(uncached_users)

    memberships =
      Enum.map(lookups, fn
        {user, {:hit, membership}} -> {user.id, membership}
        {user, :miss} -> {user.id, Map.get(fetched_by_id, user.id)}
      end)

    subscription_ids =
      memberships
      |> Enum.flat_map(fn
        {_, %Subscriptions.Subscription{id: id}} -> [id]
        _ -> []
      end)
      |> Enum.uniq()

    valid_subscription_ids = batch_validate_subscription_ids(subscription_ids)

    memberships
    |> Enum.map(fn {user_id, membership} ->
      user = Enum.find(users, &(&1.id == user_id))

      membership =
        case membership do
          %Subscriptions.Subscription{id: id} = sub ->
            if MapSet.member?(valid_subscription_ids, id) do
              sub
            else
              invalidate_user(user_id)
              get_active_membership(user)
            end

          other ->
            other
        end

      {user_id,
       {membership, get_membership_plan_type_from_membership(membership)}}
    end)
    |> Map.new()
  end

  @doc false
  def batch_validate_subscription_ids(subscription_ids)
      when subscription_ids == [],
      do: MapSet.new()

  def batch_validate_subscription_ids(subscription_ids) do
    Subscriptions.Subscription
    |> where([s], s.id in ^subscription_ids)
    |> Repo.all()
    |> Enum.filter(&Subscriptions.valid?/1)
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  @doc false
  def ci_query_explain_query do
    ids = [Ysc.Ci.QueryExplain.Fixtures.ulid()]

    from(s in Subscriptions.Subscription,
      where: s.user_id in ^ids,
      preload: [:subscription_items]
    )
  end

  @doc false
  def ci_query_explain_primary_users_query do
    ids = [Ysc.Ci.QueryExplain.Fixtures.ulid()]
    from(u in User, where: u.id in ^ids)
  end

  @doc """
  Invalidates the membership cache for a specific user.

  This should be called when a user's membership changes (subscription updated, lifetime awarded, etc.).
  """
  def invalidate_user(user_id) when is_binary(user_id) or is_integer(user_id) do
    active_key = build_cache_key(user_id, "active")
    plan_type_key = build_cache_key(user_id, "plan_type")

    Cachex.del(@cache_name, active_key)
    Cachex.del(@cache_name, plan_type_key)

    Ysc.Logging.debug("Membership cache invalidated for user", user_id: user_id)
    :ok
  end

  def invalidate_user(%{id: user_id}), do: invalidate_user(user_id)
  def invalidate_user(_), do: :ok

  @doc """
  Invalidates all membership caches.

  Use sparingly - prefer `invalidate_user/1` when possible.
  """
  def invalidate_all do
    case Cachex.keys(@cache_name) do
      {:ok, keys} ->
        keys
        |> Enum.filter(&String.starts_with?(&1, @cache_prefix))
        |> Enum.each(&Cachex.del(@cache_name, &1))

        Ysc.Logging.debug("All membership caches invalidated")
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  # Private functions

  defp build_cache_key(user_id, suffix) do
    "#{@cache_prefix}#{user_id}:#{suffix}"
  end

  defp cache_with_ttl(key, value) do
    ttl_ms = get_ttl()
    Cachex.put(@cache_name, key, {@cached_tag, value}, expire: ttl_ms)
  end

  defp read_wrapped(cache_key) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, {@cached_tag, value}} -> {:hit, value}
      {:ok, nil} -> :miss
      {:ok, value} -> {:hit, value}
      {:error, _reason} -> :miss
    end
  end

  defp get_ttl do
    Application.get_env(:ysc, :membership_cache_ttl_ms, @default_ttl)
  end

  defp fetch_and_cache_memberships([]), do: %{}

  defp fetch_and_cache_memberships(users) do
    memberships_by_id = batch_load_memberships_from_db(users)

    Enum.each(users, fn user ->
      cache_with_ttl(
        build_cache_key(user.id, "active"),
        Map.get(memberships_by_id, user.id)
      )
    end)

    memberships_by_id
  end

  defp batch_load_memberships_from_db(users) do
    users_by_id = Map.new(users, &{&1.id, &1})
    primaries_by_id = load_missing_primary_users(users, users_by_id)

    user_to_check_by_id =
      Map.new(users, fn user ->
        {user.id,
         user_to_check_for_membership(user, users_by_id, primaries_by_id)}
      end)

    {lifetime_pairs, subscription_pairs} =
      Enum.split_with(user_to_check_by_id, fn {_orig_id, check} ->
        Accounts.has_lifetime_membership?(check)
      end)

    lifetime_memberships =
      Map.new(lifetime_pairs, fn {orig_id, check} ->
        {orig_id, lifetime_membership(check)}
      end)

    check_ids =
      subscription_pairs
      |> Enum.map(fn {_orig_id, check} -> check.id end)
      |> Enum.uniq()

    subs_by_user_id = load_subscriptions_by_user_id(check_ids)

    subscription_memberships =
      Map.new(subscription_pairs, fn {orig_id, check} ->
        valid =
          subs_by_user_id
          |> Map.get(check.id, [])
          |> Enum.filter(&Subscriptions.valid?/1)

        {orig_id, pick_active_subscription(valid)}
      end)

    Map.merge(lifetime_memberships, subscription_memberships)
  end

  defp user_to_check_for_membership(user, users_by_id, primaries_by_id) do
    if Accounts.sub_account?(user) do
      Map.get(users_by_id, user.primary_user_id) ||
        Map.get(primaries_by_id, user.primary_user_id) ||
        user
    else
      user
    end
  end

  defp load_missing_primary_users(users, users_by_id) do
    missing_ids =
      users
      |> Enum.filter(&Accounts.sub_account?/1)
      |> Enum.map(& &1.primary_user_id)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(users_by_id, &1))

    if missing_ids == [] do
      %{}
    else
      from(u in User, where: u.id in ^missing_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})
    end
  end

  defp load_subscriptions_by_user_id([]), do: %{}

  defp load_subscriptions_by_user_id(user_ids) do
    from(s in Subscriptions.Subscription,
      where: s.user_id in ^user_ids,
      preload: [:subscription_items]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.user_id)
  end

  defp pick_active_subscription([]), do: nil
  defp pick_active_subscription([single]), do: single

  defp pick_active_subscription(multiple),
    do: get_most_expensive_subscription(multiple)

  defp lifetime_membership(user) do
    %{
      type: :lifetime,
      awarded_at: user.lifetime_membership_awarded_at,
      user_id: user.id
    }
  end

  # Database lookup functions (duplicated from UserAuth to avoid circular dependency)

  defp get_active_membership_db(user) do
    # For sub-accounts, check the primary user's membership
    user_to_check =
      if Accounts.sub_account?(user) do
        Accounts.get_primary_user(user) || user
      else
        user
      end

    # Check for lifetime membership first (highest priority)
    if Accounts.has_lifetime_membership?(user_to_check) do
      lifetime_membership(user_to_check)
    else
      subscriptions =
        user_to_check
        |> loaded_subscriptions()
        |> Enum.filter(&Subscriptions.valid?/1)

      pick_active_subscription(subscriptions)
    end
  end

  # Uses preloaded subscriptions when present (e.g. admin user lists); otherwise queries.
  defp loaded_subscriptions(%Accounts.User{} = user) do
    case user.subscriptions do
      %Ecto.Association.NotLoaded{} ->
        Customers.subscriptions(user)

      subscriptions when is_list(subscriptions) ->
        subscriptions
    end
  end

  defp get_most_expensive_subscription(subscriptions) do
    membership_plans = Application.get_env(:ysc, :membership_plans)

    # Create a map of price_id to amount for quick lookup
    price_to_amount =
      Map.new(membership_plans, fn plan ->
        {plan.stripe_price_id, plan.amount}
      end)

    # Find the subscription with the highest amount
    Enum.max_by(subscriptions, fn subscription ->
      # Get the first subscription item (assuming one item per subscription)
      case subscription.subscription_items do
        [item | _] ->
          Map.get(price_to_amount, item.stripe_price_id, 0)

        _ ->
          0
      end
    end)
  end

  defp get_membership_plan_type_from_membership(nil), do: nil

  defp get_membership_plan_type_from_membership(%{type: :lifetime}),
    do: :lifetime

  defp get_membership_plan_type_from_membership(
         %Subscriptions.Subscription{} = subscription
       ) do
    subscription = Repo.preload(subscription, :subscription_items)

    case subscription.subscription_items do
      [item | _] ->
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        case Enum.find(
               membership_plans,
               &(&1.stripe_price_id == item.stripe_price_id)
             ) do
          %{id: plan_id} when not is_nil(plan_id) -> plan_id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_membership_plan_type_from_membership(%{plan: %{id: plan_id}})
       when not is_nil(plan_id),
       do: plan_id

  defp get_membership_plan_type_from_membership(_), do: nil

  # Validates that a cached membership is still valid (hasn't expired).
  # Uses cached fields only — do not query here; this runs on every cache hit.
  # `nil` is a valid cached "no membership" result.
  defp membership_valid?(nil), do: true
  defp membership_valid?(%{type: :lifetime}), do: true

  defp membership_valid?(%Subscriptions.Subscription{} = subscription) do
    Subscriptions.valid?(subscription)
  end

  defp membership_valid?(_), do: false
end

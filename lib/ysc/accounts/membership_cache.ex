defmodule Ysc.Accounts.MembershipCache do
  @moduledoc """
  In-memory cache for user membership data to improve performance.

  Caches membership status and membership type per user with a short TTL (5 minutes).
  This reduces database queries when users interact with the UI.
  """

  require Ysc.Logging
  alias Ysc.Accounts
  alias Ysc.Customers
  alias Ysc.Subscriptions

  @cache_name :ysc_cache
  @cache_prefix "membership:"
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

  When `validate: false`, returns cached membership without a per-subscription
  database round-trip. Pair with `batch_validate_subscription_ids/1` for hot paths
  that load many users at once.
  """
  def get_active_membership(user, opts) when is_list(opts) do
    validate? = Keyword.get(opts, :validate, true)
    cache_key = build_cache_key(user.id, "active")

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        membership = get_active_membership_db(user)
        cache_with_ttl(cache_key, membership)
        membership

      {:ok, membership} ->
        if !validate? or membership_valid?(membership) do
          membership
        else
          invalidate_user(user.id)
          membership = get_active_membership_db(user)
          cache_with_ttl(cache_key, membership)
          membership
        end

      {:error, _reason} ->
        get_active_membership_db(user)
    end
  end

  @doc """
  Gets the membership plan type for a user from cache or fetches from database and caches it.

  Returns the plan ID as an atom (`:lifetime`, `:single`, `:family`, etc.) or `nil`.
  """
  def get_membership_plan_type(user) when is_nil(user), do: nil

  def get_membership_plan_type(user) do
    cache_key = build_cache_key(user.id, "plan_type")

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch from database
        membership = get_active_membership(user)
        plan_type = get_membership_plan_type_from_membership(membership)
        # Cache with TTL
        cache_with_ttl(cache_key, plan_type)
        plan_type

      {:ok, plan_type} ->
        plan_type

      {:error, _reason} ->
        # Cache error - fallback to database
        membership = get_active_membership_db(user)
        get_membership_plan_type_from_membership(membership)
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

  Validates cached subscriptions in a single query instead of one `Repo.get/2`
  per user — intended for membership check-in search.
  """
  def batch_membership_data_for_users(users) when is_list(users) do
    memberships =
      Enum.map(users, fn user ->
        {user.id, get_active_membership(user, validate: false)}
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

      {user_id, {membership, get_membership_plan_type_from_membership(membership)}}
    end)
    |> Map.new()
  end

  @doc false
  def batch_validate_subscription_ids(subscription_ids) when subscription_ids == [],
    do: MapSet.new()

  def batch_validate_subscription_ids(subscription_ids) do
    import Ecto.Query

    Subscriptions.Subscription
    |> where([s], s.id in ^subscription_ids)
    |> Ysc.Repo.all()
    |> Enum.filter(&Subscriptions.valid?/1)
    |> Enum.map(& &1.id)
    |> MapSet.new()
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
    Cachex.put(@cache_name, key, value, expire: ttl_ms)
  end

  defp get_ttl do
    # Use 5 minutes as default, but can be configured
    Application.get_env(:ysc, :membership_cache_ttl_ms, @default_ttl)
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
      # Return a special struct representing lifetime membership
      %{
        type: :lifetime,
        awarded_at: user_to_check.lifetime_membership_awarded_at,
        user_id: user_to_check.id
      }
    else
      subscriptions =
        user_to_check
        |> loaded_subscriptions()
        |> Enum.filter(&Subscriptions.valid?/1)

      case subscriptions do
        [] ->
          nil

        [single_subscription] ->
          single_subscription

        multiple_subscriptions ->
          # If multiple active subscriptions, pick the most expensive one
          get_most_expensive_subscription(multiple_subscriptions)
      end
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
    subscription = Ysc.Repo.preload(subscription, :subscription_items)

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

  # Validates that a cached membership is still valid (hasn't expired)
  defp membership_valid?(%{type: :lifetime}), do: true

  defp membership_valid?(%Subscriptions.Subscription{id: id}) do
    case Ysc.Repo.get(Subscriptions.Subscription, id) do
      nil -> false
      fresh -> Subscriptions.valid?(fresh)
    end
  end

  defp membership_valid?(_), do: false
end

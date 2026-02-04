defmodule Ysc.Bookings.RefundPolicyCache do
  @moduledoc """
  In-memory cache for refund policies to improve performance.

  Caches refund policies keyed by:
  {property, booking_mode}

  Cache is invalidated via PubSub when refund policies or rules are created/updated/deleted.
  """

  require Logger
  import Ecto.Query
  alias Ysc.Bookings.{RefundPolicy, RefundPolicyRule}
  alias Ysc.Repo

  @cache_name :ysc_cache
  @cache_prefix "refund_policy:"
  @cache_version_key "refund_policy:version"

  @doc """
  Gets an active refund policy from cache or fetches from database and caches it.

  Returns the refund policy with rules preloaded, or nil if not found.
  """
  def get_active(property, booking_mode) do
    cache_key = build_cache_key(property, booking_mode)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch from database
        policy = get_active_refund_policy_db(property, booking_mode)
        # Cache the result (even if nil) with version check
        cache_with_version(cache_key, policy)
        policy

      {:ok, {:version, version, policy}} ->
        # Check if cache version is still valid
        case Cachex.get(@cache_name, @cache_version_key) do
          {:ok, current_version} when current_version == version ->
            policy

          _ ->
            # Version mismatch - invalidate and refetch
            Cachex.del(@cache_name, cache_key)
            policy = get_active_refund_policy_db(property, booking_mode)
            cache_with_version(cache_key, policy)
            policy
        end

      {:ok, policy} ->
        # Legacy format (no version) - upgrade to versioned
        cache_with_version(cache_key, policy)
        policy

      {:error, _reason} ->
        # Cache error - fallback to database
        get_active_refund_policy_db(property, booking_mode)
    end
  end

  @doc """
  Invalidates the refund policy cache by bumping the version.

  This should be called when refund policies or rules are created, updated, or deleted.
  Gracefully handles cases where the cache is not initialized (e.g., in seed scripts).
  """
  def invalidate do
    # Bump version to invalidate all cached policies
    # Use millisecond resolution so multiple invalidations in quick succession
    # (e.g., in tests) always bump the version.
    new_version = System.system_time(:millisecond)

    # Try to update cache version, but don't fail if cache isn't initialized
    case Cachex.put(@cache_name, @cache_version_key, new_version) do
      {:ok, _} ->
        # Cache is available - broadcast invalidation event via PubSub
        if Process.whereis(Ysc.PubSub) do
          Phoenix.PubSub.broadcast(
            Ysc.PubSub,
            "refund_policy_cache:invalidate",
            {:refund_policy_cache_invalidated, new_version}
          )
        end

        Logger.debug("Refund policy cache invalidated", version: new_version)
        :ok

      {:error, _reason} ->
        # Cache not available (e.g., in seed scripts) - silently ignore
        Logger.debug("Refund policy cache not available, skipping invalidation")
        :ok
    end
  rescue
    ArgumentError ->
      # Cache table doesn't exist (e.g., in seed scripts) - silently ignore
      Logger.debug("Refund policy cache not initialized, skipping invalidation")
      :ok
  end

  # Private functions

  defp build_cache_key(property, booking_mode) do
    "#{@cache_prefix}property:#{property}:booking_mode:#{booking_mode}"
  end

  defp cache_with_version(key, value) do
    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, version} when is_integer(version) ->
        Cachex.put(@cache_name, key, {:version, version, value})

      _ ->
        # No version set yet - initialize it
        version = System.system_time(:millisecond)
        Cachex.put(@cache_name, @cache_version_key, version)
        Cachex.put(@cache_name, key, {:version, version, value})
    end
  end

  # Internal function that actually queries the database (called by cache on miss)
  defp get_active_refund_policy_db(property, booking_mode) do
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
end

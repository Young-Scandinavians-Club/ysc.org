defmodule Ysc.Bookings.RefundPolicyCache do
  @moduledoc """
  In-memory cache for refund policies to improve performance.

  Caches refund policies keyed by:
  {property, booking_mode}

  Cache is invalidated via PubSub when refund policies or rules are created/updated/deleted.
  """

  require Ysc.Logging
  import Ecto.Query
  alias Ysc.Bookings.{ConfigCacheTelemetry, RefundPolicy}

  @cache_name :ysc_cache
  @cache_prefix "refund_policy:"
  @cache_version_key "refund_policy:version"
  @pubsub_topic "refund_policy_cache:invalidate"

  @doc """
  Subscribes the current process to refund-policy cache invalidation events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Ysc.PubSub, @pubsub_topic)
  end

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
            policy_with_loaded_rules(policy, property, booking_mode)

          _ ->
            # Version mismatch - invalidate and refetch
            Cachex.del(@cache_name, cache_key)
            policy = get_active_refund_policy_db(property, booking_mode)
            cache_with_version(cache_key, policy)
            policy
        end

      {:ok, policy} ->
        # Legacy format (no version) - upgrade to versioned
        policy = policy_with_loaded_rules(policy, property, booking_mode)
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
    # Bump version to invalidate all cached policies.
    # Use unique_integer to guarantee the version always increases, even when
    # invalidate/0 is called multiple times within the same millisecond (e.g. in tests).
    new_version = System.unique_integer([:monotonic, :positive])

    # Try to update cache version, but don't fail if cache isn't initialized
    case Ysc.DistributedCache.put(@cache_name, @cache_version_key, new_version) do
      {:ok, _} ->
        Ysc.Logging.debug("Refund policy cache invalidated",
          version: new_version
        )

      {:error, _reason} ->
        # Cache not available (e.g., in seed scripts) - still notify LiveViews.
        Ysc.Logging.debug(
          "Refund policy cache not available, broadcasting invalidation only"
        )
    end

    # Always notify open booking sessions when PubSub is up, even if Cachex failed.
    if Process.whereis(Ysc.PubSub) do
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        @pubsub_topic,
        {:refund_policy_cache_invalidated, new_version}
      )
    end

    ConfigCacheTelemetry.invalidated(:refund_policy)
    :ok
  rescue
    ArgumentError ->
      # Cache table doesn't exist (e.g., in seed scripts) - still try PubSub.
      if Process.whereis(Ysc.PubSub) do
        new_version = System.unique_integer([:monotonic, :positive])

        Phoenix.PubSub.broadcast(
          Ysc.PubSub,
          @pubsub_topic,
          {:refund_policy_cache_invalidated, new_version}
        )
      end

      ConfigCacheTelemetry.invalidated(:refund_policy)

      Ysc.Logging.debug(
        "Refund policy cache not initialized, broadcast invalidation only"
      )

      :ok
  end

  # Private functions

  defp build_cache_key(property, booking_mode) do
    "#{@cache_prefix}property:#{property}:booking_mode:#{booking_mode}"
  end

  defp policy_with_loaded_rules(nil, _property, _booking_mode), do: nil

  defp policy_with_loaded_rules(
         %{rules: rules} = policy,
         _property,
         _booking_mode
       )
       when is_list(rules) do
    policy
  end

  defp policy_with_loaded_rules(_policy, property, booking_mode) do
    policy = get_active_refund_policy_db(property, booking_mode)
    cache_with_version(build_cache_key(property, booking_mode), policy)
    policy
  end

  defp cache_with_version(key, value) do
    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, version} when is_integer(version) ->
        Cachex.put(@cache_name, key, {:version, version, value})

      _ ->
        # No version set yet - initialize it
        version = System.unique_integer([:monotonic, :positive])
        Cachex.put(@cache_name, @cache_version_key, version)
        Cachex.put(@cache_name, key, {:version, version, value})
    end
  end

  # Internal function that actually queries the database (called by cache on miss)
  defp get_active_refund_policy_db(property, booking_mode) do
    Ysc.Bookings.get_active_refund_policy_db(property, booking_mode)
  end

  @doc false
  def ci_query_explain_query do
    property = :tahoe
    booking_mode = :room

    from(rp in RefundPolicy,
      where: rp.property == ^property,
      where: rp.booking_mode == ^booking_mode,
      where: rp.is_active == true,
      order_by: [desc: rp.inserted_at, desc: rp.id],
      limit: 1
    )
  end
end

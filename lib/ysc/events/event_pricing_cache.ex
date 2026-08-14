defmodule Ysc.Events.EventPricingCache do
  @moduledoc """
  Per-event cache for pricing enrichment (tiers, counts, images).
  """

  @cache_name :ysc_cache
  @cache_version_key "event_pricing:version"
  @default_ttl :timer.hours(24)

  # Fields computed in list_upcoming_events_from_db / list_past_events_from_db — not part of
  # pricing enrichment but must not be dropped when serving a cached pricing payload.
  @transient_list_fields [:selling_fast, :recent_tickets_count]

  def enrich_events(events) when is_list(events) do
    if events == [] do
      []
    else
      Enum.map(events, &enrich_event/1)
    end
  end

  def enrich_event(event) do
    cache_key = "event:pricing:#{event.id}"

    enriched =
      fetch_cached(cache_key, fn ->
        Ysc.Events.enrich_single_event_with_pricing_from_db(event)
      end)

    enriched
    |> merge_transient_list_fields(event)
    |> ensure_cover_image(event)
  end

  def invalidate do
    if Ysc.ProcessCache.enabled?() do
      new_version = System.unique_integer([:monotonic, :positive])
      Ysc.DistributedCache.put(@cache_name, @cache_version_key, new_version)
      Ysc.Events.EventListCache.invalidate()
    end

    :ok
  end

  def invalidate_event(_event_id) do
    invalidate()
  end

  defp fetch_cached(cache_key, fetch_fun) when is_function(fetch_fun, 0) do
    if Ysc.ProcessCache.enabled?() do
      do_fetch_cached(cache_key, fetch_fun)
    else
      fetch_fun.()
    end
  end

  defp do_fetch_cached(cache_key, fetch_fun) when is_function(fetch_fun, 0) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        value = fetch_fun.()
        cache_with_version(cache_key, value)
        value

      {:ok, {:version, version, value}} ->
        case Cachex.get(@cache_name, @cache_version_key) do
          {:ok, current_version} when current_version == version ->
            value

          _ ->
            refetch_and_cache(cache_key, fetch_fun)
        end

      {:ok, value} ->
        cache_with_version(cache_key, value)
        value

      {:error, _reason} ->
        fetch_fun.()
    end
  end

  defp refetch_and_cache(cache_key, fetch_fun) do
    Cachex.del(@cache_name, cache_key)
    value = fetch_fun.()
    cache_with_version(cache_key, value)
    value
  end

  defp merge_transient_list_fields(enriched, source) do
    Enum.reduce(@transient_list_fields, enriched, fn field, acc ->
      case Map.fetch(source, field) do
        {:ok, value} -> Map.put(acc, field, value)
        :error -> acc
      end
    end)
  end

  # Enriched events are plain maps with `:image`, not `%Event{}` with `:cover_image`.
  # Always set `:cover_image` so templates can use dot access without KeyError.
  defp ensure_cover_image(enriched, source) do
    cover_image =
      Map.get(enriched, :cover_image) ||
        Map.get(enriched, :image) ||
        source_cover_image(source)

    Map.put(enriched, :cover_image, cover_image)
  end

  defp source_cover_image(source) do
    case Map.get(source, :cover_image) do
      %Ecto.Association.NotLoaded{} -> nil
      value -> value
    end
  end

  defp cache_with_version(key, value) do
    ttl_ms = pricing_cache_ttl_ms()

    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, version} when is_integer(version) ->
        Cachex.put(@cache_name, key, {:version, version, value}, expire: ttl_ms)

      _ ->
        version = System.unique_integer([:monotonic, :positive])
        Cachex.put(@cache_name, @cache_version_key, version, expire: ttl_ms)
        Cachex.put(@cache_name, key, {:version, version, value}, expire: ttl_ms)
    end
  end

  defp pricing_cache_ttl_ms do
    Application.get_env(:ysc, :event_pricing_cache_ttl_ms, @default_ttl)
  end
end

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

  # Event-body HTML. The public list/card queries omit these columns, so the
  # cached pricing payload keyed by event id can be seeded body-less by list
  # traffic. The event page passes a full `%Event{}` here and reads the body
  # off the result, so always re-merge these from the caller's source event
  # when it carries them (a slimmed list map simply won't, and stays slim).
  @source_body_fields [:raw_details, :rendered_details]

  def enrich_events(events) when is_list(events) do
    if events == [] do
      []
    else
      events
      |> Enum.map(fn event ->
        {event, lookup_cached(cache_key_for(event))}
      end)
      |> enrich_cache_misses()
      |> Enum.map(fn {source_event, enriched} ->
        enriched
        |> merge_transient_list_fields(source_event)
        |> merge_source_body_fields(source_event)
        |> ensure_cover_image(source_event)
      end)
    end
  end

  def enrich_event(event) do
    enrich_events([event]) |> List.first()
  end

  @doc """
  Recomputes pricing for `event` from the database and force-writes the
  result into this node's cache, instead of trusting whatever is already
  cached.

  Callers reacting to an `EventUpdated` broadcast already hold the fresh,
  authoritative event — they must not read through `enrich_event/1` there.
  `invalidate/0`'s version bump is replicated to other nodes by
  `Ysc.DistributedCache` as a *separate* PubSub message from the
  `EventUpdated` broadcast, so a node can receive `EventUpdated` before it
  has applied its own cache invalidation and would otherwise hand back a
  stale cached value until the next invalidation or TTL expiry.
  """
  def refresh_event(event) do
    cache_key = "event:pricing:#{event.id}"
    enriched = Ysc.Events.enrich_single_event_with_pricing_from_db(event)

    if Ysc.ProcessCache.enabled?() do
      cache_with_version(cache_key, enriched)
    end

    enriched
    |> merge_transient_list_fields(event)
    |> merge_source_body_fields(event)
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

  defp cache_key_for(%{id: id}), do: "event:pricing:#{id}"

  defp lookup_cached(cache_key) do
    if Ysc.ProcessCache.enabled?() do
      do_lookup_cached(cache_key)
    else
      :miss
    end
  end

  defp do_lookup_cached(cache_key) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        :miss

      {:ok, {:version, version, value}} ->
        case Cachex.get(@cache_name, @cache_version_key) do
          {:ok, current_version} when current_version == version ->
            {:ok, value}

          _ ->
            :miss
        end

      {:ok, value} ->
        {:ok, value}

      {:error, _reason} ->
        :miss
    end
  end

  defp enrich_cache_misses(event_lookups) do
    miss_events =
      event_lookups
      |> Enum.filter(fn {_event, lookup} -> lookup == :miss end)
      |> Enum.map(fn {event, :miss} -> event end)

    enriched_by_id =
      if miss_events == [] do
        %{}
      else
        miss_events
        |> Ysc.Events.enrich_events_with_pricing_from_db()
        |> tap(&cache_batch_results/1)
        |> Map.new(fn enriched -> {enriched.id, enriched} end)
      end

    Enum.map(event_lookups, fn
      {event, {:ok, enriched}} ->
        {event, enriched}

      {event, :miss} ->
        {event, Map.fetch!(enriched_by_id, event.id)}
    end)
  end

  defp cache_batch_results(enriched_events) do
    Enum.each(enriched_events, &cache_with_version(cache_key_for(&1), &1))
  end

  defp merge_transient_list_fields(enriched, source) do
    merge_present_fields(enriched, source, @transient_list_fields)
  end

  # Keep the caller's event-body HTML: a cached pricing payload may have been
  # written from a body-less list map, but the event page hands us a full
  # `%Event{}` and expects the body back. A slimmed list map lacks these keys,
  # so nothing is merged and list payloads stay body-free.
  defp merge_source_body_fields(enriched, source) do
    merge_present_fields(enriched, source, @source_body_fields)
  end

  defp merge_present_fields(enriched, source, fields) do
    Enum.reduce(fields, enriched, fn field, acc ->
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

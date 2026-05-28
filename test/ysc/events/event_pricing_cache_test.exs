defmodule Ysc.Events.EventPricingCacheTest do
  use Ysc.DataCase, async: false

  alias Ysc.Events.EventPricingCache

  import Ysc.EventsFixtures, only: [event_fixture: 1, ticket_tier_fixture: 1]

  setup do
    EventPricingCache.invalidate()
    Cachex.clear(:ysc_cache)
    :ok
  end

  test "enrich_event caches pricing fields" do
    event = event_fixture(%{title: "Pricing #{System.unique_integer()}"})
    _tier = ticket_tier_fixture(%{event_id: event.id})

    enriched1 = EventPricingCache.enrich_event(event)
    enriched2 = EventPricingCache.enrich_event(event)

    assert Map.has_key?(enriched1, :pricing_info)
    assert enriched1.id == enriched2.id
    assert enriched1.pricing_info == enriched2.pricing_info
  end

  test "enrich_event preserves selling_fast from list query on cache hit" do
    event = event_fixture(%{title: "Selling Fast #{System.unique_integer()}"})
    _tier = ticket_tier_fixture(%{event_id: event.id})

    # Prime cache from a struct without list-query fields
    EventPricingCache.enrich_event(event)

    list_row =
      Map.merge(Map.from_struct(event), %{
        selling_fast: true,
        recent_tickets_count: 12
      })

    enriched = EventPricingCache.enrich_event(list_row)

    assert enriched.selling_fast == true
    assert enriched.recent_tickets_count == 12
    assert Map.has_key?(enriched, :pricing_info)
  end

  test "invalidate refetches pricing after tier change" do
    event = event_fixture(%{title: "Tier Change #{System.unique_integer()}"})

    tier =
      ticket_tier_fixture(%{
        event_id: event.id,
        name: "GA",
        price: Money.new(10, :USD)
      })

    EventPricingCache.enrich_event(event)

    Ysc.Events.EventPricingCache.invalidate()

    enriched = EventPricingCache.enrich_event(event)
    assert enriched.id == event.id
    assert enriched.ticket_tiers != []
    assert Enum.any?(enriched.ticket_tiers, &(&1.id == tier.id))
  end
end

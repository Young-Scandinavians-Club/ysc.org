defmodule Ysc.Events.EventPricingCacheTest do
  use Ysc.DataCase, async: false

  @moduletag process_caches: true

  alias Ysc.Events
  alias Ysc.Events.EventPricingCache

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures, only: [event_fixture: 1, ticket_tier_fixture: 1]
  import Ysc.TestDataFactory, only: [event_with_state: 2]

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

  test "enrich_event sets cover_image from image and preserves preloaded cover on cache hit" do
    event =
      event_with_state(:upcoming,
        with_image: true,
        attrs: %{title: "Cover Image #{System.unique_integer()}"}
      )

    _tier = ticket_tier_fixture(%{event_id: event.id})

    # Prime cache from a struct without a preloaded cover_image association
    EventPricingCache.enrich_event(event)

    event_with_cover = Ysc.Repo.preload(event, :cover_image)

    enriched = EventPricingCache.enrich_event(event_with_cover)

    assert enriched.cover_image != nil
    assert enriched.cover_image.id == event.image_id
    assert enriched.image.id == event.image_id
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

  test "create_ticket_reservation invalidates pricing cache" do
    admin = user_fixture(%{role: "admin"})
    event = event_fixture(%{organizer_id: admin.id})
    tier = ticket_tier_fixture(%{event_id: event.id})
    member = user_fixture()

    EventPricingCache.enrich_event(event)

    {:ok, version_before} = Cachex.get(:ysc_cache, "event_pricing:version")

    expires_at =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(2, :day)

    assert {:ok, _reservation} =
             Events.create_ticket_reservation(%{
               ticket_tier_id: tier.id,
               user_id: member.id,
               created_by_id: admin.id,
               quantity: 1,
               expires_at: expires_at
             })

    {:ok, version_after} = Cachex.get(:ysc_cache, "event_pricing:version")
    assert version_after != version_before
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

  test "enrich_events batches cache misses into one tier query per list" do
    events =
      for i <- 1..3 do
        event = event_fixture(%{title: "Batch Pricing #{i} #{System.unique_integer()}"})
        _tier = ticket_tier_fixture(%{event_id: event.id})
        event
      end

    tier_query_pattern = ~r/FROM "ticket_tiers"/

    {_enriched, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn -> EventPricingCache.enrich_events(events) end,
        pattern: tier_query_pattern,
        caller_pids: [self()]
      )

    # Without batching, three cache misses would issue three tier queries.
    assert query_count == 1

    enriched_again = EventPricingCache.enrich_events(events)
    assert length(enriched_again) == 3
    assert Enum.all?(enriched_again, &Map.has_key?(&1, :pricing_info))
  end
end

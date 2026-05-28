defmodule Ysc.Events.EventListCacheTest do
  use Ysc.DataCase, async: false

  @moduletag process_caches: true

  alias Ysc.Events.EventListCache

  import Ysc.EventsFixtures, only: [event_fixture: 1]

  setup do
    EventListCache.invalidate()
    Cachex.clear(:ysc_cache)
    :ok
  end

  test "subscribe receives invalidation broadcast" do
    EventListCache.subscribe()
    EventListCache.invalidate()

    assert_receive {:event_list_cache_invalidated, version}
    assert is_integer(version)
  end

  describe "list_past_events/1" do
    test "cache miss and hit return same ids" do
      past =
        event_fixture(%{
          title: "Past #{System.unique_integer()}",
          start_date: DateTime.add(DateTime.utc_now(), -30, :day)
        })

      first = EventListCache.list_past_events(20)
      second = EventListCache.list_past_events(20)

      assert Enum.any?(first, &(&1.id == past.id))
      assert Enum.map(first, & &1.id) == Enum.map(second, & &1.id)
    end

    test "invalidation after event update" do
      past =
        event_fixture(%{
          title: "Old Past",
          start_date: DateTime.add(DateTime.utc_now(), -10, :day)
        })

      EventListCache.list_past_events(20)

      {:ok, _} = Ysc.Events.update_event(past, %{title: "New Past Title"})

      events = EventListCache.list_past_events(20)

      assert Enum.any?(
               events,
               &(&1.id == past.id and &1.title == "New Past Title")
             )
    end
  end

  describe "count_upcoming_events/0" do
    test "caches count" do
      _event = event_fixture(%{title: "Upcoming #{System.unique_integer()}"})

      count1 = EventListCache.count_upcoming_events()
      count2 = EventListCache.count_upcoming_events()

      assert count1 == count2
      assert is_integer(count1)
    end
  end
end

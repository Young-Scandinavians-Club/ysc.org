defmodule Ysc.Events.GetEventForTvPosterTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias Ysc.Events

  test "returns nil when the event does not exist" do
    assert Events.get_event_for_tv_poster(Ecto.ULID.generate()) == nil
  end

  test "returns enriched event when it exists" do
    event = event_fixture(%{title: "TV Poster Event"})

    assert %{} = loaded = Events.get_event_for_tv_poster(event.id)
    assert loaded.id == event.id
    assert loaded.title == "TV Poster Event"
  end

  test "omits event-body HTML columns from the SELECT" do
    event =
      event_fixture(%{
        title: "Slim TV Poster",
        raw_details: "<p>must not load this body</p>",
        rendered_details: "<p>must not load this html</p>"
      })

    {loaded, body_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Events.get_event_for_tv_poster(event.id) end,
        pattern: ~r/raw_details|rendered_details/i,
        caller_pids: [self()]
      )

    assert loaded.id == event.id
    assert loaded.title == "Slim TV Poster"
    assert is_nil(loaded.raw_details)
    assert is_nil(loaded.rendered_details)
    assert body_cols == 0
  end
end

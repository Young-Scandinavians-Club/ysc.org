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
end

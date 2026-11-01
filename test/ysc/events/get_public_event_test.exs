defmodule Ysc.Events.GetPublicEventTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.Event

  @raw_details_pattern ~r/raw_details/i

  test "omits raw_details from the SELECT and keeps rendered_details" do
    marker = "public-page-#{System.unique_integer([:positive])}"

    event =
      event_fixture(%{
        title: "Public page body",
        raw_details: "<p>raw #{marker}</p>",
        rendered_details: "<p>rendered #{marker}</p>"
      })

    {loaded, raw_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Events.get_public_event(event.id) end,
        pattern: @raw_details_pattern,
        caller_pids: [self()]
      )

    assert %Event{id: id} = loaded
    assert id == event.id
    assert loaded.rendered_details == "<p>rendered #{marker}</p>"
    assert is_nil(loaded.raw_details)
    assert raw_cols == 0
  end

  test "get_public_event_by_reference/1 also omits raw_details" do
    marker = "public-ref-#{System.unique_integer([:positive])}"

    event =
      event_fixture(%{
        title: "Public page by reference",
        raw_details: "<p>raw #{marker}</p>",
        rendered_details: "<p>rendered #{marker}</p>"
      })

    {loaded, raw_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Events.get_public_event_by_reference(event.reference_id) end,
        pattern: @raw_details_pattern,
        caller_pids: [self()]
      )

    assert loaded.id == event.id
    assert loaded.rendered_details == "<p>rendered #{marker}</p>"
    assert is_nil(loaded.raw_details)
    assert raw_cols == 0
  end

  test "staff preview on the public page omits raw_details" do
    marker = "preview-#{System.unique_integer([:positive])}"
    admin = user_fixture(%{role: :admin})

    event =
      event_fixture(%{
        title: "Draft preview body",
        state: :draft,
        published_at: nil,
        raw_details: "<p>raw #{marker}</p>",
        rendered_details: "<p>rendered #{marker}</p>"
      })

    {loaded, raw_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Events.get_event_for_page(event.id, admin) end,
        pattern: @raw_details_pattern,
        caller_pids: [self()]
      )

    assert loaded.id == event.id
    assert loaded.rendered_details == "<p>rendered #{marker}</p>"
    assert is_nil(loaded.raw_details)
    assert raw_cols == 0
  end
end

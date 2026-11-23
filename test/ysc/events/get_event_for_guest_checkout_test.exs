defmodule Ysc.Events.GetEventForGuestCheckoutTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Repo

  @body_pattern ~r/raw_details|rendered_details/i
  @fat_column_pattern ~r/raw_details|rendered_details|send_notification|lock_version|"place_id"|organizer_id/i

  test "returns id and title for a published event" do
    event = event_fixture(%{title: "Guest checkout title"})

    loaded = Events.get_event_for_guest_checkout(event.id)

    assert %Event{id: id, title: "Guest checkout title"} = loaded
    assert id == event.id
    assert is_nil(loaded.raw_details)
    assert is_nil(loaded.rendered_details)
  end

  test "returns a cancelled event the public page still shows" do
    event = event_fixture(%{title: "Cancelled show"})
    {:ok, cancelled} = Events.update_event(event, %{state: :cancelled})

    loaded = Events.get_event_for_guest_checkout(cancelled.id)

    assert loaded.id == cancelled.id
    assert loaded.title == "Cancelled show"
  end

  test "returns nil for drafts, missing ids, and invalid ULIDs" do
    draft =
      event_fixture(%{
        title: "Draft checkout",
        state: :draft,
        published_at: nil
      })

    refute Events.get_event_for_guest_checkout(draft.id)
    refute Events.get_event_for_guest_checkout(Ecto.ULID.generate())
    refute Events.get_event_for_guest_checkout("images.php")
  end

  test "omits event-body and admin columns from the SELECT" do
    event =
      event_fixture(%{
        title: "Slim checkout",
        raw_details: "<p>must not load this body</p>",
        rendered_details: "<p>must not load this html</p>"
      })

    {sql, _params} =
      Ecto.Adapters.SQL.to_sql(
        :all,
        Repo,
        Events.ci_query_explain_guest_checkout_event_query()
      )

    refute sql =~ "raw_details"
    refute sql =~ "rendered_details"
    refute sql =~ "send_notification"
    refute sql =~ "lock_version"
    refute sql =~ "place_id"
    refute sql =~ "organizer_id"
    assert sql =~ "title"

    {loaded, body_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Events.get_event_for_guest_checkout(event.id) end,
        pattern: @body_pattern,
        caller_pids: [self()]
      )

    {_again, fat_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Events.get_event_for_guest_checkout(event.id) end,
        pattern: @fat_column_pattern,
        caller_pids: [self()]
      )

    assert loaded.id == event.id
    assert loaded.title == "Slim checkout"
    assert is_nil(loaded.raw_details)
    assert is_nil(loaded.rendered_details)
    assert body_cols == 0
    assert fat_cols == 0
  end
end

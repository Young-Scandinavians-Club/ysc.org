defmodule Ysc.Events.GetPublicEventTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Repo

  @raw_details_pattern ~r/raw_details/i
  @admin_only_pattern ~r/send_notification|notification_sent_at|notification_recipient_count|show_participants|age_restriction|"place_id"|updated_by_id|"publish_at"|"organizer_id"|"lock_version"/i

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

  test "omits admin-only columns from the SELECT" do
    event =
      event_fixture(%{
        title: "Public page slim columns",
        external_ticket_url: "https://example.org/tickets",
        external_organizer: "Norwegian Club"
      })

    {sql, _params} =
      Ecto.Adapters.SQL.to_sql(
        :all,
        Repo,
        Events.ci_query_explain_public_event_query()
      )

    refute sql =~ "send_notification"
    refute sql =~ "notification_sent_at"
    refute sql =~ "notification_recipient_count"
    refute sql =~ "show_participants"
    refute sql =~ "age_restriction"
    refute sql =~ "place_id"
    refute sql =~ "updated_by_id"
    refute sql =~ ~s("publish_at")
    refute sql =~ ~s("published_at")
    refute sql =~ "organizer_id"
    refute sql =~ "lock_version"
    refute sql =~ "raw_details"
    assert sql =~ "rendered_details"
    assert sql =~ "external_ticket_url"

    {loaded, admin_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Events.get_public_event(event.id) end,
        pattern: @admin_only_pattern,
        caller_pids: [self()]
      )

    assert loaded.id == event.id
    assert loaded.external_ticket_url == "https://example.org/tickets"
    assert loaded.external_organizer == "Norwegian Club"
    assert loaded.tickets_tbd == false
    # Unselected schema defaults (false/1) still appear on the struct; the
    # SQL above is the load we care about.
    assert admin_cols == 0
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

defmodule Ysc.Events.ExternalTicketingTest do
  @moduledoc """
  Leftover #1819 coverage: copy, listing projections, and newsletter pricing
  for events ticketed on another organization's website.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.Event

  describe "copy_event/3" do
    test "carries external ticket URL and organizer onto the draft copy" do
      user = user_fixture()

      source =
        event_fixture(%{
          organizer_id: user.id,
          title: "SWEA Christmas Fair",
          tickets_tbd: true,
          external_ticket_url: "https://example.org/fair/tickets",
          external_organizer: "SWEA San Francisco"
        })

      assert {:ok, copied} = Events.copy_event(source, user.id, actor: :system)

      assert copied.state == :draft
      assert copied.external_ticket_url == "https://example.org/fair/tickets"
      assert copied.external_organizer == "SWEA San Francisco"
      assert copied.tickets_tbd == true
      assert Event.external_ticketing?(copied)
      refute Event.tickets_tbd?(copied)
    end

    test "does not invent an external link when the source has none" do
      user = user_fixture()
      source = event_fixture(%{organizer_id: user.id, title: "YSC Mixer"})

      assert {:ok, copied} = Events.copy_event(source, user.id, actor: :system)

      assert copied.external_ticket_url == nil
      assert copied.external_organizer == nil
      refute Event.external_ticketing?(copied)
    end
  end

  describe "event_pricing_display_string/1" do
    test "returns External Tickets even when tickets_tbd is still set" do
      event =
        event_fixture(%{
          tickets_tbd: true,
          external_ticket_url: "https://example.org/tickets"
        })

      loaded = Events.get_event!(event.id)
      assert Events.event_pricing_display_string(loaded) == "External Tickets"
    end

    test "still says Tickets coming soon when there is no external link" do
      event = event_fixture(%{tickets_tbd: true})
      loaded = Events.get_event!(event.id)

      assert Events.event_pricing_display_string(loaded) ==
               "Tickets coming soon"
    end
  end

  describe "list_upcoming_events_from_db/1" do
    test "projects external fields so listings are not labeled Free" do
      event =
        event_fixture(%{
          title: "External Fair #{System.unique_integer()}",
          tickets_tbd: true,
          external_ticket_url: "https://example.org/fair",
          external_organizer: "Norwegian Club"
        })

      loaded =
        Events.list_upcoming_events_from_db(50)
        |> Enum.find(&(&1.id == event.id))

      assert loaded
      assert loaded.external_ticket_url == "https://example.org/fair"
      assert loaded.external_organizer == "Norwegian Club"
      assert loaded.pricing_info.display_text == "External Tickets"
    end
  end

  describe "list_upcoming_events_paginated/1" do
    test "includes external fields used by the mobile API" do
      event =
        event_fixture(%{
          title: "API Fair #{System.unique_integer()}",
          external_ticket_url: "https://example.org/api-fair",
          external_organizer: "SWEA"
        })

      {events, _meta} =
        Events.list_upcoming_events_paginated(%{"page_size" => "100"})

      loaded = Enum.find(events, &(&1.id == event.id))

      assert loaded
      assert loaded.external_ticket_url == "https://example.org/api-fair"
      assert loaded.external_organizer == "SWEA"
      assert loaded.pricing_info.display_text == "External Tickets"
    end
  end
end

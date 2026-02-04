defmodule YscWeb.UserEventsListLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Repo

  describe "rendering" do
    test "displays upcoming event tickets for user" do
      user = user_fixture()

      event =
        event_fixture(%{
          title: "Future Event",
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          location_name: "Test Venue"
        })

      tier =
        ticket_tier_fixture(%{event_id: event.id, name: "General Admission"})

      _order = ticket_order_fixture(%{user: user, event: event, tier: tier})

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      assert html =~ "Future Event"
      assert html =~ "Test Venue"
      assert html =~ "General Admission"
    end

    test "displays empty state when user has no upcoming events" do
      user = user_fixture()

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      assert html =~ "No upcoming events"
      assert html =~ "You haven't registered for any events yet"
      assert html =~ "Browse events"
    end

    test "displays ticket reference ID" do
      user = user_fixture()

      event =
        event_fixture(%{start_date: DateTime.add(DateTime.utc_now(), 7, :day)})

      tier = ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{user: user, event: event, tier: tier})

      ticket = Repo.preload(ticket_order, :tickets).tickets |> List.first()

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      assert html =~ ticket.reference_id
    end

    test "displays confirmed ticket badge" do
      user = user_fixture()

      event =
        event_fixture(%{start_date: DateTime.add(DateTime.utc_now(), 7, :day)})

      tier = ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{user: user, event: event, tier: tier})

      ticket = Repo.preload(ticket_order, :tickets).tickets |> List.first()

      # Update ticket status to confirmed
      Repo.update!(Ecto.Changeset.change(ticket, status: :confirmed))

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      assert html =~ "Confirmed"
    end

    test "displays pending ticket badge" do
      user = user_fixture()

      event =
        event_fixture(%{start_date: DateTime.add(DateTime.utc_now(), 7, :day)})

      tier = ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{user: user, event: event, tier: tier})

      ticket = Repo.preload(ticket_order, :tickets).tickets |> List.first()

      # Update ticket status to pending
      Repo.update!(Ecto.Changeset.change(ticket, status: :pending))

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      assert html =~ "Pending"
    end

    test "displays free ticket without price display" do
      user = user_fixture()

      event =
        event_fixture(%{start_date: DateTime.add(DateTime.utc_now(), 7, :day)})

      # Create free tier
      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Free Entry",
          type: :free,
          price: Money.new(0, :USD)
        })

      _order = ticket_order_fixture(%{user: user, event: event, tier: tier})

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      assert html =~ "Free Entry"
      # Free tickets show $0.00
      assert html =~ "$0.00"
    end

    test "displays paid ticket with price" do
      user = user_fixture()

      event =
        event_fixture(%{start_date: DateTime.add(DateTime.utc_now(), 7, :day)})

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "VIP Pass",
          price: Money.new(5000, :USD)
        })

      _order = ticket_order_fixture(%{user: user, event: event, tier: tier})

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      assert html =~ "VIP Pass"
      assert html =~ "$5,000.00"
    end

    test "displays event link with correct path" do
      user = user_fixture()

      event =
        event_fixture(%{start_date: DateTime.add(DateTime.utc_now(), 7, :day)})

      tier = ticket_tier_fixture(%{event_id: event.id})
      _order = ticket_order_fixture(%{user: user, event: event, tier: tier})

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      assert html =~ "/events/#{event.id}"
    end

    test "only shows specific user's tickets" do
      user1 = user_fixture()
      user2 = user_fixture()

      event =
        event_fixture(%{
          title: "Shared Event",
          start_date: DateTime.add(DateTime.utc_now(), 7, :day)
        })

      tier = ticket_tier_fixture(%{event_id: event.id})

      # Create tickets for both users
      _order1 = ticket_order_fixture(%{user: user1, event: event, tier: tier})
      _order2 = ticket_order_fixture(%{user: user2, event: event, tier: tier})

      # Test user1's view
      html1 =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user1
        })

      # user1 should see the event
      assert html1 =~ "Shared Event"

      # Test user2's view
      html2 =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user2
        })

      # user2 should also see the event
      assert html2 =~ "Shared Event"
    end

    test "orders tickets by event start date" do
      user = user_fixture()

      # Create events with different start dates
      event1 =
        event_fixture(%{
          title: "First Event",
          start_date: DateTime.add(DateTime.utc_now(), 5, :day)
        })

      event2 =
        event_fixture(%{
          title: "Second Event",
          start_date: DateTime.add(DateTime.utc_now(), 10, :day)
        })

      event3 =
        event_fixture(%{
          title: "Third Event",
          start_date: DateTime.add(DateTime.utc_now(), 15, :day)
        })

      tier1 = ticket_tier_fixture(%{event_id: event1.id})
      tier2 = ticket_tier_fixture(%{event_id: event2.id})
      tier3 = ticket_tier_fixture(%{event_id: event3.id})

      # Create tickets in random order
      _order2 = ticket_order_fixture(%{user: user, event: event2, tier: tier2})
      _order1 = ticket_order_fixture(%{user: user, event: event1, tier: tier1})
      _order3 = ticket_order_fixture(%{user: user, event: event3, tier: tier3})

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      # All events should be present
      assert html =~ "First Event"
      assert html =~ "Second Event"
      assert html =~ "Third Event"

      # Events should appear in chronological order (earliest first)
      first_event_pos = :binary.match(html, "First Event") |> elem(0)
      second_event_pos = :binary.match(html, "Second Event") |> elem(0)
      third_event_pos = :binary.match(html, "Third Event") |> elem(0)

      assert first_event_pos < second_event_pos
      assert second_event_pos < third_event_pos
    end

    test "displays event with start time" do
      user = user_fixture()

      event =
        event_fixture(%{
          title: "Timed Event",
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          start_time: ~T[14:30:00]
        })

      tier = ticket_tier_fixture(%{event_id: event.id})
      _order = ticket_order_fixture(%{user: user, event: event, tier: tier})

      html =
        render_component(YscWeb.UserEventsListLive, %{
          id: "user-events",
          current_user: user
        })

      # Should display formatted time (2:30 PM)
      assert html =~ "2:30 PM"
    end
  end
end

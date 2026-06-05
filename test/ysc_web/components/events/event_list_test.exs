defmodule YscWeb.EventsListLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Repo

  defp past_event_attrs(title) do
    %{
      title: title,
      state: :published,
      start_date:
        DateTime.add(DateTime.utc_now(), -20, :day)
        |> DateTime.truncate(:second),
      end_date:
        DateTime.add(DateTime.utc_now(), -19, :day)
        |> DateTime.truncate(:second)
    }
  end

  describe "YscWeb.EventsListLive" do
    test "shows loading skeleton when defer_load is true" do
      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: true,
          show_hero: true,
          upcoming: true
        })

      assert html =~ "animate-pulse"
    end

    test "shows empty state when there are no upcoming events" do
      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: false,
          upcoming: true
        })

      assert html =~ "The calendar is clear"
    end

    test "lists upcoming events when present" do
      title = "EventList Unique #{System.unique_integer()}"

      _event =
        event_fixture(%{
          title: title,
          state: :published,
          start_date:
            DateTime.add(DateTime.utc_now(), 10, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 11, :day)
            |> DateTime.truncate(:second)
        })

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: false,
          upcoming: true
        })

      assert html =~ title
    end

    test "shows hero section when show_hero is true and events exist" do
      organizer = user_fixture()

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "Hero Feature #{System.unique_integer()}",
          start_date:
            DateTime.add(DateTime.utc_now(), 14, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 15, :day)
            |> DateTime.truncate(:second)
        })

      _tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA",
          quantity: 100
        })

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "hero-event"
      assert html =~ "Happening Soon"
      assert html =~ event.title
      refute html =~ "The calendar is clear"
    end

    test "does not show empty state when sole upcoming event is displayed as hero" do
      organizer = user_fixture()

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "Solo Hero #{System.unique_integer()}",
          start_date:
            DateTime.add(DateTime.utc_now(), 14, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 15, :day)
            |> DateTime.truncate(:second)
        })

      _tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA",
          quantity: 100
        })

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true
        })

      assert html =~ "hero-event"
      assert html =~ event.title
      refute html =~ "The calendar is clear"
      refute html =~ ~s(id="upcoming-events-stream")
    end

    test "lists past events when upcoming is false" do
      title = "Past Event #{System.unique_integer()}"
      _event = event_fixture(past_event_attrs(title))

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: false,
          upcoming: false
        })

      assert html =~ title
    end

    test "shows empty state for past events when none exist" do
      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: false,
          upcoming: false
        })

      assert html =~ "The calendar is clear"
    end

    test "hero event shows grayscale when cancelled and only upcoming event" do
      title = "Cancelled Only #{System.unique_integer()}"

      _event =
        event_fixture(%{
          title: title,
          state: :cancelled,
          start_date:
            DateTime.add(DateTime.utc_now(), 10, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 11, :day)
            |> DateTime.truncate(:second)
        })

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "hero-event"
      assert html =~ "grayscale"
      assert html =~ title
    end

    test "hero shows Save the Date badge when tickets_tbd is true" do
      organizer = user_fixture()

      _event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "TBD #{System.unique_integer()}",
          tickets_tbd: true,
          start_date:
            DateTime.add(DateTime.utc_now(), 12, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 13, :day)
            |> DateTime.truncate(:second)
        })

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "Save the Date"
    end

    test "reloads list when event message is passed (send_update path)" do
      title = "EventList Unique #{System.unique_integer()}"

      _event =
        event_fixture(%{
          title: title,
          state: :published,
          start_date:
            DateTime.add(DateTime.utc_now(), 10, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 11, :day)
            |> DateTime.truncate(:second)
        })

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: false,
          upcoming: true,
          event: :refresh
        })

      assert html =~ title
    end

    test "hero shows location name and description when set" do
      organizer = user_fixture()

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "LocDesc #{System.unique_integer()}",
          description: "Unique hero description line for list test.",
          location_name: "Scandi Hall",
          start_date:
            DateTime.add(DateTime.utc_now(), 16, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 17, :day)
            |> DateTime.truncate(:second)
        })

      _tier =
        ticket_tier_fixture(%{event_id: event.id, name: "GA", quantity: 100})

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "hero-event"
      assert html =~ "Scandi Hall"
      assert html =~ "Unique hero description line for list test."
    end

    test "hero formats date without time when start_time is nil" do
      organizer = user_fixture()

      start_date =
        DateTime.add(DateTime.utc_now(), 18, :day) |> DateTime.truncate(:second)

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "DateOnly #{System.unique_integer()}",
          start_date: start_date,
          start_time: nil,
          end_date: DateTime.add(start_date, 1, :day),
          end_time: nil
        })

      _tier = ticket_tier_fixture(%{event_id: event.id, quantity: 50})

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "hero-event"
      refute html =~ " at "
    end

    test "shows Sold Out badge when paid tier has no remaining inventory" do
      organizer = user_fixture()

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "SoldOut #{System.unique_integer()}",
          start_date:
            DateTime.add(DateTime.utc_now(), 20, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 21, :day)
            |> DateTime.truncate(:second)
        })

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Limited",
          quantity: 1
        })

      order = ticket_order_fixture(%{event: event, tier: tier})

      order
      |> Repo.preload(:tickets)
      |> Map.get(:tickets)
      |> List.first()
      |> then(fn ticket ->
        Repo.update!(Ecto.Changeset.change(ticket, status: :confirmed))
      end)

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "Sold Out"
    end

    test "shows Going Fast badge when many recent tickets sold on an event" do
      organizer = user_fixture()

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "GoingFast #{System.unique_integer()}",
          start_date:
            DateTime.add(DateTime.utc_now(), 22, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 23, :day)
            |> DateTime.truncate(:second)
        })

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA",
          quantity: 100
        })

      for _ <- 1..5 do
        order = ticket_order_fixture(%{event: event, tier: tier})

        order
        |> Repo.preload(:tickets)
        |> Map.get(:tickets)
        |> List.first()
        |> then(fn ticket ->
          Repo.update!(Ecto.Changeset.change(ticket, status: :confirmed))
        end)
      end

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "Going Fast!"
    end

    test "respects limit for past events list" do
      title = "Past Limit #{System.unique_integer()}"
      _event = event_fixture(past_event_attrs(title))

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: false,
          upcoming: false,
          limit: 1
        })

      assert html =~ title
    end

    test "hero shows sold out when ticket_count reaches max_attendees" do
      organizer = user_fixture()

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "CapOut #{System.unique_integer()}",
          max_attendees: 1,
          start_date:
            DateTime.add(DateTime.utc_now(), 24, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 25, :day)
            |> DateTime.truncate(:second)
        })

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Solo",
          quantity: 10
        })

      order = ticket_order_fixture(%{event: event, tier: tier})

      order
      |> Repo.preload(:tickets)
      |> Map.get(:tickets)
      |> List.first()
      |> then(fn ticket ->
        Repo.update!(Ecto.Changeset.change(ticket, status: :confirmed))
      end)

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "CapOut"
      assert html =~ "Sold Out"
    end

    test "does not mark sold out when only donations exceed max_attendees" do
      organizer = user_fixture()

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "DonCap #{System.unique_integer()}",
          max_attendees: 1,
          start_date:
            DateTime.add(DateTime.utc_now(), 24, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 25, :day)
            |> DateTime.truncate(:second)
        })

      _paid_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA",
          quantity: 10
        })

      donation_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Support",
          type: :donation,
          quantity: 50
        })

      for _ <- 1..2 do
        order = ticket_order_fixture(%{event: event, tier: donation_tier})

        order
        |> Repo.preload(:tickets)
        |> Map.get(:tickets)
        |> List.first()
        |> then(fn ticket ->
          Repo.update!(Ecto.Changeset.change(ticket, status: :confirmed))
        end)
      end

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "DonCap"
      refute html =~ "Sold Out"
    end

    test "does not mark sold out when tiers are only pre-sale (not on sale yet)" do
      organizer = user_fixture()

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "PreSale #{System.unique_integer()}",
          start_date:
            DateTime.add(DateTime.utc_now(), 26, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 27, :day)
            |> DateTime.truncate(:second)
        })

      _tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Future sale",
          quantity: 50,
          start_date: DateTime.add(DateTime.utc_now(), 200, :day)
        })

      html =
        render_component(YscWeb.EventsListLive, %{
          id: "events-list",
          defer_load: false,
          show_hero: true,
          upcoming: true,
          limit: 4
        })

      assert html =~ "PreSale"
      refute html =~ "Sold Out"
    end
  end
end

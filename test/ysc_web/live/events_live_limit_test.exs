defmodule YscWeb.EventsLiveLimitTest do
  @moduledoc """
  Serial LiveView tests for event list cache and pagination limits.

  Uses `async: false` because EventListCache is process-global; parallel async
  tests can flood subscribed LiveViews with invalidation messages and stall clicks.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Events
  alias Ysc.Repo

  @events_async_timeout 5_000

  defp render_events_async(view), do: render_async(view, @events_async_timeout)

  defp create_past_event(attrs) do
    organizer = attrs[:organizer] || user_fixture()

    defaults = %{
      title: "Past Event #{System.unique_integer()}",
      description: "A test event description",
      start_date: DateTime.add(DateTime.utc_now(), -30, :day),
      end_date: DateTime.add(DateTime.utc_now(), -29, :day),
      state: :published,
      ticket_sales_start: DateTime.add(DateTime.utc_now(), -31, :day),
      ticket_sales_end: DateTime.add(DateTime.utc_now(), -28, :day),
      location: "Test Location",
      max_attendees: 100,
      organizer_id: organizer.id,
      image_id: nil,
      reference_id: "EVT-LIMIT-#{System.unique_integer()}"
    }

    attrs =
      attrs
      |> Map.drop([:organizer])
      |> then(&Map.merge(defaults, &1))

    %Events.Event{}
    |> Events.Event.changeset(attrs)
    |> Repo.insert!()
  end

  defp create_upcoming_event(attrs) do
    organizer = attrs[:organizer] || user_fixture()

    defaults = %{
      title: "Upcoming Event #{System.unique_integer([:positive])}",
      description: "A test event description",
      start_date: DateTime.add(DateTime.utc_now(), 7, :day),
      end_date: DateTime.add(DateTime.utc_now(), 8, :day),
      state: :published,
      ticket_sales_start: DateTime.add(DateTime.utc_now(), -1, :day),
      ticket_sales_end: DateTime.add(DateTime.utc_now(), 6, :day),
      location: "Test Location",
      max_attendees: 100,
      organizer_id: organizer.id,
      image_id: nil,
      reference_id: "EVT-UPCOMING-#{System.unique_integer([:positive])}"
    }

    attrs =
      attrs
      |> Map.drop([:organizer])
      |> then(&Map.merge(defaults, &1))

    %Events.Event{}
    |> Events.Event.changeset(attrs)
    |> Repo.insert!()
  end

  @tag process_caches: true
  test "refreshes when event list cache is invalidated", %{conn: conn} do
    title = "Live Events Refresh #{System.unique_integer([:positive])}"

    {:ok, view, _html} = live(conn, ~p"/events")
    render_events_async(view)

    event = create_upcoming_event(%{title: title})
    Ysc.Events.EventListCache.invalidate()

    # Cache invalidation refreshes via handle_info, not a new async task.
    html = render(view)
    assert html =~ title
    assert has_element?(view, "a[href='/events/#{event.id}']", title)
  end

  test "limits maximum past events to 50", %{conn: conn} do
    organizer = user_fixture()

    for i <- 1..52 do
      create_past_event(%{
        title: "Past Limit #{i}",
        organizer: organizer
      })
    end

    Ysc.Events.EventListCache.invalidate()

    {:ok, view, _html} = live(conn, ~p"/events")
    render_events_async(view)

    for _ <- 1..4 do
      render_click(view, "show_more_past_events")
    end

    assert :sys.get_state(view.pid).socket.assigns.past_events_limit == 50

    render_click(view, "show_more_past_events")

    assert :sys.get_state(view.pid).socket.assigns.past_events_limit == 50
  end
end

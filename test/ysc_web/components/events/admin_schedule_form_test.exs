defmodule YscWeb.AdminEventsLive.ScheduleEventFormTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures

  alias YscWeb.AdminEventsLive.ScheduleEventForm

  describe "rendering" do
    test "displays schedule form for unpublished event" do
      event = event_fixture(%{state: :draft})

      html =
        render_component(ScheduleEventForm, %{
          id: "schedule-#{event.id}",
          event: event,
          event_id: event.id
        })

      assert html =~ "Scheduled At"
      assert html =~ "Set Schedule"
    end

    test "displays current scheduled time when event is scheduled" do
      scheduled_time =
        DateTime.add(DateTime.utc_now(), 24, :hour)
        |> DateTime.truncate(:second)

      event =
        event_fixture(%{
          state: :scheduled,
          publish_at: scheduled_time
        })

      html =
        render_component(ScheduleEventForm, %{
          id: "schedule-#{event.id}",
          event: event,
          event_id: event.id
        })

      assert html =~ "Scheduled At"
    end

    test "displays save button" do
      event = event_fixture(%{state: :draft})

      html =
        render_component(ScheduleEventForm, %{
          id: "schedule-#{event.id}",
          event: event,
          event_id: event.id
        })

      assert html =~ "Set Schedule"
    end
  end

  describe "form fields" do
    test "displays datetime-local input field" do
      event = event_fixture(%{state: :draft})

      html =
        render_component(ScheduleEventForm, %{
          id: "schedule-#{event.id}",
          event: event,
          event_id: event.id
        })

      assert html =~ "datetime-local"
    end

    test "form submits to save event" do
      event = event_fixture(%{state: :draft})

      html =
        render_component(ScheduleEventForm, %{
          id: "schedule-#{event.id}",
          event: event,
          event_id: event.id
        })

      assert html =~ "phx-submit=\"save\""
    end
  end

  describe "timezone handling" do
    test "converts UTC scheduled time to PST for display" do
      # Create a scheduled event with UTC time
      # 8 PM UTC
      utc_time = ~U[2024-06-15 20:00:00Z]

      event =
        event_fixture(%{
          state: :scheduled,
          publish_at: utc_time
        })

      html =
        render_component(ScheduleEventForm, %{
          id: "schedule-#{event.id}",
          event: event,
          event_id: event.id
        })

      # Should display PST time (UTC-7 or UTC-8 depending on DST)
      # June 15 would be PDT (UTC-7), so 1 PM
      assert html =~ "2024-06-15T13:00" or html =~ "value=\"2024-06-15T13:00\""
    end

    test "handles nil publish_at" do
      event =
        event_fixture(%{
          state: :draft,
          publish_at: nil
        })

      html =
        render_component(ScheduleEventForm, %{
          id: "schedule-#{event.id}",
          event: event,
          event_id: event.id
        })

      assert html =~ "Scheduled At"
    end
  end

  describe "event states" do
    test "can schedule a draft event" do
      event = event_fixture(%{state: :draft})

      html =
        render_component(ScheduleEventForm, %{
          id: "schedule-#{event.id}",
          event: event,
          event_id: event.id
        })

      assert html =~ "Scheduled At"
    end

    test "can reschedule a scheduled event" do
      scheduled_time =
        DateTime.add(DateTime.utc_now(), 24, :hour)
        |> DateTime.truncate(:second)

      event =
        event_fixture(%{
          state: :scheduled,
          publish_at: scheduled_time
        })

      html =
        render_component(ScheduleEventForm, %{
          id: "schedule-#{event.id}",
          event: event,
          event_id: event.id
        })

      assert html =~ "Scheduled At"
    end
  end
end

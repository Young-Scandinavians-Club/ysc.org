defmodule YscWeb.Components.AddToCalendarButtonTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "add_to_calendar_button/1" do
    test "renders calendar attributes from the event" do
      assigns = %{
        event: %{
          title: "Midsummer",
          location_name: "YSC Hall",
          start_date: ~U[2026-10-16 00:00:00Z],
          end_date: ~U[2026-10-16 00:00:00Z],
          start_time: ~T[19:00:00],
          end_time: ~T[22:00:00]
        }
      }

      html =
        rendered_to_string(~H"""
        <.add_to_calendar_button id="event-add-to-calendar" event={@event} />
        """)

      assert html =~ ~s(id="event-add-to-calendar")
      assert html =~ ~s(name="Midsummer")
      assert html =~ ~s(start-date="2026-10-16")
      assert html =~ ~s(end-date="2026-10-16")
      assert html =~ ~s(start-time="19:00:00")
      assert html =~ ~s(end-time="22:00:00")
      assert html =~ ~s(time-zone="America/Los_Angeles")
      assert html =~ ~s(location="YSC Hall")
      assert html =~ "Apple"
      assert html =~ "Google"
      assert html =~ ~s(light-mode="bodyScheme")
      assert html =~ ~s(size="4")
    end

    test "infers a three-hour end time and overnight end date" do
      assigns = %{
        event: %{
          title: "Late Night",
          location_name: nil,
          start_date: ~D[2026-10-16],
          end_date: nil,
          start_time: ~T[22:30:00],
          end_time: nil
        }
      }

      html =
        rendered_to_string(~H"""
        <.add_to_calendar_button event={@event} light_mode="dark" />
        """)

      assert html =~ ~s(start-date="2026-10-16")
      assert html =~ ~s(end-date="2026-10-17")
      assert html =~ ~s(end-time="01:30:00")
      assert html =~ ~s(light-mode="dark")
    end
  end
end

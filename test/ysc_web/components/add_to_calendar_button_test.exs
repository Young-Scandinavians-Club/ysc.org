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

    test "strips CR/LF from name and location before rendering attributes" do
      assigns = %{
        event: %{
          title: "Party\nDESCRIPTION:evil",
          location_name: "Hall\r\nURL:https://phish.test",
          start_date: ~D[2026-10-16],
          end_date: ~D[2026-10-16],
          start_time: ~T[19:00:00],
          end_time: ~T[22:00:00]
        }
      }

      html =
        rendered_to_string(~H"""
        <.add_to_calendar_button event={@event} />
        """)

      refute html =~ "Party\nDESCRIPTION"
      refute html =~ "Hall\r\nURL"
      assert html =~ ~s(name="Party DESCRIPTION:evil")
      assert html =~ ~s(location="Hall URL:https://phish.test")
    end
  end
end

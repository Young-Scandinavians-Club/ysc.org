defmodule YscWeb.Components.CalendarMonthTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.Components.CalendarMonth

  alias YscWeb.Components.CalendarMonth

  describe "month_state/1" do
    test "returns the date, month label, and Monday-start week rows" do
      state = CalendarMonth.month_state(~D[2026-09-21])

      assert state.date == ~D[2026-09-21]
      assert state.month == "September 2026"
      assert hd(hd(state.week_rows)) == ~D[2026-08-31]
      assert List.last(List.last(state.week_rows)) == ~D[2026-10-04]
      assert Enum.all?(state.week_rows, &(length(&1) == 7))
    end
  end

  describe "week_rows/1" do
    test "covers the full weeks that overlap the month" do
      rows = CalendarMonth.week_rows(~D[2026-08-08])

      assert length(rows) == 6
      assert hd(hd(rows)) == ~D[2026-07-27]
      assert List.last(List.last(rows)) == ~D[2026-09-06]
    end
  end

  describe "showing_current_month?/2" do
    test "is true when the dates share a calendar month" do
      assert CalendarMonth.showing_current_month?(
               ~D[2026-09-01],
               ~D[2026-09-21]
             )
    end

    test "is false when the dates are in different months" do
      refute CalendarMonth.showing_current_month?(
               ~D[2026-08-31],
               ~D[2026-09-21]
             )
    end

    test "is falsy when today is missing" do
      refute CalendarMonth.showing_current_month?(~D[2026-09-21], nil)
    end
  end

  describe "calendar_month_nav/1" do
    test "renders prev, next, and a disabled Today control for the current month" do
      assigns = %{
        current: CalendarMonth.month_state(~D[2026-09-21]),
        today: ~D[2026-09-21]
      }

      html =
        rendered_to_string(~H"""
        <.calendar_month_nav
          id="calendar"
          current={@current}
          today={@today}
          target="calendar"
        />
        """)

      assert html =~ ~s(id="calendar-prev-month")
      assert html =~ ~s(id="calendar-next-month")
      assert html =~ ~s(id="calendar-go-to-today")
      assert html =~ ~s(id="calendar-month-label")
      assert html =~ "September 2026"
      assert html =~ "Today"
      assert html =~ ~s(phx-click="prev-month")
      assert html =~ ~s(phx-click="next-month")
      assert html =~ ~s(phx-click="today")
      assert html =~ ~s(aria-label="Previous month")
      assert html =~ ~s(aria-label="Next month")
      assert html =~ ~s(aria-label="Already showing September 2026")
      assert html =~ "disabled"
    end

    test "enables Today and applies optional header ids and classes" do
      assigns = %{
        current: CalendarMonth.month_state(~D[2026-08-08]),
        today: ~D[2026-09-21]
      }

      html =
        rendered_to_string(~H"""
        <.calendar_month_nav
          id="event_date"
          header_id="calendar_header"
          current={@current}
          today={@today}
          target="event_date"
          class="mb-4"
          month_label_id="current_month_year"
          month_label_class="font-semibold"
        />
        """)

      assert html =~ ~s(id="calendar_header")
      assert html =~ ~s(id="current_month_year")
      assert html =~ "mb-4"
      assert html =~ "font-semibold"
      assert html =~ "August 2026"
      assert html =~ ~s(aria-label="Go to current month, September 2026")
      refute html =~ "disabled"
      refute html =~ "Already showing"
    end
  end
end

defmodule YscWeb.Components.AvailabilityCalendarTest do
  use YscWeb.ConnCase
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Bookings
  alias Ysc.Bookings.{AvailabilityCache, BlackoutListCache}
  alias YscWeb.Components.AvailabilityCalendar

  # Dedicated dates for buyout/blackout styling tests — kept within the current
  # month so render_shifted_calendar (today = date - 1) stays in the visible month.
  defp buyout_calendar_test_date, do: styling_test_date_in_month(2)
  defp blackout_calendar_test_date, do: styling_test_date_in_month(3)

  defp styling_test_date_in_month(slot) when slot in 1..5 do
    today = Date.utc_today()
    end_of_month = Date.end_of_month(today)

    # render_shifted_calendar uses today = date - 1, so leave one day before month end.
    latest = Date.add(end_of_month, -1)
    earliest = Date.add(today, 2)
    candidate = Date.add(earliest, slot - 1)

    if Date.compare(candidate, latest) == :gt do
      Date.add(latest, -(5 - slot))
    else
      candidate
    end
  end

  # Returns a date that falls in the current calendar month. When today is the
  # last day of the month (days_left == 0) it returns today so the anchor stays
  # in the current month; otherwise it advances 1–4 days into the future.
  defp near_future_in_current_month do
    today = Date.utc_today()
    end_of_month = Date.end_of_month(today)
    days_left = Date.diff(end_of_month, today)

    if days_left == 0, do: today, else: Date.add(today, min(days_left, 4))
  end

  # Extracts the HTML content of a single day cell identified by its data-day value.
  # LazyHTML.filter only searches top-level nodes of a fragment, so it cannot reach
  # the deeply-nested day divs. Instead we split the rendered string on data-day markers.
  defp extract_day_cell(html, day_str) do
    marker = ~s|data-day="#{day_str}"|

    case String.split(html, marker, parts: 2) do
      [_before, rest] ->
        rest
        |> String.split("data-day=", parts: 2)
        |> List.first()

      _ ->
        ""
    end
  end

  # Renders the calendar with today/min shifted one day before `date` so the
  # availability window includes the "morning" reference day (date - 1), which
  # is required for gradient (check-in style) rendering to work correctly.
  defp render_shifted_calendar(date) do
    calendar_base = Date.add(date, -1)

    render_clear_lake_calendar(
      today: calendar_base,
      min: calendar_base,
      max: Date.add(date, 30)
    )
  end

  defp render_clear_lake_calendar(opts \\ []) do
    today = Date.utc_today()

    opts =
      Keyword.merge(
        [
          id: "calendar",
          today: today,
          min: today,
          max: Date.add(today, 90),
          property: :clear_lake,
          selected_booking_mode: :day,
          checkin_date: nil,
          checkout_date: nil,
          guests_count: 1
        ],
        opts
      )

    render_component(AvailabilityCalendar, opts)
  end

  describe "render" do
    test "renders calendar with current month" do
      today = Date.utc_today()
      current_month = Calendar.strftime(today, "%B %Y")

      html =
        render_component(AvailabilityCalendar,
          id: "calendar",
          today: today
        )

      assert html =~ current_month
      assert html =~ "Today"
      assert html =~ ~s|id="calendar-go-to-today"|
      assert html =~ "aria-label=\"Calendar legend\""
      assert html =~ ~s|role="grid"|
      assert html =~ ~s|role="row"|
      assert html =~ ~s|role="columnheader"|
      assert html =~ ~s|role="gridcell"|
    end

    test "disables the Today button when already showing the current month" do
      today = ~D[2026-07-21]

      html =
        render_clear_lake_calendar(
          today: today,
          min: today,
          max: Date.add(today, 90)
        )

      assert html =~ ~s|id="calendar-go-to-today" type="button"|
      assert html =~ ~s|phx-click="today" disabled|
      assert html =~ "Already showing July 2026"
    end

    test "renders descriptive aria labels and status text on day cells" do
      today = ~D[2026-07-21]

      html =
        render_clear_lake_calendar(
          today: today,
          min: today,
          max: Date.add(today, 90),
          checkin_date: today,
          checkout_date: Date.add(today, 2)
        )

      assert html =~ "aria-label="
      assert html =~ "Start"
      assert html =~ "End"
    end

    test "highlights the today assign, not UTC today" do
      today = ~D[2026-07-21]
      tomorrow = Date.add(today, 1)

      html =
        render_clear_lake_calendar(
          today: today,
          min: today,
          max: Date.add(today, 90)
        )

      today_cell = extract_day_cell(html, Date.to_iso8601(today))
      tomorrow_cell = extract_day_cell(html, Date.to_iso8601(tomorrow))

      assert today_cell =~ "border-2 border-zinc-400"
      refute tomorrow_cell =~ "border-2 border-zinc-400"
    end

    test "shows OK badge on bookable day cells" do
      today = ~D[2026-07-21]
      bookable = Date.add(today, 2)

      html =
        render_clear_lake_calendar(
          today: today,
          min: today,
          max: Date.add(today, 90)
        )

      bookable_cell = extract_day_cell(html, Date.to_iso8601(bookable))

      assert bookable_cell =~ "text-green-800"
      assert bookable_cell =~ "\n        OK\n"
    end
  end

  describe "availability display — Clear Lake day mode (no bookings)" do
    test "renders without spots-remaining text" do
      html = render_clear_lake_calendar()

      refute html =~ "spots"
      refute html =~ "spots available"
      refute html =~ " spot"
    end

    test "does not render old dot indicators" do
      html = render_clear_lake_calendar()

      refute html =~ "bg-amber-400"
      refute html =~ "bg-teal-200"
      refute html =~ "bg-red-500"
    end

    test "does not show '0 booked' for empty dates" do
      html = render_clear_lake_calendar()

      refute html =~ "0 booked"
    end
  end

  describe "availability display — Clear Lake day mode (with DB bookings)" do
    setup do
      Ysc.Ledgers.ensure_basic_accounts()
      :ok
    end

    test "shows 'X booked' for a date that has existing confirmed bookings" do
      user = user_fixture()
      checkin = near_future_in_current_month()
      # checkout one day later so checkin day counts
      checkout = Date.add(checkin, 1)

      {:ok, _booking} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :day,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 5,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      html = render_clear_lake_calendar()

      assert html =~ "5 booked"
    end

    test "accumulates booked count across multiple bookings for the same date" do
      user = user_fixture()
      checkin = near_future_in_current_month()
      checkout = Date.add(checkin, 1)

      {:ok, _b1} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :day,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 3,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      {:ok, _b2} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :day,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 4,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      html = render_clear_lake_calendar()

      assert html =~ "7 booked"
    end

    test "shows booking count well above the old 12-guest cap without disabling the date" do
      user = user_fixture()
      checkin = near_future_in_current_month()
      checkout = Date.add(checkin, 1)

      {:ok, _b1} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :day,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 15,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      html = render_clear_lake_calendar()

      assert html =~ "15 booked"

      # The date should still be available (bg-green), not shown as unavailable (bg-red-200)
      refute html =~ "Not enough spots"
    end

    test "a date with a buyout is unavailable for day bookings" do
      user = user_fixture()
      checkin = buyout_calendar_test_date()
      checkout = Date.add(checkin, 1)

      {:ok, _buyout} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :buyout,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 10,
          status: :complete,
          total_price: Money.new(500, :USD)
        })

      AvailabilityCache.invalidate()

      html = render_shifted_calendar(checkin)
      day_str = Calendar.strftime(checkin, "%Y-%m-%d")
      day_html = extract_day_cell(html, day_str)

      # Check-in day with buyout: morning open, afternoon blocked as a booking (not blackout).
      assert day_html =~ "to-red-200"
      refute day_html =~ "to-red-800"
      refute day_html =~ "Check-in allowed"
    end

    test "styles checkout dates beyond max stay as restricted when selecting end date" do
      today = ~D[2026-07-21]
      checkin = ~D[2026-07-25]
      valid_checkout = Date.add(checkin, 2)
      restricted_checkout = Date.add(checkin, 5)

      html =
        render_component(AvailabilityCalendar,
          id: "calendar",
          today: today,
          min: today,
          max: Date.add(today, 90),
          property: :tahoe,
          selected_booking_mode: :buyout,
          checkin_date: checkin,
          checkout_date: nil
        )

      valid_cell = extract_day_cell(html, Date.to_iso8601(valid_checkout))

      restricted_cell =
        extract_day_cell(html, Date.to_iso8601(restricted_checkout))

      assert valid_cell =~ "bg-green-50"
      refute valid_cell =~ "aria-disabled"

      refute restricted_cell =~ "bg-green-50"
      assert restricted_cell =~ "bg-zinc-100"
      assert restricted_cell =~ ~s|aria-disabled="true"|
      refute restricted_cell =~ " disabled"
    end

    test "shows Saturday checkout restriction when selecting end date on Tahoe" do
      today = ~D[2026-07-21]
      checkin = ~D[2026-07-23]
      saturday = ~D[2026-07-25]

      html =
        render_component(AvailabilityCalendar,
          id: "calendar",
          today: today,
          min: today,
          max: Date.add(today, 90),
          property: :tahoe,
          selected_booking_mode: :buyout,
          checkin_date: checkin,
          checkout_date: nil
        )

      saturday_cell = extract_day_cell(html, Date.to_iso8601(saturday))

      assert saturday_cell =~ "No check-out"
      assert saturday_cell =~ "Check-outs are not permitted on Saturdays"
      refute saturday_cell =~ "Restricted (e.g. min/max stay)"
    end

    test "shows Saturday check-in restriction when picking start date on Tahoe" do
      today = ~D[2026-07-21]
      saturday = ~D[2026-07-25]

      html =
        render_component(AvailabilityCalendar,
          id: "calendar",
          today: today,
          min: today,
          max: Date.add(today, 90),
          property: :tahoe,
          selected_booking_mode: :buyout
        )

      saturday_cell = extract_day_cell(html, Date.to_iso8601(saturday))

      assert saturday_cell =~ "No check-in"
      assert saturday_cell =~ "Check-ins are not permitted on Saturdays"
      assert saturday_cell =~ ~s|aria-describedby="calendar-tooltip-2026-07-25"|

      refute saturday_cell =~
               ~s|aria-label="Saturday, July 25, 2026, No check-in, Check-ins are not permitted on Saturdays"|
    end

    test "does not apply Saturday booking restrictions on Clear Lake" do
      today = ~D[2026-07-21]
      saturday = ~D[2026-07-25]

      html =
        render_clear_lake_calendar(
          today: today,
          min: today,
          max: Date.add(today, 90)
        )

      saturday_cell = extract_day_cell(html, Date.to_iso8601(saturday))

      refute saturday_cell =~ "No check-in"
      refute saturday_cell =~ "No check-out"
      refute saturday_cell =~ "Check-ins are not permitted on Saturdays"
      refute saturday_cell =~ "Check-outs are not permitted on Saturdays"
    end

    test "a blacked-out date shows blackout styling" do
      blackout_date = blackout_calendar_test_date()

      {:ok, _blackout} =
        Bookings.create_blackout(%{
          property: :clear_lake,
          start_date: blackout_date,
          end_date: blackout_date,
          reason: "Test blackout"
        })

      BlackoutListCache.invalidate()

      html = render_shifted_calendar(blackout_date)
      day_str = Calendar.strftime(blackout_date, "%Y-%m-%d")
      day_html = extract_day_cell(html, day_str)

      # The blackout day is a "check-in day" (morning available, afternoon blacked out),
      # so it renders a green-to-red-800 gradient rather than a fully blocked bg-red-800 cell.
      assert day_html =~ "to-red-800"
    end

    test "shows X icon on fully unavailable blackout cells" do
      blackout_start = blackout_calendar_test_date()
      blackout_end = Date.add(blackout_start, 2)
      fully_blocked_day = Date.add(blackout_start, 1)

      {:ok, _blackout} =
        Bookings.create_blackout(%{
          property: :clear_lake,
          start_date: blackout_start,
          end_date: blackout_end,
          reason: "Test blackout"
        })

      BlackoutListCache.invalidate()

      html = render_shifted_calendar(fully_blocked_day)
      day_str = Calendar.strftime(fully_blocked_day, "%Y-%m-%d")
      day_html = extract_day_cell(html, day_str)

      assert day_html =~ "hero-x-mark"
      refute day_html =~ "text-green-800"
    end
  end
end

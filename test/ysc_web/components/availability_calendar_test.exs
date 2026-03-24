defmodule YscWeb.Components.AvailabilityCalendarTest do
  use YscWeb.ConnCase
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Bookings
  alias YscWeb.Components.AvailabilityCalendar

  # Returns a date that falls in the current calendar month. When today is the
  # last day of the month (days_left == 0) it returns today so the anchor stays
  # in the current month; otherwise it advances 1–4 days into the future.
  defp near_future_in_current_month do
    today = Date.utc_today()
    end_of_month = Date.end_of_month(today)
    days_left = Date.diff(end_of_month, today)

    if days_left == 0, do: today, else: Date.add(today, min(days_left, 4))
  end

  defp render_clear_lake_calendar(opts \\ []) do
    today = Date.utc_today()

    render_component(
      AvailabilityCalendar,
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
      ] ++ opts
    )
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
      checkin = near_future_in_current_month()
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

      html = render_clear_lake_calendar()
      day_str = Calendar.strftime(checkin, "%Y-%m-%d")
      document = LazyHTML.from_fragment(html)
      day_cell = LazyHTML.filter(document, "[data-day=\"#{day_str}\"]")
      day_html = LazyHTML.to_html(day_cell)

      assert day_html =~ "bg-red-200" or day_html =~ "cursor-not-allowed"
    end

    test "a blacked-out date shows blackout styling" do
      blackout_date = near_future_in_current_month()

      {:ok, _blackout} =
        Bookings.create_blackout(%{
          property: :clear_lake,
          start_date: blackout_date,
          end_date: blackout_date,
          reason: "Test blackout"
        })

      html = render_clear_lake_calendar()
      day_str = Calendar.strftime(blackout_date, "%Y-%m-%d")
      document = LazyHTML.from_fragment(html)
      day_cell = LazyHTML.filter(document, "[data-day=\"#{day_str}\"]")
      day_html = LazyHTML.to_html(day_cell)

      assert day_html =~ "bg-red-800" or day_html =~ "cursor-not-allowed"
    end
  end
end

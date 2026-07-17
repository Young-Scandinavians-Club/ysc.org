defmodule YscWeb.ClearLakeBookingDeferredTest do
  @moduledoc """
  Query-count assertions for Clear Lake deferred availability loading.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel booking LiveView tests in the main suite module.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.BookingsFixtures
  import Ysc.TestDataFactory

  describe "deferred availability and pricing" do
    test "dead render skips availability queries when dates are in the URL", %{
      conn: conn
    } do
      {checkin, checkout} = tahoe_booking_dates(45)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "booking_mode" => "day"
      }

      bookings_pattern = ~r/FROM "bookings"/i

      {html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/bookings/clear-lake?#{URI.encode_query(params)}")
            |> html_response(200)
          end,
          pattern: bookings_pattern,
          caller_pids: [self()]
        )

      assert query_count == 0
      assert html =~ "Clear Lake"
    end

    test "info tab switch does not re-query availability", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {checkin, checkout} = tahoe_booking_dates(45)

      path =
        "/bookings/clear-lake?" <>
          URI.encode_query(%{
            "checkin_date" => Date.to_string(checkin),
            "checkout_date" => Date.to_string(checkout),
            "tab" => "information",
            "info_tab" => "general"
          })

      {:ok, view, _html} = live(conn, path)

      # Drain connected mount work before measuring tab navigation queries.
      html = render(view)
      assert html =~ "Clear Lake"

      # Drain any availability-cache invalidation broadcasts from parallel tests
      # before measuring info-tab navigation query counts.
      drain_availability_cache_messages(view)

      state = :sys.get_state(view.pid)
      assert state.socket.assigns.active_tab == :information
      assert state.socket.assigns.info_tab == :general

      bookings_pattern = ~r/FROM "bookings"/i

      {_html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            render_click(view, "switch-info-tab", %{"tab" => "rules"})
          end,
          pattern: bookings_pattern,
          caller_pids: [view.pid]
        )

      assert query_count == 0
      assert :sys.get_state(view.pid).socket.assigns.info_tab == :rules
    end

    test "switching to booking tab recalculates availability when dates are present",
         %{
           conn: conn
         } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {checkin, checkout} = tahoe_booking_dates(45)

      path =
        "/bookings/clear-lake?" <>
          URI.encode_query(%{
            "checkin_date" => Date.to_string(checkin),
            "checkout_date" => Date.to_string(checkout),
            "tab" => "information"
          })

      {:ok, view, _html} = live(conn, path)
      render(view)

      assert :sys.get_state(view.pid).socket.assigns.active_tab == :information

      html = render_click(view, "switch-tab", %{"tab" => "booking"})

      state = :sys.get_state(view.pid)
      assert state.socket.assigns.active_tab == :booking
      assert is_integer(state.socket.assigns.availability_cache_version)
      assert html =~ "Clear Lake"
    end

    test "availability cache invalidation on booking tab bumps cache version",
         %{
           conn: conn
         } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {checkin, checkout} = tahoe_booking_dates(45)

      path =
        "/bookings/clear-lake?" <>
          URI.encode_query(%{
            "checkin_date" => Date.to_string(checkin),
            "checkout_date" => Date.to_string(checkout),
            "tab" => "booking"
          })

      {:ok, view, _html} = live(conn, path)
      render(view)

      version_before =
        :sys.get_state(view.pid).socket.assigns.availability_cache_version

      send(view.pid, :availability_cache_invalidated)
      render(view)

      version_after =
        :sys.get_state(view.pid).socket.assigns.availability_cache_version

      assert version_after > version_before
    end

    test "availability cache invalidation on information tab is a no-op", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {checkin, checkout} = tahoe_booking_dates(45)

      path =
        "/bookings/clear-lake?" <>
          URI.encode_query(%{
            "checkin_date" => Date.to_string(checkin),
            "checkout_date" => Date.to_string(checkout),
            "tab" => "information"
          })

      {:ok, view, _html} = live(conn, path)
      render(view)

      version_before =
        :sys.get_state(view.pid).socket.assigns.availability_cache_version

      send(view.pid, :availability_cache_invalidated)
      render(view)

      version_after =
        :sys.get_state(view.pid).socket.assigns.availability_cache_version

      assert version_after == version_before
    end
  end

  defp drain_availability_cache_messages(view) do
    html = render(view)

    receive do
      :availability_cache_invalidated -> drain_availability_cache_messages(view)
    after
      0 -> html
    end
  end
end

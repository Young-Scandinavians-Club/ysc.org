defmodule YscWeb.ClearLakeBookingDeferredTest do
  @moduledoc """
  Query-count assertions for Clear Lake deferred availability loading.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel booking LiveView tests in the main suite module.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory

  alias Ysc.Bookings.AvailabilityCache

  describe "deferred availability and pricing" do
    test "dead render skips availability queries when dates are in the URL", %{
      conn: conn
    } do
      checkin = Date.add(Date.utc_today(), 45)
      checkout = Date.add(checkin, 3)

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

      checkin = Date.add(Date.utc_today(), 45)
      checkout = Date.add(checkin, 3)

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

      # Parallel tests invalidate shared caches in setup; process any broadcast
      # before measuring info-tab navigation query counts.
      AvailabilityCache.invalidate()
      render(view)

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
  end
end

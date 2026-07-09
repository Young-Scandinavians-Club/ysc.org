defmodule YscWeb.TahoeBookingDeferredTest do
  @moduledoc """
  Query-count assertions for Tahoe deferred room availability loading.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel booking LiveView tests in the main suite module.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.BookingsFixtures
  import Ysc.TestDataFactory

  alias Ysc.Bookings

  describe "deferred room availability" do
    test "dead render skips room inventory queries when dates are in the URL",
         %{
           conn: conn
         } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      tahoe_rooms =
        Bookings.list_rooms(:tahoe)
        |> Enum.filter(& &1.is_active)

      if tahoe_rooms == [] do
        assert true
      else
        room = List.first(tahoe_rooms)
        {checkin, checkout} = tahoe_booking_dates(30)

        params = %{
          "checkin_date" => Date.to_string(checkin),
          "checkout_date" => Date.to_string(checkout),
          "booking_mode" => "room"
        }

        inventory_pattern = ~r/FROM "room_inventory"/i

        {html, query_count} =
          Ysc.QueryCounter.with_query_counter(
            fn ->
              conn
              |> get(~p"/bookings/tahoe?#{URI.encode_query(params)}")
              |> html_response(200)
            end,
            pattern: inventory_pattern,
            caller_pids: [self()]
          )

        assert query_count == 0
        assert html =~ "Tahoe"
        refute html =~ ~s(id="room-#{room.id}")
      end
    end

    test "info tab switch does not re-query availability", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 45)
      checkout = Date.add(checkin, 3)

      path =
        "/bookings/tahoe?" <>
          URI.encode_query(%{
            "checkin_date" => Date.to_string(checkin),
            "checkout_date" => Date.to_string(checkout),
            "tab" => "information",
            "info_tab" => "general"
          })

      {:ok, view, _html} = live(conn, path)

      html = render(view)
      assert html =~ "Tahoe"

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

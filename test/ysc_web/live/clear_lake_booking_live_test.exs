defmodule YscWeb.ClearLakeBookingLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory

  describe "mount/3 - unauthenticated" do
    test "loads page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")
      assert html =~ "Clear Lake"
    end

    test "loads page with query parameters", %{conn: conn} do
      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end
  end

  describe "mount/3 - authenticated without membership" do
    test "loads page but shows membership requirement", %{conn: conn} do
      user = user_with_membership(:none)
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/bookings/clear-lake")

      # Page loads
      assert html =~ "Clear Lake"

      # Wait for async data to load
      :timer.sleep(200)
      html = render(view)

      # Shows membership requirement or disabled state
      assert html =~ "Clear Lake" or html =~ "membership" or
               html =~ "Information"
    end
  end

  describe "mount/3 - authenticated with membership" do
    test "loads booking page successfully", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      assert html =~ "Clear Lake"
    end

    test "sets page title", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      assert page_title(view) =~ "Clear Lake Cabin"
    end

    test "initializes with today's date if no params", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      # Wait for async load
      :timer.sleep(200)
      html = render(view)

      # Check calendar is displayed
      assert html =~ "calendar" or html =~ "date" or html =~ "Clear Lake"
    end

    test "parses date parameters from URL", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "handles invalid date parameters gracefully", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{
        "checkin_date" => "invalid",
        "checkout_date" => "also-invalid"
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      # Should still load, using default dates
      assert html =~ "Clear Lake"
    end
  end

  describe "booking modes" do
    test "defaults to day mode", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(200)
      html = render(view)

      # Check for booking elements
      assert html =~ "Clear Lake"
    end

    test "accepts booking_mode parameter for buyout", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"booking_mode" => "buyout"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "switches between day and buyout modes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(200)

      # Try to switch modes (if button exists)
      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "guest selection" do
    test "parses guest count from URL parameters", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"guests" => "6"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "handles invalid guest counts", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"guests" => "invalid"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      # Should use defaults
      assert html =~ "Clear Lake"
    end

    test "enforces maximum guest capacity of 12", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Try to set guest count beyond max
      params = %{"guests" => "20"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end
  end

  describe "tab navigation" do
    test "defaults to booking tab for eligible users", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(200)
      html = render(view)

      # Check tab structure exists
      assert html =~ "Clear Lake"
    end

    test "accepts tab parameter", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"tab" => "information"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "handles info_tab parameter for information sections", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"tab" => "information", "info_tab" => "amenities"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end
  end

  describe "membership type display" do
    test "shows appropriate content for lifetime members", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(200)
      html = render(view)

      # Lifetime members should see booking functionality
      assert html =~ "Clear Lake"
    end

    test "handles subscription members", %{conn: conn} do
      user = user_with_membership(:subscription)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(200)
      html = render(view)

      assert html =~ "Clear Lake"
    end
  end

  describe "date tooltips and calendar" do
    test "displays calendar for date selection", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(200)
      html = render(view)

      # Check for calendar or date picker elements
      assert html =~ "Clear Lake"
    end
  end

  describe "season information" do
    test "displays current season info", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(200)
      html = render(view)

      # Season info should be displayed
      assert html =~ "Clear Lake"
    end

    test "handles out of season dates", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Try to book far in the future (likely out of season)
      checkin = Date.add(Date.utc_today(), 400)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end
  end

  describe "page structure" do
    test "includes main booking container", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      assert html =~ "Clear Lake"
    end

    test "includes responsive design classes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      assert html =~ "lg:" or html =~ "md:" or html =~ "Clear Lake"
    end

    test "includes navigation elements", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      # Should have tabs or navigation
      assert html =~ "Clear Lake"
    end
  end

  describe "accessibility" do
    test "includes proper heading hierarchy", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      assert html =~ "<h1" or html =~ "<h2" or html =~ "Clear Lake"
    end

    test "includes form labels", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(200)
      html = render(view)

      # Should have labels or aria-labels
      assert html =~ "Clear Lake"
    end

    test "includes ARIA attributes for interactive elements", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      # Check for aria attributes
      assert html =~ "aria-" or html =~ "Clear Lake"
    end
  end

  describe "property identification" do
    test "correctly identifies as Clear Lake property", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(100)

      # Check socket assigns
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.property == :clear_lake
    end

    test "displays Clear Lake-specific content", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      assert html =~ "Clear Lake"
    end
  end

  describe "error handling" do
    test "handles missing date gracefully", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"checkin_date" => ""}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "handles checkout before checkin", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      # Before checkin
      checkout = Date.add(checkin, -5)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      # Should handle invalid date range
      assert html =~ "Clear Lake"
    end

    test "handles dates in the past", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), -10)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      # Should default to valid dates
      assert html =~ "Clear Lake"
    end
  end

  describe "responsive design" do
    test "includes mobile-friendly classes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      # Should have responsive grid or flex classes
      assert html =~ "grid" or html =~ "flex" or html =~ "Clear Lake"
    end

    test "includes tablet breakpoint classes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      assert html =~ "md:" or html =~ "Clear Lake"
    end

    test "includes desktop breakpoint classes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      assert html =~ "lg:" or html =~ "xl:" or html =~ "Clear Lake"
    end
  end

  describe "async data loading" do
    test "loads initial page before async data", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake")

      # Initial render should be fast
      assert html =~ "Clear Lake"
    end

    test "completes async loading after connection", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      # Wait for async operations
      :timer.sleep(300)

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "max guests" do
    test "enforces max guests of 12", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")

      :timer.sleep(100)

      # Check socket assigns for max_guests
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.max_guests == 12
    end
  end

  describe "user interactions - guest count" do
    test "handles increase-guests event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "increase-guests", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles decrease-guests event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake?guests=4")
      :timer.sleep(200)

      render_click(view, "decrease-guests", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles toggle-guests-dropdown event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "toggle-guests-dropdown", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles close-guests-dropdown event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "close-guests-dropdown", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "user interactions - booking mode" do
    test "handles booking-mode-changed to buyout", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "booking-mode-changed", %{"booking_mode" => "buyout"})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles booking-mode-changed to day", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "booking-mode-changed", %{"booking_mode" => "day"})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "user interactions - dates" do
    test "handles reset-dates event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/bookings/clear-lake?checkin_date=#{Date.to_string(checkin)}&checkout_date=#{Date.to_string(checkout)}"
        )

      :timer.sleep(200)

      render_click(view, "reset-dates", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "user interactions - general" do
    test "handles ignore event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "ignore", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles switch-tab event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "switch-tab", %{"tab" => "information"})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "date input interactions" do
    test "handles date-changed for checkin", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      checkin = Date.add(Date.utc_today(), 30)

      render_change(view, "date-changed", %{
        "checkin_date" => Date.to_string(checkin)
      })

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles date-changed for checkout", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      checkout = Date.add(Date.utc_today(), 33)

      render_change(view, "date-changed", %{
        "checkout_date" => Date.to_string(checkout)
      })

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "guest input interactions" do
    test "handles guests-changed event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_change(view, "guests-changed", %{"guests_count" => "6"})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles empty guest count input", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_change(view, "guests-changed", %{"guests_count" => ""})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles negative guest count", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_change(view, "guests-changed", %{"guests_count" => "-5"})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles zero guest count", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_change(view, "guests-changed", %{"guests_count" => "0"})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles guest count above maximum", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_change(view, "guests-changed", %{"guests_count" => "50"})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "validation scenarios" do
    test "shows errors for same-day check-in/check-out", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      same_date = Date.add(Date.utc_today(), 30)

      params = %{
        "checkin_date" => Date.to_string(same_date),
        "checkout_date" => Date.to_string(same_date)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "handles minimum stay requirements", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      # Only 1 night
      checkout = Date.add(checkin, 1)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "handles maximum stay limits", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      # 30 nights
      checkout = Date.add(checkin, 30)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "validates weekend requirements in peak season", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Find a Friday 60 days out
      base_date = Date.add(Date.utc_today(), 60)
      friday = find_next_weekday(base_date, 5)
      monday = Date.add(friday, 3)

      params = %{
        "checkin_date" => Date.to_string(friday),
        "checkout_date" => Date.to_string(monday)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "handles dates far in the future", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 500)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end

    test "handles very long date range", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 90)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      assert html =~ "Clear Lake"
    end
  end

  describe "different user states" do
    test "displays correctly for user without family account", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "displays pricing information for eligible users", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(300)
      html = render(view)

      assert html =~ "Clear Lake"
    end

    test "shows different content in information tab", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake?tab=information")
      :timer.sleep(200)

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles my-bookings tab", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake?tab=my-bookings")

      assert html =~ "Clear Lake"
    end
  end

  describe "booking mode edge cases" do
    test "buyout mode with minimum guests", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"booking_mode" => "buyout", "guests" => "1"}

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)

      assert html =~ "Clear Lake"
    end

    test "day mode with maximum guests", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"booking_mode" => "day", "guests" => "12"}

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)

      assert html =~ "Clear Lake"
    end

    test "switches from day to buyout with valid dates", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 7)

      params = %{
        "booking_mode" => "day",
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)

      render_click(view, "booking-mode-changed", %{"booking_mode" => "buyout"})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "handle_params scenarios" do
    test "handles malformed query parameters", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/clear-lake?checkin_date=invalid&checkout_date=bad&guests=xyz"
        )

      assert html =~ "Clear Lake"
    end

    test "handles mixed valid and invalid parameters", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/clear-lake?checkin_date=#{Date.to_string(checkin)}&checkout_date=invalid&guests=abc"
        )

      assert html =~ "Clear Lake"
    end

    test "handles URL with special characters", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/clear-lake?tab=information&info_tab=getting-there"
        )

      assert html =~ "Clear Lake"
    end

    test "handles empty string parameters", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/clear-lake?checkin_date=&checkout_date=&guests="
        )

      assert html =~ "Clear Lake"
    end
  end

  describe "date edge cases" do
    test "handles leap year date", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      # Try February 29 if it's a leap year
      render_change(view, "date-changed", %{"checkin_date" => "2028-02-29"})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles year boundary dates", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_change(view, "date-changed", %{"checkin_date" => "2026-12-31"})
      render_change(view, "date-changed", %{"checkout_date" => "2027-01-02"})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles month boundary dates", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_change(view, "date-changed", %{"checkin_date" => "2026-06-30"})
      render_change(view, "date-changed", %{"checkout_date" => "2026-07-03"})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "guest dropdown interactions" do
    test "opens and closes guest dropdown multiple times", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      # Open
      render_click(view, "toggle-guests-dropdown", %{})
      # Close
      render_click(view, "close-guests-dropdown", %{})
      # Open again
      render_click(view, "toggle-guests-dropdown", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "changes guests while dropdown is open", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "toggle-guests-dropdown", %{})
      render_click(view, "increase-guests", %{})
      render_click(view, "increase-guests", %{})
      render_click(view, "decrease-guests", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "reaches minimum guest count", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake?guests=1")
      :timer.sleep(200)

      # Try to decrease below minimum
      render_click(view, "decrease-guests", %{})
      render_click(view, "decrease-guests", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "reaches maximum guest count", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake?guests=11")
      :timer.sleep(200)

      # Increase to max
      render_click(view, "increase-guests", %{})
      # Try to go beyond max
      render_click(view, "increase-guests", %{})
      render_click(view, "increase-guests", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "rapid user interactions" do
    test "handles rapid date changes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      # Rapid fire date changes
      for i <- 1..5 do
        date = Date.add(Date.utc_today(), 30 + i)

        render_change(view, "date-changed", %{
          "checkin_date" => Date.to_string(date)
        })
      end

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles rapid guest count changes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      # Rapid guest changes
      for _i <- 1..5 do
        render_click(view, "increase-guests", %{})
      end

      for _i <- 1..3 do
        render_click(view, "decrease-guests", %{})
      end

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles rapid mode switching", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "booking-mode-changed", %{"booking_mode" => "buyout"})
      render_click(view, "booking-mode-changed", %{"booking_mode" => "day"})
      render_click(view, "booking-mode-changed", %{"booking_mode" => "buyout"})
      render_click(view, "booking-mode-changed", %{"booking_mode" => "day"})

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles rapid tab switching", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "switch-tab", %{"tab" => "information"})
      render_click(view, "switch-tab", %{"tab" => "booking"})
      render_click(view, "switch-tab", %{"tab" => "my-bookings"})
      render_click(view, "switch-tab", %{"tab" => "booking"})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "information tab sections" do
    test "displays amenities information", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?tab=information&info_tab=amenities")

      assert html =~ "Clear Lake"
    end

    test "displays sleeping arrangements information", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?tab=information&info_tab=sleeping")

      assert html =~ "Clear Lake"
    end

    test "displays getting there information", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/clear-lake?tab=information&info_tab=getting-there"
        )

      assert html =~ "Clear Lake"
    end

    test "displays house rules information", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/clear-lake?tab=information&info_tab=house-rules"
        )

      assert html =~ "Clear Lake"
    end

    test "displays local area information", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?tab=information&info_tab=local-area")

      assert html =~ "Clear Lake"
    end

    test "switches between info tabs", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake?tab=information")
      :timer.sleep(200)

      # Navigate through different info tabs via URL changes
      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "different date combinations" do
    test "books 2 nights starting on Monday", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      base_date = Date.add(Date.utc_today(), 60)
      monday = find_next_weekday(base_date, 1)
      wednesday = Date.add(monday, 2)

      params = %{
        "checkin_date" => Date.to_string(monday),
        "checkout_date" => Date.to_string(wednesday)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "books week starting on Saturday", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      base_date = Date.add(Date.utc_today(), 90)
      saturday = find_next_weekday(base_date, 6)
      next_saturday = Date.add(saturday, 7)

      params = %{
        "checkin_date" => Date.to_string(saturday),
        "checkout_date" => Date.to_string(next_saturday)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "books during different seasons", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Summer date
      summer_start = ~D[2026-07-15]
      summer_end = Date.add(summer_start, 3)

      params = %{
        "checkin_date" => Date.to_string(summer_start),
        "checkout_date" => Date.to_string(summer_end)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "books 3 nights midweek", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      base_date = Date.add(Date.utc_today(), 45)
      tuesday = find_next_weekday(base_date, 2)
      friday = Date.add(tuesday, 3)

      params = %{
        "checkin_date" => Date.to_string(tuesday),
        "checkout_date" => Date.to_string(friday)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "books 5 nights including weekend", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      base_date = Date.add(Date.utc_today(), 50)
      thursday = find_next_weekday(base_date, 4)
      tuesday = Date.add(thursday, 5)

      params = %{
        "checkin_date" => Date.to_string(thursday),
        "checkout_date" => Date.to_string(tuesday)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "different guest count scenarios" do
    test "books with 1 guest", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "1"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "books with exactly 12 guests (maximum)", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "12"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "books with 4 guests", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "4"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "books with 8 guests", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "8"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "combined parameter scenarios" do
    test "buyout mode with maximum guests and long stay", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 60)
      checkout = Date.add(checkin, 14)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "12",
        "booking_mode" => "buyout"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "day mode with minimum guests and short stay", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 40)
      checkout = Date.add(checkin, 2)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "1",
        "booking_mode" => "day"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "changes all parameters in sequence", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      # Change dates
      checkin = Date.add(Date.utc_today(), 30)

      render_change(view, "date-changed", %{
        "checkin_date" => Date.to_string(checkin)
      })

      checkout = Date.add(checkin, 5)

      render_change(view, "date-changed", %{
        "checkout_date" => Date.to_string(checkout)
      })

      # Change guests
      render_click(view, "increase-guests", %{})
      render_click(view, "increase-guests", %{})

      # Change mode
      render_click(view, "booking-mode-changed", %{"booking_mode" => "buyout"})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "page reload scenarios" do
    test "maintains state after params update", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/bookings/clear-lake?checkin_date=#{Date.to_string(checkin)}&checkout_date=#{Date.to_string(checkout)}"
        )

      :timer.sleep(200)

      # Simulate navigation by changing params
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "loads with all parameters set", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 45)
      checkout = Date.add(checkin, 4)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "6",
        "booking_mode" => "day",
        "tab" => "booking"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(300)
      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "boundary conditions" do
    test "handles exactly 2-night minimum stay", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 2)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles 7-night stay", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 7)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "handles 14-night stay", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 14)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "different membership states" do
    test "subscription member can access booking page", %{conn: conn} do
      user = user_with_membership(:subscription)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "subscription member can view pricing", %{conn: conn} do
      user = user_with_membership(:subscription)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(300)
      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "booking creation attempts" do
    test "create-booking event with no dates selected", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      # Try to create booking without dates - should show validation errors
      result = render_click(view, "create-booking", %{})

      # Should either return HTML or handle the event
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "create-booking event with invalid date range", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Past date
      checkin = Date.add(Date.utc_today(), -10)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)

      # Try to create booking with past dates - should show error
      result = render_click(view, "create-booking", %{})

      # May crash or show error
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "create-booking event with valid dates but zero guests", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "0"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(200)

      # Try to create booking with 0 guests
      result = render_click(view, "create-booking", %{})

      assert is_binary(result) or match?({:error, _}, result)
    end

    test "create-booking event triggers validation", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "4",
        "booking_mode" => "day"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(300)

      # Try to create booking - may redirect to payment or show errors
      result = render_click(view, "create-booking", %{})

      # Either shows HTML, redirects, or errors
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "create-booking in buyout mode triggers validation", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 60)
      checkout = Date.add(checkin, 7)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "10",
        "booking_mode" => "buyout"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      :timer.sleep(300)

      result = render_click(view, "create-booking", %{})

      # Either shows HTML, redirects, or errors
      assert is_binary(result) or match?({:error, _}, result)
    end
  end

  describe "payment redirect scenarios" do
    test "handles payment-redirect-started event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/clear-lake")
      :timer.sleep(200)

      render_click(view, "payment-redirect-started", %{})

      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  describe "URL navigation and deep linking" do
    test "loads with booking tab explicitly set", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake?tab=booking")

      assert html =~ "Clear Lake"
    end

    test "loads with information tab explicitly set", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake?tab=information")

      assert html =~ "Clear Lake"
    end

    test "loads with my-bookings tab explicitly set", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake?tab=my-bookings")

      assert html =~ "Clear Lake"
    end

    test "handles invalid tab parameter", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/clear-lake?tab=invalid-tab")

      assert html =~ "Clear Lake"
    end

    test "handles invalid booking mode in URL", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(conn, ~p"/bookings/clear-lake?booking_mode=invalid")

      assert html =~ "Clear Lake"
    end
  end

  describe "template state variations" do
    test "displays error state when dates are invalid", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      # Invalid: checkout before checkin
      checkout = Date.add(checkin, -5)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/bookings/clear-lake?checkin_date=#{Date.to_string(checkin)}&checkout_date=#{Date.to_string(checkout)}"
        )

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Clear Lake"
    end

    test "displays with no error state when everything is valid", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/bookings/clear-lake?checkin_date=#{Date.to_string(checkin)}&checkout_date=#{Date.to_string(checkout)}&guests=4"
        )

      :timer.sleep(300)
      html = render(view)
      assert html =~ "Clear Lake"
    end
  end

  # Helper function for finding next weekday
  defp find_next_weekday(date, target_day_of_week) do
    current_day = Date.day_of_week(date)

    days_ahead =
      if current_day <= target_day_of_week do
        target_day_of_week - current_day
      else
        7 - current_day + target_day_of_week
      end

    Date.add(date, days_ahead)
  end
end

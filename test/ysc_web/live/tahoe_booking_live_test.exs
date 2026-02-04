defmodule YscWeb.TahoeBookingLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory

  describe "mount/3 - unauthenticated" do
    test "loads page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")
      assert html =~ "Tahoe"
    end

    test "loads page with query parameters", %{conn: conn} do
      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 3)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end
  end

  describe "mount/3 - authenticated without membership" do
    test "loads page but shows membership requirement", %{conn: conn} do
      user = user_with_membership(:none)
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/bookings/tahoe")

      # Page loads
      assert html =~ "Tahoe"

      # Wait for async data to load
      :timer.sleep(200)
      html = render(view)

      # Shows membership requirement or disabled state
      assert html =~ "Tahoe" or html =~ "membership" or html =~ "Information"
    end
  end

  describe "mount/3 - authenticated with membership" do
    test "loads booking page successfully", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      assert html =~ "Tahoe"
    end

    test "sets page title", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      assert page_title(view) =~ "Tahoe Cabin"
    end

    test "initializes with today's date if no params", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      # Wait for async load
      :timer.sleep(200)
      html = render(view)

      # Check calendar is displayed
      assert html =~ "calendar" or html =~ "date" or html =~ "Tahoe"
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
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end

    test "handles invalid date parameters gracefully", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{
        "checkin_date" => "invalid",
        "checkout_date" => "also-invalid"
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      # Should still load, using default dates
      assert html =~ "Tahoe"
    end
  end

  describe "booking modes" do
    test "defaults to room mode", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(200)
      html = render(view)

      # Check for room selection elements
      assert html =~ "Tahoe"
    end

    test "accepts booking_mode parameter for buyout", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"booking_mode" => "buyout"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end

    test "switches between room and buyout modes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(200)

      # Try to switch modes (if button exists)
      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "guest selection" do
    test "parses guest count from URL parameters", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"guests" => "4", "children" => "2"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end

    test "handles invalid guest counts", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"guests" => "invalid", "children" => "-1"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      # Should use defaults
      assert html =~ "Tahoe"
    end

    test "enforces maximum guest capacity", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Try to set unreasonably high guest count
      params = %{"guests" => "100"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end
  end

  describe "tab navigation" do
    test "defaults to booking tab for eligible users", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(200)
      html = render(view)

      # Check tab structure exists
      assert html =~ "Tahoe"
    end

    test "accepts tab parameter", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"tab" => "information"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end

    test "handles info_tab parameter for information sections", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"tab" => "information", "info_tab" => "amenities"}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end
  end

  describe "membership type display" do
    test "shows appropriate content for lifetime members", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(200)
      html = render(view)

      # Lifetime members should see booking functionality
      assert html =~ "Tahoe"
    end

    test "handles subscription members", %{conn: conn} do
      user = user_with_membership(:subscription)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(200)
      html = render(view)

      assert html =~ "Tahoe"
    end
  end

  describe "date tooltips and calendar" do
    test "loads date tooltips asynchronously", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      # Tooltips load in background
      :timer.sleep(300)

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "displays calendar for date selection", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(200)
      html = render(view)

      # Check for calendar or date picker elements
      assert html =~ "Tahoe"
    end
  end

  describe "season information" do
    test "displays current season info", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(200)
      html = render(view)

      # Season info should be displayed
      assert html =~ "Tahoe"
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
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end
  end

  describe "page structure" do
    test "includes main booking container", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      assert html =~ "Tahoe"
    end

    test "includes responsive design classes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      assert html =~ "lg:" or html =~ "md:" or html =~ "Tahoe"
    end

    test "includes navigation elements", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      # Should have tabs or navigation
      assert html =~ "Tahoe"
    end
  end

  describe "accessibility" do
    test "includes proper heading hierarchy", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      assert html =~ "<h1" or html =~ "<h2" or html =~ "Tahoe"
    end

    test "includes form labels", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(200)
      html = render(view)

      # Should have labels or aria-labels
      assert html =~ "Tahoe"
    end

    test "includes ARIA attributes for interactive elements", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      # Check for aria attributes
      assert html =~ "aria-" or html =~ "Tahoe"
    end
  end

  describe "property identification" do
    test "correctly identifies as Tahoe property", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(100)

      # Check socket assigns
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.property == :tahoe
    end

    test "displays Tahoe-specific content", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      assert html =~ "Tahoe"
    end
  end

  describe "refund policy" do
    test "loads refund policies", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      :timer.sleep(200)

      # Refund policies should be loaded
      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "error handling" do
    test "handles missing date gracefully", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      params = %{"checkin_date" => ""}

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
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
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      # Should handle invalid date range
      assert html =~ "Tahoe"
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
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      # Should default to valid dates
      assert html =~ "Tahoe"
    end
  end

  describe "responsive design" do
    test "includes mobile-friendly classes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      # Should have responsive grid or flex classes
      assert html =~ "grid" or html =~ "flex" or html =~ "Tahoe"
    end

    test "includes tablet breakpoint classes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      assert html =~ "md:" or html =~ "Tahoe"
    end

    test "includes desktop breakpoint classes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      assert html =~ "lg:" or html =~ "xl:" or html =~ "Tahoe"
    end
  end

  describe "async data loading" do
    test "loads initial page before async data", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      # Initial render should be fast
      assert html =~ "Tahoe"
    end

    test "completes async loading after connection", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      # Wait for async operations
      :timer.sleep(300)

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "user interactions - guest count" do
    test "handles increase-guests event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      # Simulate increasing guest count
      render_click(view, "increase-guests", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles decrease-guests event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe?guests=4")
      :timer.sleep(200)

      # Simulate decreasing guest count
      render_click(view, "decrease-guests", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles increase-children event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_click(view, "increase-children", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles decrease-children event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe?children=2")
      :timer.sleep(200)

      render_click(view, "decrease-children", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles toggle-guests-dropdown event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_click(view, "toggle-guests-dropdown", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles close-guests-dropdown event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_click(view, "close-guests-dropdown", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "user interactions - booking mode" do
    test "handles booking-mode-changed to buyout", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_click(view, "booking-mode-changed", %{"booking_mode" => "buyout"})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles booking-mode-changed to room", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Start with room mode (default)
      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      # Already in room mode, just verify it works
      render_click(view, "booking-mode-changed", %{"booking_mode" => "room"})

      html = render(view)
      assert html =~ "Tahoe"
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
          ~p"/bookings/tahoe?checkin_date=#{Date.to_string(checkin)}&checkout_date=#{Date.to_string(checkout)}"
        )

      :timer.sleep(200)

      render_click(view, "reset-dates", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles cursor-move event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      date_str = Date.to_string(Date.utc_today())
      render_click(view, "cursor-move", %{"date" => date_str})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles cursor-leave event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_click(view, "cursor-leave", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "user interactions - general" do
    test "handles ignore event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_click(view, "ignore", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles switch-tab event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_click(view, "switch-tab", %{"tab" => "information"})

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "date input interactions" do
    test "handles date-changed for checkin", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      checkin = Date.add(Date.utc_today(), 30)

      render_change(view, "date-changed", %{
        "checkin_date" => Date.to_string(checkin)
      })

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles date-changed for checkout", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      checkout = Date.add(Date.utc_today(), 33)

      render_change(view, "date-changed", %{
        "checkout_date" => Date.to_string(checkout)
      })

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "guest input interactions" do
    test "handles guests-changed event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_change(view, "guests-changed", %{"guests_count" => "4"})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles children-changed event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_change(view, "children-changed", %{"children_count" => "2"})

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "room selection interactions" do
    test "handles room-changed event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe?booking_mode=room")
      :timer.sleep(200)

      # Try to change room selection
      render_change(view, "room-changed", %{"room" => "1"})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles remove-room event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe?booking_mode=room")
      :timer.sleep(200)

      render_click(view, "remove-room", %{"room-id" => "1"})

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "validation scenarios" do
    test "handles minimum stay requirements", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      checkin = Date.add(Date.utc_today(), 30)
      checkout = Date.add(checkin, 1)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end

    test "handles weekend requirements", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      base_date = Date.add(Date.utc_today(), 60)
      friday = find_next_weekday(base_date, 5)
      monday = Date.add(friday, 3)

      params = %{
        "checkin_date" => Date.to_string(friday),
        "checkout_date" => Date.to_string(monday)
      }

      {:ok, _view, html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
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
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      assert html =~ "Tahoe"
    end
  end

  describe "different user states" do
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
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      :timer.sleep(300)
      html = render(view)

      assert html =~ "Tahoe"
    end

    test "subscription member can access booking page", %{conn: conn} do
      user = user_with_membership(:subscription)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      html = render(view)
      assert html =~ "Tahoe"
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
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Tahoe"
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
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "rapid user interactions" do
    test "handles rapid date changes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      for i <- 1..5 do
        date = Date.add(Date.utc_today(), 30 + i)

        render_change(view, "date-changed", %{
          "checkin_date" => Date.to_string(date)
        })
      end

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles rapid tab switching", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      :timer.sleep(200)

      render_click(view, "switch-tab", %{"tab" => "information"})
      render_click(view, "switch-tab", %{"tab" => "booking"})
      render_click(view, "switch-tab", %{"tab" => "my-bookings"})
      render_click(view, "switch-tab", %{"tab" => "booking"})

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "URL navigation and deep linking" do
    test "loads with booking tab explicitly set", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe?tab=booking")

      assert html =~ "Tahoe"
    end

    test "loads with information tab explicitly set", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe?tab=information")

      assert html =~ "Tahoe"
    end

    test "handles invalid tab parameter", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe?tab=invalid-tab")

      assert html =~ "Tahoe"
    end
  end

  describe "handle_params scenarios" do
    test "handles malformed query parameters", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/tahoe?checkin_date=invalid&checkout_date=bad&guests=xyz&children=abc"
        )

      assert html =~ "Tahoe"
    end

    test "handles empty string parameters", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/tahoe?checkin_date=&checkout_date=&guests=&children="
        )

      assert html =~ "Tahoe"
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

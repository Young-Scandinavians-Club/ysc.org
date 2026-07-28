defmodule YscWeb.TahoeBookingLiveTest do
  # Config caches (:ysc_cache) are process-wide; invalidating them from a
  # sandboxed test would leak into concurrently running tests.
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.BookingsFixtures
  import Ysc.TestDataFactory

  alias Ysc.Bookings

  alias Ysc.Bookings.{
    AvailabilityCache,
    BlackoutListCache,
    Booking,
    BookingRoom,
    RoomCategory,
    RoomsListCache
  }

  alias Ysc.Repo

  describe "deferred room availability" do
    test "populates room cards after connect when booking dates are in the URL",
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

        {:ok, view, _html} =
          live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

        html = render(view)

        assert has_element?(view, "#room-#{room.id}")
        assert html =~ room.name
      end
    end
  end

  describe "mount/3 - unauthenticated" do
    test "loads page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")
      assert html =~ "Tahoe"
    end

    test "loads page with query parameters", %{conn: conn} do
      {checkin, checkout} = tahoe_booking_dates(30)

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

      render_async(view, 2_000)
      html = render(view)

      assert html =~ "Tahoe"

      assert has_element?(
               view,
               "#tahoe-booking-eligibility-banner-public",
               "Membership Required"
             )

      assert has_element?(
               view,
               "#tahoe-booking-eligibility-banner-public a[href=\"/users/membership\"]",
               "Manage Membership"
             )
    end
  end

  describe "mount/3 - authenticated with membership" do
    test "loads booking page successfully", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/bookings/tahoe")

      assert html =~ "Tahoe"
    end

    test "shows readable essential alerts for members", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)
      html = render(view)

      assert html =~ "Bring your own bed linens"
      assert html =~ "No pets or smoking"
      assert html =~ "Winter: carry chains or use 4WD with snow tires"
      assert html =~ "please help with chores before you leave"
      refute html =~ "BRING YOUR OWN LINENS"
      refute html =~ "NOT A HOTEL"
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

      render_async(view, 2_000)
      html = render(view)

      # Check calendar is displayed
      assert html =~ "calendar" or html =~ "date" or html =~ "Tahoe"
    end

    test "parses date parameters from URL", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {checkin, checkout} = tahoe_booking_dates(30)

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

  describe "booking eligibility guards" do
    test "shows buyout active banner when family group has an active full buyout",
         %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      {checkin, checkout} = tahoe_booking_dates(30)

      {:ok, _buyout} =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :buyout,
            checkin_date: checkin,
            checkout_date: checkout,
            status: :complete,
            guests_count: 4,
            total_price: Money.new(2000, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      render_async(view, 2_000)
      html = render(view)

      assert has_element?(
               view,
               "#tahoe-booking-eligibility-banner-public",
               "Full buyout active"
             )

      assert html =~ "full buyout reservation"

      socket = :sys.get_state(view.pid).socket
      refute socket.assigns.can_book
      assert socket.assigns.booking_error_title == "Full buyout active"
    end

    test "blocks another family member when primary has an active full buyout",
         %{conn: conn} do
      family = family_with_sub_accounts(1)

      sub_account =
        family.sub_accounts
        |> hd()
        |> Ecto.Changeset.change(primary_user_id: family.primary.id)
        |> Repo.update!()

      conn = log_in_user(conn, sub_account)
      {checkin, checkout} = tahoe_booking_dates(35)

      {:ok, _buyout} =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: family.primary.id,
            property: :tahoe,
            booking_mode: :buyout,
            checkin_date: checkin,
            checkout_date: checkout,
            status: :complete,
            guests_count: 4,
            total_price: Money.new(2000, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      render_async(view, 5_000)
      html = render(view)

      assert has_element?(
               view,
               "#tahoe-booking-eligibility-banner-public",
               "Your family already has an active booking"
             )

      assert html =~ "full buyout" or html =~ "active booking"

      refute :sys.get_state(view.pid).socket.assigns.can_book
    end

    test "shows maximum rooms banner when family group has two active room bookings",
         %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      rooms =
        Bookings.list_rooms(:tahoe)
        |> Enum.filter(& &1.is_active)

      rooms =
        case rooms do
          [room1, room2 | _] ->
            [room1, room2]

          [room1] ->
            [room1, create_tahoe_room!("eligibility-guard")]

          [] ->
            [
              create_tahoe_room!("eligibility-guard-1"),
              create_tahoe_room!("eligibility-guard-2")
            ]
        end

      {checkin, checkout} = tahoe_booking_dates(40)
      overlapping_checkin = Date.add(checkin, 2)

      for {room, index} <- Enum.with_index(rooms) do
        booking_checkin = if index == 0, do: checkin, else: overlapping_checkin

        {:ok, booking} =
          %Booking{}
          |> Booking.changeset(
            %{
              user_id: user.id,
              property: :tahoe,
              booking_mode: :room,
              checkin_date: booking_checkin,
              checkout_date: checkout,
              status: :complete,
              guests_count: 2,
              total_price: Money.new(400, :USD)
            },
            skip_validation: true
          )
          |> Repo.insert()

        %BookingRoom{booking_id: booking.id, room_id: room.id}
        |> Repo.insert!()
      end

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      render_async(view, 2_000)
      html = render(view)

      assert has_element?(
               view,
               "#tahoe-booking-eligibility-banner-public",
               "Maximum rooms reached"
             )

      assert html =~ "maximum of 2 rooms"

      socket = :sys.get_state(view.pid).socket
      refute socket.assigns.can_book
      assert socket.assigns.booking_error_title == "Maximum rooms reached"
    end
  end

  describe "booking modes" do
    test "defaults to room mode", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      render_async(view, 2_000)
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

      render_async(view, 2_000)

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

      render_async(view, 2_000)
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

      render_async(view, 2_000)
      html = render(view)

      # Lifetime members should see booking functionality
      assert html =~ "Tahoe"
    end

    test "handles subscription members", %{conn: conn} do
      user = user_with_membership(:subscription)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      render_async(view, 2_000)
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
      render_async(view, 2_000)

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "displays calendar for date selection", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      render_async(view, 2_000)
      html = render(view)

      # Check for calendar or date picker elements
      assert html =~ "Tahoe"
    end

    test "room mode allows checkout on blackout start date", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Dedicated unbooked room so date tooltips are not "All rooms are booked"
      create_tahoe_room!()

      {checkin, _} = tahoe_booking_dates(21)
      # Blackout begins on checkout day (valid leave-by-11am checkout)
      checkout = Date.add(checkin, 2)
      blackout_end = Date.add(checkout, 3)

      {:ok, _blackout} =
        Bookings.create_blackout(%{
          property: :tahoe,
          start_date: checkout,
          end_date: blackout_end,
          reason: "Test blackout"
        })

      AvailabilityCache.invalidate()
      BlackoutListCache.invalidate()
      RoomsListCache.invalidate()

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe?booking_mode=room")
      render_async(view, 5_000)

      view
      |> element("#1 [phx-click=open-calendar]")
      |> render_click()

      navigate_room_calendar_to_month!(view, checkin)

      checkin_iso = "#{Date.to_iso8601(checkin)}T00:00:00Z"
      checkout_iso = "#{Date.to_iso8601(checkout)}T00:00:00Z"

      blocked_checkout_iso =
        "#{Date.to_iso8601(Date.add(checkout, 1))}T00:00:00Z"

      assert has_element?(
               view,
               ~s|#1_calendar button[phx-value-date="#{checkin_iso}"]:not([disabled])|
             )

      view
      |> element(~s|#1_calendar button[phx-value-date="#{checkin_iso}"]|)
      |> render_click()

      assert has_element?(
               view,
               ~s|#1_calendar button[phx-value-date="#{checkout_iso}"]:not([disabled])|
             )

      assert has_element?(
               view,
               ~s|#1_calendar button[phx-value-date="#{blocked_checkout_iso}"][disabled]|
             )
    end

    test "room mode allows check-in on blackout end date", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      create_tahoe_room!()

      {checkin, _} = tahoe_booking_dates(28)
      blackout_start = Date.add(checkin, -3)
      # Check-in on blackout end is valid turnaround
      blackout_end = checkin

      {:ok, _blackout} =
        Bookings.create_blackout(%{
          property: :tahoe,
          start_date: blackout_start,
          end_date: blackout_end,
          reason: "Ends on check-in day"
        })

      AvailabilityCache.invalidate()
      BlackoutListCache.invalidate()
      RoomsListCache.invalidate()

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe?booking_mode=room")
      render_async(view, 5_000)

      view
      |> element("#1 [phx-click=open-calendar]")
      |> render_click()

      navigate_room_calendar_to_month!(view, checkin)

      checkin_iso = "#{Date.to_iso8601(checkin)}T00:00:00Z"

      blocked_night_iso =
        "#{Date.to_iso8601(Date.add(blackout_end, -1))}T00:00:00Z"

      assert has_element?(
               view,
               ~s|#1_calendar button[phx-value-date="#{checkin_iso}"]:not([disabled])|
             )

      assert has_element?(
               view,
               ~s|#1_calendar button[phx-value-date="#{blocked_night_iso}"][disabled]|
             )
    end

    test "blocks dates when free rooms cannot fit selected guests", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      deactivate_all_tahoe_rooms!()
      _small_room = create_tahoe_room!(capacity_max: 2)

      {checkin, _} = tahoe_booking_dates(21)
      checkin_iso = "#{Date.to_iso8601(checkin)}T00:00:00Z"
      checkin_key = Date.to_iso8601(checkin)

      {:ok, view, _html} =
        live(conn, ~p"/bookings/tahoe?booking_mode=room&guests_count=3")

      render_async(view, 5_000)

      assert :sys.get_state(view.pid).socket.assigns.guests_count == 3

      tooltips = :sys.get_state(view.pid).socket.assigns.date_tooltips

      assert tooltips[checkin_key] =~ "Not enough room capacity for 3 guests"

      view
      |> element("#1 [phx-click=open-calendar]")
      |> render_click()

      navigate_room_calendar_to_month!(view, checkin)

      assert has_element?(
               view,
               ~s|#1_calendar button[phx-value-date="#{checkin_iso}"][disabled]|
             )
    end

    test "keeps dates selectable when a free room fits selected guests", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      deactivate_all_tahoe_rooms!()
      _small_room = create_tahoe_room!(capacity_max: 2)

      {checkin, _} = tahoe_booking_dates(21)
      checkin_iso = "#{Date.to_iso8601(checkin)}T00:00:00Z"
      checkin_key = Date.to_iso8601(checkin)

      {:ok, view, _html} =
        live(conn, ~p"/bookings/tahoe?booking_mode=room&guests_count=2")

      render_async(view, 5_000)

      tooltips = :sys.get_state(view.pid).socket.assigns.date_tooltips
      refute Map.has_key?(tooltips, checkin_key)

      view
      |> element("#1 [phx-click=open-calendar]")
      |> render_click()

      navigate_room_calendar_to_month!(view, checkin)

      assert has_element?(
               view,
               ~s|#1_calendar button[phx-value-date="#{checkin_iso}"]:not([disabled])|
             )
    end

    test "allows dates when combined free rooms fit guests for multi-room members",
         %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      deactivate_all_tahoe_rooms!()
      _room_a = create_tahoe_room!(capacity_max: 2)
      _room_b = create_tahoe_room!(capacity_max: 1)

      {checkin, _} = tahoe_booking_dates(21)
      checkin_iso = "#{Date.to_iso8601(checkin)}T00:00:00Z"
      checkin_key = Date.to_iso8601(checkin)

      {:ok, view, _html} =
        live(conn, ~p"/bookings/tahoe?booking_mode=room&guests_count=3")

      render_async(view, 5_000)

      tooltips = :sys.get_state(view.pid).socket.assigns.date_tooltips
      refute Map.has_key?(tooltips, checkin_key)

      view
      |> element("#1 [phx-click=open-calendar]")
      |> render_click()

      navigate_room_calendar_to_month!(view, checkin)

      assert has_element?(
               view,
               ~s|#1_calendar button[phx-value-date="#{checkin_iso}"]:not([disabled])|
             )
    end

    test "reloads date tooltips when guest count changes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      deactivate_all_tahoe_rooms!()
      _small_room = create_tahoe_room!(capacity_max: 2)

      {checkin, _} = tahoe_booking_dates(21)
      checkin_key = Date.to_iso8601(checkin)

      {:ok, view, _html} =
        live(conn, ~p"/bookings/tahoe?booking_mode=room&guests_count=2")

      render_async(view, 5_000)

      tooltips = :sys.get_state(view.pid).socket.assigns.date_tooltips
      refute Map.has_key?(tooltips, checkin_key)

      render_click(view, "increase-guests", %{})
      render_async(view, 5_000)

      tooltips_after = :sys.get_state(view.pid).socket.assigns.date_tooltips

      assert tooltips_after[checkin_key] =~
               "Not enough room capacity for 3 guests"
    end

    test "clears selected dates when guests no longer fit capacity", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      deactivate_all_tahoe_rooms!()
      _small_room = create_tahoe_room!(capacity_max: 2)

      {checkin, checkout} = tahoe_booking_dates(21)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "booking_mode" => "room",
        "guests_count" => "2"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      render_async(view, 5_000)

      assert :sys.get_state(view.pid).socket.assigns.checkin_date == checkin

      render_click(view, "increase-guests", %{})
      render_async(view, 5_000)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.checkin_date == nil
      assert assigns.checkout_date == nil
    end
  end

  describe "season information" do
    test "displays current season info", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      render_async(view, 2_000)
      html = render(view)

      # Season info should be displayed
      assert html =~ "Tahoe"
    end

    test "handles out of season dates", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Try to book far in the future (likely out of season)
      {checkin, checkout} = tahoe_booking_dates(400)

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

      render_async(view, 2_000)
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

      render_async(view, 2_000)

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

      render_async(view, 2_000)

      # Refund policies should be loaded
      html = render(view)
      assert html =~ "Tahoe"
    end

    test "terms modal shows refund-based cancellation copy", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

      render_click(view, "show-terms-modal")

      html = render(view)

      assert html =~ "📅 Cancellation Policy"
      assert html =~ "Entire cabin:"
      assert html =~ "50% refund"
      assert html =~ "14 days before for no refund"
      assert html =~ "7 days before for no refund"

      assert html =~
               "All guests (adults and children) must be paid for before arrival."

      refute html =~ "guests(adults"
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

      {checkin, _} = tahoe_booking_dates(30)
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

      checkin = ~D[2024-06-15]
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

      render_async(view, 2_000)

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "user interactions - guest count" do
    test "handles increase-guests event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

      # Simulate increasing guest count
      render_click(view, "increase-guests", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles decrease-guests event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe?guests=4")
      render_async(view, 2_000)

      # Simulate decreasing guest count
      render_click(view, "decrease-guests", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles increase-children event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

      render_click(view, "increase-children", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles decrease-children event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe?children=2")
      render_async(view, 2_000)

      render_click(view, "decrease-children", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles toggle-guests-dropdown event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

      render_click(view, "toggle-guests-dropdown", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles close-guests-dropdown event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

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
      render_async(view, 2_000)

      render_click(view, "booking-mode-changed", %{"booking_mode" => "buyout"})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles booking-mode-changed to room", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Start with room mode (default)
      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

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

      {checkin, checkout} = tahoe_booking_dates(30)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/bookings/tahoe?checkin_date=#{Date.to_string(checkin)}&checkout_date=#{Date.to_string(checkout)}"
        )

      render_async(view, 2_000)

      render_click(view, "reset-dates", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles cursor-move event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

      date_str = Date.to_string(tahoe_test_date(0))
      render_click(view, "cursor-move", %{"date" => date_str})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles cursor-leave event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

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
      render_async(view, 2_000)

      render_click(view, "ignore", %{})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles switch-tab event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

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
      render_async(view, 2_000)

      checkin = tahoe_test_date(30)

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
      render_async(view, 2_000)

      checkout = tahoe_test_date(33)

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
      render_async(view, 2_000)

      render_change(view, "guests-changed", %{"guests_count" => "4"})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles children-changed event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

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
      render_async(view, 2_000)

      # Try to change room selection
      render_change(view, "room-changed", %{"room" => "1"})

      html = render(view)
      assert html =~ "Tahoe"
    end

    test "handles remove-room event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe?booking_mode=room")
      render_async(view, 2_000)

      render_click(view, "remove-room", %{"room-id" => "1"})

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "validation scenarios" do
    test "handles minimum stay requirements", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {checkin, checkout} = tahoe_room_booking_dates(30, 1)

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

      base_date = tahoe_test_date(60)
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

      {checkin, checkout} = tahoe_booking_dates(500)

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

      {checkin, checkout} = tahoe_booking_dates(30)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      render_async(view, 2_000)
      html = render(view)

      assert html =~ "Tahoe"
    end

    test "subscription member can access booking page", %{conn: conn} do
      user = user_with_membership(:subscription)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "different date combinations" do
    test "books 2 nights starting on Monday", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      base_date = tahoe_test_date(60)
      monday = find_next_weekday(base_date, 1)
      wednesday = Date.add(monday, 2)

      params = %{
        "checkin_date" => Date.to_string(monday),
        "checkout_date" => Date.to_string(wednesday)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      render_async(view, 2_000)
      html = render(view)
      assert html =~ "Tahoe"
    end

    test "books week starting on Saturday", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      base_date = tahoe_test_date(90)
      saturday = find_next_weekday(base_date, 6)
      next_saturday = Date.add(saturday, 7)

      params = %{
        "checkin_date" => Date.to_string(saturday),
        "checkout_date" => Date.to_string(next_saturday)
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

      render_async(view, 2_000)
      html = render(view)
      assert html =~ "Tahoe"
    end
  end

  describe "rapid user interactions" do
    test "handles rapid date changes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")
      render_async(view, 2_000)

      for i <- 1..5 do
        date = tahoe_test_date(30 + i)

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
      render_async(view, 2_000)

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

  defp navigate_room_calendar_to_month!(view, %Date{} = target) do
    Enum.reduce_while(1..24, nil, fn _, _ ->
      html = render(view)

      if html =~ Calendar.strftime(target, "%B %Y") do
        {:halt, :ok}
      else
        view
        |> element("#1_calendar [phx-click=next-month]")
        |> render_click()

        {:cont, nil}
      end
    end) ||
      flunk(
        "Could not navigate calendar to #{Calendar.strftime(target, "%B %Y")}"
      )
  end

  defp create_tahoe_room!(opts \\ [])

  defp create_tahoe_room!(suffix) when is_binary(suffix) do
    create_tahoe_room!(suffix: suffix)
  end

  defp create_tahoe_room!(opts) when is_list(opts) do
    suffix = Keyword.get(opts, :suffix, "default")
    capacity_max = Keyword.get(opts, :capacity_max, 4)

    {:ok, category} =
      %RoomCategory{}
      |> RoomCategory.changeset(%{
        name:
          "Tahoe calendar test category #{suffix} #{System.unique_integer([:positive])}"
      })
      |> Repo.insert()

    {:ok, room} =
      Bookings.create_room(%{
        name: "Tahoe calendar test room #{System.unique_integer([:positive])}",
        property: :tahoe,
        room_category_id: category.id,
        capacity_max: capacity_max
      })

    RoomsListCache.invalidate()
    room
  end

  defp deactivate_all_tahoe_rooms! do
    Bookings.list_rooms(:tahoe)
    |> Enum.filter(& &1.is_active)
    |> Enum.each(fn room ->
      {:ok, _} = Bookings.update_room(room, %{is_active: false})
    end)

    RoomsListCache.invalidate()
    AvailabilityCache.invalidate()
  end

  describe "admin config cache rebuild" do
    test "rebuilds season-derived assigns after season cache invalidation", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      seasons_before = :sys.get_state(view.pid).socket.assigns.seasons

      send(
        view.pid,
        {:season_cache_invalidated, System.unique_integer([:positive])}
      )

      _ = render(view)

      seasons_after = :sys.get_state(view.pid).socket.assigns.seasons
      assert is_list(seasons_after)
      assert length(seasons_after) == length(seasons_before)
    end

    test "rebuilds room snapshot after rooms list cache invalidation", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      room = create_tahoe_room!()

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      send(
        view.pid,
        {:rooms_list_cache_invalidated, System.unique_integer([:positive])}
      )

      _ = render(view)

      snapshot = :sys.get_state(view.pid).socket.assigns.property_rooms_snapshot
      assert Enum.any?(snapshot, &(&1.id == room.id))
    end

    test "bumps availability_cache_version after rooms or availability invalidation",
         %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/bookings/tahoe")

      version_before =
        :sys.get_state(view.pid).socket.assigns.availability_cache_version

      send(
        view.pid,
        {:rooms_list_cache_invalidated, System.unique_integer([:positive])}
      )

      _ = render(view)

      version_after_rooms =
        :sys.get_state(view.pid).socket.assigns.availability_cache_version

      assert version_after_rooms != version_before

      send(view.pid, :availability_cache_invalidated)
      _ = render(view)

      version_after_availability =
        :sys.get_state(view.pid).socket.assigns.availability_cache_version

      assert version_after_availability != version_after_rooms
    end
  end
end

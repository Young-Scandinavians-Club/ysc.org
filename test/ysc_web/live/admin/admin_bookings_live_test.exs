defmodule YscWeb.Admin.AdminBookingsLiveTest do
  @moduledoc """
  Tests for AdminBookingsLive — admin booking management (calendar, reservations,
  configuration, pending refunds).
  """
  use YscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings
  alias Ysc.Bookings.Booking
  alias Ysc.Bookings.PendingRefund
  alias Ysc.Ledgers
  alias Ysc.Repo

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp section_label("calendar"), do: "Calendar"
  defp section_label("config"), do: "Configuration"
  defp section_label("pending_refunds"), do: "Pending Refunds"
  defp section_label("reservations"), do: "Reservations"

  defp day_capacity_booked_for(property, days) do
    alias Ysc.Bookings.PropertyInventory

    days
    |> Enum.map(fn day ->
      Repo.one!(
        from(pi in PropertyInventory,
          where: pi.property == ^property and pi.day == ^day,
          select: pi.capacity_booked
        )
      )
    end)
  end

  defp day_capacity_held_for(property, days) do
    alias Ysc.Bookings.PropertyInventory

    days
    |> Enum.map(fn day ->
      Repo.one!(
        from(pi in PropertyInventory,
          where: pi.property == ^property and pi.day == ^day,
          select: pi.capacity_held
        )
      )
    end)
  end

  defp insert_pending_refund!(property) do
    user = user_fixture()
    booking = booking_fixture(%{user_id: user.id, property: property})

    {:ok, booking} =
      booking
      |> Ecto.Changeset.change(%{status: :complete})
      |> Repo.update()

    {:ok, {payment, _, _}} =
      Ledgers.process_payment(%{
        user_id: user.id,
        amount: booking.total_price,
        entity_type: :booking,
        entity_id: booking.id,
        external_payment_id:
          "pi_admin_bk_#{System.unique_integer([:positive])}",
        stripe_fee: Money.new(100, :USD),
        description: "Booking payment",
        property: booking.property,
        payment_method_id: nil
      })

    {:ok, pr} =
      %PendingRefund{}
      |> PendingRefund.changeset(%{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(1000, :USD),
        status: :pending
      })
      |> Repo.insert()

    {pr, booking}
  end

  describe "access control" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/bookings")

      assert path =~ "/users/log"
    end

    test "redirects regular members to home", %{conn: conn} do
      member = user_fixture()
      conn = log_in_user(conn, member)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/bookings")

      assert path == ~p"/"
    end

    test "redirects volunteers to admin home (full admin only)", %{conn: conn} do
      volunteer = user_fixture(%{role: "volunteer"})
      conn = log_in_user(conn, volunteer)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/bookings")

      assert path == ~p"/admin"
    end
  end

  describe "mount and sections" do
    setup [:create_admin]

    test "renders bookings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/bookings")
      assert html =~ "Bookings"
      assert html =~ "Calendar"
    end

    test "loads reservations section from query param", %{conn: conn} do
      {:ok, view, html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      assert html =~ "All Reservations"
      assert render(view) =~ "All Reservations"
    end

    test "loads configuration section from query param", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings?section=config")
      assert render(view) =~ "Door Codes"
      assert render(view) =~ "Seasons"
    end

    test "loads pending refunds section", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=pending_refunds")

      assert render(view) =~ "Pending Refunds"
      assert render(view) =~ "No pending refunds at this time"
    end

    test "filters by property via URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings?property=clear_lake")
      assert render(view) =~ "Clear Lake"
    end

    test "preserves calendar range from URL params", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=tahoe&from_date=2030-01-01&to_date=2030-01-31"
        )

      html = render(view)
      assert html =~ "01/01"
      assert html =~ "01/31"
    end
  end

  describe "deferred data loading" do
    setup [:create_admin]

    test "reservations section replaces loading placeholder with the table", %{
      conn: conn
    } do
      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      html = render(view)

      refute html =~ "Loading reservations…"
      assert has_element?(view, "#admin_reservations_list")
      refute has_element?(view, "#reservations-loading")
    end

    test "switching to reservations section loads the table after connect", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings?property=tahoe")

      view
      |> element("button[phx-value-section=reservations]", "Reservations")
      |> render_click()

      html = render(view)

      refute html =~ "Loading reservations…"
      assert has_element?(view, "#admin_reservations_list")
    end

    test "initial calendar mount issues at most one seasons query after connect",
         %{conn: conn} do
      seasons_pattern = ~r/FROM "seasons"/i

      {{:ok, view, _initial_html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, initial_html} =
              live(conn, ~p"/admin/bookings?property=tahoe")

            Ysc.QueryCounter.track_caller_pid(view.pid)
            render(view)
            {:ok, view, initial_html}
          end,
          pattern: seasons_pattern,
          caller_pids: [self()]
        )

      assert query_count <= 1
      assert render(view) =~ "Calendar"
    end

    test "initial reservations mount skips seasons and pricing reference queries",
         %{conn: conn} do
      reference_pattern =
        ~r/FROM "(seasons|pricing_rules|refund_policies|rooms|room_categories|door_codes)"/i

      {{:ok, view, _initial_html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, initial_html} =
              live(
                conn,
                ~p"/admin/bookings?property=tahoe&section=reservations"
              )

            Ysc.QueryCounter.track_caller_pid(view.pid)
            render(view)
            {:ok, view, initial_html}
          end,
          pattern: reference_pattern,
          caller_pids: [self()]
        )

      assert query_count == 0
      assert has_element?(view, "#admin_reservations_list")
    end

    test "switching to calendar from reservations lazy-loads reference data",
         %{conn: conn} do
      unique = "LazyCal#{System.unique_integer([:positive])}"

      {:ok, _room} =
        %Ysc.Bookings.Room{}
        |> Ysc.Bookings.Room.changeset(%{
          name: unique,
          property: :tahoe,
          capacity_max: 2,
          is_active: true
        })
        |> Repo.insert()

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      refute render(view) =~ "Calendar Overview"

      view
      |> element("button[phx-value-section=calendar]", "Calendar")
      |> render_click()

      html = render(view)
      assert html =~ "Calendar Overview"
      assert html =~ unique
    end

    test "configuration section shows only pricing rules for selected property",
         %{conn: conn} do
      _tahoe_rule =
        insert_pricing_rule!(%{property: :tahoe, amount: Money.new(111, :USD)})

      _clear_lake_rule =
        insert_pricing_rule!(%{
          property: :clear_lake,
          amount: Money.new(222, :USD)
        })

      {:ok, view, _html} = live(conn, ~p"/admin/bookings?property=tahoe")

      view
      |> element("button[phx-value-section=config]", "Configuration")
      |> render_click()

      html = render(view)
      assert html =~ "$111.00"
      refute html =~ "$222.00"

      view
      |> element("a[href*=\"property=clear_lake\"]", "Clear Lake")
      |> render_click()

      html = render(view)
      assert html =~ "$222.00"
      refute html =~ "$111.00"
    end

    test "select-property skips calendar reload when not on calendar section",
         %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=config")

      html =
        render_click(view, "select-property", %{"property" => "clear_lake"})

      assert html =~ "Configuration"
      refute html =~ "Calendar Overview"
    end
  end

  describe "navigation and calendar controls" do
    setup [:create_admin]

    test "switches section tabs via select-section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings")

      view
      |> element("button[phx-value-section=reservations]", "Reservations")
      |> render_click()

      assert_patch(view)

      view
      |> element("button[phx-value-section=config]", "Configuration")
      |> render_click()

      assert_patch(view)

      view
      |> element("button[phx-value-section=calendar]", "Calendar")
      |> render_click()

      assert_patch(view)
    end

    test "switches property tab to Clear Lake", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings?property=tahoe")

      view
      |> element("a[href*=\"property=clear_lake\"]", "Clear Lake")
      |> render_click()

      assert_patched(view, ~p"/admin/bookings?property=clear_lake")
    end

    test "prev-month shifts calendar range", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=tahoe&from_date=2030-06-01&to_date=2030-06-30"
        )

      view
      |> element("button[title=\"Previous 30 days\"]")
      |> render_click()

      assert_patch(view)
    end

    test "next-month shifts calendar range", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=tahoe&from_date=2030-06-01&to_date=2030-06-30"
        )

      view
      |> element("button[title=\"Next 30 days\"]")
      |> render_click()

      assert_patch(view)
    end

    test "today resets range to default window", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=tahoe&from_date=2030-06-01&to_date=2030-06-30"
        )

      view
      |> element("button[title=\"Go to current month\"]")
      |> render_click()

      assert_patch(view)
      assert render(view) =~ "Calendar Overview"
    end

    test "update-calendar-range form patches URL", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=tahoe&from_date=2030-01-01&to_date=2030-01-20"
        )

      view
      |> form("form[phx-change=update-calendar-range]", %{
        "from_date" => "2030-02-01",
        "to_date" => "2030-02-28"
      })
      |> render_change()

      assert_patch(view)
    end
  end

  describe "calendar booking continuation indicators" do
    setup [:create_admin]

    # Bypass season/advance-booking rules so dates are fully deterministic.
    defp insert_tahoe_buyout_booking!(user_id, checkin, checkout) do
      %Ysc.Bookings.Booking{}
      |> Ysc.Bookings.Booking.changeset(
        %{
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 2,
          property: :tahoe,
          booking_mode: :buyout,
          user_id: user_id,
          status: :complete,
          total_price: Money.new(200, :USD)
        },
        skip_validation: true
      )
      |> Repo.insert!()
    end

    defp calendar_view(conn, from_date, to_date) do
      live(
        conn,
        ~p"/admin/bookings?property=tahoe&from_date=#{from_date}&to_date=#{to_date}"
      )
    end

    test "shows left continuation when booking started before the visible range",
         %{
           conn: conn
         } do
      user = user_fixture(%{first_name: "Spill", last_name: "Before"})
      insert_tahoe_buyout_booking!(user.id, ~D[2030-06-05], ~D[2030-06-15])

      {:ok, view, _html} = calendar_view(conn, "2030-06-10", "2030-06-20")

      html = render(view)
      assert html =~ "calendar-booking-continues-left"
      refute html =~ "calendar-booking-continues-right"
      assert html =~ "Continues before view"
      refute html =~ "Continues after view"
    end

    test "shows right continuation when booking ends after the visible range",
         %{
           conn: conn
         } do
      user = user_fixture(%{first_name: "Spill", last_name: "After"})
      insert_tahoe_buyout_booking!(user.id, ~D[2030-07-10], ~D[2030-07-25])

      {:ok, view, _html} = calendar_view(conn, "2030-07-10", "2030-07-20")

      html = render(view)
      assert html =~ "calendar-booking-continues-right"
      refute html =~ "calendar-booking-continues-left"
      assert html =~ "Continues after view"
      refute html =~ "Continues before view"
    end

    test "shows both continuation edges when booking spans the entire visible range",
         %{
           conn: conn
         } do
      user = user_fixture(%{first_name: "Spill", last_name: "Both"})
      insert_tahoe_buyout_booking!(user.id, ~D[2030-08-01], ~D[2030-08-31])

      {:ok, view, _html} = calendar_view(conn, "2030-08-10", "2030-08-20")

      html = render(view)
      assert html =~ "calendar-booking-continues-left"
      assert html =~ "calendar-booking-continues-right"
      assert html =~ "Continues before view"
      assert html =~ "Continues after view"
    end
  end

  describe "calendar date selection" do
    setup [:create_admin]

    test "two-click blackout selection opens new blackout", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=tahoe&from_date=2030-03-01&to_date=2030-03-31"
        )

      view
      |> element(
        "div[phx-click=select-date-blackout][data-date=\"2030-03-10\"]:not(.relative)"
      )
      |> render_click()

      view
      |> element(
        "div[phx-click=select-date-blackout][data-date=\"2030-03-14\"]:not(.relative)"
      )
      |> render_click()

      assert_patch(view)
    end

    test "two-click buyout selection opens new booking (buyout)", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=tahoe&from_date=2030-04-01&to_date=2030-04-30"
        )

      view
      |> element(
        "div[phx-click=select-date-buyout][data-date=\"2030-04-05\"]:not(.relative)"
      )
      |> render_click()

      view
      |> element(
        "div[phx-click=select-date-buyout][data-date=\"2030-04-08\"]:not(.relative)"
      )
      |> render_click()

      assert_patch(view)
    end

    test "two-click Guests row selection opens new day booking on Clear Lake",
         %{
           conn: conn
         } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=2030-04-01&to_date=2030-04-30"
        )

      view
      |> element("button[phx-click=select-date-day][data-date=\"2030-04-05\"]")
      |> render_click()

      view
      |> element("button[phx-click=select-date-day][data-date=\"2030-04-08\"]")
      |> render_click()

      assert_patch(view)

      assert has_element?(view, "#booking-form")

      assert has_element?(
               view,
               "#booking-form input[name='booking[booking_mode]'][value=day]"
             )

      assert has_element?(view, "#booking-form-modal", "New Day Booking")
    end

    test "two-click room row selection opens new room booking when rooms exist",
         %{
           conn: conn
         } do
      rooms =
        Enum.filter(Bookings.list_rooms(), fn r ->
          r.property == :tahoe and r.is_active
        end)

      if rooms == [] do
        assert true
      else
        room = List.first(rooms)
        room_id = room.id

        {:ok, view, _html} =
          live(
            conn,
            ~p"/admin/bookings?property=tahoe&from_date=2030-05-01&to_date=2030-05-31"
          )

        view
        |> element(
          "div[phx-click=select-date-room][data-room-id=\"#{room_id}\"][data-date=\"2030-05-10\"]:not(.relative)"
        )
        |> render_click()

        view
        |> element(
          "div[phx-click=select-date-room][data-room-id=\"#{room_id}\"][data-date=\"2030-05-12\"]:not(.relative)"
        )
        |> render_click()

        assert_patch(view)
      end
    end
  end

  describe "blackout modal" do
    setup [:create_admin]

    test "validate-blackout updates form on change", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/blackouts/new?property=tahoe&from_date=2030-06-01&to_date=2030-06-30"
        )

      html =
        view
        |> form("#blackout-form", %{
          "blackout" => %{
            "reason" => "Maintenance window",
            "property" => "tahoe",
            "start_date" => "2030-06-10",
            "end_date" => "2030-06-12"
          }
        })
        |> render_change()

      assert html =~ "Maintenance window"
    end

    test "creates blackout then deletes from edit modal", %{conn: conn} do
      {:ok, blackout} =
        Bookings.create_blackout(%{
          property: :tahoe,
          reason: "Test delete blackout",
          start_date: ~D[2031-07-01],
          end_date: ~D[2031-07-03]
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/blackouts/#{blackout.id}/edit?property=tahoe&from_date=2031-07-01&to_date=2031-07-31"
        )

      assert render(view) =~ "Edit Blackout"

      view
      |> element("button", "Delete")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_blackout!(blackout.id)
      end
    end
  end

  describe "pricing rules" do
    setup [:create_admin]

    test "opens new pricing rule modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings?section=config")

      view
      |> element("button", "New Pricing Rule")
      |> render_click()

      assert_patched(
        view,
        "/admin/bookings/pricing-rules/new?property=tahoe&section=config"
      )
    end

    test "validate-pricing-rule runs on form change", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/pricing-rules/new?property=tahoe&section=config"
        )

      html =
        view
        |> form("#pricing-rule-form", %{
          "pricing_rule" => %{
            "booking_mode" => "room",
            "price_unit" => "per_person_per_night",
            "amount" => "150.00",
            "property" => "tahoe"
          }
        })
        |> render_change()

      assert html =~ "150"
    end

    test "updates pricing rule list after saving from edit modal", %{conn: conn} do
      rule =
        insert_pricing_rule!(%{
          property: :tahoe,
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/pricing-rules/#{rule.id}/edit?property=tahoe&section=config"
        )

      view
      |> form("#pricing-rule-form", %{
        "pricing_rule" => %{
          "booking_mode" => "room",
          "price_unit" => "per_person_per_night",
          "amount" => "275.00",
          "property" => "tahoe"
        }
      })
      |> render_submit()

      assert_patch(
        view,
        "/admin/bookings?property=tahoe&section=config"
      )

      html = render(view)
      assert html =~ "$275.00"
      refute html =~ "$100.00"
      refute has_element?(view, "#pricing-rule-modal")
    end
  end

  describe "reservations" do
    setup [:create_admin]

    test "change-reservation-search patches URL", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      view
      |> form("form[phx-change=change-reservation-search]", %{
        "search" => %{"query" => "findme"}
      })
      |> render_change()

      assert_patch(view)
    end

    test "lists a booking and opens view modal", %{conn: conn} do
      unique = "AdminBk#{System.unique_integer([:positive])}"
      user = user_fixture(%{first_name: unique, last_name: "Guest"})
      _booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      view
      |> form("form[phx-change=change-reservation-search]", %{
        "search" => %{"query" => unique}
      })
      |> render_change()

      view
      |> element("button", "View")
      |> render_click()

      assert_patch(view)
      assert has_element?(view, "#booking-modal")
      assert render(view) =~ "Booking Details"
      assert render(view) =~ unique
    end

    test "clicking a reservation row opens the booking modal", %{conn: conn} do
      unique = "RowClick#{System.unique_integer([:positive])}"
      user = user_fixture(%{first_name: unique, last_name: "Guest"})
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      view
      |> form("form[phx-change=change-reservation-search]", %{
        "search" => %{"query" => unique}
      })
      |> render_change()

      html = render(view)
      assert html =~ "cursor-pointer"

      view
      |> render_click("view-booking", %{"booking-id" => booking.id})

      assert_patch(view)
      assert has_element?(view, "#booking-modal")
      assert render(view) =~ unique
    end

    test "reservations table shows checked-in status when booking.checked_in is true",
         %{
           conn: conn
         } do
      unique = "CheckedIn#{System.unique_integer([:positive])}"
      user = user_fixture(%{first_name: unique, last_name: "Guest"})
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      assert {:ok, _} =
               Bookings.create_check_in(%{
                 bookings: [booking],
                 rules_agreed: true,
                 checked_in_at: DateTime.utc_now()
               })

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      view
      |> form("form[phx-change=change-reservation-search]", %{
        "search" => %{"query" => unique}
      })
      |> render_change()

      html = render(view)
      assert html =~ unique
      assert html =~ "text-green-700 font-medium\">Yes<"
    end

    test "reservations table shows unchecked status when booking.checked_in is false",
         %{
           conn: conn
         } do
      unique = "NotChecked#{System.unique_integer([:positive])}"
      user = user_fixture(%{first_name: unique, last_name: "Guest"})
      _booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      view
      |> form("form[phx-change=change-reservation-search]", %{
        "search" => %{"query" => unique}
      })
      |> render_change()

      html = render(view)
      assert html =~ unique
      refute html =~ "text-green-700 font-medium\">Yes<"
    end

    test "keeps reservations table populated after switching section tabs", %{
      conn: conn
    } do
      unique = "TabSwitch#{System.unique_integer([:positive])}"
      user = user_fixture(%{first_name: unique, last_name: "Guest"})
      _booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      view
      |> form("form[phx-change=change-reservation-search]", %{
        "search" => %{"query" => unique}
      })
      |> render_change()

      assert render(view) =~ unique

      for section <- ["calendar", "config", "pending_refunds", "reservations"] do
        view
        |> element(
          "button[phx-value-section=#{section}]",
          section_label(section)
        )
        |> render_click()

        assert_patch(view)
      end

      assert has_element?(view, "#admin_reservations_list")
      assert render(view) =~ unique
    end

    test "does not re-query reservations list when opening view booking modal",
         %{
           conn: conn
         } do
      unique = "PerfList#{System.unique_integer([:positive])}"
      user = user_fixture(%{first_name: unique, last_name: "Guest"})
      _booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      view
      |> form("form[phx-change=change-reservation-search]", %{
        "search" => %{"query" => unique}
      })
      |> render_change()

      bookings_list_pattern = ~r/FROM "bookings".*ORDER BY.*inserted_at/is

      {_html, reservation_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> element("button", "View")
            |> render_click()
          end,
          pattern: bookings_list_pattern,
          caller_pids: [view.pid]
        )

      assert reservation_queries == 0
      assert has_element?(view, "#booking-modal")
    end

    test "does not re-query pending refund badge counts when opening view booking modal",
         %{conn: conn} do
      unique = "PerfBadge#{System.unique_integer([:positive])}"
      user = user_fixture(%{first_name: unique, last_name: "Guest"})
      _booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      view
      |> form("form[phx-change=change-reservation-search]", %{
        "search" => %{"query" => unique}
      })
      |> render_change()

      pending_refund_pattern = ~r/FROM "pending_refunds"/i

      {_html, badge_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> element("button", "View")
            |> render_click()
          end,
          pattern: pending_refund_pattern,
          caller_pids: [view.pid]
        )

      assert badge_queries == 0
      assert has_element?(view, "#booking-modal")
    end

    test "reservations table shows checked-in status from denormalized flag", %{
      conn: conn
    } do
      unique = "CheckedIn#{System.unique_integer([:positive])}"
      user = user_fixture(%{first_name: unique, last_name: "Guest"})
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      assert {:ok, _} =
               Bookings.create_check_in(%{
                 bookings: [booking],
                 rules_agreed: true
               })

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      html =
        view
        |> form("form[phx-change=change-reservation-search]", %{
          "search" => %{"query" => unique}
        })
        |> render_change()

      assert html =~ unique
      assert html =~ ~s(text-green-700 font-medium">Yes<)
    end

    test "reservations table omits checked-in indicator for unchecked bookings",
         %{
           conn: conn
         } do
      unique = "NotChecked#{System.unique_integer([:positive])}"
      user = user_fixture(%{first_name: unique, last_name: "Guest"})
      _booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=reservations")

      html =
        view
        |> form("form[phx-change=change-reservation-search]", %{
          "search" => %{"query" => unique}
        })
        |> render_change()

      assert html =~ unique
      refute html =~ ~s(text-green-700 font-medium">Yes<)
    end
  end

  describe "new booking form" do
    setup [:create_admin]

    test "validate-booking runs on change", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/new?property=tahoe&from_date=2030-08-01&to_date=2030-08-15&type=buyout"
        )

      html =
        view
        |> form("#booking-form", %{
          "booking" => %{
            "checkin_date" => "2030-08-05",
            "checkout_date" => "2030-08-08",
            "guests_count" => "2",
            "children_count" => "0"
          }
        })
        |> render_change()

      assert html =~ "2030-08-05"
      _ = user
    end

    test "defaults checkout to the next day when the calendar sends a single date",
         %{
           conn: conn
         } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/new?property=clear_lake&from_date=2036-06-01&to_date=2036-06-15&type=day&date=2036-06-05"
        )

      assert has_element?(view, "#booking-form")
      assert has_element?(view, "#booking_checkin_date[value='2036-06-05']")
      assert has_element?(view, "#booking_checkout_date[value='2036-06-06']")
    end

    test "loads new refund policy modal route", %{conn: conn} do
      {:ok, view, html} =
        live(
          conn,
          ~p"/admin/bookings/refund-policies/new?property=tahoe&section=config"
        )

      assert html =~ "New Refund Policy"
      assert render(view) =~ "Refund Policy"
    end
  end

  describe "edit booking form" do
    setup [:create_admin]

    test "cancel button dismisses without submitting the form", %{conn: conn} do
      user = user_fixture()

      booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :buyout,
          status: :complete,
          reference_id: "MIG-WP-63892",
          checkin_date: ~D[2030-07-31],
          checkout_date: ~D[2030-08-02],
          guests_count: 18
        })

      {:ok, view, html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=tahoe&from_date=2030-07-28&to_date=2030-08-10"
        )

      assert html =~ "MIG-WP-63892"
      assert has_element?(view, "#booking-form")

      # Cancel must be type=button so it does not submit and create a duplicate booking
      assert has_element?(
               view,
               "#booking-form button[type=button]",
               "Cancel"
             )

      view
      |> element("#booking-form button[type=button]", "Cancel")
      |> render_click()

      refute has_element?(view, "#booking-form")

      assert Bookings.get_booking!(booking.id).reference_id == "MIG-WP-63892"

      assert Repo.aggregate(
               from(b in Booking, where: b.user_id == ^user.id),
               :count
             ) ==
               1
    end

    test "can cancel a migrated WP booking without changing its reference_id",
         %{
           conn: conn
         } do
      user = user_fixture()

      booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :buyout,
          status: :complete,
          reference_id: "MIG-WP-63892",
          checkin_date: ~D[2030-07-31],
          checkout_date: ~D[2030-08-02],
          guests_count: 18
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=tahoe&from_date=2030-07-28&to_date=2030-08-10"
        )

      view
      |> form("#booking-form", %{"booking" => %{"status" => "canceled"}})
      |> render_submit()

      updated = Bookings.get_booking!(booking.id)
      assert updated.status == :canceled
      assert updated.reference_id == "MIG-WP-63892"

      assert Repo.aggregate(
               from(b in Booking, where: b.user_id == ^user.id),
               :count
             ) ==
               1
    end
  end

  describe "door codes" do
    setup [:create_admin]

    test "validate-door-code warns on reuse of recent code", %{conn: conn} do
      suffix =
        Integer.to_string(System.unique_integer([:positive]))
        |> String.slice(-2, 2)

      code = "9#{suffix}12"

      {:ok, _} =
        Bookings.create_door_code(%{
          "property" => :tahoe,
          "code" => code
        })

      {:ok, view, _html} = live(conn, ~p"/admin/bookings?section=config")

      html =
        view
        |> form("#door-code-form", %{"door_code" => %{"code" => code}})
        |> render_change()

      assert html =~ "reuse" or html =~ "last 3"
    end
  end

  describe "pending refunds UI" do
    setup [:create_admin]

    test "reject flow for pending refund", %{conn: conn} do
      {pr, _booking} = insert_pending_refund!(:tahoe)

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=pending_refunds")

      assert render(view) =~ "Booking:"

      view
      |> element("button", "Reject")
      |> render_click()

      assert has_element?(view, "#reject-refund-form")

      view
      |> form("#reject-refund-form", %{
        "reject_refund" => %{"admin_notes" => "Does not qualify per policy."}
      })
      |> render_submit()

      updated = Repo.get!(PendingRefund, pr.id)
      assert updated.status == :rejected
      assert updated.admin_notes =~ "qualify"
    end

    test "opens and closes approve refund modal without approving", %{
      conn: conn
    } do
      {pr, _booking} = insert_pending_refund!(:tahoe)

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings?property=tahoe&section=pending_refunds")

      view
      |> element("button", "Approve Custom Amount")
      |> render_click()

      assert has_element?(view, "#approve-refund-form")

      view
      |> element(
        "#approve-refund-modal button[phx-click=close-approve-refund-modal]",
        "Cancel"
      )
      |> render_click()

      refute has_element?(view, "#approve-refund-form")

      _ = pr
    end
  end

  describe "configuration navigation" do
    setup [:create_admin]

    test "navigates to configuration section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings")

      view
      |> element("button", "Configuration")
      |> render_click()

      assert render(view) =~ "Door Codes"
      assert render(view) =~ "Seasons"
      assert render(view) =~ "Pricing Rules"
    end
  end

  describe "Clear Lake day guests modal" do
    setup [:create_admin]

    # Insert a Clear Lake :day booking bypassing business-logic validation so
    # tests are fully deterministic and independent of season/advance-booking rules.
    # We use the Booking changeset with skip_validation: true so that reference_id
    # is still generated by the changeset but booking-rule validations are skipped.
    defp insert_clear_lake_day_booking!(
           user_id,
           checkin,
           checkout,
           guests_count \\ 3
         ) do
      %Ysc.Bookings.Booking{}
      |> Ysc.Bookings.Booking.changeset(
        %{
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: guests_count,
          property: :clear_lake,
          booking_mode: :day,
          user_id: user_id,
          status: :complete,
          total_price: Money.new(400, :USD)
        },
        skip_validation: true
      )
      |> Ysc.Repo.insert!()
    end

    # Dates far enough in the future to avoid collisions with other tests.
    defp future_checkin, do: Date.add(Date.utc_today(), 120)

    test "0-guest dates render as non-interactive text, not a button", %{
      conn: conn
    } do
      from_date = "2035-01-01"
      to_date = "2035-01-07"

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=#{from_date}&to_date=#{to_date}"
        )

      html = render(view)
      assert html =~ "0 guests"
      refute has_element?(view, "button[phx-click='show-day-guests']")
    end

    test "dates with bookings render guest count as a clickable button", %{
      conn: conn
    } do
      user = user_fixture(%{first_name: "Alice", last_name: "ClearLake"})
      checkin = future_checkin()
      checkout = Date.add(checkin, 4)
      insert_clear_lake_day_booking!(user.id, checkin, checkout)

      from_date = Date.to_string(Date.add(checkin, -1))
      to_date = Date.to_string(Date.add(checkout, 1))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=#{from_date}&to_date=#{to_date}"
        )

      html = render(view)
      assert html =~ "3 guests"

      assert has_element?(
               view,
               "button[phx-click='show-day-guests'][phx-value-date='#{Date.to_string(checkin)}']"
             )
    end

    test "clicking guest count opens modal with the correct header date", %{
      conn: conn
    } do
      user = user_fixture(%{first_name: "Bob", last_name: "DayGuest"})
      checkin = Date.add(future_checkin(), 10)
      checkout = Date.add(checkin, 3)
      insert_clear_lake_day_booking!(user.id, checkin, checkout)

      from_date = Date.to_string(Date.add(checkin, -1))
      to_date = Date.to_string(Date.add(checkout, 1))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=#{from_date}&to_date=#{to_date}"
        )

      view
      |> element(
        "button[phx-click='show-day-guests'][phx-value-date='#{Date.to_string(checkin)}']"
      )
      |> render_click()

      assert has_element?(view, "#day-guests-modal")
      html = render(view)
      assert html =~ Calendar.strftime(checkin, "%B %d, %Y")
      assert html =~ "1 booking"
    end

    test "modal lists the booked user's name and email", %{conn: conn} do
      user = user_fixture(%{first_name: "Carol", last_name: "GuestUser"})
      checkin = Date.add(future_checkin(), 20)
      checkout = Date.add(checkin, 5)
      insert_clear_lake_day_booking!(user.id, checkin, checkout)

      from_date = Date.to_string(Date.add(checkin, -1))
      to_date = Date.to_string(Date.add(checkout, 1))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=#{from_date}&to_date=#{to_date}"
        )

      view
      |> element(
        "button[phx-click='show-day-guests'][phx-value-date='#{Date.to_string(checkin)}']"
      )
      |> render_click()

      assert has_element?(view, "#day-guests-modal")
      html = render(view)
      assert html =~ "Carol"
      assert html =~ "GuestUser"
      assert html =~ user.email
    end

    test "close button dismisses the modal", %{conn: conn} do
      user = user_fixture()
      checkin = Date.add(future_checkin(), 30)
      checkout = Date.add(checkin, 3)
      insert_clear_lake_day_booking!(user.id, checkin, checkout)

      from_date = Date.to_string(Date.add(checkin, -1))
      to_date = Date.to_string(Date.add(checkout, 1))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=#{from_date}&to_date=#{to_date}"
        )

      view
      |> element(
        "button[phx-click='show-day-guests'][phx-value-date='#{Date.to_string(checkin)}']"
      )
      |> render_click()

      assert has_element?(view, "#day-guests-modal")

      view
      |> element(
        "#day-guests-modal button[phx-click='close-day-guests-modal']",
        "Close"
      )
      |> render_click()

      refute has_element?(view, "#day-guests-modal")
    end

    test "View button inside modal opens booking details modal", %{conn: conn} do
      user = user_fixture(%{first_name: "Dave", last_name: "ViewTest"})
      checkin = Date.add(future_checkin(), 40)
      checkout = Date.add(checkin, 4)
      insert_clear_lake_day_booking!(user.id, checkin, checkout)

      from_date = Date.to_string(Date.add(checkin, -1))
      to_date = Date.to_string(Date.add(checkout, 1))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=#{from_date}&to_date=#{to_date}"
        )

      view
      |> element(
        "button[phx-click='show-day-guests'][phx-value-date='#{Date.to_string(checkin)}']"
      )
      |> render_click()

      assert has_element?(view, "#day-guests-modal")

      view
      |> element("#day-guests-modal button[phx-click='view-booking']")
      |> render_click()

      assert_patch(view)
      assert has_element?(view, "#booking-modal")
      assert render(view) =~ "Booking Details"
      assert render(view) =~ "Dave"
    end

    test "checkout day does not show a guest button (guests have left)", %{
      conn: conn
    } do
      user = user_fixture()
      checkin = Date.add(future_checkin(), 50)
      checkout = Date.add(checkin, 3)
      insert_clear_lake_day_booking!(user.id, checkin, checkout)

      from_date = Date.to_string(Date.add(checkout, -2))
      to_date = Date.to_string(Date.add(checkout, 3))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=#{from_date}&to_date=#{to_date}"
        )

      # The checkout date itself has 0 guests (they leave at 11am)
      refute has_element?(
               view,
               "button[phx-click='show-day-guests'][phx-value-date='#{Date.to_string(checkout)}']"
             )
    end

    test "multiple bookings on same day are all listed in the modal", %{
      conn: conn
    } do
      user1 = user_fixture(%{first_name: "Eve", last_name: "MultiA"})
      user2 = user_fixture(%{first_name: "Frank", last_name: "MultiB"})
      checkin = Date.add(future_checkin(), 60)
      checkout = Date.add(checkin, 3)
      insert_clear_lake_day_booking!(user1.id, checkin, checkout, 2)
      insert_clear_lake_day_booking!(user2.id, checkin, checkout, 2)

      from_date = Date.to_string(Date.add(checkin, -1))
      to_date = Date.to_string(Date.add(checkout, 1))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=#{from_date}&to_date=#{to_date}"
        )

      view
      |> element(
        "button[phx-click='show-day-guests'][phx-value-date='#{Date.to_string(checkin)}']"
      )
      |> render_click()

      assert has_element?(view, "#day-guests-modal")
      html = render(view)
      assert html =~ "Eve"
      assert html =~ "Frank"
      assert html =~ "2 bookings"
    end

    test "canceled bookings are excluded from the modal", %{conn: conn} do
      user = user_fixture(%{first_name: "Grace", last_name: "Canceled"})
      checkin = Date.add(future_checkin(), 70)
      checkout = Date.add(checkin, 3)

      booking = insert_clear_lake_day_booking!(user.id, checkin, checkout)

      # Cancel the booking after insertion
      booking
      |> Ecto.Changeset.change(%{status: :canceled})
      |> Ysc.Repo.update!()

      # Need another active booking so the guest button exists at all
      active_user = user_fixture(%{first_name: "Henry", last_name: "Active"})
      insert_clear_lake_day_booking!(active_user.id, checkin, checkout)

      from_date = Date.to_string(Date.add(checkin, -1))
      to_date = Date.to_string(Date.add(checkout, 1))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=#{from_date}&to_date=#{to_date}"
        )

      view
      |> element(
        "button[phx-click='show-day-guests'][phx-value-date='#{Date.to_string(checkin)}']"
      )
      |> render_click()

      html = render(view)
      assert html =~ "Henry"
      refute html =~ "Grace"
    end
  end

  describe "Clear Lake day/spot booking create and edit" do
    setup [:create_admin]

    defp insert_clear_lake_day_booking_for_edit!(
           user_id,
           checkin,
           checkout,
           guests_count \\ 3
         ) do
      %Ysc.Bookings.Booking{}
      |> Ysc.Bookings.Booking.changeset(
        %{
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: guests_count,
          property: :clear_lake,
          booking_mode: :day,
          user_id: user_id,
          status: :complete,
          total_price: Money.new(400, :USD)
        },
        skip_validation: true
      )
      |> Ysc.Repo.insert!()
    end

    test "new day booking form creates a complete Clear Lake spot booking", %{
      conn: conn
    } do
      user = user_fixture(%{first_name: "Spot", last_name: "AdminCreate"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/new?property=clear_lake&from_date=2036-06-01&to_date=2036-06-15&type=day&start_date=2036-06-05&end_date=2036-06-08"
        )

      assert has_element?(view, "#booking-form-modal", "New Day Booking")
      assert has_element?(view, "#booking-form")

      assert has_element?(
               view,
               "#booking-form input[name='booking[booking_mode]'][value=day]"
             )

      view
      |> element("#booking-user-autocomplete-input")
      |> render_keyup(%{"value" => user.email})

      view
      |> element(
        "button[phx-click='select-booking-user'][phx-value-id='#{user.id}']"
      )
      |> render_click()

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2036-06-05",
          "checkout_date" => "2036-06-08",
          "guests_count" => "2",
          "children_count" => "0",
          "booking_mode" => "day",
          "property" => "clear_lake"
        }
      })
      |> render_submit()

      booking =
        Repo.one!(
          from(b in Booking,
            where: b.user_id == ^user.id and b.property == :clear_lake,
            order_by: [desc: b.inserted_at],
            limit: 1
          )
        )

      assert booking.booking_mode == :day
      assert booking.status == :complete
      assert booking.checkin_date == ~D[2036-06-05]
      assert booking.checkout_date == ~D[2036-06-08]
      assert booking.guests_count == 2
    end

    test "edit day booking keeps booking_mode day (does not flip to buyout)", %{
      conn: conn
    } do
      user = user_fixture(%{first_name: "Spot", last_name: "EditKeep"})
      checkin = ~D[2036-07-10]
      checkout = ~D[2036-07-13]

      booking =
        insert_clear_lake_day_booking_for_edit!(user.id, checkin, checkout)

      {:ok, view, html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=clear_lake&from_date=2036-07-01&to_date=2036-07-20"
        )

      assert html =~ "Edit Booking"

      assert has_element?(
               view,
               "#booking-form input[name='booking[booking_mode]'][value=day]"
             )

      refute has_element?(
               view,
               "#booking-form input[name='booking[booking_mode]'][value=buyout]"
             )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2036-07-10",
          "checkout_date" => "2036-07-13",
          "guests_count" => "4",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "complete"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(booking.id)
      assert updated.booking_mode == :day
      assert updated.guests_count == 4
      assert updated.status == :complete
    end

    test "edit hold day booking reconciles capacity_held inventory", %{
      conn: conn
    } do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "HoldInventory"})

      checkin = ~D[2036-09-25]
      checkout = ~D[2036-09-28]

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_held_for(:clear_lake, stay_days) == [2, 2, 2]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=clear_lake&from_date=2036-09-01&to_date=2036-09-30"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2036-09-25",
          "checkout_date" => "2036-09-28",
          "guests_count" => "5",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "hold"
        }
      })
      |> render_submit()

      assert Bookings.get_booking!(hold.id).guests_count == 5
      assert day_capacity_held_for(:clear_lake, stay_days) == [5, 5, 5]
    end

    test "edit hold day booking to complete reconciles held and booked inventory",
         %{
           conn: conn
         } do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "HoldConfirm"})

      checkin = ~D[2036-12-05]
      checkout = ~D[2036-12-08]

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_held_for(:clear_lake, stay_days) == [2, 2, 2]
      assert day_capacity_booked_for(:clear_lake, stay_days) == [0, 0, 0]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=clear_lake&from_date=2036-12-01&to_date=2036-12-15"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2036-12-05",
          "checkout_date" => "2036-12-08",
          "guests_count" => "2",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "complete"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(hold.id)
      assert updated.status == :complete
      assert day_capacity_held_for(:clear_lake, stay_days) == [0, 0, 0]
      assert day_capacity_booked_for(:clear_lake, stay_days) == [2, 2, 2]
    end

    test "edit hold day booking to draft releases capacity_held inventory", %{
      conn: conn
    } do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "HoldDraft"})

      checkin = ~D[2037-01-10]
      checkout = ~D[2037-01-13]

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_held_for(:clear_lake, stay_days) == [2, 2, 2]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=clear_lake&from_date=2037-01-01&to_date=2037-01-20"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2037-01-10",
          "checkout_date" => "2037-01-13",
          "guests_count" => "2",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "draft"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(hold.id)
      assert updated.status == :draft
      assert day_capacity_held_for(:clear_lake, stay_days) == [0, 0, 0]
      assert day_capacity_booked_for(:clear_lake, stay_days) == [0, 0, 0]
    end

    test "edit complete day booking to draft releases capacity_booked inventory",
         %{conn: conn} do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "CompleteDraft"})

      checkin = ~D[2037-02-10]
      checkout = ~D[2037-02-13]

      {:ok, booking} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      {:ok, booking} = Ysc.Bookings.BookingLocker.confirm_booking(booking.id)

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_booked_for(:clear_lake, stay_days) == [2, 2, 2]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=clear_lake&from_date=2037-02-01&to_date=2037-02-20"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2037-02-10",
          "checkout_date" => "2037-02-13",
          "guests_count" => "2",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "draft"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(booking.id)
      assert updated.status == :draft
      assert day_capacity_booked_for(:clear_lake, stay_days) == [0, 0, 0]
      assert day_capacity_held_for(:clear_lake, stay_days) == [0, 0, 0]
    end

    test "edit draft day booking to complete reclaims capacity_booked inventory",
         %{conn: conn} do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "DraftToComplete"})

      checkin = ~D[2037-03-10]
      checkout = ~D[2037-03-13]

      {:ok, booking} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      {:ok, booking} = Ysc.Bookings.BookingLocker.confirm_booking(booking.id)
      {:ok, _} = Ysc.Bookings.BookingLocker.revert_complete_to_draft(booking.id)

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_booked_for(:clear_lake, stay_days) == [0, 0, 0]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=clear_lake&from_date=2037-03-01&to_date=2037-03-20"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2037-03-10",
          "checkout_date" => "2037-03-13",
          "guests_count" => "2",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "complete"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(booking.id)
      assert updated.status == :complete
      assert day_capacity_booked_for(:clear_lake, stay_days) == [2, 2, 2]
      assert day_capacity_held_for(:clear_lake, stay_days) == [0, 0, 0]
    end

    test "edit draft day booking to hold reclaims capacity_held inventory", %{
      conn: conn
    } do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "DraftToHold"})

      checkin = ~D[2037-04-10]
      checkout = ~D[2037-04-13]

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      {:ok, _} = Ysc.Bookings.BookingLocker.revert_hold_to_draft(hold.id)

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_held_for(:clear_lake, stay_days) == [0, 0, 0]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=clear_lake&from_date=2037-04-01&to_date=2037-04-20"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2037-04-10",
          "checkout_date" => "2037-04-13",
          "guests_count" => "2",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "hold"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(hold.id)
      assert updated.status == :hold
      assert day_capacity_held_for(:clear_lake, stay_days) == [2, 2, 2]
      assert day_capacity_booked_for(:clear_lake, stay_days) == [0, 0, 0]
    end

    test "saving a draft day booking without changing status does not crash", %{
      conn: conn
    } do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "DraftResave"})

      checkin = ~D[2037-05-10]
      checkout = ~D[2037-05-13]

      {:ok, booking} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      {:ok, booking} = Ysc.Bookings.BookingLocker.confirm_booking(booking.id)
      {:ok, _} = Ysc.Bookings.BookingLocker.revert_complete_to_draft(booking.id)

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=clear_lake&from_date=2037-05-01&to_date=2037-05-20"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2037-05-10",
          "checkout_date" => "2037-05-13",
          "guests_count" => "3",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "draft"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(booking.id)
      assert updated.status == :draft
      assert updated.guests_count == 3
      assert day_capacity_booked_for(:clear_lake, stay_days) == [0, 0, 0]
      assert day_capacity_held_for(:clear_lake, stay_days) == [0, 0, 0]
    end

    test "edit hold day booking to complete with guest count change reconciles inventory",
         %{conn: conn} do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "HoldConfirmGuests"})

      checkin = ~D[2036-12-20]
      checkout = ~D[2036-12-23]

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_held_for(:clear_lake, stay_days) == [2, 2, 2]
      assert day_capacity_booked_for(:clear_lake, stay_days) == [0, 0, 0]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=clear_lake&from_date=2036-12-15&to_date=2036-12-31"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2036-12-20",
          "checkout_date" => "2036-12-23",
          "guests_count" => "5",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "complete"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(hold.id)
      assert updated.status == :complete
      assert updated.guests_count == 5
      assert day_capacity_held_for(:clear_lake, stay_days) == [0, 0, 0]
      assert day_capacity_booked_for(:clear_lake, stay_days) == [5, 5, 5]
    end

    test "rejects changing a complete booking to hold", %{conn: conn} do
      user = user_fixture(%{first_name: "Spot", last_name: "NoHoldRevert"})
      checkin = ~D[2036-08-05]
      checkout = ~D[2036-08-08]

      booking =
        insert_clear_lake_day_booking_for_edit!(user.id, checkin, checkout)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=clear_lake&from_date=2036-08-01&to_date=2036-08-15"
        )

      html =
        view
        |> form("#booking-form", %{
          "booking" => %{
            "checkin_date" => "2036-08-05",
            "checkout_date" => "2036-08-08",
            "guests_count" => "3",
            "children_count" => "0",
            "booking_mode" => "day",
            "status" => "hold"
          }
        })
        |> render_submit()

      assert html =~ "Cannot mark a complete booking as hold"
      assert Bookings.get_booking!(booking.id).status == :complete
    end

    test "edit hold day booking shows blackout conflict toast", %{conn: conn} do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "HoldBlackout"})

      checkin = ~D[2036-10-05]
      checkout = ~D[2036-10-08]
      new_checkin = ~D[2036-10-20]
      new_checkout = ~D[2036-10-23]

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :clear_lake,
                 start_date: new_checkin,
                 end_date: new_checkout,
                 reason: "Admin hold modify blackout conflict"
               })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=clear_lake&from_date=2036-10-01&to_date=2036-10-31"
        )

      html =
        view
        |> form("#booking-form", %{
          "booking" => %{
            "checkin_date" => "2036-10-20",
            "checkout_date" => "2036-10-23",
            "guests_count" => "2",
            "children_count" => "0",
            "booking_mode" => "day",
            "status" => "hold"
          }
        })
        |> render_submit()

      assert html =~
               "Cannot update booking: selected dates overlap a blackout period."
    end

    test "edit hold day booking shows error when new dates overlap booked capacity",
         %{conn: conn} do
      ensure_clear_lake_pricing_rules!()

      booked_user =
        user_fixture(%{first_name: "Spot", last_name: "BookedCapacity"})

      hold_user = user_fixture(%{first_name: "Spot", last_name: "HoldOverlap"})

      checkin = ~D[2036-11-10]
      checkout = ~D[2036-11-12]
      hold_checkin = ~D[2036-11-20]
      hold_checkout = ~D[2036-11-22]

      assert {:ok, _complete} =
               Ysc.Bookings.BookingLocker.create_admin_booking(
                 %{
                   user_id: booked_user.id,
                   property: :clear_lake,
                   checkin_date: checkin,
                   checkout_date: checkout,
                   guests_count: 12,
                   booking_mode: :day
                 },
                 skip_email: true,
                 skip_reminders: true
               )

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          hold_user.id,
          :clear_lake,
          hold_checkin,
          hold_checkout,
          2
        )

      booked_days =
        Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      hold_days =
        Date.range(hold_checkin, Date.add(hold_checkout, -1)) |> Enum.to_list()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=clear_lake&from_date=2036-11-01&to_date=2036-11-30"
        )

      html =
        view
        |> form("#booking-form", %{
          "booking" => %{
            "checkin_date" => "2036-11-10",
            "checkout_date" => "2036-11-12",
            "guests_count" => "2",
            "children_count" => "0",
            "booking_mode" => "day",
            "status" => "hold"
          }
        })
        |> render_submit()

      assert html =~ "Failed to update booking"
      assert html =~ "stale_inventory"

      unchanged = Bookings.get_booking!(hold.id)
      assert unchanged.checkin_date == hold_checkin
      assert unchanged.checkout_date == hold_checkout
      assert day_capacity_booked_for(:clear_lake, booked_days) == [12, 12]
      assert day_capacity_held_for(:clear_lake, hold_days) == [2, 2]
    end

    test "edit hold buyout booking shows error when new dates overlap booked buyout",
         %{conn: conn} do
      allow_far_future_booking_dates()
      booked_user = user_fixture(%{first_name: "Buyout", last_name: "Booked"})

      hold_user =
        user_fixture(%{first_name: "Buyout", last_name: "HoldOverlap"})

      {checkin, checkout} = locker_buyout_dates(850)
      {hold_checkin, hold_checkout} = locker_buyout_dates(860)

      assert {:ok, _complete} =
               Ysc.Bookings.BookingLocker.create_admin_booking(
                 %{
                   user_id: booked_user.id,
                   property: :tahoe,
                   checkin_date: checkin,
                   checkout_date: checkout,
                   booking_mode: :buyout,
                   guests_count: 4,
                   total_price: Money.new(:USD, "500.00")
                 },
                 skip_email: true,
                 skip_reminders: true
               )

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_buyout_booking(
          hold_user.id,
          :tahoe,
          hold_checkin,
          hold_checkout,
          4
        )

      from_date = Date.add(checkin, -7) |> Date.to_string()
      to_date = Date.add(hold_checkout, 7) |> Date.to_string()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=tahoe&from_date=#{from_date}&to_date=#{to_date}"
        )

      html =
        view
        |> form("#booking-form", %{
          "booking" => %{
            "checkin_date" => Date.to_string(checkin),
            "checkout_date" => Date.to_string(checkout),
            "guests_count" => "4",
            "children_count" => "0",
            "booking_mode" => "buyout",
            "status" => "hold"
          }
        })
        |> render_submit()

      assert html =~ "Failed to update booking"
      assert html =~ "stale_inventory"

      unchanged = Bookings.get_booking!(hold.id)
      assert unchanged.checkin_date == hold_checkin
      assert unchanged.checkout_date == hold_checkout
    end

    test "edit hold room booking shows error when new dates overlap booked room",
         %{conn: conn} do
      allow_far_future_booking_dates()

      insert_pricing_rule!(%{
        property: :tahoe,
        booking_mode: :room,
        price_unit: :per_person_per_night,
        season_id: nil
      })

      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Admin hold overlap #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Admin hold overlap room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      booked_user = user_fixture(%{first_name: "Room", last_name: "Booked"})
      hold_user = user_fixture(%{first_name: "Room", last_name: "HoldOverlap"})

      {checkin, checkout} = locker_room_dates(850, 2)
      {hold_checkin, hold_checkout} = locker_room_dates(860, 2)

      assert {:ok, _complete} =
               Ysc.Bookings.BookingLocker.create_admin_booking(
                 %{
                   user_id: booked_user.id,
                   property: :tahoe,
                   checkin_date: checkin,
                   checkout_date: checkout,
                   booking_mode: :room,
                   guests_count: 2,
                   total_price: Money.new(:USD, "200.00")
                 },
                 rooms: [room],
                 skip_email: true,
                 skip_reminders: true
               )

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_room_booking(
          hold_user.id,
          room.id,
          hold_checkin,
          hold_checkout,
          2
        )

      from_date = Date.add(checkin, -7) |> Date.to_string()
      to_date = Date.add(hold_checkout, 7) |> Date.to_string()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=tahoe&from_date=#{from_date}&to_date=#{to_date}"
        )

      html =
        view
        |> form("#booking-form", %{
          "booking" => %{
            "checkin_date" => Date.to_string(checkin),
            "checkout_date" => Date.to_string(checkout),
            "guests_count" => "2",
            "children_count" => "0",
            "booking_mode" => "room",
            "status" => "hold"
          }
        })
        |> render_submit()

      assert html =~ "Failed to update booking"
      assert html =~ "stale_inventory"

      unchanged = Bookings.get_booking!(hold.id)
      assert unchanged.checkin_date == hold_checkin
      assert unchanged.checkout_date == hold_checkout
    end

    test "edit hold day booking without inventory changes uses plain update path",
         %{conn: conn} do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "HoldChildren"})

      checkin = ~D[2036-11-05]
      checkout = ~D[2036-11-08]

      {:ok, hold} =
        Ysc.Bookings.BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_held_for(:clear_lake, stay_days) == [2, 2, 2]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{hold.id}/edit?property=clear_lake&from_date=2036-11-01&to_date=2036-11-15"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2036-11-05",
          "checkout_date" => "2036-11-08",
          "guests_count" => "2",
          "children_count" => "1",
          "booking_mode" => "day",
          "status" => "hold"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(hold.id)
      assert updated.children_count == 1
      assert updated.guests_count == 2
      assert day_capacity_held_for(:clear_lake, stay_days) == [2, 2, 2]
    end

    test "edit day booking reconciles capacity_booked inventory", %{conn: conn} do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "Inventory"})

      checkin = ~D[2036-09-10]
      checkout = ~D[2036-09-13]

      {:ok, booking} =
        Ysc.Bookings.BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :clear_lake,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 2,
            booking_mode: :day
          },
          skip_email: true,
          skip_reminders: true
        )

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      assert day_capacity_booked_for(:clear_lake, stay_days) == [2, 2, 2]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=clear_lake&from_date=2036-09-01&to_date=2036-09-20"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2036-09-10",
          "checkout_date" => "2036-09-13",
          "guests_count" => "5",
          "children_count" => "0",
          "booking_mode" => "day",
          "status" => "complete"
        }
      })
      |> render_submit()

      assert Bookings.get_booking!(booking.id).guests_count == 5
      assert day_capacity_booked_for(:clear_lake, stay_days) == [5, 5, 5]
    end

    test "edit complete day booking without inventory changes uses plain update path",
         %{conn: conn} do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "Children"})

      checkin = ~D[2036-09-20]
      checkout = ~D[2036-09-23]

      {:ok, booking} =
        Ysc.Bookings.BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :clear_lake,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 2,
            children_count: 0,
            booking_mode: :day
          },
          skip_email: true,
          skip_reminders: true
        )

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_booked_for(:clear_lake, stay_days) == [2, 2, 2]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=clear_lake&from_date=2036-09-01&to_date=2036-09-30"
        )

      view
      |> form("#booking-form", %{
        "booking" => %{
          "checkin_date" => "2036-09-20",
          "checkout_date" => "2036-09-23",
          "guests_count" => "2",
          "children_count" => "1",
          "booking_mode" => "day",
          "status" => "complete"
        }
      })
      |> render_submit()

      updated = Bookings.get_booking!(booking.id)
      assert updated.children_count == 1
      assert updated.guests_count == 2
      assert day_capacity_booked_for(:clear_lake, stay_days) == [2, 2, 2]
    end

    test "edit complete day booking shows blackout conflict toast", %{
      conn: conn
    } do
      ensure_clear_lake_pricing_rules!()
      user = user_fixture(%{first_name: "Spot", last_name: "Blackout"})

      checkin = ~D[2036-10-01]
      checkout = ~D[2036-10-04]
      new_checkin = ~D[2036-10-20]
      new_checkout = ~D[2036-10-23]

      {:ok, booking} =
        Ysc.Bookings.BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :clear_lake,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 2,
            booking_mode: :day
          },
          skip_email: true,
          skip_reminders: true
        )

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :clear_lake,
                 start_date: new_checkin,
                 end_date: new_checkout,
                 reason: "Admin edit blackout conflict"
               })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=clear_lake&from_date=2036-10-01&to_date=2036-10-31"
        )

      html =
        view
        |> form("#booking-form", %{
          "booking" => %{
            "checkin_date" => "2036-10-20",
            "checkout_date" => "2036-10-23",
            "guests_count" => "2",
            "children_count" => "0",
            "booking_mode" => "day",
            "status" => "complete"
          }
        })
        |> render_submit()

      assert html =~
               "Cannot update booking: selected dates overlap a blackout period."
    end

    test "edit complete room booking shows stale_inventory when dates overlap booked room",
         %{conn: conn} do
      allow_far_future_booking_dates()

      insert_pricing_rule!(%{
        property: :tahoe,
        booking_mode: :room,
        price_unit: :per_person_per_night,
        season_id: nil
      })

      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Admin complete overlap #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Admin complete overlap room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      booked_user =
        user_fixture(%{first_name: "Room", last_name: "BookedComplete"})

      moving_user =
        user_fixture(%{first_name: "Room", last_name: "MovingComplete"})

      {checkin, checkout} = locker_room_dates(870, 2)
      {move_checkin, move_checkout} = locker_room_dates(880, 2)

      assert {:ok, _complete} =
               Ysc.Bookings.BookingLocker.create_admin_booking(
                 %{
                   user_id: booked_user.id,
                   property: :tahoe,
                   checkin_date: checkin,
                   checkout_date: checkout,
                   booking_mode: :room,
                   guests_count: 2,
                   total_price: Money.new(:USD, "200.00")
                 },
                 rooms: [room],
                 skip_email: true,
                 skip_reminders: true
               )

      {:ok, booking} =
        Ysc.Bookings.BookingLocker.create_admin_booking(
          %{
            user_id: moving_user.id,
            property: :tahoe,
            checkin_date: move_checkin,
            checkout_date: move_checkout,
            booking_mode: :room,
            guests_count: 2,
            total_price: Money.new(:USD, "200.00")
          },
          rooms: [room],
          skip_email: true,
          skip_reminders: true
        )

      from_date = Date.add(checkin, -7) |> Date.to_string()
      to_date = Date.add(move_checkout, 7) |> Date.to_string()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings/bookings/#{booking.id}/edit?property=tahoe&from_date=#{from_date}&to_date=#{to_date}"
        )

      html =
        view
        |> form("#booking-form", %{
          "booking" => %{
            "checkin_date" => Date.to_string(checkin),
            "checkout_date" => Date.to_string(checkout),
            "guests_count" => "2",
            "children_count" => "0",
            "booking_mode" => "room",
            "room_id" => room.id,
            "status" => "complete"
          }
        })
        |> render_submit()

      assert html =~ "Failed to update booking"
      assert html =~ "stale_inventory"

      unchanged = Bookings.get_booking!(booking.id)
      assert unchanged.checkin_date == move_checkin
      assert unchanged.checkout_date == move_checkout

      nights = Date.diff(checkout, checkin)

      booked_count =
        Repo.aggregate(
          from(ri in Ysc.Bookings.RoomInventory,
            where:
              ri.room_id == ^room.id and ri.day >= ^checkin and
                ri.day < ^checkout and ri.booked == true and ri.held == false
          ),
          :count
        )

      assert booked_count == nights
    end

    test "day bookings are not rendered on the Full Buyout calendar row", %{
      conn: conn
    } do
      user = user_fixture(%{first_name: "Spot", last_name: "NotBuyout"})
      checkin = ~D[2036-08-05]
      checkout = ~D[2036-08-08]

      booking =
        insert_clear_lake_day_booking_for_edit!(user.id, checkin, checkout)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/bookings?property=clear_lake&from_date=2036-08-01&to_date=2036-08-15"
        )

      # Buyout booking bars use view-booking with booking id; day stays must not appear there
      refute has_element?(
               view,
               "[phx-click=view-booking][phx-value-booking-id='#{booking.id}']"
             )
    end
  end

  describe "booking refund modal" do
    setup [:create_admin]

    test "process refund with release availability releases day capacity inventory",
         %{
           conn: conn
         } do
      ensure_clear_lake_pricing_rules!()
      guest = user_fixture(%{first_name: "Refund", last_name: "Release"})

      checkin = ~D[2037-05-10]
      checkout = ~D[2037-05-13]

      {:ok, booking} =
        Ysc.Bookings.BookingLocker.create_admin_booking(
          %{
            user_id: guest.id,
            property: :clear_lake,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 2,
            booking_mode: :day,
            total_price: Money.new(400, :USD)
          },
          skip_email: true,
          skip_reminders: true
        )

      assert {:ok, {payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: guest.id,
                 amount: booking.total_price,
                 entity_type: :booking,
                 entity_id: booking.id,
                 external_payment_id:
                   "pi_admin_refund_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(100, :USD),
                 description: "Booking payment",
                 property: booking.property,
                 payment_method_id: nil
               })

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_booked_for(:clear_lake, stay_days) == [2, 2, 2]

      refund_amount =
        payment.amount
        |> Money.to_decimal()
        |> Decimal.to_string(:normal)

      {:ok, view, _html} = live(conn, ~p"/admin/bookings/#{booking.id}")

      assert has_element?(view, "#show-booking-refund-modal")
      # Native data-confirm can be auto-cancelled by the browser and silently
      # swallow the click; the amount/reason modal is the confirmation step.
      refute has_element?(view, "#show-booking-refund-modal[data-confirm]")

      view |> render_click("show-booking-refund-modal")

      assert has_element?(view, "#booking-refund-form")

      view
      |> form("#booking-refund-form", %{
        "refund" => %{
          "amount" => refund_amount,
          "reason" => "Admin refund test",
          "release_availability" => "true"
        }
      })
      |> render_submit()

      assert Bookings.get_booking!(booking.id).status == :refunded
      assert day_capacity_booked_for(:clear_lake, stay_days) == [0, 0, 0]
    end
  end

  defp insert_pricing_rule!(attrs) do
    default_attrs = %{
      amount: Money.new(100, :USD),
      booking_mode: :room,
      price_unit: :per_person_per_night,
      property: :tahoe
    }

    {:ok, rule} =
      default_attrs
      |> Map.merge(attrs)
      |> Bookings.create_pricing_rule()

    rule
  end
end

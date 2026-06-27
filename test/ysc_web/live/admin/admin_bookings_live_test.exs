defmodule YscWeb.Admin.AdminBookingsLiveTest do
  @moduledoc """
  Tests for AdminBookingsLive — admin booking management (calendar, reservations,
  configuration, pending refunds).
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings
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

            render(view)
            {:ok, view, initial_html}
          end,
          pattern: seasons_pattern
        )

      assert query_count <= 1
      assert render(view) =~ "Calendar"
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
          pattern: bookings_list_pattern
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
          pattern: pending_refund_pattern
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
end

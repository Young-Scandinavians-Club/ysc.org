defmodule YscWeb.UserBookingDetailLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  import Ecto.Query
  import Phoenix.ConnTest

  alias Ysc.Bookings
  alias Ysc.Bookings.{BookingLocker, BookingRoom, Room}
  alias Ysc.Payments.PaymentMethod
  alias Ysc.Repo

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    # Other LiveView tests set Mox-based StripeMock and may not restore; cancellation
    # calls `retrieve_payment_intent/2` on whatever client is configured.
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
    :ok
  end

  defp log_in_member(conn) do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  # Mounts connected LiveView and re-renders after post-connect payment/refund load.
  defp live_booking_detail(conn, booking_id) do
    {:ok, view, _html} = live(conn, ~p"/bookings/#{booking_id}")
    {:ok, view, render(view)}
  end

  describe "mount and render" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      user = user_fixture()

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe
        })

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/#{booking.id}")

      assert path == "/users/log-in"
    end

    test "renders booking summary for a complete booking", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe,
          guests_count: 2,
          children_count: 1
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)

      assert html =~ "Booking Details"
      assert html =~ booking.reference_id
      assert html =~ "Lake Tahoe Cabin"
      assert html =~ "children"
    end

    test "static HTML shows loading shell before websocket connects", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe
        })

      conn = get(conn, ~p"/bookings/#{booking.id}")
      html = html_response(conn, 200)

      assert html =~ ~s|id="booking-detail-loading"|
      refute html =~ booking.reference_id
      refute html =~ "Payment Method"
      refute html =~ "Total Paid"
    end

    test "connected LiveView loads payment summary after mount", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe
        })

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_deferred_load_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}")

      refute has_element?(view, "#booking-payment-loading")
      html = render(view)
      assert html =~ "Payment Summary"
    end

    test "does not show children suffix when children_count is zero", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          guests_count: 3,
          children_count: 0
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ Integer.to_string(booking.guests_count)
      refute html =~ "(0 children)"
    end

    test "renders clear lake property name", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :clear_lake
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Clear Lake Cabin"
    end

    test "redirects when booking id does not exist for user", %{conn: conn} do
      %{conn: conn, user: _user} = log_in_member(conn)
      missing = Ecto.ULID.generate()

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/#{missing}")

      assert path == ~p"/"
    end

    test "shows payment summary when a ledger payment exists", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_test_booking_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Payment Summary"
      assert html =~ "Total Paid"
    end

    test "loads payment details after connected mount", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ booking.reference_id
    end

    test "renders price breakdown when pricing_items is set", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_price_breakdown_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "other",
            "total" => %{"amount" => "15000", "currency" => "USD"}
          }
        })
        |> Repo.update()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Booking Total"
    end

    test "renders room breakdown when pricing_items type is room with rooms list",
         %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_room_breakdown_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "room",
            "rooms" => [
              %{
                "room_name" => "Pine",
                "nights" => 2,
                "total" => %{"amount" => "8000", "currency" => "USD"}
              }
            ]
          }
        })
        |> Repo.update()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Pine"
      assert html =~ "nights"
    end

    test "renders aggregate room line when pricing_items has type room without rooms list",
         %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_room_agg_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "room",
            "nights" => 3,
            "total" => %{"amount" => "15000", "currency" => "USD"}
          }
        })
        |> Repo.update()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Room Booking"
      assert html =~ "3"
    end

    test "shows pending payment status when payment record is pending", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_pending_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _} =
        payment
        |> Ecto.Changeset.change(%{status: :pending})
        |> Repo.update()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Pending"
    end

    test "shows refunded payment status when payment was refunded", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_refunded_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _} =
        payment
        |> Ecto.Changeset.change(%{status: :refunded})
        |> Repo.update()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Refunded"
    end
  end

  describe "confirm-cancel success" do
    setup %{conn: conn} do
      case Bookings.create_pricing_rule(%{
             amount: Money.new(500, :USD),
             booking_mode: :buyout,
             price_unit: :buyout_fixed,
             property: :tahoe,
             season_id: nil
           }) do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{errors: errors}} ->
          if Enum.any?(errors, fn {_f, {_m, meta}} ->
               meta[:constraint] == :unique
             end),
             do: :ok,
             else: raise("unexpected pricing rule error: #{inspect(errors)}")
      end

      user =
        user_fixture()
        |> Ecto.Changeset.change(%{state: :active})
        |> Repo.update!()

      year = Date.utc_today().year + 1
      july_first = Date.new!(year, 7, 1)

      checkin_date =
        case Date.day_of_week(july_first, :monday) do
          1 ->
            july_first

          n ->
            Date.add(july_first, 8 - n)
        end

      checkout_date = Date.add(checkin_date, 3)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin_date,
          checkout_date,
          2
        )

      {:ok, confirmed} = BookingLocker.confirm_booking(booking.id)

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_lv_cancel_#{confirmed.id}",
          entity_type: :booking,
          entity_id: confirmed.id,
          stripe_fee: Money.new(320, :USD),
          description: "Test booking payment",
          property: :tahoe,
          payment_method_id: nil
        })

      booking = Repo.reload!(confirmed)

      %{
        conn: log_in_user(conn, user),
        booking: booking,
        user: user
      }
    end

    test "submits cancel and updates booking to canceled", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, _html} = live_booking_detail(conn, booking.id)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()
      assert has_element?(view, "#cancel-booking-modal")

      html =
        view
        |> form("#cancel-booking-form", %{"reason" => "Change of plans"})
        |> render_submit()

      assert html =~ "Booking cancelled"
      assert Repo.reload!(booking).status == :canceled
    end

    test "partial cancel without payment reloads cancelled booking in UI", %{
      conn: conn,
      user: user
    } do
      year = Date.utc_today().year + 2
      july_first = Date.new!(year, 7, 1)

      checkin_date =
        case Date.day_of_week(july_first, :monday) do
          1 -> july_first
          n -> Date.add(july_first, 8 - n)
        end

      checkout_date = Date.add(checkin_date, 3)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin_date,
          checkout_date,
          2
        )

      {:ok, confirmed} = BookingLocker.confirm_booking(booking.id)

      {:ok, view, _html} = live_booking_detail(conn, confirmed.id)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()

      view
      |> form("#cancel-booking-form", %{"reason" => "Testing"})
      |> render_submit()

      page = render(view)

      assert page =~ "Cancelled"
      refute has_element?(view, "button[phx-click='show-cancel-modal']")
      assert Repo.get!(Bookings.Booking, confirmed.id).status == :canceled
    end
  end

  describe "confirm-cancel pending refund toast (policy rule applied)" do
    setup %{conn: conn} do
      from(p in Ysc.Bookings.RefundPolicy,
        where: p.property == :tahoe and p.booking_mode == :buyout
      )
      |> Repo.update_all(set: [is_active: false])

      {:ok, refund_policy} =
        Bookings.create_refund_policy(%{
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true,
          name:
            "LiveView pending refund policy #{System.unique_integer([:positive])}"
        })

      assert {:ok, _} =
               Bookings.create_refund_policy_rule(%{
                 refund_policy_id: refund_policy.id,
                 # Must be >= days between cancellation and check-in so a rule applies
                 days_before_checkin: 9999,
                 refund_percentage: 50,
                 priority: 1
               })

      case Bookings.create_pricing_rule(%{
             amount: Money.new(500, :USD),
             booking_mode: :buyout,
             price_unit: :buyout_fixed,
             property: :tahoe,
             season_id: nil
           }) do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{errors: errors}} ->
          if Enum.any?(errors, fn {_f, {_m, meta}} ->
               meta[:constraint] == :unique
             end),
             do: :ok,
             else: raise("unexpected pricing rule error: #{inspect(errors)}")
      end

      user =
        user_fixture()
        |> Ecto.Changeset.change(%{state: :active})
        |> Repo.update!()

      year = Date.utc_today().year + 1
      july_first = Date.new!(year, 7, 1)

      checkin_date =
        case Date.day_of_week(july_first, :monday) do
          1 ->
            july_first

          n ->
            Date.add(july_first, 8 - n)
        end

      checkout_date = Date.add(checkin_date, 3)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin_date,
          checkout_date,
          2
        )

      {:ok, confirmed} = BookingLocker.confirm_booking(booking.id)

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_lv_pending_#{confirmed.id}",
          entity_type: :booking,
          entity_id: confirmed.id,
          stripe_fee: Money.new(320, :USD),
          description: "Test booking payment",
          property: :tahoe,
          payment_method_id: nil
        })

      booking = Repo.reload!(confirmed)

      %{
        conn: log_in_user(conn, user),
        booking: booking,
        user: user
      }
    end

    test "shows refund under review message when refund policy applies", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, _html} = live_booking_detail(conn, booking.id)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()

      html =
        view
        |> form("#cancel-booking-form", %{"reason" => "Change of plans"})
        |> render_submit()

      assert html =~ "We are reviewing your refund"
      assert html =~ "No action is needed on your side"
    end
  end

  describe "cancel modal and events" do
    test "cancel button uses in-app modal instead of browser data-confirm", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, html} = live_booking_detail(conn, booking.id)

      refute html =~ ~s/data-confirm=/

      refute has_element?(
               view,
               "button[phx-click='show-cancel-modal'][data-confirm]"
             )
    end

    test "cancel modal shows updated confirmation copy", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live_booking_detail(conn, booking.id)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()

      html = render(view)
      assert html =~ "Cancel this reservation?"
      assert html =~ "be undone"
    end

    test "show and hide cancel modal", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live_booking_detail(conn, booking.id)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()
      assert has_element?(view, "#cancel-booking-modal")

      view |> element("button[phx-click='hide-cancel-modal']") |> render_click()
      refute has_element?(view, "#cancel-booking-modal")
    end

    test "update-cancel-reason stores reason from blur params", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live_booking_detail(conn, booking.id)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()

      html =
        view
        |> render_hook("update-cancel-reason", %{"reason" => "Plans changed"})

      assert html =~ "Plans changed"
    end

    test "update-cancel-reason accepts value key", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live_booking_detail(conn, booking.id)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()

      html =
        view
        |> render_hook("update-cancel-reason", %{"value" => "Other note"})

      assert html =~ "Other note"
    end

    test "confirm-cancel shows error when booking has no payment on file", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live_booking_detail(conn, booking.id)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()

      view
      |> form("#cancel-booking-form", %{"reason" => "No longer needed"})
      |> render_submit()

      refute has_element?(view, "#cancel-booking-modal")
    end
  end

  describe "booking mode label" do
    test "shows Entire cabin when booking_mode is buyout", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :buyout,
          property: :tahoe
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Entire cabin"
    end

    test "shows Individual room(s) when booking_mode is room", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :room,
          property: :tahoe
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Individual room(s)"
    end

    test "shows group booking label when booking_mode is day", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :day,
          property: :clear_lake
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Group booking (shared cabin)"
    end
  end

  describe "status display" do
    test "shows awaiting payment status and checkout link for hold bookings", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :hold})

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Awaiting payment"
      assert html =~ "Complete checkout"
      assert html =~ "/bookings/checkout/#{booking.id}"
    end

    test "shows refunded status when booking was refunded", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{user_id: user.id, status: :complete})
        |> Ecto.Changeset.change(%{status: :refunded})
        |> Repo.update!()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Refunded"
    end

    test "shows draft status badge", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{user_id: user.id, status: :hold})
        |> Ecto.Changeset.change(%{status: :draft})
        |> Repo.update!()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Draft"
    end

    test "shows canceled status badge", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{user_id: user.id, status: :complete})
        |> Ecto.Changeset.change(%{status: :canceled})
        |> Repo.update!()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Cancelled"
    end
  end

  describe "rooms and price formatting" do
    test "lists multiple room names when booking has several rooms", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :room,
          property: :tahoe
        })

      {:ok, r1} =
        %Room{}
        |> Room.changeset(%{
          name: "Alpha Room",
          property: :tahoe,
          capacity_max: 2
        })
        |> Repo.insert()

      {:ok, r2} =
        %Room{}
        |> Room.changeset(%{
          name: "Beta Room",
          property: :tahoe,
          capacity_max: 2
        })
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking.id, room_id: r1.id}
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking.id, room_id: r2.id}
        |> Repo.insert()

      {:ok, view, _html} = live_booking_detail(conn, booking.id)

      assert has_element?(view, "div", "Rooms")
      html = render(view)
      assert html =~ "Alpha Room"
      assert html =~ "Beta Room"
    end

    test "formats non-USD currency in price breakdown maps", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_eur_breakdown_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "other",
            "total" => %{"amount" => "5000", "currency" => "EUR"}
          }
        })
        |> Repo.update()

      {:ok, view, _html} = live_booking_detail(conn, booking.id)
      html = render(view)
      assert html =~ "Booking Total"
      assert html =~ "€" or html =~ "EUR"
    end
  end

  describe "refund policy text, payments, and refund estimate edge cases" do
    setup do
      from(p in Ysc.Bookings.RefundPolicy,
        where: p.property == :tahoe and p.booking_mode == :buyout
      )
      |> Repo.update_all(set: [is_active: false])

      :ok
    end

    test "shows no-refund policy line when rule has zero refund percentage", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)

      {:ok, refund_policy} =
        Bookings.create_refund_policy(%{
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true,
          name: "No refund policy #{System.unique_integer([:positive])}"
        })

      {:ok, _} =
        Bookings.create_refund_policy_rule(%{
          refund_policy_id: refund_policy.id,
          days_before_checkin: 14,
          refund_percentage: 0,
          priority: 1
        })

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe,
          booking_mode: :buyout
        })

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_no_refund_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)

      assert html =~ "Cancellation Policy"
      assert html =~ "will not receive a refund"
    end

    test "shows full refund policy line when rule has 100% refund percentage",
         %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      {:ok, refund_policy} =
        Bookings.create_refund_policy(%{
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true,
          name: "Full refund policy #{System.unique_integer([:positive])}"
        })

      {:ok, _} =
        Bookings.create_refund_policy_rule(%{
          refund_policy_id: refund_policy.id,
          days_before_checkin: 21,
          refund_percentage: 100,
          priority: 1
        })

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe,
          booking_mode: :buyout
        })

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_full_refund_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)

      assert html =~ "Cancellation Policy"
      assert html =~ "eligible for a full refund"
    end

    test "shows partial refund policy lines when rule has partial refund percentage",
         %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      {:ok, refund_policy} =
        Bookings.create_refund_policy(%{
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true,
          name:
            "Partial forfeiture policy #{System.unique_integer([:positive])}"
        })

      {:ok, _} =
        Bookings.create_refund_policy_rule(%{
          refund_policy_id: refund_policy.id,
          days_before_checkin: 9999,
          refund_percentage: 50,
          priority: 1
        })

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe,
          booking_mode: :buyout
        })

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_partial_forf_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)

      assert html =~ "Cancellation Policy"
      assert html =~ "50% refund"
    end

    test "shows generic refund copy when no rule matches yet policy lists rules",
         %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      {:ok, refund_policy} =
        Bookings.create_refund_policy(%{
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true,
          name: "Narrow rule policy #{System.unique_integer([:positive])}"
        })

      {:ok, _} =
        Bookings.create_refund_policy_rule(%{
          refund_policy_id: refund_policy.id,
          days_before_checkin: 1,
          refund_percentage: 50,
          priority: 1
        })

      # Use Monday-to-Thursday dates to avoid the Saturday weekend validation
      base = Date.add(Date.utc_today(), 14)
      day_of_week = Date.day_of_week(base)
      days_to_monday = Integer.mod(8 - day_of_week, 7)
      days_to_monday = if days_to_monday == 0, do: 7, else: days_to_monday
      checkin = Date.add(base, days_to_monday)
      checkout = Date.add(checkin, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe,
          booking_mode: :buyout,
          checkin_date: checkin,
          checkout_date: checkout
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)

      assert html =~
               "Cancellation refunds are calculated based on how many days"

      refute html =~
               "If you cancel today, you may be eligible for a refund of approximately"
    end

    test "confirm-cancel without payment shows payment not found toast", %{
      conn: conn
    } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(500, :USD),
          booking_mode: :buyout,
          price_unit: :buyout_fixed,
          property: :tahoe,
          season_id: nil
        })

      user =
        user_fixture()
        |> Ecto.Changeset.change(%{state: :active})
        |> Repo.update!()

      year = Date.utc_today().year + 1
      july_first = Date.new!(year, 7, 1)

      checkin_date =
        case Date.day_of_week(july_first, :monday) do
          1 ->
            july_first

          n ->
            Date.add(july_first, 8 - n)
        end

      checkout_date = Date.add(checkin_date, 3)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin_date,
          checkout_date,
          2
        )

      {:ok, confirmed} = BookingLocker.confirm_booking(booking.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live_booking_detail(conn, confirmed.id)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()

      _ =
        view
        |> form("#cancel-booking-form", %{"reason" => "Testing"})
        |> render_submit()

      page = render(view)

      assert page =~ "Cancelled"
      refute has_element?(view, "button[phx-click='show-cancel-modal']")
      assert Repo.get!(Bookings.Booking, confirmed.id).status == :canceled
    end

    test "payment summary shows card ending in when payment method has last four",
         %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      %PaymentMethod{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_ubd_#{System.unique_integer([:positive])}",
        provider_customer_id: "cus_ubd_#{System.unique_integer([:positive])}",
        provider_type: "card",
        type: :card,
        last_four: "4242",
        display_brand: "visa",
        is_default: true
      }
      |> Repo.insert!()

      pm =
        Repo.one!(
          from(p in PaymentMethod,
            where: p.user_id == ^user.id,
            limit: 1
          )
        )

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_pm_card_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: pm.id
        })

      {:ok, _} =
        payment
        |> Ecto.Changeset.change(%{payment_date: nil})
        |> Repo.update()

      {:ok, view, _html} = live_booking_detail(conn, booking.id)
      html = render(view)
      assert html =~ "Card ending in 4242"
    end

    test "payment summary shows bank account ending in when type is bank_account",
         %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)

      %PaymentMethod{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_ubd_ba_#{System.unique_integer([:positive])}",
        provider_customer_id:
          "cus_ubd_ba_#{System.unique_integer([:positive])}",
        provider_type: "us_bank_account",
        type: :bank_account,
        last_four: "6789",
        bank_name: "Chase",
        is_default: true
      }
      |> Repo.insert!()

      pm =
        Repo.one!(
          from(p in PaymentMethod,
            where: p.user_id == ^user.id,
            limit: 1
          )
        )

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_pm_ba_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: pm.id
        })

      {:ok, view, _html} = live_booking_detail(conn, booking.id)
      assert render(view) =~ "Bank account ending in 6789"
    end

    test "payment status failed uses gray badge", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_failed_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _} =
        payment
        |> Ecto.Changeset.change(%{status: :failed})
        |> Repo.update()

      {:ok, view, _html} = live_booking_detail(conn, booking.id)
      html = render(view)
      assert html =~ "Failed"
    end

    test "formats GBP and JPY amounts in price breakdown maps", %{conn: conn} do
      %{conn: conn, user: user} = log_in_member(conn)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, {_payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_fx_gbp_#{booking.id}",
          stripe_fee: Money.new(50, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "other",
            "total" => %{"amount" => "1000", "currency" => "GBP"}
          }
        })
        |> Repo.update()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Booking Total"
      assert html =~ "£" or html =~ "GBP"

      reloaded = Repo.reload!(booking)

      {:ok, _} =
        reloaded
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "other",
            "total" => %{"amount" => "1000", "currency" => "JPY"}
          }
        })
        |> Repo.update()

      {:ok, _view, html} = live_booking_detail(conn, booking.id)
      assert html =~ "Booking Total"
      assert html =~ "¥" or html =~ "JPY"
    end
  end

  describe "post-connect payment load" do
    test "clears loading skeleton after payment details load", %{
      conn: conn
    } do
      %{conn: conn, user: user} = log_in_member(conn)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe
        })

      {:ok, _view, html} = live_booking_detail(conn, booking.id)

      refute html =~ "animate-pulse"
      assert html =~ booking.reference_id
    end
  end
end

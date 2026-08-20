defmodule YscWeb.BookingChangeLiveTest do
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Mox

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker, RoomCategory}
  alias Ysc.Ledgers
  alias Ysc.Repo
  alias Ysc.StripeMock

  setup do
    Ledgers.ensure_basic_accounts()

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(500, :USD),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe,
        season_id: nil
      })

    :ok
  end

  @change_async_timeout 5_000

  defp live_change(conn, booking) do
    {:ok, view, html} = live(conn, ~p"/bookings/#{booking.id}/change")
    html = render_async(view, @change_async_timeout) || html
    {view, html}
  end

  defp complete_booking!(user) do
    {checkin, checkout} = tahoe_booking_dates(35)

    assert {:ok, total, _} =
             Bookings.calculate_booking_price(
               :tahoe,
               checkin,
               checkout,
               :buyout,
               guests_count: 4
             )

    assert {:ok, booking} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: user.id,
                 property: :tahoe,
                 checkin_date: checkin,
                 checkout_date: checkout,
                 booking_mode: :buyout,
                 guests_count: 4,
                 total_price: total
               },
               skip_email: true,
               skip_reminders: true
             )

    assert {:ok, _} =
             Ledgers.process_payment(%{
               user_id: user.id,
               amount: total,
               entity_type: :booking,
               entity_id: booking.id,
               external_payment_id:
                 "pi_change_live_#{System.unique_integer([:positive])}",
               stripe_fee: Money.new(100, :USD),
               description: "Booking payment",
               property: booking.property,
               payment_method_id: nil
             })

    Repo.preload(booking, [:rooms, :user])
  end

  test "redirects when booking is not found", %{conn: conn} do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: path}}} =
             live(conn, ~p"/bookings/#{Ecto.ULID.generate()}/change")

    assert path == ~p"/"
  end

  test "shows forfeiture notice and change form for eligible booking", %{
    conn: conn
  } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, html} = live_change(conn, booking)

    assert html =~ "Change Booking"
    assert html =~ "No refunds for changed dates"
    assert html =~ "cannot get a refund later"
    assert html =~ "Check-in &amp; Check-out Dates"
    assert has_element?(view, "#modification-dates")
    assert has_element?(view, "#refund-forfeiture-notice")
    assert has_element?(view, "#acknowledge-forfeiture")
    assert has_element?(view, "#submit-modification-button")

    refute html =~ "Loading availability and price preview"
    refute html =~ "Number of guests"
  end

  test "dead render serves loading shell without booking or availability queries",
       %{
         conn: conn
       } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    conn = get(conn, ~p"/bookings/#{booking.id}/change")
    html = html_response(conn, 200)

    assert html =~ ~s|id="booking-change-loading"|
    refute html =~ booking.reference_id
    refute html =~ "Loading availability and price preview"
    refute html =~ "No refunds for changed dates"
  end

  test "submit is blocked until acknowledgment is checked", %{conn: conn} do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, _html} = live_change(conn, booking)

    new_checkin = Date.add(booking.checkin_date, 7)
    new_checkout = Date.add(booking.checkout_date, 7)

    send(view.pid, {:updated_event, updated_event(new_checkin, new_checkout)})
    _html = render(view)

    checkin = date_to_datetime_string(new_checkin)
    checkout = date_to_datetime_string(new_checkout)

    view
    |> form("#booking-change-form", %{
      "modification" => %{
        "checkin_date" => checkin,
        "checkout_date" => checkout
      }
    })
    |> render_submit()

    assert render(view) =~
             "Please check the box at the bottom of the form confirming you understand"

    view |> element("#acknowledge-forfeiture") |> render_click()

    refute has_element?(view, "#submit-modification-button[disabled]")
  end

  test "payment-redirect-started is a no-op", %{conn: conn} do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, html} = live_change(conn, booking)

    assert html =~ "Change Booking"

    html =
      view
      |> render_click("payment-redirect-started", %{})

    assert html =~ "Change Booking"
  end

  test "Clear Lake change calendar allows Saturday check-in and check-out", %{
    conn: conn
  } do
    ensure_clear_lake_day_pricing_rule!()

    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)

    # Stay inside Clear Lake summer (calendar max is season end when advance is nil).
    checkin = Date.utc_today() |> Date.add(21) |> first_monday_on_or_after()
    checkout = Date.add(checkin, 2)
    booking = complete_clear_lake_day_booking!(user, checkin, checkout, 3)

    {view, _html} = live_change(conn, booking)

    saturday = first_saturday_on_or_after(Date.add(checkin, 7))
    sunday = Date.add(saturday, 1)

    view
    |> element("#modification-dates [phx-click=open-calendar]")
    |> render_click()

    # Navigate to the month containing the Saturday if needed
    navigate_calendar_to_month!(view, saturday)

    assert has_element?(
             view,
             ~s|#modification-dates button[phx-value-date="#{Date.to_iso8601(saturday)}T00:00:00Z"]:not([disabled])|
           )

    assert has_element?(
             view,
             ~s|#modification-dates button[phx-value-date="#{Date.to_iso8601(sunday)}T00:00:00Z"]:not([disabled])|
           )
  end

  test "Tahoe change calendar allows Saturday check-in for Sat→Sun stays", %{
    conn: conn
  } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, _html} = live_change(conn, booking)

    saturday = first_saturday_on_or_after(Date.add(booking.checkin_date, 7))
    sunday = Date.add(saturday, 1)
    monday = Date.add(saturday, 2)

    view
    |> element("#modification-dates [phx-click=open-calendar]")
    |> render_click()

    navigate_calendar_to_month!(view, saturday)

    assert has_element?(
             view,
             ~s|#modification-dates button[phx-value-date="#{Date.to_iso8601(saturday)}T00:00:00Z"]:not([disabled])|
           )

    view
    |> element(
      ~s|#modification-dates button[phx-value-date="#{Date.to_iso8601(saturday)}T00:00:00Z"]|
    )
    |> render_click()

    assert has_element?(
             view,
             ~s|#modification-dates button[phx-value-date="#{Date.to_iso8601(sunday)}T00:00:00Z"]:not([disabled])|
           )

    assert has_element?(
             view,
             ~s|#modification-dates button[phx-value-date="#{Date.to_iso8601(monday)}T00:00:00Z"][disabled]|
           )
  end

  test "shows guest info step when adding guests to tahoe room booking", %{
    conn: conn
  } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: nil
      })

    room = create_test_room!()
    {checkin, checkout} = tahoe_booking_dates(35)
    booking = complete_room_booking!(user, room, checkin, checkout)

    assert {:ok, _} =
             Bookings.create_booking_guests(booking.id, [
               {0,
                %{
                  "first_name" => user.first_name || "Test",
                  "last_name" => user.last_name || "User",
                  "is_child" => false,
                  "is_booking_user" => true
                }},
               {1,
                %{
                  "first_name" => "Guest",
                  "last_name" => "Two",
                  "is_child" => false,
                  "is_booking_user" => false
                }}
             ])

    {view, _html} = live_change(conn, booking)

    checkin_str = date_to_datetime_string(booking.checkin_date)
    checkout_str = date_to_datetime_string(booking.checkout_date)

    view
    |> form("#booking-change-form", %{
      "modification" => %{
        "checkin_date" => checkin_str,
        "checkout_date" => checkout_str,
        "guests_count" => "3",
        "children_count" => "0"
      }
    })
    |> render_change()

    view |> element("#acknowledge-forfeiture") |> render_click()

    html =
      view
      |> form("#booking-change-form", %{
        "modification" => %{
          "checkin_date" => checkin_str,
          "checkout_date" => checkout_str,
          "guests_count" => "3",
          "children_count" => "0"
        }
      })
      |> render_submit()

    assert html =~ "Guest Information"
    assert has_element?(view, "#modification-guest-info-form")
    assert has_element?(view, "#guest-1-first-name")
    assert render(view) =~ "Guest"
  end

  test "shows capacity error when children exceed room max occupancy", %{
    conn: conn
  } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: nil
      })

    room = create_test_room!()
    {checkin, checkout} = tahoe_booking_dates(35)
    booking = complete_room_booking!(user, room, checkin, checkout)

    {view, _html} = live_change(conn, booking)

    checkin_str = date_to_datetime_string(booking.checkin_date)
    checkout_str = date_to_datetime_string(booking.checkout_date)

    html =
      view
      |> form("#booking-change-form", %{
        "modification" => %{
          "checkin_date" => checkin_str,
          "checkout_date" => checkout_str,
          "guests_count" => "2",
          "children_count" => "3"
        }
      })
      |> render_change()

    assert html =~ "modification-preview-error"
    assert html =~ "Total room capacity is 4"
  end

  test "shows plain-language buyout message when extending into a buyout reservation",
       %{
         conn: conn
       } do
    user = user_fixture() |> active_user(conn)
    other_user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: nil
      })

    room = create_test_room!()
    # Mon–Wed room stay, then a Wed–Fri buyout (weekday nights only) so the
    # one-night extension collides without hitting winter/weekend rules.
    {checkin, _} = locker_buyout_dates(8)
    checkout = Date.add(checkin, 2)
    booking = complete_room_booking!(user, room, checkin, checkout)

    overlapping_checkin = checkout
    overlapping_checkout = Date.add(checkout, 2)

    assert {:ok, _} =
             BookingLocker.create_buyout_booking(
               other_user.id,
               :tahoe,
               overlapping_checkin,
               overlapping_checkout,
               4
             )

    {view, _html} = live_change(conn, booking)

    checkin_str = date_to_datetime_string(booking.checkin_date)
    extended_checkout_str = date_to_datetime_string(Date.add(checkout, 1))

    send(
      view.pid,
      {:updated_event,
       updated_event(booking.checkin_date, Date.add(checkout, 1))}
    )

    render(view)

    html =
      view
      |> form("#booking-change-form", %{
        "modification" => %{
          "checkin_date" => checkin_str,
          "checkout_date" => extended_checkout_str
        }
      })
      |> render_change()

    assert html =~ "modification-preview-error"
    assert html =~ "whole cabin is already booked"
  end

  test "shows plain-language blackout message when dates overlap a blackout period",
       %{
         conn: conn
       } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    extended_checkout = Date.add(booking.checkout_date, 1)

    assert {:ok, _} =
             Bookings.create_blackout(%{
               property: :tahoe,
               reason: "Maintenance",
               start_date: booking.checkout_date,
               end_date: extended_checkout
             })

    {view, _html} = live_change(conn, booking)

    checkin_str = date_to_datetime_string(booking.checkin_date)
    extended_checkout_str = date_to_datetime_string(extended_checkout)

    send(
      view.pid,
      {:updated_event, updated_event(booking.checkin_date, extended_checkout)}
    )

    render(view)

    html =
      view
      |> form("#booking-change-form", %{
        "modification" => %{
          "checkin_date" => checkin_str,
          "checkout_date" => extended_checkout_str
        }
      })
      |> render_change()

    assert html =~ "modification-preview-error"
    assert html =~ "available for booking"
    refute html =~ "blackout"
  end

  test "dismisses payment form when dates no longer require additional payment",
       %{
         conn: conn
       } do
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, StripeMock)

    stub(StripeMock, :create_payment_intent, fn _params, _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_change_upgrade",
         client_secret: "pi_change_upgrade_secret",
         status: "requires_payment_method"
       }}
    end)

    stub(StripeMock, :cancel_payment_intent, fn "pi_change_upgrade", _opts ->
      {:ok, %Stripe.PaymentIntent{id: "pi_change_upgrade", status: "canceled"}}
    end)

    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    extended_checkout = Date.add(booking.checkout_date, 1)
    checkin_str = date_to_datetime_string(booking.checkin_date)
    extended_checkout_str = date_to_datetime_string(extended_checkout)

    {view, _html} = live_change(conn, booking)

    send(
      view.pid,
      {:updated_event, updated_event(booking.checkin_date, extended_checkout)}
    )

    render(view)

    view |> element("#acknowledge-forfeiture") |> render_click()

    html =
      view
      |> form("#booking-change-form", %{
        "modification" => %{
          "checkin_date" => checkin_str,
          "checkout_date" => extended_checkout_str
        }
      })
      |> render_submit()

    assert html =~ "Additional payment required" || html =~ "Complete payment"
    assert has_element?(view, "#modification-payment-step")
    assert has_element?(view, "#stripe-payment-container")
    refute has_element?(view, "#modification-dates")
    refute has_element?(view, "#submit-modification-button")
    refute has_element?(view, "#refund-forfeiture-notice")

    view |> element("#back-to-modification-button") |> render_click()

    html = render(view)
    assert has_element?(view, "#modification-dates")
    assert has_element?(view, "#submit-modification-button")
    refute has_element?(view, "#modification-payment-step")
    assert html =~ date_to_datetime_string(extended_checkout)

    send(
      view.pid,
      {:updated_event,
       updated_event(booking.checkin_date, booking.checkout_date)}
    )

    _html = render(view)
    refute has_element?(view, "#stripe-payment-container")
    assert has_element?(view, "#submit-modification-button")
    refute has_element?(view, "#submit-payment")
  end

  test "returns to editable form with pending changes when backing out of payment",
       %{conn: conn} do
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, StripeMock)

    stub(StripeMock, :create_payment_intent, fn _params, _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_change_back",
         client_secret: "pi_change_back_secret",
         status: "requires_payment_method"
       }}
    end)

    expect(StripeMock, :cancel_payment_intent, fn "pi_change_back", _opts ->
      {:ok, %Stripe.PaymentIntent{id: "pi_change_back", status: "canceled"}}
    end)

    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    extended_checkout = Date.add(booking.checkout_date, 1)
    checkin_str = date_to_datetime_string(booking.checkin_date)
    extended_checkout_str = date_to_datetime_string(extended_checkout)

    {view, _html} = live_change(conn, booking)

    send(
      view.pid,
      {:updated_event, updated_event(booking.checkin_date, extended_checkout)}
    )

    render(view)

    view |> element("#acknowledge-forfeiture") |> render_click()

    view
    |> form("#booking-change-form", %{
      "modification" => %{
        "checkin_date" => checkin_str,
        "checkout_date" => extended_checkout_str
      }
    })
    |> render_submit()

    assert has_element?(view, "#modification-payment-step")

    view |> element("#back-to-modification-button") |> render_click()

    html = render(view)
    assert has_element?(view, "#modification-dates")
    assert has_element?(view, "#submit-modification-button")
    assert html =~ extended_checkout_str
    refute has_element?(view, "#modification-payment-step")
  end

  test "shows downgrade notice when shortening stay reduces total", %{
    conn: conn
  } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, _html} = live_change(conn, booking)

    shorter_checkout = Date.add(booking.checkout_date, -1)

    send(
      view.pid,
      {:updated_event, updated_event(booking.checkin_date, shorter_checkout)}
    )

    _html = render(view)

    view
    |> form("#booking-change-form", %{
      "modification" => %{
        "checkin_date" => date_to_datetime_string(booking.checkin_date),
        "checkout_date" => date_to_datetime_string(shorter_checkout)
      }
    })
    |> render_change()

    html = render(view)
    assert html =~ "modification-downgrade-notice"
    assert html =~ "do not refund the difference"
  end

  test "Clear Lake price preview shows previous and new calculation breakdown",
       %{
         conn: conn
       } do
    ensure_clear_lake_day_pricing_rule!()

    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)

    checkin = Date.utc_today() |> Date.add(21) |> first_monday_on_or_after()
    checkout = Date.add(checkin, 2)
    booking = complete_clear_lake_day_booking!(user, checkin, checkout, 3)

    {view, _html} = live_change(conn, booking)

    new_checkin = Date.add(checkin, 7)
    new_checkout = Date.add(new_checkin, 1)

    send(view.pid, {:updated_event, updated_event(new_checkin, new_checkout)})
    _html = render(view)

    view
    |> form("#booking-change-form", %{
      "modification" => %{
        "checkin_date" => date_to_datetime_string(new_checkin),
        "checkout_date" => date_to_datetime_string(new_checkout),
        "guests_count" => "3"
      }
    })
    |> render_change()

    html = render(view)

    assert has_element?(view, "#modification-price-preview")
    assert has_element?(view, "#modification-price-comparison")
    assert has_element?(view, "#modification-previous-price")
    assert has_element?(view, "#modification-new-price")
    assert has_element?(view, "#modification-amount-due")
    assert html =~ "Price Summary"
    assert html =~ "Previous"
    assert html =~ "New"
    assert html =~ "3 guests"
    assert html =~ "2 nights"
    assert html =~ "1 night"
  end

  defp complete_room_booking!(user, room, checkin, checkout) do
    assert {:ok, total, _} =
             Bookings.calculate_booking_price(
               :tahoe,
               checkin,
               checkout,
               :room,
               room_id: room.id,
               guests_count: 2
             )

    assert {:ok, booking} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: user.id,
                 property: :tahoe,
                 checkin_date: checkin,
                 checkout_date: checkout,
                 booking_mode: :room,
                 guests_count: 2,
                 total_price: total
               },
               rooms: [room],
               skip_email: true,
               skip_reminders: true
             )

    assert {:ok, _} =
             Ledgers.process_payment(%{
               user_id: user.id,
               amount: total,
               entity_type: :booking,
               entity_id: booking.id,
               external_payment_id:
                 "pi_change_room_#{System.unique_integer([:positive])}",
               stripe_fee: Money.new(100, :USD),
               description: "Booking payment",
               property: booking.property,
               payment_method_id: nil
             })

    Repo.preload(booking, [:rooms, :user])
  end

  defp create_test_room! do
    {:ok, category} =
      %RoomCategory{}
      |> RoomCategory.changeset(%{name: "Change live test category"})
      |> Repo.insert()

    {:ok, room} =
      Bookings.create_room(%{
        name: "Change live test room #{System.unique_integer([:positive])}",
        property: :tahoe,
        room_category_id: category.id,
        capacity_max: 4
      })

    room
  end

  defp active_user(user, _conn) do
    user
    |> Ecto.Changeset.change(state: :active)
    |> Repo.update!()
  end

  defp date_to_datetime_string(%Date{} = date) do
    Date.to_iso8601(date) <> "T00:00:00Z"
  end

  defp updated_event(checkin, checkout) do
    %{
      id: "modification-dates",
      start_date: DateTime.new!(checkin, ~T[00:00:00], "Etc/UTC"),
      end_date: DateTime.new!(checkout, ~T[00:00:00], "Etc/UTC")
    }
  end

  defp first_monday_on_or_after(%Date{} = date) do
    days_until_monday = rem(8 - Date.day_of_week(date, :monday), 7)
    Date.add(date, days_until_monday)
  end

  defp first_saturday_on_or_after(%Date{} = date) do
    days_until_saturday = rem(6 - Date.day_of_week(date, :monday), 7)
    Date.add(date, days_until_saturday)
  end

  defp ensure_clear_lake_day_pricing_rule! do
    Ysc.Bookings.SeasonCache.invalidate()
    Cachex.clear(:ysc_cache)

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(:USD, 30),
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        property: :clear_lake,
        season_id: nil
      })
  end

  defp complete_clear_lake_day_booking!(user, checkin, checkout, guests) do
    assert {:ok, hold} =
             BookingLocker.create_per_guest_booking(
               user.id,
               :clear_lake,
               checkin,
               checkout,
               guests
             )

    assert {:ok, booking} = BookingLocker.confirm_booking(hold.id)

    assert {:ok, _} =
             Ledgers.process_payment(%{
               user_id: user.id,
               amount: booking.total_price,
               entity_type: :booking,
               entity_id: booking.id,
               external_payment_id:
                 "pi_change_cl_#{System.unique_integer([:positive])}",
               stripe_fee: Money.new(100, :USD),
               description: "Booking payment",
               property: booking.property,
               payment_method_id: nil
             })

    Repo.preload(booking, [:rooms, :user])
  end

  test "payment-success redirects to receipt when paid modification cannot be applied yet",
       %{conn: conn} do
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, StripeMock)

    stub(StripeMock, :create_payment_intent, fn _params, _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_change_recover",
         client_secret: "pi_change_recover_secret",
         status: "requires_payment_method"
       }}
    end)

    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    extended_checkout = Date.add(booking.checkout_date, 1)
    checkin_str = date_to_datetime_string(booking.checkin_date)
    extended_checkout_str = date_to_datetime_string(extended_checkout)

    {view, _html} = live_change(conn, booking)

    send(
      view.pid,
      {:updated_event, updated_event(booking.checkin_date, extended_checkout)}
    )

    render(view)

    view |> element("#acknowledge-forfeiture") |> render_click()

    view
    |> form("#booking-change-form", %{
      "modification" => %{
        "checkin_date" => checkin_str,
        "checkout_date" => extended_checkout_str
      }
    })
    |> render_submit()

    assert has_element?(view, "#modification-payment-step")

    payment_delta =
      :sys.get_state(view.pid).socket.assigns.payment_delta

    assert Money.positive?(payment_delta)

    payment_intent_id =
      "pi_change_recover_#{System.unique_integer([:positive])}"

    amount_cents = Ysc.MoneyHelper.money_to_cents(payment_delta)

    expired_at =
      DateTime.utc_now()
      |> DateTime.add(-1, :minute)
      |> DateTime.truncate(:second)

    Repo.get!(Booking, booking.id)
    |> Ecto.Changeset.change(modification_hold_expires_at: expired_at)
    |> Repo.update!()

    assert {:ok, _} =
             Bookings.create_blackout(%{
               property: :tahoe,
               reason: "Blocks change live recoverable path",
               start_date: booking.checkin_date,
               end_date: extended_checkout
             })

    stub(StripeMock, :retrieve_payment_intent, fn ^payment_intent_id, _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: payment_intent_id,
         status: "succeeded",
         amount: amount_cents,
         metadata: %{
           "booking_id" => to_string(booking.id),
           "user_id" => to_string(booking.user_id),
           "modification" => "true"
         },
         latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
       }}
    end)

    render_click(view, "payment-success", %{
      "payment_intent_id" => payment_intent_id
    })

    {path, _flash} = assert_redirect(view, @change_async_timeout)

    assert path =~ "/bookings/#{booking.id}/receipt"
    assert path =~ "payment_intent=#{payment_intent_id}"
    assert path =~ "redirect_status=succeeded"
  end

  test "reloads change data after pricing rule cache invalidation", %{
    conn: conn
  } do
    user = user_fixture()
    booking = complete_booking!(user)
    conn = log_in_user(conn, user)

    {view, _html} = live_change(conn, booking)

    assert :sys.get_state(view.pid).socket.assigns.change_data_loaded?

    send(
      view.pid,
      {:pricing_rule_cache_invalidated, System.unique_integer([:positive])}
    )

    _ = render_async(view, @change_async_timeout)

    assert :sys.get_state(view.pid).socket.assigns.change_data_loaded?
    assert is_list(:sys.get_state(view.pid).socket.assigns.seasons)
  end

  test "reloads change data after season and rooms list cache invalidation",
       %{conn: conn} do
    user = user_fixture()
    booking = complete_booking!(user)
    conn = log_in_user(conn, user)

    {view, _html} = live_change(conn, booking)

    assert :sys.get_state(view.pid).socket.assigns.change_data_loaded?

    send(
      view.pid,
      {:season_cache_invalidated, System.unique_integer([:positive])}
    )

    _ = render_async(view, @change_async_timeout)
    assert :sys.get_state(view.pid).socket.assigns.change_data_loaded?

    send(
      view.pid,
      {:rooms_list_cache_invalidated, System.unique_integer([:positive])}
    )

    _ = render_async(view, @change_async_timeout)
    assert :sys.get_state(view.pid).socket.assigns.change_data_loaded?
  end

  test "back-to-modification without pending changes restores the current form",
       %{conn: conn} do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, _html} = live_change(conn, booking)

    html = view |> render_click("back-to-modification", %{})

    assert has_element?(view, "#modification-dates")
    assert html =~ date_to_datetime_string(booking.checkin_date)
  end

  test "stripe payment element loading and ready events toggle the assign",
       %{conn: conn} do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, _html} = live_change(conn, booking)

    render_click(view, "stripe-payment-element-ready", %{})

    assert :sys.get_state(view.pid).socket.assigns.stripe_payment_element_ready

    render_click(view, "stripe-payment-element-loading", %{})

    refute :sys.get_state(view.pid).socket.assigns.stripe_payment_element_ready
  end

  test "select-guest-attendee without a target key is a no-op", %{conn: conn} do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: nil
      })

    room = create_test_room!()
    {checkin, checkout} = tahoe_booking_dates(36)
    booking = complete_room_booking!(user, room, checkin, checkout)

    assert {:ok, _} =
             Bookings.create_booking_guests(booking.id, [
               {0,
                %{
                  "first_name" => user.first_name || "Test",
                  "last_name" => user.last_name || "User",
                  "is_child" => false,
                  "is_booking_user" => true
                }},
               {1,
                %{
                  "first_name" => "Guest",
                  "last_name" => "Two",
                  "is_child" => false,
                  "is_booking_user" => false
                }}
             ])

    {view, _html} = live_change(conn, booking)

    checkin_str = date_to_datetime_string(booking.checkin_date)
    checkout_str = date_to_datetime_string(booking.checkout_date)

    view |> element("#acknowledge-forfeiture") |> render_click()

    # Increasing guests_count enters the :guest_info step, which is the only
    # place guest_info_form/selected_family_members_for_guests get populated
    # — without this, both assigns would just be nil before and after,
    # making the no-op assertion below vacuous.
    view
    |> form("#booking-change-form", %{
      "modification" => %{
        "checkin_date" => checkin_str,
        "checkout_date" => checkout_str,
        "guests_count" => "3",
        "children_count" => "0"
      }
    })
    |> render_submit()

    assigns_before = :sys.get_state(view.pid).socket.assigns
    assert assigns_before.guest_info_form

    render_click(view, "select-guest-attendee", %{"foo" => "bar"})

    assigns_after = :sys.get_state(view.pid).socket.assigns
    assert assigns_after.guest_info_form == assigns_before.guest_info_form

    assert assigns_after.selected_family_members_for_guests ==
             assigns_before.selected_family_members_for_guests
  end

  test "submit-modification shows toast when no changes were made", %{
    conn: conn
  } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, _html} = live_change(conn, booking)

    view |> element("#acknowledge-forfeiture") |> render_click()

    html =
      view
      |> form("#booking-change-form", %{
        "modification" => %{
          "checkin_date" => date_to_datetime_string(booking.checkin_date),
          "checkout_date" => date_to_datetime_string(booking.checkout_date)
        }
      })
      |> render_submit()

    assert html =~ "No changes were made to your booking."
  end

  test "submit-modification shows a validation error for an invalid date range",
       %{conn: conn} do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, _html} = live_change(conn, booking)

    view |> element("#acknowledge-forfeiture") |> render_click()

    invalid_checkout = Date.add(booking.checkin_date, -1)

    # Submitted directly via render_submit (bypassing the `form/2` DOM
    # helper) because the date-range picker's rendered hidden inputs only
    # allow the currently-selectable dates — submitting a date outside that
    # rendered range is exactly the invalid-input case under test here, and
    # `form/2` would reject it client-side before the server ever saw it.
    html =
      render_submit(view, "submit-modification", %{
        "modification" => %{
          "checkin_date" => date_to_datetime_string(booking.checkin_date),
          "checkout_date" => date_to_datetime_string(invalid_checkout)
        }
      })

    assert html =~ "modification-preview-error"
    assert html =~ "must be on or after check-in date"
  end

  test "submit-modification shows friendly error when check-in date is in the past",
       %{conn: conn} do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, _html} = live_change(conn, booking)

    view |> element("#acknowledge-forfeiture") |> render_click()

    past_checkin = Date.add(Date.utc_today(), -3)
    past_checkout = Date.add(past_checkin, 1)

    # See the invalid-date-range test above for why render_submit is used
    # directly instead of the `form/2` DOM helper.
    html =
      render_submit(view, "submit-modification", %{
        "modification" => %{
          "checkin_date" => date_to_datetime_string(past_checkin),
          "checkout_date" => date_to_datetime_string(past_checkout)
        }
      })

    assert html =~ "modification-preview-error"
    assert html =~ "Check-in date cannot be in the past."
  end

  test "submit-modification applies immediately when the change requires no additional payment",
       %{conn: conn} do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, _html} = live_change(conn, booking)

    shorter_checkout = Date.add(booking.checkout_date, -1)

    send(
      view.pid,
      {:updated_event, updated_event(booking.checkin_date, shorter_checkout)}
    )

    render(view)

    view |> element("#acknowledge-forfeiture") |> render_click()

    view
    |> form("#booking-change-form", %{
      "modification" => %{
        "checkin_date" => date_to_datetime_string(booking.checkin_date),
        "checkout_date" => date_to_datetime_string(shorter_checkout)
      }
    })
    |> render_submit()

    {path, flash} = assert_redirect(view, @change_async_timeout)

    assert path =~ "/bookings/#{booking.id}/receipt"
    assert path =~ "updated=true"
    assert flash["info"] =~ "Your booking has been updated."

    updated = Repo.get!(Booking, booking.id)
    assert updated.checkout_date == shorter_checkout
  end

  test "submit-modification shows an error when payment intent creation fails",
       %{conn: conn} do
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, StripeMock)

    stub(StripeMock, :create_payment_intent, fn _params, _opts ->
      {:error, "stripe is down"}
    end)

    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    extended_checkout = Date.add(booking.checkout_date, 1)
    checkin_str = date_to_datetime_string(booking.checkin_date)
    extended_checkout_str = date_to_datetime_string(extended_checkout)

    {view, _html} = live_change(conn, booking)

    send(
      view.pid,
      {:updated_event, updated_event(booking.checkin_date, extended_checkout)}
    )

    render(view)

    view |> element("#acknowledge-forfeiture") |> render_click()

    html =
      render_submit(view, "submit-modification", %{
        "modification" => %{
          "checkin_date" => checkin_str,
          "checkout_date" => extended_checkout_str
        }
      })

    # Avoid asserting across the apostrophe Phoenix HTML-escapes to &#39;.
    assert html =~ "start the payment form"
    refute has_element?(view, "#modification-payment-step")
    assert has_element?(view, "#modification-dates")
  end

  test "guest info flow: validate, select attendee, and save completes to payment",
       %{conn: conn} do
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, StripeMock)

    stub(StripeMock, :create_payment_intent, fn _params, _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_change_guest_flow",
         client_secret: "pi_change_guest_flow_secret",
         status: "requires_payment_method"
       }}
    end)

    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: nil
      })

    room = create_test_room!()
    {checkin, checkout} = tahoe_booking_dates(35)
    booking = complete_room_booking!(user, room, checkin, checkout)

    assert {:ok, _} =
             Bookings.create_booking_guests(booking.id, [
               {0,
                %{
                  "first_name" => user.first_name || "Test",
                  "last_name" => user.last_name || "User",
                  "is_child" => false,
                  "is_booking_user" => true
                }},
               {1,
                %{
                  "first_name" => "Guest",
                  "last_name" => "Two",
                  "is_child" => false,
                  "is_booking_user" => false
                }}
             ])

    {view, _html} = live_change(conn, booking)

    checkin_str = date_to_datetime_string(booking.checkin_date)
    checkout_str = date_to_datetime_string(booking.checkout_date)

    view |> element("#acknowledge-forfeiture") |> render_click()

    view
    |> form("#booking-change-form", %{
      "modification" => %{
        "checkin_date" => checkin_str,
        "checkout_date" => checkout_str,
        "guests_count" => "3",
        "children_count" => "0"
      }
    })
    |> render_submit()

    assert has_element?(view, "#modification-guest-info-form")

    # select-guest-attendee with a target key exercises the handled branch.
    render_click(view, "select-guest-attendee", %{
      "guest-2-attendee-select" => "other"
    })

    # validate-guest-info without a "guests" key is a no-op clause.
    render_change(view, "validate-guest-info", %{})

    # save-guest-info without a "guests" key shows the general error clause.
    html_missing = render_submit(view, "save-guest-info", %{})
    assert html_missing =~ "Please complete guest information"

    view
    |> form("#modification-guest-info-form", %{
      "guests" => %{"2" => %{"first_name" => "New", "last_name" => "Guest"}}
    })
    |> render_change()

    html =
      view
      |> form("#modification-guest-info-form", %{
        "guests" => %{"2" => %{"first_name" => "New", "last_name" => "Guest"}}
      })
      |> render_submit()

    assert html =~ "Complete payment"
    assert has_element?(view, "#modification-payment-step")
  end

  defp navigate_calendar_to_month!(view, %Date{} = target) do
    Enum.reduce_while(1..24, nil, fn _, _ ->
      html = render(view)

      if html =~ Calendar.strftime(target, "%B %Y") do
        {:halt, :ok}
      else
        view
        |> element("#modification-dates [phx-click=next-month]")
        |> render_click()

        {:cont, nil}
      end
    end) ||
      flunk(
        "Could not navigate calendar to #{Calendar.strftime(target, "%B %Y")}"
      )
  end
end

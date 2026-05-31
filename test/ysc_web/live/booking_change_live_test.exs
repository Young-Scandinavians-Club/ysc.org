defmodule YscWeb.BookingChangeLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings
  alias Ysc.Bookings.{BookingLocker, RoomCategory}
  alias Ysc.Ledgers
  alias Ysc.Repo

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

    assert {:error, {:redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/bookings/#{Ecto.ULID.generate()}/change")

    assert path == ~p"/"
    assert flash["error"] =~ "couldn't find this reservation"
  end

  test "shows forfeiture notice and change form for eligible booking", %{
    conn: conn
  } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    {view, html} = live_change(conn, booking)

    assert html =~ "Change Reservation"
    assert html =~ "Important: changing your dates affects refunds"
    assert html =~ "forfeit all refund eligibility"
    assert html =~ "cannot be undone"
    assert html =~ "Check-in &amp; Check-out Dates"
    assert has_element?(view, "#modification-dates")
    assert has_element?(view, "#refund-forfeiture-notice")
    assert has_element?(view, "#acknowledge-forfeiture")
    assert has_element?(view, "#submit-modification-button")

    refute html =~ "Loading availability and price preview"
    refute html =~ "Number of guests"
  end

  test "dead render serves change page shell without loading availability data",
       %{
         conn: conn
       } do
    user = user_fixture() |> active_user(conn)
    conn = log_in_user(conn, user)
    booking = complete_booking!(user)

    conn = get(conn, ~p"/bookings/#{booking.id}/change")
    html = html_response(conn, 200)

    assert html =~ "Change Reservation"
    assert html =~ "Loading availability and price preview"
    assert html =~ "refund forfeiture"
    refute html =~ "Price preview"
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

    assert html =~ "Change Reservation"

    html =
      view
      |> render_click("payment-redirect-started", %{})

    assert html =~ "Change Reservation"
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
end

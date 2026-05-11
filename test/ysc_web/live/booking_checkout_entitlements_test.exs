defmodule YscWeb.BookingCheckoutEntitlementsTest do
  @moduledoc """
  End-to-end LiveView coverage for cabin checkout with booking entitlements.

  Covers **Tahoe** and **Clear Lake**, **buyout** (direct payment step) and **room**
  (guest form → payment) flows.

  | Scenario | Expected checkout surface |
  |----------|---------------------------|
  | 100% percent-off (high cap), fixed amount ≥ subtotal, free nights = stay | Complimentary confirm |
  | Partial percent / fixed / free nights, or buyout cap | Stripe Elements (`#stripe-payment-container`) |
  | Entitlement property or room mismatch (including wrong `room_id`) | Redirect + flash (invalid benefit) |

  Buyout pricing is ensured via `ensure_buyout_base_pricing!/0` so totals are deterministic
  even when the DB has no seasonal buyout rules yet.
  """
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Ecto.Changeset
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Mox

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker, RoomCategory}
  alias Ysc.Bookings.Entitlements
  alias Ysc.Ledgers
  alias Ysc.Repo
  alias Ysc.StripeMock

  setup %{conn: conn} do
    Ledgers.ensure_basic_accounts()
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, StripeMock)

    stub(StripeMock, :create_payment_intent, fn _params, _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_test_#{System.unique_integer([:positive])}",
         client_secret: "pi_test_secret",
         status: "requires_payment_method"
       }}
    end)

    stub(StripeMock, :retrieve_payment_intent, fn _id, _opts ->
      {:error, :not_stubbed}
    end)

    stub(Stripe.PaymentIntentMock, :list, fn _params ->
      {:ok,
       %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         url: "/v1/payment_intents"
       }}
    end)

    ensure_buyout_base_pricing!()

    {:ok, conn: conn}
  end

  describe "buyout checkout — Tahoe" do
    setup %{conn: conn} do
      user = user_fixture()
      {checkin, checkout} = buyout_stay_dates()

      %{
        conn: log_in_user(conn, user),
        user: user,
        checkin: checkin,
        checkout: checkout
      }
    end

    test "100% percent-off with high cap → complimentary flow and confirmation",
         %{
           conn: conn,
           user: user,
           checkin: checkin,
           checkout: checkout
         } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :tahoe,
            percent_off: Decimal.new("100"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      assert checkout_shows_complimentary?(conn, booking)
      assert {:ok, _} = confirm_complimentary(conn, booking)
    end

    test "100% percent-off capped by buyout_max_discount → Stripe payment UI",
         %{
           conn: conn,
           user: user,
           checkin: checkin,
           checkout: checkout
         } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :tahoe,
            percent_off: Decimal.new("100"),
            buyout_max_discount: Money.new(1, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_paid_stripe?(conn, booking)
    end

    test "15% percent-off → Stripe payment UI", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :tahoe,
            percent_off: Decimal.new("15"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_paid_stripe?(conn, booking)
    end

    test "fixed amount off covering full subtotal → complimentary", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      subtotal = buyout_subtotal!(:tahoe, checkin, checkout, 4)
      {:ok, amount_off} = Money.add(subtotal, Money.new(500, :USD))

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :fixed_amount_off,
            property: :tahoe,
            amount_off: amount_off,
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_complimentary?(conn, booking)
      assert {:ok, _} = confirm_complimentary(conn, booking)
    end

    test "small fixed amount off → Stripe payment UI", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :fixed_amount_off,
            property: :tahoe,
            amount_off: Money.new(5, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_paid_stripe?(conn, booking)
    end

    test "free nights covering entire stay → complimentary", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      nights = Date.diff(checkout, checkin)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :free_nights,
            property: :tahoe,
            free_nights: nights,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_complimentary?(conn, booking)
      assert {:ok, _} = confirm_complimentary(conn, booking)
    end

    test "one free night on a longer stay → Stripe payment UI", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      assert Date.diff(checkout, checkin) > 1

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :free_nights,
            property: :tahoe,
            free_nights: 1,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_paid_stripe?(conn, booking)
    end

    test "100% percent-off with max_guests below party size scales discount → Stripe UI",
         %{
           conn: conn,
           user: user,
           checkin: checkin,
           checkout: checkout
         } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :tahoe,
            percent_off: Decimal.new("100"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 1
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_paid_stripe?(conn, booking)
    end

    test "redirects when locked entitlement is for another property", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :clear_lake,
            percent_off: Decimal.new("100"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      assert {:error, {:redirect, %{flash: flash}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert flash["error"] =~ "benefit" or flash["error"] =~ "valid"
    end
  end

  describe "buyout checkout — Clear Lake" do
    setup %{conn: conn} do
      user = user_fixture()
      {checkin, checkout} = buyout_stay_dates()

      %{
        conn: log_in_user(conn, user),
        user: user,
        checkin: checkin,
        checkout: checkout
      }
    end

    test "100% percent-off → complimentary and confirmation", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :clear_lake,
            percent_off: Decimal.new("100"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_complimentary?(conn, booking)
      assert {:ok, _} = confirm_complimentary(conn, booking)
    end

    test "25% percent-off → Stripe payment UI", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :clear_lake,
            percent_off: Decimal.new("25"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_paid_stripe?(conn, booking)
    end

    test "fixed amount off covering full subtotal → complimentary", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 4
               )

      subtotal = buyout_subtotal!(:clear_lake, checkin, checkout, 4)
      {:ok, amount_off} = Money.add(subtotal, Money.new(250, :USD))

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :fixed_amount_off,
            property: :clear_lake,
            amount_off: amount_off,
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_complimentary?(conn, booking)
      assert {:ok, _} = confirm_complimentary(conn, booking)
    end

    test "free nights covering entire stay → complimentary", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      nights = Date.diff(checkout, checkin)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :free_nights,
            property: :clear_lake,
            free_nights: nights,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_complimentary?(conn, booking)
      assert {:ok, _} = confirm_complimentary(conn, booking)
    end

    test "one free night on a longer stay → Stripe payment UI", %{
      conn: conn,
      user: user,
      checkin: checkin,
      checkout: checkout
    } do
      assert Date.diff(checkout, checkin) > 1

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 4
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :free_nights,
            property: :clear_lake,
            free_nights: 1,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)
      assert checkout_shows_paid_stripe?(conn, booking)
    end
  end

  describe "room checkout — Tahoe" do
    setup %{conn: conn} do
      user = user_fixture()
      {checkin, checkout} = room_stay_dates()

      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{
          name: "EntCat #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name: "EntRoom #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(120, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      assert {:ok, booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 2,
                 children_count: 0
               )

      booking = Repo.preload(booking, [:rooms])

      %{
        conn: log_in_user(conn, user),
        user: user,
        booking: booking,
        checkin: checkin,
        checkout: checkout
      }
    end

    test "100% percent-off → guest step then complimentary and confirmation", %{
      conn: conn,
      user: user,
      booking: booking
    } do
      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :tahoe,
            percent_off: Decimal.new("100"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      assert html =~ "Guest Information"

      html_after_save =
        view
        |> render_submit("save-guest-info", guest_form_params(user, 2, 0))

      assert html_after_save =~ "No payment is required" or
               html_after_save =~ "confirm-complimentary-booking"

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element("#confirm-complimentary-booking")
               |> render_click()

      assert path =~ "/receipt"
      assert Repo.get!(Booking, booking.id).status == :complete
    end

    test "20% percent-off → guest step then Stripe payment UI", %{
      conn: conn,
      user: user,
      booking: booking
    } do
      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :tahoe,
            percent_off: Decimal.new("20"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      assert html =~ "Guest Information"

      html_after_save =
        render_submit(view, "save-guest-info", guest_form_params(user, 2, 0))

      assert html_after_save =~ "stripe-payment-container"
      refute html_after_save =~ "confirm-complimentary-booking"
    end

    test "fixed amount covering computed room total → complimentary after guests",
         %{
           conn: conn,
           user: user,
           booking: booking,
           checkin: checkin,
           checkout: checkout
         } do
      {:ok, recalc_total, _} =
        Bookings.calculate_booking_price(
          :tahoe,
          checkin,
          checkout,
          :room,
          room_id: List.first(booking.rooms).id,
          guests_count: 2,
          children_count: 0
        )

      {:ok, amount_off} = Money.add(recalc_total, Money.new(100, :USD))

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :fixed_amount_off,
            property: :tahoe,
            amount_off: amount_off,
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      render_submit(view, "save-guest-info", guest_form_params(user, 2, 0))
      html = render(view)

      assert html =~ "confirm-complimentary-booking"

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element("#confirm-complimentary-booking")
               |> render_click()

      assert path =~ "/receipt"
    end

    test "free nights covering entire stay → complimentary after guests", %{
      conn: conn,
      user: user,
      booking: booking,
      checkin: checkin,
      checkout: checkout
    } do
      nights = Date.diff(checkout, checkin)

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :free_nights,
            property: :tahoe,
            free_nights: nights,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      render_submit(view, "save-guest-info", guest_form_params(user, 2, 0))
      assert render(view) =~ "confirm-complimentary-booking"

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element("#confirm-complimentary-booking")
               |> render_click()

      assert path =~ "/receipt"
      assert Repo.get!(Booking, booking.id).status == :complete
    end

    test "one free night on a longer stay → Stripe after guest save", %{
      conn: conn,
      user: user,
      booking: booking,
      checkin: checkin,
      checkout: checkout
    } do
      assert Date.diff(checkout, checkin) > 1

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :free_nights,
            property: :tahoe,
            free_nights: 1,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html =
        render_submit(view, "save-guest-info", guest_form_params(user, 2, 0))

      assert html =~ "stripe-payment-container"
      refute html =~ "confirm-complimentary-booking"
    end
  end

  describe "room checkout — Clear Lake" do
    setup %{conn: conn} do
      user = user_fixture()
      {checkin, checkout} = room_stay_dates()

      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{
          name: "EntCatCL #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name: "EntRoomCL #{System.unique_integer([:positive])}",
          property: :clear_lake,
          room_category_id: category.id,
          capacity_max: 4
        })

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(95, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :clear_lake,
          room_id: room.id,
          season_id: nil
        })

      assert {:ok, booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 2,
                 children_count: 0
               )

      booking = Repo.preload(booking, [:rooms])

      %{
        conn: log_in_user(conn, user),
        user: user,
        booking: booking,
        checkin: checkin,
        checkout: checkout
      }
    end

    test "100% percent-off → complimentary after guest save", %{
      conn: conn,
      user: user,
      booking: booking
    } do
      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :clear_lake,
            percent_off: Decimal.new("100"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      render_submit(view, "save-guest-info", guest_form_params(user, 2, 0))
      assert render(view) =~ "confirm-complimentary-booking"

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element("#confirm-complimentary-booking")
               |> render_click()

      assert path =~ "/receipt"
      assert Repo.get!(Booking, booking.id).status == :complete
    end

    test "30% percent-off → Stripe after guest save", %{
      conn: conn,
      user: user,
      booking: booking
    } do
      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :clear_lake,
            percent_off: Decimal.new("30"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html =
        render_submit(view, "save-guest-info", guest_form_params(user, 2, 0))

      assert html =~ "stripe-payment-container"
      refute html =~ "confirm-complimentary-booking"
    end

    test "room-scoped entitlement on booked room → complimentary", %{
      conn: conn,
      user: user,
      booking: booking
    } do
      room_id = booking.rooms |> hd() |> Map.fetch!(:id)

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :clear_lake,
            percent_off: Decimal.new("100"),
            room_id: room_id,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      render_submit(view, "save-guest-info", guest_form_params(user, 2, 0))
      assert render(view) =~ "confirm-complimentary-booking"

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element("#confirm-complimentary-booking")
               |> render_click()

      assert path =~ "/receipt"
    end

    test "free nights covering entire stay → complimentary after guests", %{
      conn: conn,
      user: user,
      booking: booking,
      checkin: checkin,
      checkout: checkout
    } do
      nights = Date.diff(checkout, checkin)

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :free_nights,
            property: :clear_lake,
            free_nights: nights,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      render_submit(view, "save-guest-info", guest_form_params(user, 2, 0))
      assert render(view) =~ "confirm-complimentary-booking"

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element("#confirm-complimentary-booking")
               |> render_click()

      assert path =~ "/receipt"
      assert Repo.get!(Booking, booking.id).status == :complete
    end

    test "one free night on a longer stay → Stripe after guest save", %{
      conn: conn,
      user: user,
      booking: booking,
      checkin: checkin,
      checkout: checkout
    } do
      assert Date.diff(checkout, checkin) > 1

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :free_nights,
            property: :clear_lake,
            free_nights: 1,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html =
        render_submit(view, "save-guest-info", guest_form_params(user, 2, 0))

      assert html =~ "stripe-payment-container"
      refute html =~ "confirm-complimentary-booking"
    end
  end

  describe "room checkout — wrong-room entitlement scope" do
    test "Tahoe: redirects when locked entitlement room_id is not the booked room",
         %{
           conn: conn
         } do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {checkin, checkout} = room_stay_dates()

      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{
          name: "WrongScopeCat #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, room_booked} =
        Bookings.create_room(%{
          name: "BookedScope #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {:ok, room_other} =
        Bookings.create_room(%{
          name: "OtherScope #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      for r <- [room_booked, room_other] do
        {:ok, _} =
          Bookings.create_pricing_rule(%{
            amount: Money.new(110, :USD),
            booking_mode: :room,
            price_unit: :per_person_per_night,
            property: :tahoe,
            room_id: r.id,
            season_id: nil
          })
      end

      assert {:ok, booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 room_booked.id,
                 checkin,
                 checkout,
                 2,
                 children_count: 0
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :tahoe,
            room_id: room_other.id,
            percent_off: Decimal.new("100"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      assert {:error, {:redirect, %{flash: flash}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      err = Map.get(flash, "error") || Map.get(flash, :error) || ""
      assert err =~ "benefit" or err =~ "valid"
    end

    test "Clear Lake: redirects when locked entitlement room_id is not the booked room",
         %{
           conn: conn
         } do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {checkin, checkout} = room_stay_dates()

      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{
          name: "WrongScopeCL #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, room_booked} =
        Bookings.create_room(%{
          name: "BookedScopeCL #{System.unique_integer([:positive])}",
          property: :clear_lake,
          room_category_id: category.id,
          capacity_max: 4
        })

      {:ok, room_other} =
        Bookings.create_room(%{
          name: "OtherScopeCL #{System.unique_integer([:positive])}",
          property: :clear_lake,
          room_category_id: category.id,
          capacity_max: 4
        })

      for r <- [room_booked, room_other] do
        {:ok, _} =
          Bookings.create_pricing_rule(%{
            amount: Money.new(88, :USD),
            booking_mode: :room,
            price_unit: :per_person_per_night,
            property: :clear_lake,
            room_id: r.id,
            season_id: nil
          })
      end

      assert {:ok, booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 room_booked.id,
                 checkin,
                 checkout,
                 2,
                 children_count: 0
               )

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :percent_off,
            property: :clear_lake,
            room_id: room_other.id,
            percent_off: Decimal.new("100"),
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking = attach_entitlement!(booking, ent.id)

      assert {:error, {:redirect, %{flash: flash}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      err = Map.get(flash, "error") || Map.get(flash, :error) || ""
      assert err =~ "benefit" or err =~ "valid"
    end
  end

  ## ——— helpers ———

  defp ensure_buyout_base_pricing! do
    for prop <- [:tahoe, :clear_lake] do
      case Bookings.create_pricing_rule(%{
             amount: Money.new(430, :USD),
             booking_mode: :buyout,
             price_unit: :buyout_fixed,
             property: prop,
             season_id: nil,
             room_id: nil,
             room_category_id: nil
           }) do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{} = cs} ->
          if duplicate_buyout_base_pricing_rule?(cs) do
            :ok
          else
            flunk(
              "unexpected Bookings.create_pricing_rule failure in ensure_buyout_base_pricing!: #{inspect(cs.errors)}"
            )
          end

        {:error, other} ->
          flunk(
            "unexpected Bookings.create_pricing_rule result in ensure_buyout_base_pricing!: #{inspect(other)}"
          )
      end
    end

    :ok
  end

  defp duplicate_buyout_base_pricing_rule?(%Ecto.Changeset{} = cs) do
    # Any unique violation on this insert is the global buyout rule already present
    # (seeds or a prior test); other validation failures must still fail fast.
    Enum.any?(cs.errors, fn {_field, {_msg, meta}} ->
      meta[:constraint] == :unique
    end)
  end

  defp buyout_stay_dates do
    rot = rem(System.unique_integer([:positive]), 4)
    tahoe_booking_dates(28 + rot * 7)
  end

  defp room_stay_dates do
    rot = rem(System.unique_integer([:positive]), 4)
    tahoe_booking_dates(105 + rot * 7)
  end

  defp buyout_subtotal!(property, checkin, checkout, guests) do
    case Bookings.calculate_booking_price(
           property,
           checkin,
           checkout,
           :buyout,
           guests_count: guests,
           children_count: 0
         ) do
      {:ok, total, _} ->
        total

      other ->
        flunk("expected buyout price, got #{inspect(other)}")
    end
  end

  defp attach_entitlement!(%Booking{} = booking, entitlement_id) do
    booking
    |> change(%{applied_booking_entitlement_id: entitlement_id})
    |> Repo.update!()
  end

  defp checkout_shows_complimentary?(conn, %Booking{} = booking) do
    {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")

    has_element?(view, "#confirm-complimentary-booking") and
      not has_element?(view, "#stripe-payment-container")
  end

  defp checkout_shows_paid_stripe?(conn, %Booking{} = booking) do
    {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")

    has_element?(view, "#stripe-payment-container") and
      has_element?(view, "#submit-payment") and
      not has_element?(view, "#confirm-complimentary-booking")
  end

  defp confirm_complimentary(conn, %Booking{} = booking) do
    {:ok, view, _} = live(conn, ~p"/bookings/checkout/#{booking.id}")

    case view |> element("#confirm-complimentary-booking") |> render_click() do
      {:error, {:live_redirect, %{to: path}}} ->
        if path =~ "/receipt" do
          {:ok, path}
        else
          {:error, {:unexpected_path, path}}
        end

      other ->
        {:error, other}
    end
  end

  defp guest_form_params(user, adults, children) do
    first = user.first_name || "Pat"
    last = user.last_name || "Member"

    base =
      %{
        "0" => %{
          "first_name" => first,
          "last_name" => last,
          "is_child" => "false",
          "is_booking_user" => "true",
          "order_index" => "0"
        }
      }

    others =
      if adults > 1 do
        for i <- 1..(adults - 1), into: %{} do
          {Integer.to_string(i),
           %{
             "first_name" => "Guest",
             "last_name" => "#{i}",
             "is_child" => "false",
             "is_booking_user" => "false",
             "order_index" => Integer.to_string(i)
           }}
        end
      else
        %{}
      end

    child_entries =
      if children > 0 do
        start_at = adults

        for j <- 0..(children - 1), into: %{} do
          idx = start_at + j

          {Integer.to_string(idx),
           %{
             "first_name" => "Kid",
             "last_name" => "#{j}",
             "is_child" => "true",
             "is_booking_user" => "false",
             "order_index" => Integer.to_string(idx)
           }}
        end
      else
        %{}
      end

    %{"guests" => Map.merge(base, Map.merge(others, child_entries))}
  end
end

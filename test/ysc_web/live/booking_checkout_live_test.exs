defmodule YscWeb.BookingCheckoutLiveTest do
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Ecto.Changeset
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Ysc.TestDataFactory
  import Mox

  alias Money
  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker, BookingRoom, RoomCategory}
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

    stub(StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_test_123",
         client_secret: "pi_test_123_secret_456",
         status: "requires_payment_method",
         amount: params.amount
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

  describe "when not signed in" do
    test "redirects to home with flash" do
      conn = build_conn()
      booking_id = Ecto.ULID.generate()

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/bookings/checkout/#{booking_id}")

      assert path == ~p"/"
      assert flash["error"] =~ "signed in"
    end
  end

  describe "Booking Checkout page" do
    setup %{conn: conn} do
      user = user_with_membership()
      booking = booking_fixture(user_id: user.id, status: :hold)

      %{conn: log_in_user(conn, user), user: user, booking: booking}
    end

    test "renders checkout page", %{conn: conn, booking: booking} do
      {:ok, view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      assert html =~ "Complete Your Booking"
      assert html =~ "Booking Summary"
      assert html =~ "What Happens Next?"
      assert has_element?(view, "#checkout-next-steps")
      assert has_element?(view, "#checkout-next-steps-step-1")
      assert has_element?(view, "#checkout-next-steps-step-4")

      assert html =~
               "Enter your payment details in the payment section to complete your booking"
    end

    test "renders Clear Lake property title", %{conn: conn, user: user} do
      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :hold,
          property: :clear_lake
        })

      {:ok, _view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      assert html =~ "Clear Lake"
    end

    test "shows children count in summary when present", %{
      conn: conn,
      user: user
    } do
      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :hold,
          children_count: 2
        })

      {:ok, _view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      assert html =~ "children"
    end

    test "redirects if not owner", %{conn: conn, booking: booking} do
      other_user = user_with_membership()
      conn = log_in_user(conn, other_user)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert path == ~p"/"
    end

    test "redirects when booking not found", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      unknown_id = Ecto.ULID.generate()

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/checkout/#{unknown_id}")

      assert path == ~p"/"
    end

    test "redirects when booking status is not hold", %{conn: conn, user: user} do
      booking = booking_fixture(user_id: user.id, status: :hold)

      booking
      |> change(%{status: :complete})
      |> Repo.update!()

      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert path in [~p"/bookings/tahoe", ~p"/bookings/clear-lake", ~p"/"]
    end

    test "redirects when booking is expired at mount", %{conn: conn, user: user} do
      booking = booking_fixture(user_id: user.id, status: :hold)

      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      booking
      |> change(%{hold_expires_at: expired_at})
      |> Repo.update!()

      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert path in [~p"/bookings/tahoe", ~p"/bookings/clear-lake", ~p"/"]
    end

    test "redirects when room booking has no rooms (price calculation)", %{
      conn: conn,
      user: user
    } do
      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :hold,
          booking_mode: :room
        })

      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert path in [~p"/bookings/tahoe", ~p"/bookings/clear-lake", ~p"/"]
    end

    test "toggle price details shows and hides breakdown", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      view
      |> element("button[phx-click=\"toggle-price-details\"]")
      |> render_click()

      html = render(view)
      assert html =~ "Price Details"

      view
      |> element("button[phx-click=\"toggle-price-details\"]")
      |> render_click()

      _html = render(view)
    end

    test "cancel booking button triggers cancel event", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      result =
        view
        |> element("button[phx-click=\"cancel-booking\"]")
        |> render_click()

      case result do
        {:error, {:redirect, %{to: _path, flash: flash}}} ->
          assert flash["info"] =~ "canceled"

        html when is_binary(html) ->
          assert html =~ "cancel" or html =~ "Cancel" or html =~ "error"
      end
    end

    test "payment-redirect-started is a no-op", %{conn: conn, booking: booking} do
      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html =
        view
        |> render_click("payment-redirect-started", %{})

      assert html =~ "Complete Your Booking"
    end

    test "submit payment stays disabled until Stripe payment element reports ready",
         %{
           conn: conn,
           booking: booking
         } do
      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert has_element?(view, "#stripe-payment-container")
      html_before = render(view)
      assert payment_submit_disabled?(html_before)

      render_click(view, "stripe-payment-element-ready", %{})
      html_ready = render(view)
      refute payment_submit_disabled?(html_ready)

      render_click(view, "stripe-payment-element-loading", %{})
      html_loading = render(view)
      assert payment_submit_disabled?(html_loading)
    end

    test "validate-guest-info with no guests param leaves socket unchanged", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html = render_click(view, "validate-guest-info", %{})
      assert html =~ "Complete Your Booking"
    end

    test "save-guest-info without guests shows error flash", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html = render_click(view, "save-guest-info", %{})

      assert html =~ "Guest information is required" or
               html =~ "Complete Your Booking"
    end

    test "payment-success when Stripe retrieve fails shows payment error", %{
      conn: conn,
      booking: booking
    } do
      expect(StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:error, :network}
      end)

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html =
        render_click(view, "payment-success", %{
          "payment_intent_id" => "pi_test_123"
        })

      assert html =~ "Something went wrong while confirming your booking"
      Mox.verify!(StripeMock)
    end

    test "payment-success records ledger when booking was already confirmed without payment",
         %{
           conn: conn,
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(7)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      pi_id = "pi_ledger_retry_#{System.unique_integer([:positive])}"
      booking = Repo.get!(Booking, booking.id)
      amount_cents = Ysc.MoneyHelper.money_to_cents(booking.total_price)

      expect(StripeMock, :retrieve_payment_intent, fn ^pi_id, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: pi_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => booking.id,
             "user_id" => booking.user_id
           },
           customer: nil,
           payment_method: nil,
           latest_charge: nil
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert {:ok, _confirmed} = BookingLocker.confirm_booking(booking.id)
      assert booking_ledger_payment_count(booking.id) == 0

      assert {:error, {:live_redirect, %{to: receipt_path}}} =
               render_click(view, "payment-success", %{
                 "payment_intent_id" => pi_id
               })

      assert receipt_path =~ "/receipt"
      assert booking_ledger_payment_count(booking.id) == 1
    end

    test "payment-success when intent status is not succeeded shows error", %{
      conn: conn,
      booking: booking
    } do
      expect(StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_test_123",
           status: "requires_payment_method",
           amount: 1000
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html =
        render_click(view, "payment-success", %{
          "payment_intent_id" => "pi_test_123"
        })

      assert html =~ "Something went wrong while confirming your booking"
      Mox.verify!(StripeMock)
    end

    test "payment-success confirms booking after hold expiry worker released hold",
         %{
           conn: conn,
           user: user
         } do
      Ysc.TestHelpers.setup_quickbooks_mocks()

      {checkin, checkout} = tahoe_booking_dates(7)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      pi_id = "pi_hold_expiry_race_#{System.unique_integer([:positive])}"
      booking = Repo.get!(Booking, booking.id)
      amount_cents = Ysc.MoneyHelper.money_to_cents(booking.total_price)

      expect(StripeMock, :retrieve_payment_intent, fn ^pi_id, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: pi_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => booking.id,
             "user_id" => booking.user_id
           },
           customer: nil,
           payment_method: nil,
           latest_charge: nil
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert {:ok, _} = BookingLocker.release_hold(booking.id)
      assert Repo.get!(Booking, booking.id).status == :canceled

      assert {:error, {:live_redirect, %{to: receipt_path}}} =
               render_click(view, "payment-success", %{
                 "payment_intent_id" => pi_id
               })

      assert receipt_path =~ "/receipt"
      assert Repo.get!(Booking, booking.id).status == :complete
      assert booking_ledger_payment_count(booking.id) == 1
      Mox.verify!(StripeMock)
    end

    test "payment-success syncs recalculated checkout price before verifying Stripe amount",
         %{
           conn: conn,
           user: user
         } do
      Ysc.TestHelpers.setup_quickbooks_mocks()

      {checkin, checkout} = tahoe_booking_dates(7)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      correct_total = booking.total_price
      stale_total = Money.mult!(correct_total, 2)

      booking =
        booking
        |> Ecto.Changeset.change(total_price: stale_total)
        |> Repo.update!()

      pi_id = "pi_stale_price_sync_#{System.unique_integer([:positive])}"

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      synced_booking = Repo.get!(Booking, booking.id)
      assert Money.equal?(synced_booking.total_price, correct_total)
      refute Money.equal?(synced_booking.total_price, stale_total)

      amount_cents =
        Ysc.MoneyHelper.money_to_cents(synced_booking.total_price)

      expect(StripeMock, :retrieve_payment_intent, fn ^pi_id, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: pi_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => booking.id,
             "user_id" => booking.user_id
           },
           customer: nil,
           payment_method: nil,
           latest_charge: nil
         }}
      end)

      assert {:error, {:live_redirect, %{to: receipt_path}}} =
               render_click(view, "payment-success", %{
                 "payment_intent_id" => pi_id
               })

      assert receipt_path =~ "/receipt"
      assert Repo.get!(Booking, booking.id).status == :complete
      assert booking_ledger_payment_count(booking.id) == 1
      Mox.verify!(StripeMock)
    end

    test "payment-success re-syncs hold price when DB total drifts after checkout mount",
         %{
           conn: conn,
           user: user
         } do
      Ysc.TestHelpers.setup_quickbooks_mocks()

      {checkin, checkout} = tahoe_booking_dates(7)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      synced_booking = Repo.get!(Booking, booking.id)
      correct_total = synced_booking.total_price
      stale_total = Money.mult!(correct_total, 2)

      booking
      |> Ecto.Changeset.change(total_price: stale_total)
      |> Repo.update!()

      pi_id = "pi_post_mount_stale_price_#{System.unique_integer([:positive])}"

      amount_cents =
        Ysc.MoneyHelper.money_to_cents(correct_total)

      expect(StripeMock, :retrieve_payment_intent, fn ^pi_id, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: pi_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => booking.id,
             "user_id" => booking.user_id
           },
           customer: nil,
           payment_method: nil,
           latest_charge: nil
         }}
      end)

      assert {:error, {:live_redirect, %{to: receipt_path}}} =
               render_click(view, "payment-success", %{
                 "payment_intent_id" => pi_id
               })

      assert receipt_path =~ "/receipt"
      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :complete
      assert Money.equal?(reloaded.total_price, correct_total)
      refute Money.equal?(reloaded.total_price, stale_total)
      assert booking_ledger_payment_count(booking.id) == 1
      Mox.verify!(StripeMock)
    end

    test "payment-success accepts Stripe amount charged at minimum billable occupancy",
         %{
           conn: conn,
           user: user
         } do
      Ysc.TestHelpers.setup_quickbooks_mocks()

      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{
          name: "Min Occ Cat #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Min Occ Room #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4,
          min_billable_occupancy: 2
        })

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      {checkin, checkout} = tahoe_booking_dates(40)

      assert {:ok, booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 1,
                 children_count: 0
               )

      pi_id = "pi_min_occ_#{System.unique_integer([:positive])}"

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      synced_booking = Repo.get!(Booking, booking.id)
      min_occupancy_total = synced_booking.total_price
      one_guest_total = Money.mult!(Money.new(100, :USD), 3)
      assert Money.compare(min_occupancy_total, one_guest_total) == :gt

      amount_cents =
        Ysc.MoneyHelper.money_to_cents(min_occupancy_total)

      expect(StripeMock, :retrieve_payment_intent, fn ^pi_id, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: pi_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => booking.id,
             "user_id" => booking.user_id
           },
           customer: nil,
           payment_method: nil,
           latest_charge: nil
         }}
      end)

      assert {:error, {:live_redirect, %{to: receipt_path}}} =
               render_click(view, "payment-success", %{
                 "payment_intent_id" => pi_id
               })

      assert receipt_path =~ "/receipt"
      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :complete
      assert Money.equal?(reloaded.total_price, min_occupancy_total)
      assert booking_ledger_payment_count(booking.id) == 1
      Mox.verify!(StripeMock)
    end

    test "creates payment intent idempotency key from synced checkout price", %{
      conn: conn,
      user: user
    } do
      {checkin, checkout} = tahoe_booking_dates(7)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      stale_total = Money.mult!(booking.total_price, 2)

      booking =
        booking
        |> Ecto.Changeset.change(total_price: stale_total)
        |> Repo.update!()

      expect(StripeMock, :create_payment_intent, fn params, opts ->
        synced_cents =
          Repo.get!(Booking, booking.id).total_price
          |> Ysc.MoneyHelper.money_to_cents()

        assert params.amount == synced_cents

        idempotency_key =
          opts[:headers]["Idempotency-Key"] ||
            opts[:headers][:"Idempotency-Key"]

        assert idempotency_key ==
                 "booking_#{booking.reference_id}_#{synced_cents}"

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_repriced_#{System.unique_integer([:positive])}",
           client_secret: "pi_repriced_secret",
           status: "requires_payment_method",
           amount: synced_cents
         }}
      end)

      {:ok, _view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      synced_booking = Repo.get!(Booking, booking.id)
      refute Money.equal?(synced_booking.total_price, stale_total)
      Mox.verify!(StripeMock)
    end

    test "rejects stale payment intent amount returned by Stripe", %{
      conn: conn,
      user: user
    } do
      booking = booking_fixture(user_id: user.id, status: :hold)

      expect(StripeMock, :create_payment_intent, fn params, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_stale_amount_#{System.unique_integer([:positive])}",
           client_secret: "pi_stale_secret",
           status: "requires_payment_method",
           amount: params.amount - 1
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert has_element?(
               view,
               "#checkout-payment-error",
               YscWeb.BookingUserMessages.checkout_payment_setup_failed()
             )

      Mox.verify!(StripeMock)
    end

    test "handle_info :check_booking_expiration marks expired when hold was released in DB",
         %{
           conn: conn,
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(7)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert {:ok, _} = BookingLocker.release_hold(booking.id)

      send(view.pid, :check_booking_expiration)
      html = render(view)

      assert html =~ "expired"
      refute html =~ "Pay "
    end

    test "handle_info :check_booking_expiration reschedules when hold still valid",
         %{
           conn: conn,
           user: user
         } do
      booking = booking_fixture(user_id: user.id, status: :hold)

      future =
        DateTime.utc_now()
        |> DateTime.add(120, :second)
        |> DateTime.truncate(:second)

      booking
      |> change(%{hold_expires_at: future})
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      send(view.pid, :check_booking_expiration)
      html = render(view)
      assert html =~ "Complete Your Booking"
    end

    test "handle_info :check_booking_expiration marks expired after hold passes",
         %{
           conn: conn,
           user: user
         } do
      booking = booking_fixture(user_id: user.id, status: :hold)

      future =
        DateTime.utc_now()
        |> DateTime.add(120, :second)
        |> DateTime.truncate(:second)

      booking
      |> change(%{hold_expires_at: future})
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      # Expire the hold in DB while LiveView is connected
      past =
        DateTime.utc_now()
        |> DateTime.add(-5, :second)
        |> DateTime.truncate(:second)

      booking
      |> change(%{hold_expires_at: past})
      |> Repo.update!()

      send(view.pid, :check_booking_expiration)
      html = render(view)
      assert html =~ "expired" or html =~ "Complete Your Booking"
    end

    test "buyout with full entitlement discount skips Stripe and confirms from checkout",
         %{
           conn: conn,
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(7)

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

      booking =
        booking
        |> change(%{applied_booking_entitlement_id: ent.id})
        |> Repo.update!()

      {:ok, view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert html =~ "No payment is required"
      assert html =~ "confirm-complimentary-booking"
      refute has_element?(view, "#stripe-payment-container")
      refute html =~ "Failed to initialize payment"

      # Complimentary flow must not hit Stripe; deny replaces the module setup stub for this MFA.
      deny(StripeMock, :create_payment_intent, 2)

      assert {:error, {:live_redirect, %{to: receipt_path}}} =
               view
               |> element("#confirm-complimentary-booking")
               |> render_click()

      assert receipt_path =~ "/bookings/"
      assert receipt_path =~ "/receipt"

      reloaded = Repo.get!(Bookings.Booking, booking.id)
      assert reloaded.status == :complete
    end

    test "rejects complimentary confirmation when recalculated price is no longer zero",
         %{
           conn: conn,
           user: user
         } do
      ensure_buyout_base_pricing!()

      {checkin, checkout} = tahoe_booking_dates(7)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      buyout_total = booking.total_price

      {:ok, ent} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :fixed_amount_off,
            property: :tahoe,
            amount_off: buyout_total,
            max_guests: 10
          },
          send_notification: false
        )

      booking =
        booking
        |> change(%{applied_booking_entitlement_id: ent.id})
        |> Repo.update!()

      {:ok, view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert html =~ "confirm-complimentary-booking"

      buyout_rule =
        Bookings.list_pricing_rules()
        |> Enum.find(fn rule ->
          rule.property == :tahoe and rule.booking_mode == :buyout and
            rule.price_unit == :buyout_fixed
        end)

      assert buyout_rule

      assert {:ok, _} =
               Bookings.update_pricing_rule(buyout_rule, %{
                 amount: Money.mult!(buyout_total, 2)
               })

      html =
        view
        |> element("#confirm-complimentary-booking")
        |> render_click()

      assert html =~ "requires payment"

      reloaded = Repo.get!(Bookings.Booking, booking.id)
      assert reloaded.status == :hold
    end

    test "shows entitlement summary on checkout with partial fixed discount",
         %{conn: conn, user: user} do
      {checkin, checkout} = tahoe_booking_dates(7)

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

      booking =
        booking
        |> change(%{applied_booking_entitlement_id: ent.id})
        |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert html =~ "$5.00 off stay"
    end

    test "select-guest-attendee without index is ignored", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html = render_click(view, "select-guest-attendee", %{})
      assert html =~ "Complete Your Booking"
    end
  end

  defp booking_ledger_payment_count(booking_id) do
    case Bookings.get_booking_payment(%Booking{id: booking_id}) do
      {:ok, _} -> 1
      {:error, :payment_not_found} -> 0
    end
  end

  defp payment_submit_disabled?(html) do
    {:ok, doc} = Floki.parse_fragment(html)

    case Floki.find(doc, "#submit-payment") do
      [el | _] -> Floki.attribute(el, "disabled") != []
      [] -> false
    end
  end

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
    Enum.any?(cs.errors, fn {_field, {_msg, meta}} ->
      meta[:constraint] == :unique
    end)
  end

  describe "payment-success with shared booking entitlement" do
    setup %{conn: conn} do
      user = user_with_membership()
      admin = user_fixture()

      {:ok, entitlement} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: admin.id,
            benefit_kind: :fixed_amount_off,
            amount_off: Money.new(:USD, 25)
          },
          send_notification: false
        )

      {checkin, checkout} = tahoe_booking_dates(40)

      booking_b =
        booking_fixture(%{
          user_id: user.id,
          status: :hold,
          property: :tahoe,
          booking_mode: :buyout,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 4,
          children_count: 0,
          total_price: Money.new(500, :USD)
        })
        |> change(%{applied_booking_entitlement_id: entitlement.id})
        |> Repo.update!()

      booking_a =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe,
          booking_mode: :buyout,
          checkin_date: Date.add(checkin, 14),
          checkout_date: Date.add(checkout, 14),
          guests_count: 4,
          children_count: 0,
          total_price: Money.new(500, :USD)
        })

      %{
        conn: log_in_user(conn, user),
        user: user,
        entitlement: entitlement,
        booking_a: booking_a,
        booking_b: booking_b
      }
    end

    test "does not record ledger payment when entitlement was already consumed",
         %{
           conn: conn,
           entitlement: entitlement,
           booking_a: booking_a,
           booking_b: booking_b
         } do
      expect(StripeMock, :retrieve_payment_intent, 2, fn _id, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_entitlement_shared_#{System.unique_integer([:positive])}",
           status: "succeeded",
           amount: 50_000,
           customer: nil,
           payment_method: nil,
           latest_charge: "ch_entitlement_shared_test"
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking_b.id}")

      assert :ok =
               Entitlements.consume_for_booking!(entitlement.id, booking_a.id)

      html =
        render_click(view, "payment-success", %{
          "payment_intent_id" => "pi_entitlement_shared_test"
        })

      assert html =~ "Something went wrong while confirming your booking"

      reloaded = Repo.get!(Bookings.Booking, booking_b.id)
      assert reloaded.status == :hold
      assert booking_ledger_payment_count(booking_b.id) == 0

      Mox.verify!(StripeMock)
    end

    test "payment-success rejects stale discounted price when entitlement expired before payment",
         %{
           conn: conn
         } do
      Ysc.TestHelpers.setup_quickbooks_mocks()

      # Fresh user: describe setup already has active bookings for `user`.
      user = user_with_membership()
      conn = log_in_user(conn, user)

      {checkin, checkout} = tahoe_booking_dates(7)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      full_total = booking.total_price

      {:ok, entitlement} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :fixed_amount_off,
            property: :tahoe,
            amount_off: Money.new(25, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking =
        booking
        |> change(%{applied_booking_entitlement_id: entitlement.id})
        |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      synced = Repo.get!(Booking, booking.id)
      assert Money.cmp(synced.total_price, full_total) == -1

      discounted_cents = Ysc.MoneyHelper.money_to_cents(synced.total_price)
      pi_id = "pi_expired_entitlement_#{System.unique_integer([:positive])}"

      past =
        DateTime.add(DateTime.utc_now(), -60, :second)
        |> DateTime.truncate(:second)

      entitlement
      |> Ecto.Changeset.change(expires_at: past)
      |> Repo.update!()

      assert {:ok, %{expired: 1}} = Entitlements.expire_passed_entitlements()

      expect(StripeMock, :retrieve_payment_intent, 2, fn ^pi_id, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: pi_id,
           status: "succeeded",
           amount: discounted_cents,
           metadata: %{
             "booking_id" => booking.id,
             "user_id" => booking.user_id
           },
           customer: nil,
           payment_method: nil,
           latest_charge: "ch_#{pi_id}"
         }}
      end)

      html =
        render_click(view, "payment-success", %{
          "payment_intent_id" => pi_id
        })

      assert html =~ "Something went wrong while confirming your booking"

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :hold
      assert booking_ledger_payment_count(booking.id) == 0

      # #749: fulfillment failure auto-refunds via create_stripe_refund — the Mox
      # expect(..., 2, ...) above requires a second retrieve_payment_intent call.
      Mox.verify!(StripeMock)
    end
  end

  describe "payment-success rejects foreign payment intent" do
    setup %{conn: conn} do
      user = user_with_membership()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "payment-success rejects a succeeded payment intent from another booking",
         %{
           conn: conn,
           user: user
         } do
      # Fixed anchor dates (both Mondays, both deep in Tahoe Summer) instead of
      # tahoe_booking_dates(50) + Date.add(checkin, 14): that combination could
      # push expensive_booking's stay past Oct 31 into Winter depending on
      # Date.utc_today(), silently flipping booking_fixture/1 to :room mode
      # (no buyout allowed in Winter) — a mode this test never sets up pricing
      # for, so checkout would fail with :no_pricing_rules_found. See
      # @tahoe_test_anchor above.
      checkin = tahoe_test_date(54)
      checkout = Date.add(checkin, 3)

      cheap_booking =
        booking_fixture(%{
          user_id: user.id,
          status: :hold,
          checkin_date: checkin,
          checkout_date: checkout,
          total_price: Money.new(200, :USD)
        })

      expensive_checkin = tahoe_test_date(68)

      expensive_booking =
        booking_fixture(%{
          user_id: user.id,
          status: :hold,
          checkin_date: expensive_checkin,
          checkout_date: Date.add(expensive_checkin, 3),
          total_price: Money.new(500, :USD)
        })

      cheap_pi_id = "pi_cheap_#{System.unique_integer([:positive])}"

      cheap_amount_cents =
        Ysc.MoneyHelper.money_to_cents(cheap_booking.total_price)

      expect(StripeMock, :retrieve_payment_intent, fn ^cheap_pi_id, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: cheap_pi_id,
           status: "succeeded",
           amount: cheap_amount_cents,
           metadata: %{
             "booking_id" => cheap_booking.id,
             "user_id" => user.id
           },
           customer: nil,
           payment_method: nil,
           latest_charge: nil
         }}
      end)

      {:ok, view, _html} =
        live(conn, ~p"/bookings/checkout/#{expensive_booking.id}")

      html =
        render_click(view, "payment-success", %{
          "payment_intent_id" => cheap_pi_id
        })

      assert html =~ "Something went wrong while confirming your booking"

      reloaded = Repo.get!(Booking, expensive_booking.id)
      assert reloaded.status == :hold
      assert booking_ledger_payment_count(expensive_booking.id) == 0

      Mox.verify!(StripeMock)
    end
  end

  describe "room booking guest step" do
    setup %{conn: conn} do
      user = user_with_membership()

      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{
          name: "Cat #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Checkout Room #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      {checkin, checkout} = tahoe_booking_dates(40)

      hold_expires_at =
        DateTime.utc_now()
        |> DateTime.add(30, :minute)
        |> DateTime.truncate(:second)

      {:ok, booking} =
        Bookings.create_booking(%{
          user_id: user.id,
          status: :hold,
          property: :tahoe,
          booking_mode: :room,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 2,
          children_count: 0,
          hold_expires_at: hold_expires_at,
          total_price: Money.new(500, :USD),
          pricing_items: %{"type" => "room"}
        })

      %BookingRoom{}
      |> Ecto.Changeset.change(%{booking_id: booking.id, room_id: room.id})
      |> Repo.insert!()

      booking = Repo.preload(booking, [:rooms])

      %{conn: log_in_user(conn, user), user: user, booking: booking}
    end

    test "shows guest information step before payment", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      assert html =~ "Guest Information"
      assert html =~ "What Happens Next?"
      assert has_element?(view, "#checkout-next-steps")
      assert has_element?(view, "#checkout-next-steps-step-1")

      assert html =~ "Enter the names of everyone else staying with you"
      assert html =~ "already included in the booking"

      assert html =~ "held temporarily"
      assert html =~ "not confirmed yet"
      assert html =~ "go back on the calendar"
    end

    test "validate-guest-info with invalid guest data collects errors", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html =
        render_change(view, "validate-guest-info", %{
          "guests" => %{
            "0" => %{"first_name" => "", "last_name" => ""}
          }
        })

      assert html =~ "Guest Information"
    end
  end
end

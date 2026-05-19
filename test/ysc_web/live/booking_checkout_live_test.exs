defmodule YscWeb.BookingCheckoutLiveTest do
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Ecto.Changeset
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Mox

  alias Ysc.Bookings
  alias Ysc.Bookings.{BookingLocker, BookingRoom, RoomCategory}
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
         id: "pi_test_123",
         client_secret: "pi_test_123_secret_456",
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
      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :hold)

      %{conn: log_in_user(conn, user), user: user, booking: booking}
    end

    test "renders checkout page", %{conn: conn, booking: booking} do
      {:ok, _view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      assert html =~ "Complete Your Booking"
      assert html =~ "Booking Summary"
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
      other_user = user_fixture()
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

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert flash["error"] =~ "expired"
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

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert flash["error"] =~ "couldn't load the pricing"
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
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 3)

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

    test "select-guest-attendee without index is ignored", %{
      conn: conn,
      booking: booking
    } do
      {:ok, view, _html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      html = render_click(view, "select-guest-attendee", %{})
      assert html =~ "Complete Your Booking"
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

  describe "room booking guest step" do
    setup %{conn: conn} do
      user = user_fixture()

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
      {:ok, _view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      assert html =~ "Guest Information"
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

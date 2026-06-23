defmodule YscWeb.BookingReceiptLiveTest do
  # async: false — setup and redirect tests override global :stripe_client via Application.put_env
  use YscWeb.ConnCase, async: false

  import Ecto.Changeset
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Money
  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker}
  alias Ysc.Bookings.Entitlements
  alias Ysc.Payments
  alias Ysc.Repo

  @async_timeout_ms 5_000

  setup do
    original_stripe_client = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    :ok
  end

  describe "mount/3 - authentication and security" do
    test "redirects to home when user is not authenticated", %{conn: conn} do
      booking = booking_fixture()

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert path == "/"
    end

    test "redirects to home when booking is not found", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/bookings/#{Ecto.ULID.generate()}/receipt")

      assert path == "/"
      assert flash["error"] =~ "couldn't find this reservation"
    end

    test "prevents accessing another user's booking", %{conn: conn} do
      user = user_fixture()
      other_user = user_fixture()
      conn = log_in_user(conn, user)

      # Create booking for other user
      booking = booking_fixture(%{user_id: other_user.id})

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert path == "/"
      assert flash["error"] =~ "couldn't find this reservation"
    end

    test "loads booking receipt successfully for own booking", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Booking Confirmation"
      assert html =~ booking.reference_id
      assert has_element?(view, "#booking-receipt")
    end
  end

  describe "mount/3 - stripe redirect handling" do
    test "handles successful payment redirect", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :hold})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded&confetti=true"
        )

      # Note: In real scenario, would need valid payment_intent parameter
      # Just checking that the page loads with redirect params
      assert html =~ "Booking Confirmation"
    end

    test "handles failed payment redirect", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :hold})

      {:ok, _view, html} =
        live(conn, ~p"/bookings/#{booking.id}/receipt?redirect_status=failed")

      assert html =~ "Payment failed"
    end

    test "shows confetti on successful payment", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} =
        live(conn, ~p"/bookings/#{booking.id}/receipt?confetti=true")

      assert has_element?(view, ~s([data-show-confetti="true"]))
    end
  end

  describe "booking display" do
    test "displays complete booking details", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      today = Date.utc_today()
      # Monday check-in, Thursday checkout (no Saturday in range)
      base = Date.add(today, 30)
      dow = Date.day_of_week(base, :monday)
      checkin_date = Date.add(base, rem(8 - dow, 7))
      checkout_date = Date.add(checkin_date, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe,
          checkin_date: checkin_date,
          checkout_date: checkout_date,
          guests_count: 2,
          children_count: 1
        })

      {:ok, view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Reservation Confirmed"
      assert html =~ booking.reference_id
      assert html =~ "Lake Tahoe Cabin"
      assert has_element?(view, ~s(#booking-receipt))
    end

    test "displays cancelled booking with appropriate styling", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :canceled})

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Reservation Cancelled"
      assert html =~ "Booking Cancelled"
      assert html =~ booking.reference_id
    end

    test "displays guest information when booking guests exist", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      # Create booking guests - function expects list of {index, attrs} tuples
      {:ok, _guests} =
        Ysc.Bookings.create_booking_guests(booking.id, [
          {0,
           %{
             first_name: "John",
             last_name: "Doe",
             is_booking_user: true,
             is_child: false
           }},
          {1,
           %{
             first_name: "Jane",
             last_name: "Doe",
             is_booking_user: false,
             is_child: false
           }}
        ])

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Guest Information"
      assert html =~ "John Doe"
      assert html =~ "Jane Doe"
    end
  end

  describe "async data loading" do
    test "shows loading skeleton initially", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      # Initial render should show loading skeleton
      html = render(view)
      # The skeleton has animate-pulse class
      assert html =~ "animate-pulse" or html =~ "Payment Summary"
    end

    test "loads payment data asynchronously", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      # Create a payment for the booking
      create_payment_for_booking(booking, Money.new(10_000, :USD))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_async(view, @async_timeout_ms)

      html = render(view)
      assert html =~ "Payment Summary" or html =~ "$100.00"
    end

    test "payment summary shows Link with card PAN mask", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, payment_method} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_link_#{System.unique_integer([:positive])}",
          provider_customer_id: "cus_#{System.unique_integer([:positive])}",
          type: :link,
          provider_type: "card",
          display_brand: "visa",
          last_four: "4242",
          is_default: false
        })

      create_payment_for_booking(booking, Money.new(27_000, :USD),
        payment_method_id: payment_method.id
      )

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_async(view, @async_timeout_ms)

      html = render(view)
      assert html =~ "Link · Visa **** **** **** 4242"
    end

    test "payment summary enriches Link from Stripe when last four is missing",
         %{
           conn: conn
         } do
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      payment_intent_id = "pi_link_mask_#{System.unique_integer([:positive])}"

      {:module, test_stripe_client, _, _} =
        defmodule :"ReceiptLinkMaskStripe#{System.unique_integer([:positive])}" do
          @behaviour Ysc.StripeBehaviour

          def create_payment_intent(_params, _opts),
            do: {:error, :not_implemented}

          def cancel_payment_intent(_id, _opts), do: {:error, :not_implemented}
          def create_customer(_params), do: {:error, :not_implemented}
          def update_customer(_id, _params), do: {:error, :not_implemented}
          def list_events(_params, _opts), do: {:error, :not_implemented}
          def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

          def list_balance_transactions(_params, _opts),
            do: {:error, :not_implemented}

          def retrieve_payment_method(id) do
            {:ok,
             %Stripe.PaymentMethod{
               id: id,
               type: "link",
               link: %{email: "user@example.com"}
             }}
          end

          def retrieve_charge(charge_id, _opts) do
            {:ok,
             %Stripe.Charge{
               id: charge_id,
               payment_method_details: %{
                 card: %{
                   brand: "visa",
                   last4: "1111",
                   wallet: %{type: "link", dynamic_last4: "4242"}
                 }
               }
             }}
          end

          def retrieve_payment_intent(id, _opts) do
            {:ok,
             %Stripe.PaymentIntent{
               id: id,
               status: "succeeded",
               amount: 27_000,
               customer: nil,
               payment_method: "pm_link_wallet",
               latest_charge: "ch_link_wallet_test"
             }}
          end
        end

      Application.put_env(:ysc, :stripe_client, test_stripe_client)

      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, payment_method} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_link_#{System.unique_integer([:positive])}",
          provider_customer_id: "cus_#{System.unique_integer([:positive])}",
          type: :link,
          provider_type: "link",
          display_brand: "Link",
          is_default: false
        })

      create_payment_for_booking(booking, Money.new(27_000, :USD),
        payment_method_id: payment_method.id,
        external_payment_id: payment_intent_id
      )

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_async(view, @async_timeout_ms)

      html = render(view)
      assert html =~ "Link · Visa **** **** **** 4242"
    end

    test "shows reservation updated notice when updated query param is set", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})
      create_payment_for_booking(booking, Money.new(27_000, :USD))

      {:ok, view, html} =
        live(conn, ~p"/bookings/#{booking.id}/receipt?updated=true")

      assert html =~ "Reservation Updated"

      render_async(view, @async_timeout_ms)

      html = render(view)
      assert has_element?(view, "#reservation-updated-notice")
      assert html =~ "Reservation updated"
      assert html =~ "Your changes are saved"
    end

    test "shows cumulative total paid when booking has multiple payments", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete
        })
        |> Ecto.Changeset.change(
          total_price: Money.new(150, :USD),
          refund_forfeited_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      {:ok, card_payment_method} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_card_#{System.unique_integer([:positive])}",
          provider_customer_id: "cus_#{System.unique_integer([:positive])}",
          type: :card,
          provider_type: "card",
          display_brand: "visa",
          last_four: "4242",
          is_default: false
        })

      {:ok, link_payment_method} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_link_#{System.unique_integer([:positive])}",
          provider_customer_id: "cus_#{System.unique_integer([:positive])}",
          type: :link,
          provider_type: "link",
          display_brand: "visa",
          last_four: "9999",
          is_default: false
        })

      create_payment_for_booking(booking, Money.new(50, :USD),
        payment_method_id: card_payment_method.id
      )

      create_payment_for_booking(booking, Money.new(100, :USD),
        payment_method_id: link_payment_method.id
      )

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")
      render_async(view, @async_timeout_ms)

      html = render(view)
      assert has_element?(view, "#booking-payment-history")
      refute has_element?(view, "#payment-method-summary")
      refute has_element?(view, "#payment-date-summary")
      assert html =~ "Reservation total"
      assert html =~ "$150.00"
      assert html =~ "$50.00"
      assert html =~ "$100.00"
      assert html =~ "Link"
      assert html =~ "4242"
    end
  end

  describe "event handlers - navigation" do
    test "view-bookings redirects to property bookings page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(view, "view-bookings")

      assert path == "/bookings/tahoe"
    end

    test "view-bookings redirects to clear lake bookings for clear_lake property",
         %{
           conn: conn
         } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, property: :clear_lake})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(view, "view-bookings")

      assert path == "/bookings/clear-lake"
    end

    test "go-home redirects to home page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(view, "go-home")

      assert path == "/"
    end
  end

  describe "event handlers - cancel modal" do
    test "show-cancel-modal displays the modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      today = Date.utc_today()
      # Find next Friday
      days_to_friday = 5 - Date.day_of_week(today, :monday)

      days_to_friday =
        if days_to_friday < 0, do: days_to_friday + 7, else: days_to_friday

      checkin_date = Date.add(today, days_to_friday + 7)
      checkout_date = Date.add(checkin_date, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin_date,
          checkout_date: checkout_date
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      result = render_click(view, "show-cancel-modal")

      assert result =~ "Cancel Booking"
      assert result =~ "Cancellation Reason"
      assert result =~ "Cancel this reservation?"
      assert result =~ "be undone"
    end

    test "hide-cancel-modal hides the modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      today = Date.utc_today()
      # Find next Friday
      days_to_friday = 5 - Date.day_of_week(today, :monday)

      days_to_friday =
        if days_to_friday < 0, do: days_to_friday + 7, else: days_to_friday

      checkin_date = Date.add(today, days_to_friday + 7)
      checkout_date = Date.add(checkin_date, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin_date,
          checkout_date: checkout_date
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      # First show the modal
      result = render_click(view, "show-cancel-modal")
      assert result =~ "Cancel Booking"

      # Then hide it - modal should no longer be shown
      result = render_click(view, "hide-cancel-modal")
      # Event handler updates state successfully - check for booking reference
      assert result =~ booking.reference_id
    end

    test "update-cancel-reason updates the reason", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      today = Date.utc_today()
      # Find next Friday
      days_to_friday = 5 - Date.day_of_week(today, :monday)

      days_to_friday =
        if days_to_friday < 0, do: days_to_friday + 7, else: days_to_friday

      checkin_date = Date.add(today, days_to_friday + 7)
      checkout_date = Date.add(checkin_date, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin_date,
          checkout_date: checkout_date
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      # Show modal first
      render_click(view, "show-cancel-modal")

      # Update reason - event should succeed
      result =
        render_click(view, "update-cancel-reason", %{
          "reason" => "Change of plans"
        })

      # Event should update state without error and page should still render
      assert result =~ booking.reference_id
    end
  end

  describe "cancellation flow" do
    test "shows cancel button for future bookings", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      today = Date.utc_today()

      # Use Monday–Thursday range to satisfy "Saturday must include Sunday" rule
      base = Date.add(today, 10)
      dow = Date.day_of_week(base, :monday)
      days_until_monday = rem(8 - dow, 7)
      checkin_date = Date.add(base, days_until_monday)

      # Buyout only allowed in summer; use first Monday on or after May 1 if in winter
      checkin_date =
        if checkin_date.month in [1, 2, 3, 4, 11, 12] do
          year =
            if checkin_date.month in [1, 2, 3, 4],
              do: checkin_date.year,
              else: checkin_date.year + 1

          may_first = Date.new!(year, 5, 1)
          dow_may = Date.day_of_week(may_first, :monday)
          Date.add(may_first, rem(8 - dow_may, 7))
        else
          checkin_date
        end

      checkout_date = Date.add(checkin_date, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin_date,
          checkout_date: checkout_date
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_async(view, @async_timeout_ms)

      assert has_element?(view, ~s(button), "Cancel Reservation")
    end

    test "shows change reservation link for future complete bookings", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {checkin_date, checkout_date} =
        Ysc.BookingsFixtures.tahoe_booking_dates(30)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin_date,
          checkout_date: checkout_date
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_async(view, @async_timeout_ms)

      assert has_element?(view, "#change-reservation-button")
    end

    test "cancel modal shows modified no-refund copy for forfeited bookings", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {checkin_date, checkout_date} =
        Ysc.BookingsFixtures.tahoe_booking_dates(30)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin_date,
          checkout_date: checkout_date,
          refund_forfeited_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")
      render_async(view, @async_timeout_ms)

      view |> element(~s(button), "Cancel Reservation") |> render_click()

      html = render(view)
      assert html =~ "reservation was modified"
      assert html =~ "will not receive a refund"
    end

    test "does not show cancel button for past bookings", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      today = Date.utc_today()

      # Find a past Monday to avoid weekend validation issues
      # Go back 10 days and then adjust to previous Monday
      past_date = Date.add(today, -10)
      days_since_monday = Date.day_of_week(past_date, :monday) - 1
      checkin_date = Date.add(past_date, -days_since_monday)
      checkout_date = Date.add(checkin_date, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin_date,
          checkout_date: checkout_date
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      refute has_element?(view, ~s(button), "Cancel Reservation")
    end

    test "does not show cancel button for cancelled bookings", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :canceled})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      refute has_element?(view, ~s(button), "Cancel Reservation")
    end
  end

  describe "door code visibility" do
    test "does not show door code for future bookings beyond 48 hours", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      today = Date.utc_today()

      # Use Monday–Thursday range to satisfy "Saturday must include Sunday" rule
      base = Date.add(today, 10)
      dow = Date.day_of_week(base, :monday)
      days_until_monday = rem(8 - dow, 7)
      checkin_date = Date.add(base, days_until_monday)

      # Buyout only allowed in summer; use first Monday on or after May 1 if in winter
      checkin_date =
        if checkin_date.month in [1, 2, 3, 4, 11, 12] do
          year =
            if checkin_date.month in [1, 2, 3, 4],
              do: checkin_date.year,
              else: checkin_date.year + 1

          may_first = Date.new!(year, 5, 1)
          dow_may = Date.day_of_week(may_first, :monday)
          Date.add(may_first, rem(8 - dow_may, 7))
        else
          checkin_date
        end

      checkout_date = Date.add(checkin_date, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin_date,
          checkout_date: checkout_date
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_async(view, @async_timeout_ms)

      html = render(view)
      refute html =~ "Your Door Code"
    end

    test "does not show door code for cancelled bookings", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      # Use a Monday-Thursday booking to avoid weekend validation rules
      # Find the next Monday
      today = Date.utc_today()

      next_monday =
        Enum.find(1..7, fn days ->
          Date.day_of_week(Date.add(today, days)) == 1
        end)
        |> then(&Date.add(today, &1))

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :canceled,
          checkin_date: next_monday,
          checkout_date: Date.add(next_monday, 3)
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_async(view, @async_timeout_ms)

      html = render(view)
      refute html =~ "Your Door Code"
    end
  end

  describe "page title and metadata" do
    test "sets correct page title", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert page_title(view) =~ "Booking Confirmation"
    end
  end

  describe "greeting and stay copy" do
    test "shows past-stay copy when checkout date is in the past", %{conn: conn} do
      user = user_fixture(%{first_name: "Ingrid"})
      conn = log_in_user(conn, user)

      # Use a past Monday–Thursday stay
      today = Date.utc_today()
      past_base = Date.add(today, -14)
      days_since_monday = Date.day_of_week(past_base, :monday) - 1
      checkin_date = Date.add(past_base, -days_since_monday)
      checkout_date = Date.add(checkin_date, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin_date,
          checkout_date: checkout_date
        })

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert has_element?(view, "#booking-receipt", "What a stay, Ingrid")

      assert has_element?(
               view,
               "#booking-receipt",
               "Hope you had an amazing time"
             )

      assert has_element?(view, "#booking-receipt", "See you next time")
    end

    test "shows upcoming copy when checkout date is in the future", %{
      conn: conn
    } do
      user = user_fixture(%{first_name: "Bjorn"})
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert has_element?(
               view,
               "#booking-receipt",
               "See you at the Cabin, Bjorn"
             )

      assert has_element?(view, "#booking-receipt", "is all set")
    end

    test "uses Member when user has no first name", %{conn: conn} do
      user = user_fixture()

      {:ok, user} =
        user |> Ecto.Changeset.change(%{first_name: nil}) |> Repo.update()

      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "See you at the Cabin, Member"
    end

    test "buyout booking shows Entire cabin when no rooms linked", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :buyout
        })

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Entire cabin"
      assert html =~ "Reservation type"
    end

    test "displays Clear Lake in copy", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :clear_lake
        })

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Clear Lake" or html =~ "clear"
    end

    test "shows singular Night for one-night stay", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      today = Date.utc_today()
      checkin = Date.add(today, 40) |> first_weekday_on_or_after(1)
      checkout = Date.add(checkin, 1)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin,
          checkout_date: checkout
        })

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "1"
      assert html =~ "Night"
      refute html =~ "1 Nights"
    end

    test "shows plural Nights for multi-night stay", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      today = Date.utc_today()
      checkin = Date.add(today, 35)
      checkin = first_weekday_on_or_after(checkin, 1)
      checkout = Date.add(checkin, 3)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          checkin_date: checkin,
          checkout_date: checkout
        })

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Nights"
    end
  end

  describe "stripe redirect params" do
    test "succeeded without payment_intent does not break mount", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded"
        )

      assert html =~ "Booking Confirmation"
    end

    test "dead render does not confirm booking when redirect succeeded without payment_intent",
         %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      ensure_receipt_buyout_base_pricing!()

      user = user_fixture()
      conn = log_in_user(conn, user)

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

      assert booking.status == :hold
      assert receipt_ledger_payment_count(booking.id) == 0

      conn
      |> get(~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded")
      |> html_response(200)

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :hold
      assert receipt_ledger_payment_count(booking.id) == 0
    end

    test "dead render shows payment failed flash when redirect_status is failed",
         %{
           conn: conn
         } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :hold})

      html =
        conn
        |> get(~p"/bookings/#{booking.id}/receipt?redirect_status=failed")
        |> html_response(200)

      assert html =~ "Payment failed"
      assert Repo.get!(Booking, booking.id).status == :hold
    end

    test "unknown redirect_status loads page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking.id}/receipt?redirect_status=processing"
        )

      assert html =~ "Booking Confirmation"
    end

    test "does not record ledger payment when confirm fails after Stripe redirect succeeded",
         %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      {:module, test_stripe_client, _, _} =
        defmodule :"ReceiptRedirectStripe#{System.unique_integer([:positive])}" do
          @behaviour Ysc.StripeBehaviour

          def create_payment_intent(_params, _opts),
            do: {:error, :not_implemented}

          def cancel_payment_intent(_id, _opts), do: {:error, :not_implemented}
          def create_customer(_params), do: {:error, :not_implemented}
          def update_customer(_id, _params), do: {:error, :not_implemented}
          def retrieve_payment_method(_id), do: {:error, :not_implemented}
          def list_events(_params, _opts), do: {:error, :not_implemented}
          def retrieve_charge(_id, _opts), do: {:error, :not_implemented}
          def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

          def list_balance_transactions(_params, _opts),
            do: {:error, :not_implemented}

          def retrieve_payment_intent(id, _opts) do
            {:ok,
             %Stripe.PaymentIntent{
               id: id,
               status: "succeeded",
               amount: 50_000,
               customer: nil,
               payment_method: nil,
               latest_charge: nil
             }}
          end
        end

      Application.put_env(:ysc, :stripe_client, test_stripe_client)
      ensure_receipt_buyout_base_pricing!()

      user = user_fixture()
      admin = user_fixture()
      conn = log_in_user(conn, user)

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

      assert :ok =
               Entitlements.consume_for_booking!(entitlement.id, booking_a.id)

      payment_intent_id =
        "pi_receipt_entitlement_#{System.unique_integer([:positive])}"

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking_b.id}/receipt?redirect_status=succeeded&payment_intent=#{payment_intent_id}"
        )

      assert html =~ "issue updating your reservation"

      reloaded = Repo.get!(Booking, booking_b.id)
      assert reloaded.status == :hold
      assert receipt_ledger_payment_count(booking_b.id) == 0
    end

    test "records ledger when booking was already confirmed before Stripe redirect",
         %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      ensure_receipt_buyout_base_pricing!()

      user = user_fixture()
      conn = log_in_user(conn, user)

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

      booking = Repo.get!(Booking, booking.id)
      pi_id = "pi_receipt_ledger_retry_#{System.unique_integer([:positive])}"
      amount_cents = Ysc.MoneyHelper.money_to_cents(booking.total_price)

      module_name =
        :"ReceiptLedgerRetryStripe#{System.unique_integer([:positive])}"

      {:module, test_stripe_client, _, _} =
        Module.create(
          module_name,
          quote do
            @behaviour Ysc.StripeBehaviour

            @pi_amount unquote(amount_cents)
            @booking_id unquote(booking.id)
            @user_id unquote(booking.user_id)

            def create_payment_intent(_params, _opts),
              do: {:error, :not_implemented}

            def cancel_payment_intent(_id, _opts),
              do: {:error, :not_implemented}

            def create_customer(_params), do: {:error, :not_implemented}
            def update_customer(_id, _params), do: {:error, :not_implemented}
            def retrieve_payment_method(_id), do: {:error, :not_implemented}
            def list_events(_params, _opts), do: {:error, :not_implemented}
            def retrieve_charge(_id, _opts), do: {:error, :not_implemented}
            def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

            def list_balance_transactions(_params, _opts),
              do: {:error, :not_implemented}

            def retrieve_payment_intent(id, _opts) do
              {:ok,
               %Stripe.PaymentIntent{
                 id: id,
                 status: "succeeded",
                 amount: @pi_amount,
                 metadata: %{
                   "booking_id" => @booking_id,
                   "user_id" => @user_id
                 },
                 customer: nil,
                 payment_method: nil,
                 latest_charge: nil
               }}
            end
          end,
          Macro.Env.location(__ENV__)
        )

      Application.put_env(:ysc, :stripe_client, test_stripe_client)

      assert {:ok, _confirmed} = BookingLocker.confirm_booking(booking.id)
      assert receipt_ledger_payment_count(booking.id) == 0

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded&payment_intent=#{pi_id}"
        )

      assert html =~ "Payment successful"
      assert receipt_ledger_payment_count(booking.id) == 1
    end

    test "dead render confirms booking when Stripe redirect params are present",
         %{
           conn: conn
         } do
      Ysc.Ledgers.ensure_basic_accounts()
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      ensure_receipt_buyout_base_pricing!()

      user = user_fixture()
      conn = log_in_user(conn, user)

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

      booking = Repo.get!(Booking, booking.id)
      assert booking.status == :hold

      pi_id = "pi_receipt_dead_render_#{System.unique_integer([:positive])}"
      amount_cents = Ysc.MoneyHelper.money_to_cents(booking.total_price)

      module_name =
        :"ReceiptDeadRenderStripe#{System.unique_integer([:positive])}"

      {:module, test_stripe_client, _, _} =
        Module.create(
          module_name,
          quote do
            @behaviour Ysc.StripeBehaviour

            @pi_amount unquote(amount_cents)
            @booking_id unquote(booking.id)
            @user_id unquote(booking.user_id)

            def create_payment_intent(_params, _opts),
              do: {:error, :not_implemented}

            def cancel_payment_intent(_id, _opts),
              do: {:error, :not_implemented}

            def create_customer(_params), do: {:error, :not_implemented}
            def update_customer(_id, _params), do: {:error, :not_implemented}
            def retrieve_payment_method(_id), do: {:error, :not_implemented}
            def list_events(_params, _opts), do: {:error, :not_implemented}
            def retrieve_charge(_id, _opts), do: {:error, :not_implemented}
            def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

            def list_balance_transactions(_params, _opts),
              do: {:error, :not_implemented}

            def retrieve_payment_intent(id, _opts) do
              {:ok,
               %Stripe.PaymentIntent{
                 id: id,
                 status: "succeeded",
                 amount: @pi_amount,
                 metadata: %{
                   "booking_id" => @booking_id,
                   "user_id" => @user_id
                 },
                 customer: nil,
                 payment_method: nil,
                 latest_charge: nil
               }}
            end
          end,
          Macro.Env.location(__ENV__)
        )

      Application.put_env(:ysc, :stripe_client, test_stripe_client)

      assert receipt_ledger_payment_count(booking.id) == 0

      conn
      |> get(
        ~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded&payment_intent=#{pi_id}&confetti=true"
      )
      |> html_response(200)

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :complete
      assert receipt_ledger_payment_count(booking.id) == 1
      assert Ysc.Ledgers.get_payment_by_external_id(pi_id)
    end

    test "stripe redirect syncs recalculated hold price before confirming payment",
         %{
           conn: conn
         } do
      Ysc.Ledgers.ensure_basic_accounts()
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      ensure_receipt_buyout_base_pricing!()

      user = user_fixture()
      conn = log_in_user(conn, user)

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

      correct_total = booking.total_price
      stale_total = Money.mult!(correct_total, 2)

      booking =
        booking
        |> Ecto.Changeset.change(total_price: stale_total)
        |> Repo.update!()

      pi_id =
        "pi_receipt_stale_price_sync_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(correct_total)

      module_name =
        :"ReceiptStalePriceStripe#{System.unique_integer([:positive])}"

      {:module, test_stripe_client, _, _} =
        Module.create(
          module_name,
          quote do
            @behaviour Ysc.StripeBehaviour

            @pi_amount unquote(amount_cents)
            @booking_id unquote(booking.id)
            @user_id unquote(booking.user_id)

            def create_payment_intent(_params, _opts),
              do: {:error, :not_implemented}

            def cancel_payment_intent(_id, _opts),
              do: {:error, :not_implemented}

            def create_customer(_params), do: {:error, :not_implemented}
            def update_customer(_id, _params), do: {:error, :not_implemented}
            def retrieve_payment_method(_id), do: {:error, :not_implemented}
            def list_events(_params, _opts), do: {:error, :not_implemented}
            def retrieve_charge(_id, _opts), do: {:error, :not_implemented}
            def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

            def list_balance_transactions(_params, _opts),
              do: {:error, :not_implemented}

            def retrieve_payment_intent(id, _opts) do
              {:ok,
               %Stripe.PaymentIntent{
                 id: id,
                 status: "succeeded",
                 amount: @pi_amount,
                 metadata: %{
                   "booking_id" => @booking_id,
                   "user_id" => @user_id
                 },
                 customer: nil,
                 payment_method: nil,
                 latest_charge: nil
               }}
            end
          end,
          Macro.Env.location(__ENV__)
        )

      Application.put_env(:ysc, :stripe_client, test_stripe_client)

      assert receipt_ledger_payment_count(booking.id) == 0

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded&payment_intent=#{pi_id}"
        )

      assert html =~ "Payment successful"
      assert Repo.get!(Booking, booking.id).status == :complete
      assert receipt_ledger_payment_count(booking.id) == 1

      assert Money.equal?(
               Repo.get!(Booking, booking.id).total_price,
               correct_total
             )
    end

    test "applies paid modification after redirect-based Stripe payment", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      user =
        user_fixture()
        |> Ecto.Changeset.change(state: :active)
        |> Repo.update!()

      conn = log_in_user(conn, user)

      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Receipt modify category"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Receipt modify room #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = tahoe_booking_dates(140)
      short_checkout = Date.add(checkin, 1)

      assert {:ok, total, _} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 short_checkout,
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
                   checkout_date: short_checkout,
                   booking_mode: :room,
                   guests_count: 2,
                   total_price: total
                 },
                 rooms: [room],
                 skip_email: true,
                 skip_reminders: true
               )

      assert {:ok, _} =
               Ysc.Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: total,
                 entity_type: :booking,
                 entity_id: booking.id,
                 external_payment_id:
                   "pi_receipt_modify_base_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(100, :USD),
                 description: "Booking payment",
                 property: booking.property,
                 payment_method_id: nil
               })

      attrs = %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 2,
        children_count: 0
      }

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(checkin),
                 "checkout_date" => Date.to_string(checkout),
                 "guests_count" => "2",
                 "children_count" => "0"
               })

      assert Money.positive?(preview.delta)

      assert {:ok, _} = Bookings.place_modification_hold(booking, attrs)

      payment_intent_id =
        "pi_receipt_modify_redirect_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stripe_metadata = %{
        "booking_id" => to_string(booking.id),
        "user_id" => to_string(user.id),
        "modification" => "true"
      }

      module_name =
        :"ReceiptModificationRedirectStripe#{System.unique_integer([:positive])}"

      {:module, test_stripe_client, _, _} =
        Module.create(
          module_name,
          quote do
            @behaviour Ysc.StripeBehaviour

            def create_payment_intent(_params, _opts),
              do: {:error, :not_implemented}

            def cancel_payment_intent(_id, _opts),
              do: {:error, :not_implemented}

            def create_customer(_params), do: {:error, :not_implemented}
            def update_customer(_id, _params), do: {:error, :not_implemented}
            def retrieve_payment_method(_id), do: {:error, :not_implemented}
            def list_events(_params, _opts), do: {:error, :not_implemented}
            def retrieve_charge(_id, _opts), do: {:error, :not_implemented}
            def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

            def list_balance_transactions(_params, _opts),
              do: {:error, :not_implemented}

            def retrieve_payment_intent(id, _opts) do
              {:ok,
               %Stripe.PaymentIntent{
                 id: id,
                 status: "succeeded",
                 amount: unquote(amount_cents),
                 metadata: unquote(Macro.escape(stripe_metadata)),
                 latest_charge: %Stripe.Charge{id: "ch_#{id}"}
               }}
            end
          end,
          Macro.Env.location(__ENV__)
        )

      Application.put_env(:ysc, :stripe_client, test_stripe_client)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded&payment_intent=#{payment_intent_id}&updated=true"
        )

      assert html =~ "Reservation updated"

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.checkout_date == checkout
      assert reloaded.refund_forfeited_at

      assert Ysc.Ledgers.get_payment_by_external_id(payment_intent_id)
    end

    test "persists guest details after redirect-based paid modification with more guests",
         %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      user =
        user_fixture()
        |> Ecto.Changeset.change(state: :active)
        |> Repo.update!()

      conn = log_in_user(conn, user)

      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Receipt guest modify category"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name:
            "Receipt guest modify room #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = tahoe_booking_dates(150)

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
               Ysc.Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: total,
                 entity_type: :booking,
                 entity_id: booking.id,
                 external_payment_id:
                   "pi_receipt_guest_base_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(100, :USD),
                 description: "Booking payment",
                 property: booking.property,
                 payment_method_id: nil
               })

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

      attrs = %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 3,
        children_count: 0
      }

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(checkin),
                 "checkout_date" => Date.to_string(checkout),
                 "guests_count" => "3",
                 "children_count" => "0"
               })

      assert Money.positive?(preview.delta)

      guest_params = %{
        "0" => %{
          "first_name" => user.first_name || "Test",
          "last_name" => user.last_name || "User",
          "is_child" => false,
          "is_booking_user" => true,
          "order_index" => 0
        },
        "1" => %{
          "first_name" => "Guest",
          "last_name" => "Two",
          "is_child" => false,
          "is_booking_user" => false,
          "order_index" => 1
        },
        "2" => %{
          "first_name" => "New",
          "last_name" => "Guest",
          "is_child" => false,
          "is_booking_user" => false,
          "order_index" => 2
        }
      }

      assert {:ok, _} =
               Bookings.place_modification_hold(booking, attrs,
                 guest_params: guest_params
               )

      payment_intent_id =
        "pi_receipt_guest_redirect_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stripe_metadata = %{
        "booking_id" => to_string(booking.id),
        "user_id" => to_string(user.id),
        "modification" => "true"
      }

      module_name =
        :"ReceiptGuestModificationRedirectStripe#{System.unique_integer([:positive])}"

      {:module, test_stripe_client, _, _} =
        Module.create(
          module_name,
          quote do
            @behaviour Ysc.StripeBehaviour

            def create_payment_intent(_params, _opts),
              do: {:error, :not_implemented}

            def cancel_payment_intent(_id, _opts),
              do: {:error, :not_implemented}

            def create_customer(_params), do: {:error, :not_implemented}
            def update_customer(_id, _params), do: {:error, :not_implemented}
            def retrieve_payment_method(_id), do: {:error, :not_implemented}
            def list_events(_params, _opts), do: {:error, :not_implemented}
            def retrieve_charge(_id, _opts), do: {:error, :not_implemented}
            def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

            def list_balance_transactions(_params, _opts),
              do: {:error, :not_implemented}

            def retrieve_payment_intent(id, _opts) do
              {:ok,
               %Stripe.PaymentIntent{
                 id: id,
                 status: "succeeded",
                 amount: unquote(amount_cents),
                 metadata: unquote(Macro.escape(stripe_metadata)),
                 latest_charge: %Stripe.Charge{id: "ch_#{id}"}
               }}
            end
          end,
          Macro.Env.location(__ENV__)
        )

      Application.put_env(:ysc, :stripe_client, test_stripe_client)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded&payment_intent=#{payment_intent_id}&updated=true"
        )

      assert html =~ "Reservation updated"

      reloaded = Repo.get!(Booking, booking.id) |> Repo.preload(:booking_guests)
      assert reloaded.guests_count == 3

      guests =
        reloaded.booking_guests
        |> Enum.sort_by(& &1.order_index)

      assert length(guests) == 3
      assert Enum.at(guests, 2).first_name == "New"
      assert Enum.at(guests, 2).last_name == "Guest"
    end

    test "records modification ledger after redirect when change was already applied",
         %{
           conn: conn
         } do
      Ysc.Ledgers.ensure_basic_accounts()
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      user =
        user_fixture()
        |> Ecto.Changeset.change(state: :active)
        |> Repo.update!()

      conn = log_in_user(conn, user)

      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Receipt ledger recovery category"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name:
            "Receipt ledger recovery room #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = tahoe_booking_dates(142)
      short_checkout = Date.add(checkin, 1)

      assert {:ok, total, _} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 short_checkout,
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
                   checkout_date: short_checkout,
                   booking_mode: :room,
                   guests_count: 2,
                   total_price: total
                 },
                 rooms: [room],
                 skip_email: true,
                 skip_reminders: true
               )

      assert {:ok, _} =
               Ysc.Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: total,
                 entity_type: :booking,
                 entity_id: booking.id,
                 external_payment_id:
                   "pi_receipt_ledger_recovery_base_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(100, :USD),
                 description: "Booking payment",
                 property: booking.property,
                 payment_method_id: nil
               })

      hold_attrs = %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 2,
        children_count: 0
      }

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(checkin),
                 "checkout_date" => Date.to_string(checkout),
                 "guests_count" => "2",
                 "children_count" => "0"
               })

      assert Money.positive?(preview.delta)

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, hold_attrs)

      assert {:ok, updated_booking} =
               BookingLocker.modify_complete_booking(
                 held_booking,
                 hold_attrs,
                 previous_details: %{
                   checkin_date: booking.checkin_date,
                   checkout_date: booking.checkout_date,
                   guests_count: booking.guests_count,
                   children_count: booking.children_count || 0,
                   total_price: booking.total_price
                 }
               )

      assert updated_booking.checkout_date == checkout
      assert is_nil(updated_booking.modification_hold_attrs)
      assert is_nil(updated_booking.modification_hold_expires_at)

      payment_intent_id =
        "pi_receipt_ledger_recovery_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stripe_metadata = %{
        "booking_id" => to_string(booking.id),
        "user_id" => to_string(user.id),
        "modification" => "true"
      }

      module_name =
        :"ReceiptLedgerRecoveryStripe#{System.unique_integer([:positive])}"

      {:module, test_stripe_client, _, _} =
        Module.create(
          module_name,
          quote do
            @behaviour Ysc.StripeBehaviour

            def create_payment_intent(_params, _opts),
              do: {:error, :not_implemented}

            def cancel_payment_intent(_id, _opts),
              do: {:error, :not_implemented}

            def create_customer(_params), do: {:error, :not_implemented}
            def update_customer(_id, _params), do: {:error, :not_implemented}
            def retrieve_payment_method(_id), do: {:error, :not_implemented}
            def list_events(_params, _opts), do: {:error, :not_implemented}
            def retrieve_charge(_id, _opts), do: {:error, :not_implemented}
            def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

            def list_balance_transactions(_params, _opts),
              do: {:error, :not_implemented}

            def retrieve_payment_intent(id, _opts) do
              {:ok,
               %Stripe.PaymentIntent{
                 id: id,
                 status: "succeeded",
                 amount: unquote(amount_cents),
                 metadata: unquote(Macro.escape(stripe_metadata)),
                 latest_charge: %Stripe.Charge{id: "ch_#{id}"}
               }}
            end
          end,
          Macro.Env.location(__ENV__)
        )

      Application.put_env(:ysc, :stripe_client, test_stripe_client)

      refute Ysc.Ledgers.get_payment_by_external_id(payment_intent_id)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded&payment_intent=#{payment_intent_id}&updated=true"
        )

      assert html =~ "Reservation updated"
      assert Ysc.Ledgers.get_payment_by_external_id(payment_intent_id)

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.checkout_date == checkout
    end

    test "applies paid modification after hold expiry worker cleared inventory",
         %{
           conn: conn
         } do
      Ysc.Ledgers.ensure_basic_accounts()
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      user =
        user_fixture()
        |> Ecto.Changeset.change(state: :active)
        |> Repo.update!()

      conn = log_in_user(conn, user)

      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Receipt worker expiry category"
        })
        |> Repo.insert()

      {:ok, room} =
        Bookings.create_room(%{
          name:
            "Receipt worker expiry room #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = tahoe_booking_dates(141)
      short_checkout = Date.add(checkin, 1)

      assert {:ok, total, _} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 short_checkout,
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
                   checkout_date: short_checkout,
                   booking_mode: :room,
                   guests_count: 2,
                   total_price: total
                 },
                 rooms: [room],
                 skip_email: true,
                 skip_reminders: true
               )

      assert {:ok, _} =
               Ysc.Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: total,
                 entity_type: :booking,
                 entity_id: booking.id,
                 external_payment_id:
                   "pi_receipt_worker_base_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(100, :USD),
                 description: "Booking payment",
                 property: booking.property,
                 payment_method_id: nil
               })

      attrs = %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 2,
        children_count: 0
      }

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(checkin),
                 "checkout_date" => Date.to_string(checkout),
                 "guests_count" => "2",
                 "children_count" => "0"
               })

      assert Money.positive?(preview.delta)

      assert {:ok, _} = Bookings.place_modification_hold(booking, attrs)

      held_booking = Repo.get!(Booking, booking.id)

      held_booking
      |> Ecto.Changeset.change(
        modification_hold_expires_at:
          DateTime.add(
            DateTime.utc_now() |> DateTime.truncate(:second),
            -5,
            :minute
          )
      )
      |> Repo.update!()

      Ysc.Bookings.ModificationHoldExpiryWorker.expire_expired_modification_holds()

      reloaded = Repo.get!(Booking, booking.id)
      assert is_nil(reloaded.modification_hold_expires_at)
      assert reloaded.modification_hold_attrs

      payment_intent_id =
        "pi_receipt_worker_expiry_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stripe_metadata = %{
        "booking_id" => to_string(booking.id),
        "user_id" => to_string(user.id),
        "modification" => "true"
      }

      module_name =
        :"ReceiptModificationWorkerExpiryStripe#{System.unique_integer([:positive])}"

      {:module, test_stripe_client, _, _} =
        Module.create(
          module_name,
          quote do
            @behaviour Ysc.StripeBehaviour

            def create_payment_intent(_params, _opts),
              do: {:error, :not_implemented}

            def cancel_payment_intent(_id, _opts),
              do: {:error, :not_implemented}

            def create_customer(_params), do: {:error, :not_implemented}
            def update_customer(_id, _params), do: {:error, :not_implemented}
            def retrieve_payment_method(_id), do: {:error, :not_implemented}
            def list_events(_params, _opts), do: {:error, :not_implemented}
            def retrieve_charge(_id, _opts), do: {:error, :not_implemented}
            def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

            def list_balance_transactions(_params, _opts),
              do: {:error, :not_implemented}

            def retrieve_payment_intent(id, _opts) do
              {:ok,
               %Stripe.PaymentIntent{
                 id: id,
                 status: "succeeded",
                 amount: unquote(amount_cents),
                 metadata: unquote(Macro.escape(stripe_metadata)),
                 latest_charge: %Stripe.Charge{id: "ch_#{id}"}
               }}
            end
          end,
          Macro.Env.location(__ENV__)
        )

      Application.put_env(:ysc, :stripe_client, test_stripe_client)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/bookings/#{booking.id}/receipt?redirect_status=succeeded&payment_intent=#{payment_intent_id}&updated=true"
        )

      assert html =~ "Reservation updated"

      final_booking = Repo.get!(Booking, booking.id)
      assert final_booking.checkout_date == checkout
      assert Ysc.Ledgers.get_payment_by_external_id(payment_intent_id)
    end
  end

  describe "confirm-cancel" do
    test "submits cancellation for future booking with payment on file", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)
      booking = future_booking_for_cancel(user)
      create_payment_for_booking(booking, Money.new(10_000, :USD))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_click(view, "show-cancel-modal")
      render_async(view, @async_timeout_ms)

      result =
        view
        |> form("#cancel-booking-form", %{"reason" => "Integration test cancel"})
        |> render_submit()

      case result do
        {:error, {:live_redirect, %{to: to}}} ->
          assert to =~ "/bookings/#{booking.id}/receipt"

        html when is_binary(html) ->
          assert html =~ booking.reference_id
      end
    end
  end

  describe "handle_async load_receipt_data exit" do
    test "marks async data loaded when async task exits", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      %{socket: socket} = :sys.get_state(view.pid)

      assert {:noreply, new_socket} =
               YscWeb.BookingReceiptLive.handle_async(
                 :load_receipt_data,
                 {:exit, :test_reason},
                 socket
               )

      assert new_socket.assigns.async_data_loaded == true
    end
  end

  describe "cancel modal input variants" do
    test "update-cancel-reason accepts value key", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = future_booking_for_cancel(user)

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_click(view, "show-cancel-modal")

      html =
        render_click(view, "update-cancel-reason", %{"value" => "Travel change"})

      assert html =~ booking.reference_id
    end

    test "hide-cancel-modal after show returns to main view", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = future_booking_for_cancel(user)

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_click(view, "show-cancel-modal")
      html = render_click(view, "hide-cancel-modal")
      assert html =~ booking.reference_id
    end
  end

  describe "booking references and status" do
    test "hold status still renders receipt shell", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :hold})

      {:ok, view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert has_element?(view, "#booking-receipt")
      assert html =~ booking.reference_id
    end

    test "displays children count line when children present", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :room,
          children_count: 2
        })

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Children" or html =~ "children"
    end
  end

  describe "property and layout details" do
    test "Tahoe booking mentions Lake Tahoe", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe
        })

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Lake Tahoe" or html =~ "Tahoe"
    end

    test "shows confetti disabled without query param", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert has_element?(view, ~s([data-show-confetti="false"]))
    end

    test "room mode without preloaded rooms shows Individual room(s) label", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :room
        })

      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Individual room(s)"
      assert html =~ "Reservation type"
    end
  end

  describe "pricing_items breakdown in payment summary" do
    test "renders buyout line items when pricing_items stored on booking", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :buyout
        })

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "buyout",
            "nights" => 3,
            "price_per_night" => %{"amount" => "100", "currency" => "USD"}
          }
        })
        |> Repo.update()

      booking = Repo.reload!(booking)
      create_payment_for_booking(booking, Money.new(10_000, :USD))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")
      render_async(view, @async_timeout_ms)
      html = render(view)

      assert html =~ "Entire cabin"
      assert html =~ "× 3"
    end

    test "buyout line amount matches nights × rate when subtotal_price is stale",
         %{
           conn: conn
         } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :buyout,
          total_price: Money.new(1275, :USD),
          subtotal_price: Money.new(850, :USD)
        })

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "buyout",
            "nights" => 3,
            "price_per_night" => %{"amount" => "425", "currency" => "USD"},
            "total" => %{"amount" => "1275", "currency" => "USD"}
          }
        })
        |> Repo.update()

      booking = Repo.reload!(booking)

      create_payment_for_booking(booking, Money.new(850, :USD))
      create_payment_for_booking(booking, Money.new(425, :USD))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")
      render_async(view, @async_timeout_ms)

      assert has_element?(
               view,
               "#payment-summary-buyout-line",
               "($425.00 × 3 nights)"
             )

      assert has_element?(view, "#payment-summary-buyout-line", "$1,275.00")
      refute has_element?(view, "#payment-summary-buyout-line", "$850.00")
    end

    test "renders room breakdown with children line when pricing_items include room rooms",
         %{
           conn: conn
         } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :room,
          children_count: 1
        })

      room_item = %{
        "type" => "room",
        "room_id" => "r1",
        "room_name" => "Pine",
        "nights" => 2,
        "guests_count" => 2,
        "children_count" => 1,
        "base" => %{"amount" => "200", "currency" => "USD"},
        "adult_price_per_night" => %{"amount" => "100", "currency" => "USD"},
        "children" => %{"amount" => "40", "currency" => "USD"},
        "billable_people" => 2
      }

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "room",
            "nights" => 2,
            "guests_count" => 2,
            "children_count" => 1,
            "rooms" => [room_item]
          }
        })
        |> Repo.update()

      booking = Repo.reload!(booking)
      create_payment_for_booking(booking, Money.new(25_000, :USD))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")
      render_async(view, @async_timeout_ms)
      html = render(view)

      assert html =~ "Children"
      assert html =~ "Base Price"
    end

    test "renders per-guest line when pricing_items type is per_guest", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :day,
          guests_count: 2
        })

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "per_guest",
            "nights" => 2,
            "guests_count" => 2,
            "price_per_guest_per_night" => %{
              "amount" => "50",
              "currency" => "USD"
            }
          }
        })
        |> Repo.update()

      booking = Repo.reload!(booking)
      create_payment_for_booking(booking, Money.new(10_000, :USD))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")
      render_async(view, @async_timeout_ms)
      html = render(view)

      assert html =~ "Spot Rental"
      assert html =~ "2 adults"
      assert html =~ "2 nights"
    end

    test "renders entitlement discount line when pricing_items include discounts",
         %{
           conn: conn
         } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :room,
          children_count: 1,
          total_price: Money.new(:USD, "76.67"),
          subtotal_price: Money.new(:USD, "230"),
          discount_total: Money.new(:USD, "153.33")
        })

      room_item = %{
        "type" => "room",
        "room_id" => "r1",
        "room_name" => "Pine",
        "nights" => 2,
        "guests_count" => 2,
        "children_count" => 1,
        "base" => %{"amount" => "180", "currency" => "USD"},
        "adult_price_per_night" => %{"amount" => "45", "currency" => "USD"},
        "children" => %{"amount" => "50", "currency" => "USD"},
        "billable_people" => 2
      }

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "room",
            "nights" => 2,
            "guests_count" => 2,
            "children_count" => 1,
            "rooms" => [room_item],
            "subtotal" => %{"amount" => "230", "currency" => "USD"},
            "discount_total" => %{"amount" => "153.33", "currency" => "USD"},
            "discounts" => [
              %{
                "entitlement_id" => Ecto.ULID.generate(),
                "summary" => "50% off stay",
                "amount" => %{"amount" => "153.33", "currency" => "USD"}
              }
            ]
          }
        })
        |> Repo.update()

      booking = Repo.reload!(booking)
      create_payment_for_booking(booking, Money.new(:USD, "76.67"))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")
      render_async(view, @async_timeout_ms)
      html = render(view)

      assert has_element?(
               view,
               "#payment-summary-entitlement-discount",
               "50% off stay"
             )

      assert has_element?(
               view,
               "#payment-summary-entitlement-discount",
               "−$153.33"
             )

      assert html =~ "$76.67"
    end

    test "falls back to booking.discount_total when pricing_items omit discount fields",
         %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :buyout,
          total_price: Money.new(:USD, "850")
        })

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{
          subtotal_price: Money.new(:USD, "1275"),
          discount_total: Money.new(:USD, "425"),
          pricing_items: %{
            "type" => "buyout",
            "nights" => 3,
            "price_per_night" => %{"amount" => "425", "currency" => "USD"}
          }
        })
        |> Repo.update()

      booking = Repo.reload!(booking)
      create_payment_for_booking(booking, Money.new(:USD, "850"))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")
      render_async(view, @async_timeout_ms)

      assert has_element?(
               view,
               "#payment-summary-entitlement-discount",
               "Member discount"
             )

      assert has_element?(
               view,
               "#payment-summary-entitlement-discount",
               "−$425.00"
             )
    end

    test "renders buyout entitlement discount from top-level pricing_items fields",
         %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          booking_mode: :buyout,
          total_price: Money.new(:USD, "850"),
          subtotal_price: Money.new(:USD, "850")
        })

      {:ok, _} =
        booking
        |> Ecto.Changeset.change(%{
          pricing_items: %{
            "type" => "buyout",
            "nights" => 3,
            "price_per_night" => %{"amount" => "425", "currency" => "USD"},
            "entitlement_discount" => %{"amount" => "425", "currency" => "USD"},
            "entitlement_subtotal" => %{"amount" => "1275", "currency" => "USD"}
          }
        })
        |> Repo.update()

      booking = Repo.reload!(booking)
      create_payment_for_booking(booking, Money.new(:USD, "850"))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")
      render_async(view, @async_timeout_ms)
      html = render(view)

      assert has_element?(
               view,
               "#payment-summary-buyout-line",
               "($425.00 × 3 nights)"
             )

      assert has_element?(view, "#payment-summary-buyout-line", "$1,275.00")

      assert has_element?(
               view,
               "#payment-summary-entitlement-discount",
               "Member discount"
             )

      assert has_element?(
               view,
               "#payment-summary-entitlement-discount",
               "−$425.00"
             )

      assert html =~ "$850.00"
    end
  end

  describe "async loading" do
    test "render_async completes payment section for paid booking", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})
      create_payment_for_booking(booking, Money.new(10_000, :USD))

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_async(view, @async_timeout_ms)
      html = render(view)
      assert html =~ "Payment Summary" or html =~ "$100.00"
    end

    test "async_data_loaded after render_async", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, status: :complete})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      render_async(view, @async_timeout_ms)
      html = render(view)
      assert html =~ booking.reference_id
    end
  end

  # Helper functions

  defp first_weekday_on_or_after(date, target_dow) do
    dow = Date.day_of_week(date, :monday)
    days = rem(target_dow - dow + 7, 7)
    Date.add(date, days)
  end

  defp future_booking_for_cancel(user) do
    today = Date.utc_today()
    days_to_friday = 5 - Date.day_of_week(today, :monday)

    days_to_friday =
      if days_to_friday < 0, do: days_to_friday + 7, else: days_to_friday

    checkin_date = Date.add(today, days_to_friday + 7)
    checkout_date = Date.add(checkin_date, 3)

    booking_fixture(%{
      user_id: user.id,
      status: :complete,
      checkin_date: checkin_date,
      checkout_date: checkout_date
    })
  end

  # Helper function to create a payment for a booking
  defp create_payment_for_booking(booking, amount, opts \\ []) do
    payment_method_id = Keyword.get(opts, :payment_method_id)

    external_payment_id =
      Keyword.get(
        opts,
        :external_payment_id,
        "pi_test_#{System.unique_integer()}"
      )

    # Get or create the stripe account
    stripe_account =
      case Ysc.Ledgers.get_account_by_name("stripe_account") do
        nil ->
          {:ok, account} =
            Ysc.Ledgers.create_account(%{
              name: "stripe_account",
              account_type: :asset,
              description: "Stripe Account"
            })

          account

        account ->
          account
      end

    # Create payment
    {:ok, payment} =
      Ysc.Ledgers.create_payment(%{
        user_id: booking.user_id,
        amount: amount,
        entity_type: :booking,
        entity_id: booking.id,
        external_provider: :stripe,
        external_payment_id: external_payment_id,
        status: :completed,
        stripe_fee: Money.new(300, :USD),
        description: "Test booking payment",
        property: booking.property,
        payment_date: DateTime.utc_now(),
        payment_method_id: payment_method_id
      })

    # Create ledger transaction and entries
    {:ok, transaction} =
      Ysc.Ledgers.create_transaction(%{
        description: "Booking payment - #{booking.reference_id}",
        transaction_date: DateTime.utc_now(),
        payment_id: payment.id,
        type: :payment,
        total_amount: amount,
        status: :completed
      })

    # Create debit entry to stripe account
    {:ok, _debit_entry} =
      Ysc.Ledgers.create_entry(%{
        transaction_id: transaction.id,
        account_id: stripe_account.id,
        debit_credit: "debit",
        amount: amount,
        related_entity_type: :booking,
        related_entity_id: booking.id,
        payment_id: payment.id
      })

    payment
  end

  defp receipt_ledger_payment_count(booking_id) do
    case Bookings.get_booking_payment(%Booking{id: booking_id}) do
      {:ok, _} -> 1
      {:error, :payment_not_found} -> 0
    end
  end

  defp ensure_receipt_buyout_base_pricing! do
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
          if duplicate_receipt_buyout_pricing_rule?(cs),
            do: :ok,
            else: raise(cs)

        {:error, other} ->
          raise("unexpected create_pricing_rule: #{inspect(other)}")
      end
    end

    :ok
  end

  defp duplicate_receipt_buyout_pricing_rule?(%Ecto.Changeset{} = cs) do
    Enum.any?(cs.errors, fn {_field, {_msg, meta}} ->
      meta[:constraint] == :unique
    end)
  end
end

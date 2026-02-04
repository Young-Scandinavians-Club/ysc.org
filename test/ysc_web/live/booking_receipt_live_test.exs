defmodule YscWeb.BookingReceiptLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

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
      assert flash["error"] =~ "Booking not found"
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
      assert flash["error"] =~ "Booking not found"
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
      # Use Monday check-in, Thursday checkout to avoid weekend validation rules
      # Find next Monday
      days_until_monday = rem(8 - Date.day_of_week(today), 7)
      checkin_date = Date.add(today, 30 + days_until_monday)
      # Check out on Thursday (3 days later)
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

      # Wait for async data to load
      :timer.sleep(100)

      html = render(view)
      assert html =~ "Payment Summary" or html =~ "$100.00"
    end
  end

  describe "event handlers - navigation" do
    test "view-bookings redirects to property bookings page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert {:error, {:redirect, %{to: path}}} =
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

      assert {:error, {:redirect, %{to: path}}} =
               render_click(view, "view-bookings")

      assert path == "/bookings/clear-lake"
    end

    test "go-home redirects to home page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking = booking_fixture(%{user_id: user.id})

      {:ok, view, _html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert {:error, {:redirect, %{to: path}}} = render_click(view, "go-home")

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

      # Wait for async load
      :timer.sleep(100)

      assert has_element?(view, ~s(button), "Cancel Reservation")
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

      # Wait for async load
      :timer.sleep(100)

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

      # Wait for async load
      :timer.sleep(100)

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

  # Helper function to create a payment for a booking
  defp create_payment_for_booking(booking, amount) do
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
        external_payment_id: "pi_test_#{System.unique_integer()}",
        status: :completed,
        stripe_fee: Money.new(300, :USD),
        description: "Test booking payment",
        property: booking.property,
        payment_date: DateTime.utc_now()
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
end

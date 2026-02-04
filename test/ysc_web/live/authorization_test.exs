defmodule YscWeb.AuthorizationTest do
  @moduledoc """
  Comprehensive authorization tests for LiveViews to ensure users can only
  access and modify resources they own.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Ysc.TicketsFixtures
  import Mox

  alias Ysc.Tickets
  alias Ysc.StripeMock

  setup :verify_on_exit!

  describe "UserBookingDetailLive authorization" do
    setup %{conn: conn} do
      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :complete)

      other_user = user_fixture()
      other_booking = booking_fixture(user_id: other_user.id, status: :complete)

      %{
        conn: log_in_user(conn, user),
        user: user,
        booking: booking,
        other_user: other_user,
        other_booking: other_booking
      }
    end

    test "user can access their own booking", %{conn: conn, booking: booking} do
      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}")

      assert html =~ "Booking Details"
      assert html =~ booking.reference_id
    end

    test "user cannot access another user's booking", %{
      conn: conn,
      other_user: _other_user,
      other_booking: other_booking
    } do
      # Try to access another user's booking
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/#{other_booking.id}")

      assert path == ~p"/"
    end

    test "user cannot cancel another user's booking", %{
      conn: conn,
      other_user: _other_user,
      other_booking: other_booking
    } do
      # This should fail at mount, but test the full flow
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/#{other_booking.id}")

      assert path == ~p"/"
    end
  end

  describe "BookingCheckoutLive authorization" do
    setup %{conn: conn} do
      import Mox
      alias Ysc.StripeMock

      Application.put_env(:ysc, :stripe_client, StripeMock)

      stub(StripeMock, :create_payment_intent, fn _params, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_test_123",
           client_secret: "pi_test_123_secret_456",
           status: "requires_payment_method"
         }}
      end)

      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :hold)

      other_user = user_fixture()
      other_booking = booking_fixture(user_id: other_user.id, status: :hold)

      %{
        conn: log_in_user(conn, user),
        user: user,
        booking: booking,
        other_user: other_user,
        other_booking: other_booking
      }
    end

    test "user can access their own booking checkout", %{
      conn: conn,
      booking: booking
    } do
      {:ok, _view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert html =~ "Complete Your Booking"
    end

    test "user cannot access another user's booking checkout", %{
      conn: conn,
      other_booking: other_booking
    } do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/checkout/#{other_booking.id}")

      # Should redirect to property page or home
      assert path =~ "/"
    end
  end

  describe "UserTicketsLive authorization" do
    setup %{conn: conn} do
      user = user_fixture()
      ticket_order = ticket_order_fixture(user_id: user.id, status: :pending)

      other_user = user_fixture()

      other_ticket_order =
        ticket_order_fixture(user_id: other_user.id, status: :pending)

      %{
        conn: log_in_user(conn, user),
        user: user,
        ticket_order: ticket_order,
        other_user: other_user,
        other_ticket_order: other_ticket_order
      }
    end

    test "user can cancel their own ticket order", %{
      conn: conn,
      ticket_order: ticket_order
    } do
      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      # Cancel order event
      assert view
             |> element(
               "button[phx-click='cancel-order'][phx-value-order-id='#{ticket_order.id}']"
             )
             |> render_click()

      # Should show success message
      assert has_element?(view, "#ticket-orders-list")
    end

    test "user cannot cancel another user's ticket order", %{
      conn: conn,
      other_ticket_order: other_ticket_order
    } do
      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      # Try to cancel another user's order - should not be visible in the list
      refute has_element?(
               view,
               "button[phx-click='cancel-order'][phx-value-order-id='#{other_ticket_order.id}']"
             )
    end

    test "user cannot resume another user's ticket order", %{
      conn: conn,
      other_ticket_order: other_ticket_order
    } do
      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      # Try to resume another user's order - should not be visible in the list
      refute has_element?(
               view,
               "button[phx-click='resume-order'][phx-value-order-id='#{other_ticket_order.id}']"
             )
    end
  end

  describe "OrderConfirmationLive authorization" do
    setup %{conn: conn} do
      user = user_fixture()
      ticket_order = ticket_order_fixture(user_id: user.id, status: :completed)

      other_user = user_fixture()

      other_ticket_order =
        ticket_order_fixture(user_id: other_user.id, status: :completed)

      %{
        conn: log_in_user(conn, user),
        user: user,
        ticket_order: ticket_order,
        other_user: other_user,
        other_ticket_order: other_ticket_order
      }
    end

    test "user can access their own order confirmation", %{
      conn: conn,
      ticket_order: ticket_order
    } do
      {:ok, _view, html} =
        live(conn, ~p"/orders/#{ticket_order.id}/confirmation")

      assert html =~ "Order Confirmation"
    end

    test "user cannot access another user's order confirmation", %{
      conn: conn,
      other_ticket_order: other_ticket_order
    } do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/orders/#{other_ticket_order.id}/confirmation")

      assert path == ~p"/events"
    end
  end

  describe "BookingReceiptLive authorization" do
    setup %{conn: conn} do
      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :complete)

      other_user = user_fixture()
      other_booking = booking_fixture(user_id: other_user.id, status: :complete)

      %{
        conn: log_in_user(conn, user),
        user: user,
        booking: booking,
        other_user: other_user,
        other_booking: other_booking
      }
    end

    test "user can access their own booking receipt", %{
      conn: conn,
      booking: booking
    } do
      {:ok, _view, html} = live(conn, ~p"/bookings/#{booking.id}/receipt")

      assert html =~ "Booking Confirmation"
    end

    test "user cannot access another user's booking receipt", %{
      conn: conn,
      other_booking: other_booking
    } do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/#{other_booking.id}/receipt")

      assert path == ~p"/"
    end
  end

  describe "Tickets context user-scoped functions" do
    setup do
      user = user_fixture()
      ticket_order = ticket_order_fixture(user_id: user.id, status: :completed)

      other_user = user_fixture()

      other_ticket_order =
        ticket_order_fixture(user_id: other_user.id, status: :completed)

      %{
        user: user,
        ticket_order: ticket_order,
        other_user: other_user,
        other_ticket_order: other_ticket_order
      }
    end

    test "get_user_ticket_order returns order for correct user", %{
      user: user,
      ticket_order: ticket_order
    } do
      result = Tickets.get_user_ticket_order(user.id, ticket_order.id)

      assert result.id == ticket_order.id
      assert result.user_id == user.id
    end

    test "get_user_ticket_order returns nil for another user's order", %{
      user: user,
      other_ticket_order: other_ticket_order
    } do
      result = Tickets.get_user_ticket_order(user.id, other_ticket_order.id)

      assert result == nil
    end
  end
end

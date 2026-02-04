defmodule YscWeb.BookingCheckoutLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Mox

  alias Ysc.StripeMock

  setup :verify_on_exit!

  describe "Booking Checkout page" do
    setup %{conn: conn} do
      Application.put_env(:ysc, :stripe_client, StripeMock)

      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :hold)

      stub(StripeMock, :create_payment_intent, fn _params, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_test_123",
           client_secret: "pi_test_123_secret_456",
           status: "requires_payment_method"
         }}
      end)

      %{conn: log_in_user(conn, user), user: user, booking: booking}
    end

    test "renders checkout page", %{conn: conn, booking: booking} do
      {:ok, _view, html} = live(conn, ~p"/bookings/checkout/#{booking.id}")
      assert html =~ "Complete Your Booking"
      assert html =~ "Booking Summary"
    end

    test "redirects if not owner", %{conn: conn, booking: booking} do
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      # When booking is not found (not owned by user), redirects to home
      assert path == ~p"/"
    end
  end
end

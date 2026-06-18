defmodule YscWeb.BookingCheckoutDeferredTest do
  @moduledoc """
  Query-count assertions for booking checkout deferred loading.
  """
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Mox

  alias Ysc.Ledgers
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

    ensure_buyout_base_pricing!()

    user = user_fixture()
    booking = booking_fixture(user_id: user.id, status: :hold)

    {:ok, conn: log_in_user(conn, user), user: user, booking: booking}
  end

  test "dead render skips checkout queries and shows loading state", %{
    conn: conn,
    booking: booking
  } do
    bookings_pattern = ~r/FROM "bookings"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get(~p"/bookings/checkout/#{booking.id}")
          |> html_response(200)
        end,
        pattern: bookings_pattern
      )

    assert query_count == 0
    assert html =~ "Complete Your Booking"
    assert html =~ "Loading checkout details"
    refute html =~ "Booking Summary"
  end
end

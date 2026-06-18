defmodule YscWeb.BookingCheckoutDeferredTest do
  @moduledoc """
  Query-count assertions for booking checkout deferred loading.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  setup %{conn: conn} do
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

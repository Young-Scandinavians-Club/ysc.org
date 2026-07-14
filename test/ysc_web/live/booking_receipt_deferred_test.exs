defmodule YscWeb.BookingReceiptDeferredTest do
  @moduledoc """
  Query-count assertions for booking receipt deferred loading.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    booking = booking_fixture(%{user_id: user.id, status: :complete})

    {:ok, conn: log_in_user(conn, user), booking: booking}
  end

  test "dead render skips booking queries and shows loading state", %{
    conn: conn,
    booking: booking
  } do
    bookings_pattern = ~r/FROM "bookings"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get(~p"/bookings/#{booking.id}/receipt")
          |> html_response(200)
        end,
        pattern: bookings_pattern
      )

    assert query_count == 0
    assert html =~ "Loading booking confirmation"
    refute html =~ booking.reference_id
  end

  test "dead render with stripe redirect still loads booking", %{
    conn: conn,
    booking: booking
  } do
    bookings_pattern = ~r/FROM "bookings"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get(~p"/bookings/#{booking.id}/receipt?redirect_status=failed")
          |> html_response(200)
        end,
        pattern: bookings_pattern
      )

    assert query_count >= 1
    assert html =~ "Payment failed"
  end
end

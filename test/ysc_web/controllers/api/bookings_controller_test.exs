defmodule YscWeb.Api.BookingsControllerTest do
  @moduledoc """
  Tests for the mobile API bookings endpoints.

  Covers index (list), calendar view, and lookup (by last name) actions,
  including property filtering, date filtering, and validation errors.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.BookingsFixtures
  import Ysc.AccountsFixtures

  # Creates a booking that is currently active (checked in already, not yet checked out),
  # which is required for the lookup endpoint to find it.
  defp active_booking_fixture(attrs) do
    today = Date.utc_today()
    attrs = Map.new(attrs)
    user_id = Map.get(attrs, :user_id) || Ysc.AccountsFixtures.user_fixture().id

    {:ok, booking} =
      attrs
      |> Enum.into(%{
        checkin_date: Date.add(today, -1),
        checkout_date: Date.add(today, 2),
        guests_count: 2,
        property: :tahoe,
        booking_mode: :buyout,
        user_id: user_id,
        status: :complete,
        total_price: Money.new(200, :USD)
      })
      |> Ysc.Bookings.create_booking()

    booking
  end

  @test_token "test-kiosk-secret"

  setup %{conn: conn} do
    previous = Application.get_env(:ysc, :kiosk_api_key)
    Application.put_env(:ysc, :kiosk_api_key, @test_token)

    on_exit(fn ->
      Application.put_env(:ysc, :kiosk_api_key, previous)
    end)

    authed_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{@test_token}")

    {:ok, conn: authed_conn}
  end

  describe "GET /api/v1/mobile/bookings (index)" do
    test "returns bookings for a valid property", %{conn: conn} do
      booking = booking_fixture()
      response = get(conn, ~p"/api/v1/mobile/bookings?property=tahoe")

      assert %{"data" => bookings} = json_response(response, 200)
      assert is_list(bookings)
      assert Enum.any?(bookings, &(&1["id"] == to_string(booking.id)))
    end

    test "returns empty list when no bookings match", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/bookings?property=clear_lake")

      assert %{"data" => bookings} = json_response(response, 200)
      assert bookings == []
    end

    test "returns 400 for missing property param", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/bookings")

      assert %{"error" => _} = json_response(response, 400)
    end

    test "returns 400 for invalid property value", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/bookings?property=invalid")

      assert %{"error" => _} = json_response(response, 400)
    end

    test "returns 400 for invalid start_date format", %{conn: conn} do
      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings?property=tahoe&start_date=not-a-date"
        )

      assert %{"error" => _} = json_response(response, 400)
    end

    test "filters bookings by date range", %{conn: conn} do
      booking = booking_fixture()
      far_future = Date.add(booking.checkout_date, 365)
      end_date = Date.add(booking.checkin_date, -1)

      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings?property=tahoe&start_date=2000-01-01&end_date=#{Date.to_iso8601(end_date)}"
        )

      assert %{"data" => bookings} = json_response(response, 200)
      refute Enum.any?(bookings, &(&1["id"] == to_string(booking.id)))

      _ = far_future
    end

    test "returns 401 without auth token", %{conn: conn} do
      unauthed_conn = delete_req_header(conn, "authorization")
      response = get(unauthed_conn, ~p"/api/v1/mobile/bookings?property=tahoe")

      assert json_response(response, 401)
    end

    test "booking response includes expected fields", %{conn: conn} do
      booking_fixture()
      response = get(conn, ~p"/api/v1/mobile/bookings?property=tahoe")

      assert %{"data" => [booking | _]} = json_response(response, 200)

      assert Map.has_key?(booking, "id")
      assert Map.has_key?(booking, "property")
      assert Map.has_key?(booking, "status")
      assert Map.has_key?(booking, "checkin_date")
      assert Map.has_key?(booking, "checkout_date")
      assert Map.has_key?(booking, "guests_count")
      assert Map.has_key?(booking, "checked_in")
      assert Map.has_key?(booking, "member")
      assert Map.has_key?(booking, "rooms")
      assert Map.has_key?(booking, "guests")
      assert Map.has_key?(booking, "check_ins")
    end
  end

  describe "GET /api/v1/mobile/bookings/calendar (calendar)" do
    test "returns calendar data for a valid property", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/bookings/calendar?property=tahoe")

      assert %{"data" => _, "start_date" => _, "end_date" => _} =
               json_response(response, 200)
    end

    test "groups bookings by date", %{conn: conn} do
      booking = booking_fixture()
      checkin_str = Date.to_iso8601(booking.checkin_date)

      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings/calendar?property=tahoe&start_date=#{checkin_str}&end_date=#{Date.to_iso8601(booking.checkout_date)}"
        )

      assert %{"data" => grouped} = json_response(response, 200)
      assert Map.has_key?(grouped, checkin_str)
      assert is_list(grouped[checkin_str])
    end

    test "returns 400 for missing property", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/bookings/calendar")

      assert %{"error" => _} = json_response(response, 400)
    end

    test "returns 400 for invalid end_date format", %{conn: conn} do
      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings/calendar?property=tahoe&end_date=bad-date"
        )

      assert %{"error" => _} = json_response(response, 400)
    end

    test "returns empty calendar when no bookings in range", %{conn: conn} do
      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings/calendar?property=tahoe&start_date=2000-01-01&end_date=2000-01-02"
        )

      assert %{"data" => grouped} = json_response(response, 200)
      assert grouped == %{}
    end
  end

  describe "GET /api/v1/mobile/bookings/lookup (lookup)" do
    test "finds bookings by member last name", %{conn: conn} do
      user = user_fixture(last_name: "Testsson")
      booking = active_booking_fixture(user_id: user.id)

      response =
        get(conn, ~p"/api/v1/mobile/bookings/lookup?last_name=Testsson")

      assert %{"data" => bookings} = json_response(response, 200)
      assert Enum.any?(bookings, &(&1["id"] == to_string(booking.id)))
    end

    test "lookup is case-insensitive", %{conn: conn} do
      user = user_fixture(last_name: "Johansson")
      booking = active_booking_fixture(user_id: user.id)

      response =
        get(conn, ~p"/api/v1/mobile/bookings/lookup?last_name=johansson")

      assert %{"data" => bookings} = json_response(response, 200)
      assert Enum.any?(bookings, &(&1["id"] == to_string(booking.id)))
    end

    test "trims whitespace from last_name", %{conn: conn} do
      user = user_fixture(last_name: "Lindgren")
      booking = active_booking_fixture(user_id: user.id)

      response =
        get(conn, ~p"/api/v1/mobile/bookings/lookup?last_name= Lindgren ")

      assert %{"data" => bookings} = json_response(response, 200)
      assert Enum.any?(bookings, &(&1["id"] == to_string(booking.id)))
    end

    test "returns 422 when last_name is missing", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/bookings/lookup")

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "last_name"
    end

    test "returns 422 when last_name is blank", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/bookings/lookup?last_name=  ")

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "last_name"
    end

    test "returns 400 for invalid property filter", %{conn: conn} do
      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings/lookup?last_name=Smith&property=invalid"
        )

      assert %{"error" => _} = json_response(response, 400)
    end

    test "filters by property when specified", %{conn: conn} do
      user = user_fixture(last_name: "Eriksson")
      tahoe_booking = active_booking_fixture(user_id: user.id, property: :tahoe)

      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings/lookup?last_name=Eriksson&property=clear_lake"
        )

      assert %{"data" => bookings} = json_response(response, 200)
      refute Enum.any?(bookings, &(&1["id"] == to_string(tahoe_booking.id)))
    end

    test "returns empty list when no match found", %{conn: conn} do
      response =
        get(conn, ~p"/api/v1/mobile/bookings/lookup?last_name=Xyzzy_NoMatch")

      assert %{"data" => []} = json_response(response, 200)
    end
  end
end

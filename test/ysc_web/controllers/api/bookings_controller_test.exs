defmodule YscWeb.Api.BookingsControllerTest do
  @moduledoc """
  Tests for the mobile API bookings endpoints.

  Covers index (list), calendar view, and lookup (by last name) actions,
  including property filtering, date filtering, and validation errors.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.BookingsFixtures
  import Ysc.AccountsFixtures

  alias Ysc.Test.KioskAPIKeyHelper

  @test_token "test-kiosk-secret"

  # Creates a booking that is currently active (checked in already, not yet checked out),
  # which is required for the lookup endpoint to find it.
  defp active_booking_fixture(attrs) do
    attrs = Map.new(attrs)
    user_id = Map.get(attrs, :user_id) || Ysc.AccountsFixtures.user_fixture().id
    {checkin, checkout} = active_stay_dates()

    {:ok, booking} =
      attrs
      |> Enum.into(%{
        checkin_date: checkin,
        checkout_date: checkout,
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

  # Index defaults to today-7 .. today+30; fixture stays can land outside that
  # window when seasons push buyout nights later — always pass an explicit range.
  defp index_path_covering(booking, property \\ "tahoe") do
    start_date = Date.add(booking.checkin_date, -1) |> Date.to_iso8601()
    end_date = Date.add(booking.checkout_date, 1) |> Date.to_iso8601()

    "/api/v1/mobile/bookings?property=#{property}&start_date=#{start_date}&end_date=#{end_date}"
  end

  setup %{conn: conn} do
    original = KioskAPIKeyHelper.capture_kiosk_api_key!(@test_token)

    on_exit(fn ->
      KioskAPIKeyHelper.restore_kiosk_api_key!(original)
    end)

    seed_canonical_seasons!()

    authed_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{@test_token}")

    {:ok, conn: authed_conn}
  end

  describe "GET /api/v1/mobile/bookings (index)" do
    test "returns bookings for a valid property", %{conn: conn} do
      booking = booking_fixture()
      response = get(conn, index_path_covering(booking))

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

    test "returns 422 when explicit date range exceeds the maximum span", %{
      conn: conn
    } do
      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings?property=tahoe&start_date=2000-01-01&end_date=2099-12-31"
        )

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "date range cannot exceed"
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

    test "defaults to a bounded date window when dates are omitted", %{
      conn: conn
    } do
      {old_checkin, old_checkout} = past_booking_dates_outside_default_window()

      {:ok, old_booking} =
        %{
          checkin_date: old_checkin,
          checkout_date: old_checkout,
          guests_count: 2,
          property: :tahoe,
          booking_mode: :buyout,
          user_id: user_fixture().id,
          status: :complete,
          total_price: Money.new(200, :USD)
        }
        |> Ysc.Bookings.create_booking()

      response = get(conn, ~p"/api/v1/mobile/bookings?property=tahoe")

      assert %{"data" => bookings} = json_response(response, 200)
      refute Enum.any?(bookings, &(&1["id"] == to_string(old_booking.id)))
    end

    test "returns 401 without auth token", %{conn: conn} do
      unauthed_conn = delete_req_header(conn, "authorization")
      response = get(unauthed_conn, ~p"/api/v1/mobile/bookings?property=tahoe")

      assert json_response(response, 401)
    end

    test "booking response includes expected fields", %{conn: conn} do
      booking = booking_fixture()
      response = get(conn, index_path_covering(booking))

      assert %{"data" => [booking | _]} = json_response(response, 200)

      assert Map.has_key?(booking, "id")
      assert Map.has_key?(booking, "property")
      assert Map.has_key?(booking, "status")
      assert Map.has_key?(booking, "checkin_date")
      assert Map.has_key?(booking, "checkout_date")
      assert Map.has_key?(booking, "guests_count")
      assert Map.has_key?(booking, "checked_in")
      assert Map.has_key?(booking, "member")
      member = booking["member"]
      assert member != nil
      assert Map.has_key?(member, "avatar_url")
      assert String.starts_with?(member["avatar_url"], "http")
      assert Map.has_key?(booking, "rooms")
      assert Map.has_key?(booking, "guests")
      assert Map.has_key?(booking, "check_ins")
    end

    test "booking response includes full check-in and vehicle details", %{
      conn: conn
    } do
      booking = booking_fixture()

      {:ok, _check_in} =
        Ysc.Bookings.create_check_in(%{
          bookings: [booking],
          rules_agreed: true,
          vehicles: [
            %{"type" => "sedan", "color" => "blue", "make" => "Toyota"},
            %{"type" => "suv", "color" => "black", "make" => "Honda"}
          ]
        })

      response =
        get(
          conn,
          "/api/v1/mobile/bookings?property=tahoe&start_date=#{Date.to_iso8601(booking.checkin_date)}&end_date=#{Date.to_iso8601(booking.checkout_date)}"
        )

      assert %{"data" => bookings} = json_response(response, 200)
      found = Enum.find(bookings, &(&1["id"] == to_string(booking.id)))
      assert found != nil

      assert [check_in | _] = found["check_ins"]
      assert Map.has_key?(check_in, "id")
      assert Map.has_key?(check_in, "checked_in_at")
      assert check_in["rules_agreed"] == true
      assert Map.has_key?(check_in, "vehicles")

      assert [vehicle1, vehicle2] = check_in["vehicles"]
      assert vehicle1["type"] == "sedan"
      assert vehicle1["color"] == "blue"
      assert vehicle1["make"] == "Toyota"
      assert Map.has_key?(vehicle1, "id")

      assert vehicle2["type"] == "suv"
      assert vehicle2["color"] == "black"
      assert vehicle2["make"] == "Honda"
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

    test "lookup returns check-ins with vehicle details", %{conn: conn} do
      user = user_fixture(last_name: "VehicleTest")
      booking = active_booking_fixture(user_id: user.id)

      {:ok, _check_in} =
        Ysc.Bookings.create_check_in(%{
          bookings: [booking],
          rules_agreed: true,
          vehicles: [%{"type" => "truck", "color" => "red", "make" => "Ford"}]
        })

      response =
        get(conn, ~p"/api/v1/mobile/bookings/lookup?last_name=VehicleTest")

      assert %{"data" => [found | _]} = json_response(response, 200)
      assert found["id"] == to_string(booking.id)
      assert [check_in | _] = found["check_ins"]
      assert [vehicle | _] = check_in["vehicles"]
      assert vehicle["type"] == "truck"
      assert vehicle["color"] == "red"
      assert vehicle["make"] == "Ford"
    end
  end

  describe "member avatar_url" do
    test "index includes member avatar_url with country-based default",
         %{
           conn: conn
         } do
      user = user_fixture(email: "avatar-test@example.com")
      booking = booking_fixture(user_id: user.id)

      response = get(conn, index_path_covering(booking))

      assert %{"data" => [booking | _]} = json_response(response, 200)
      member = booking["member"]
      avatar_url = member["avatar_url"]
      assert String.starts_with?(avatar_url, "http")
      assert avatar_url =~ "/images/default_avatars/"
    end

    test "calendar includes member avatar_url in each booking", %{conn: conn} do
      user = user_fixture(last_name: "CalendarAvatar")
      booking = active_booking_fixture(user_id: user.id)

      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings/calendar?property=tahoe&start_date=#{Date.to_iso8601(booking.checkin_date)}&end_date=#{Date.to_iso8601(booking.checkout_date)}"
        )

      assert %{"data" => grouped} = json_response(response, 200)
      date_str = Date.to_iso8601(booking.checkin_date)
      assert [calendar_booking | _] = grouped[date_str]
      assert calendar_booking["member"]["avatar_url"] != nil

      assert String.starts_with?(
               calendar_booking["member"]["avatar_url"],
               "http"
             )
    end

    test "lookup includes member avatar_url", %{conn: conn} do
      user = user_fixture(last_name: "LookupAvatar")
      _booking = active_booking_fixture(user_id: user.id)

      response =
        get(conn, ~p"/api/v1/mobile/bookings/lookup?last_name=LookupAvatar")

      assert %{"data" => [booking | _]} = json_response(response, 200)
      assert booking["member"]["avatar_url"] != nil
      assert String.starts_with?(booking["member"]["avatar_url"], "http")
    end

    test "avatar_url uses country-based default path when user has most_connected_country",
         %{
           conn: conn
         } do
      user =
        user_fixture(
          email: "norway-user@example.com",
          most_connected_country: "NO"
        )

      booking = booking_fixture(user_id: user.id)

      response = get(conn, index_path_covering(booking))

      assert %{"data" => [booking | _]} = json_response(response, 200)
      avatar_url = booking["member"]["avatar_url"]

      assert avatar_url =~ "norway"
      assert avatar_url =~ "/images/"
    end
  end
end

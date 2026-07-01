defmodule YscWeb.Api.CheckInsControllerTest do
  @moduledoc """
  Tests for the mobile API check-in endpoint.

  Covers successful check-in, input validation, property scope enforcement,
  vehicle handling, and malformed payload protection.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.BookingsFixtures

  @test_token "test-kiosk-secret"

  setup %{conn: conn} do
    prev = Application.get_env(:ysc, :kiosk_api_key)
    Application.put_env(:ysc, :kiosk_api_key, @test_token)

    on_exit(fn ->
      Application.put_env(:ysc, :kiosk_api_key, prev)
    end)

    authed_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{@test_token}")

    {:ok, conn: authed_conn}
  end

  describe "POST /api/v1/mobile/check-in (create)" do
    test "successfully checks in a booking by ULID id", %{conn: conn} do
      booking = active_check_in_booking_fixture()

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"data" => data} = json_response(response, 201)
      assert data["rules_agreed"] == true
      assert is_binary(data["id"])
      assert is_binary(data["checked_in_at"])
      assert to_string(booking.id) in data["booking_ids"]
    end

    test "successfully checks in using reference_id", %{conn: conn} do
      booking = active_check_in_booking_fixture()

      payload = %{
        property: "tahoe",
        booking_ids: [booking.reference_id],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"data" => data} = json_response(response, 201)
      assert to_string(booking.id) in data["booking_ids"]
    end

    test "successfully checks in with vehicles", %{conn: conn} do
      booking = active_check_in_booking_fixture()

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true,
        vehicles: [
          %{type: "sedan", color: "blue", make: "Toyota"}
        ]
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"data" => data} = json_response(response, 201)
      assert [vehicle] = data["vehicles"]
      assert vehicle["type"] == "sedan"
      assert vehicle["color"] == "blue"
      assert vehicle["make"] == "Toyota"
    end

    test "check-in response includes expected fields", %{conn: conn} do
      booking = active_check_in_booking_fixture()

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"data" => data} = json_response(response, 201)
      assert Map.has_key?(data, "id")
      assert Map.has_key?(data, "checked_in_at")
      assert Map.has_key?(data, "rules_agreed")
      assert Map.has_key?(data, "booking_ids")
      assert Map.has_key?(data, "vehicles")
    end
  end

  describe "POST /api/v1/mobile/check-in - property validation" do
    test "returns error when property is missing", %{conn: conn} do
      booking = booking_fixture()

      payload = %{
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "property"
    end

    test "returns error for invalid property value", %{conn: conn} do
      booking = booking_fixture()

      payload = %{
        property: "invalid_place",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "tahoe"
    end

    test "returns error when booking belongs to a different property", %{
      conn: conn
    } do
      booking = booking_fixture(property: :tahoe)

      payload = %{
        property: "clear_lake",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "tahoe"
    end
  end

  describe "POST /api/v1/mobile/check-in - rules_agreed validation" do
    test "returns error when rules_agreed is false", %{conn: conn} do
      booking = booking_fixture()

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: false
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "rules_agreed"
    end

    test "returns error when rules_agreed is missing", %{conn: conn} do
      booking = booking_fixture()

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)]
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "rules_agreed"
    end
  end

  describe "POST /api/v1/mobile/check-in - booking_ids validation" do
    test "returns error when booking_ids is missing", %{conn: conn} do
      payload = %{
        property: "tahoe",
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "booking_ids"
    end

    test "returns error when booking_ids is an empty list", %{conn: conn} do
      payload = %{
        property: "tahoe",
        booking_ids: [],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "booking_ids"
    end

    test "returns error when booking_ids contains invalid types (maps)", %{
      conn: conn
    } do
      payload = %{
        property: "tahoe",
        booking_ids: [%{}],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "booking_id"
    end

    test "returns error for non-existent booking id", %{conn: conn} do
      # Use a valid ULID-format string that doesn't match any booking
      nonexistent_ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

      payload = %{
        property: "tahoe",
        booking_ids: [nonexistent_ulid],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "booking not found"
    end
  end

  describe "POST /api/v1/mobile/check-in - vehicle handling" do
    test "proceeds with empty vehicles list when none provided", %{conn: conn} do
      booking = active_check_in_booking_fixture()

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true,
        vehicles: []
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"data" => data} = json_response(response, 201)
      assert data["vehicles"] == []
    end

    test "ignores invalid vehicle entries (non-maps) gracefully", %{conn: conn} do
      booking = active_check_in_booking_fixture()

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true,
        vehicles: [1, "not-a-map"]
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"data" => data} = json_response(response, 201)
      assert data["vehicles"] == []
    end
  end

  describe "POST /api/v1/mobile/check-in - booking eligibility" do
    test "rejects draft bookings", %{conn: conn} do
      booking = booking_fixture(%{status: :draft})

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "not confirmed"
    end

    test "rejects canceled bookings", %{conn: conn} do
      booking = active_check_in_booking_fixture(%{status: :canceled})

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "not confirmed"
    end

    test "rejects bookings that have not started yet", %{conn: conn} do
      today_pst =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

      booking =
        active_check_in_booking_fixture(%{
          checkin_date: Date.add(today_pst, 3),
          checkout_date: Date.add(today_pst, 5)
        })

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "not yet active"
    end

    test "rejects bookings that have already ended", %{conn: conn} do
      today_pst =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

      booking =
        active_check_in_booking_fixture(%{
          checkin_date: Date.add(today_pst, -5),
          checkout_date: Date.add(today_pst, -1)
        })

      payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      response = post(conn, ~p"/api/v1/mobile/check-in", payload)

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "already ended"
    end

    test "rejects bookings that are already checked in", %{conn: conn} do
      booking = active_check_in_booking_fixture()

      first_payload = %{
        property: "tahoe",
        booking_ids: [to_string(booking.id)],
        rules_agreed: true
      }

      assert %{"data" => _} =
               json_response(
                 post(conn, ~p"/api/v1/mobile/check-in", first_payload),
                 201
               )

      second_response = post(conn, ~p"/api/v1/mobile/check-in", first_payload)

      assert %{"error" => error} = json_response(second_response, 422)
      assert error =~ "already checked in"
    end
  end

  describe "POST /api/v1/mobile/check-in - authentication" do
    test "returns 401 without auth token", %{conn: conn} do
      unauthed_conn = delete_req_header(conn, "authorization")

      payload = %{
        property: "tahoe",
        booking_ids: ["some-id"],
        rules_agreed: true
      }

      response = post(unauthed_conn, ~p"/api/v1/mobile/check-in", payload)

      assert json_response(response, 401)
    end

    test "returns 401 with wrong token", %{conn: conn} do
      bad_conn = put_req_header(conn, "authorization", "Bearer wrong-token")

      payload = %{
        property: "tahoe",
        booking_ids: ["some-id"],
        rules_agreed: true
      }

      response = post(bad_conn, ~p"/api/v1/mobile/check-in", payload)

      assert json_response(response, 401)
    end
  end
end

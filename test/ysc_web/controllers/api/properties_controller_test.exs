defmodule YscWeb.Api.PropertiesControllerTest do
  @moduledoc """
  Tests for the mobile API properties info endpoint.

  Covers static property info, settings overrides, and validation.
  """
  use YscWeb.ConnCase, async: false

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
      |> put_req_header("authorization", "Bearer #{@test_token}")

    {:ok, conn: authed_conn}
  end

  describe "GET /api/v1/mobile/properties/:property/info" do
    test "returns property info for tahoe", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["property"] == "tahoe"
      assert data["name"] == "Lake Tahoe Cabin"
    end

    test "returns property info for clear_lake", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/clear_lake/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["property"] == "clear_lake"
      assert data["name"] == "Clear Lake Cabin"
    end

    test "returns 400 for invalid property", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/invalid/info")

      assert %{"error" => _} = json_response(response, 400)
    end

    test "response includes required fields", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert Map.has_key?(data, "property")
      assert Map.has_key?(data, "name")
      assert Map.has_key?(data, "check_in_time")
      assert Map.has_key?(data, "check_out_time")
      assert Map.has_key?(data, "check_in_instructions")
      assert Map.has_key?(data, "check_out_instructions")
      assert Map.has_key?(data, "notices")
      assert Map.has_key?(data, "rules_categories")
      assert Map.has_key?(data, "rules")
      assert Map.has_key?(data, "additional_settings")
    end

    test "tahoe response includes static check-in and check-out times", %{
      conn: conn
    } do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["check_in_time"] == "3:00 PM"
      assert data["check_out_time"] == "11:00 AM"
    end

    test "tahoe response includes rules categories", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      category_ids = Enum.map(data["rules_categories"], & &1["id"])

      assert "welcome" in category_ids
      assert "trash" in category_ids
      assert "kitchen" in category_ids
      assert "bears" in category_ids
      assert "quiet" in category_ids
      assert "checkout" in category_ids
      assert "emergency" in category_ids
    end

    test "tahoe response includes rules content", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert %{"data" => data} = json_response(response, 200)
      assert is_map(data["rules"])
      assert Map.has_key?(data["rules"], "welcome")
      assert is_list(data["rules"]["welcome"])
    end

    test "clear_lake response has empty rules", %{conn: conn} do
      response = get(conn, ~p"/api/v1/mobile/properties/clear_lake/info")

      assert %{"data" => data} = json_response(response, 200)
      assert data["rules_categories"] == []
      assert data["rules"] == %{}
    end

    test "returns 401 without auth token", %{conn: conn} do
      unauthed_conn = delete_req_header(conn, "authorization")
      response = get(unauthed_conn, ~p"/api/v1/mobile/properties/tahoe/info")

      assert json_response(response, 401)
    end
  end
end

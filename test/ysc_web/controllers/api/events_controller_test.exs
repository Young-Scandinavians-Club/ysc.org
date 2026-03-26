defmodule YscWeb.Api.EventsControllerTest do
  @moduledoc """
  Tests for the mobile API upcoming events list (`EventsController` + `EventsJSON`).
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  @test_token "test-kiosk-secret-events-api"

  setup %{conn: conn} do
    prev = Application.get_env(:ysc, :kiosk_api_key)
    Application.put_env(:ysc, :kiosk_api_key, @test_token)
    Ysc.Settings.clear_cache()

    on_exit(fn ->
      Application.put_env(:ysc, :kiosk_api_key, prev)
    end)

    authed_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{@test_token}")

    {:ok, conn: authed_conn}
  end

  describe "GET /api/v1/mobile/events" do
    test "returns paginated JSON with data and meta", %{conn: conn} do
      organizer = user_fixture()
      _event = event_fixture(%{organizer_id: organizer.id, state: :published})

      response = get(conn, ~p"/api/v1/mobile/events")

      assert %{"data" => data, "meta" => meta} = json_response(response, 200)
      assert is_list(data)
      assert meta["page"] == 1
      assert meta["page_size"] == 20
      assert is_integer(meta["total_count"])
      assert meta["total_count"] >= 1
      assert meta["has_prev_page"] == false

      assert [first | _] = data
      assert Map.has_key?(first, "id")
      assert Map.has_key?(first, "title")
      assert Map.has_key?(first, "pricing_info")
      assert Map.has_key?(first, "ticket_tiers")
      assert Map.has_key?(first, "cover_image")
    end

    test "accepts page and page_size query params", %{conn: conn} do
      organizer = user_fixture()

      for _ <- 1..3 do
        event_fixture(%{organizer_id: organizer.id, state: :published})
      end

      response =
        get(conn, ~p"/api/v1/mobile/events?page=1&page_size=2")

      assert %{"data" => data, "meta" => meta} = json_response(response, 200)
      assert length(data) <= 2
      assert meta["page"] == 1
      assert meta["page_size"] == 2
    end

    test "returns 401 without bearer token", %{conn: conn} do
      conn = Plug.Conn.delete_req_header(conn, "authorization")
      response = get(conn, ~p"/api/v1/mobile/events")
      assert json_response(response, 401)
    end
  end
end

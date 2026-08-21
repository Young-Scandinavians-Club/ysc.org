defmodule YscWeb.Api.AppEventsControllerTest do
  @moduledoc """
  Tests that `GET /api/v1/app/events` (the admin/volunteer mobile app's
  events list, reusing `EventsController`/`EventsJSON`) is gated by a
  per-user mobile bearer token rather than the kiosk shared secret.
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Accounts

  describe "GET /api/v1/app/events" do
    test "returns events for an authenticated admin", %{conn: conn} do
      admin = user_fixture(%{role: :admin})
      token = Accounts.generate_user_mobile_token(admin)

      organizer = user_fixture()
      _event = event_fixture(%{organizer_id: organizer.id, state: :published})

      response =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/app/events")

      assert %{"data" => data} = json_response(response, 200)
      assert is_list(data)
    end

    test "returns 401 for a plain member", %{conn: conn} do
      member = user_fixture(%{role: :member})
      token = Accounts.generate_user_mobile_token(member)

      response =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/app/events")

      assert json_response(response, 401)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/app/events")

      assert json_response(response, 401)
    end
  end
end

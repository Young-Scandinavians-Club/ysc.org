defmodule YscWeb.Api.AppMembersControllerTest do
  @moduledoc """
  Tests for the admin/volunteer mobile app's member search endpoint
  (`AppMembersController` + `AppMembersJSON`).
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  setup %{conn: conn} do
    admin = user_fixture(%{role: :admin})
    token = Accounts.generate_user_mobile_token(admin)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn}
  end

  describe "GET /api/v1/app/members/search" do
    test "finds a member by name", %{conn: conn} do
      unique = System.unique_integer([:positive])

      member =
        user_fixture(%{
          first_name: "Zaphod#{unique}",
          last_name: "Beeblebrox",
          email: unique_user_email()
        })

      response = get(conn, ~p"/api/v1/app/members/search?q=Zaphod#{unique}")

      assert %{"data" => [result]} = json_response(response, 200)
      assert result["id"] == to_string(member.id)
      assert result["first_name"] == member.first_name
      assert result["email"] == member.email
      assert Map.has_key?(result, "has_active_membership")
    end

    test "finds a member by email", %{conn: conn} do
      member = user_fixture()

      response = get(conn, ~p"/api/v1/app/members/search?q=#{member.email}")

      assert %{"data" => data} = json_response(response, 200)
      assert Enum.any?(data, &(&1["id"] == to_string(member.id)))
    end

    test "returns an empty list for no matches", %{conn: conn} do
      response = get(conn, ~p"/api/v1/app/members/search?q=nonexistent-zzz")

      assert %{"data" => []} = json_response(response, 200)
    end

    test "returns 400 when q is missing", %{conn: conn} do
      response = get(conn, ~p"/api/v1/app/members/search")

      assert json_response(response, 400)
    end

    test "returns 400 when q is too short", %{conn: conn} do
      response = get(conn, ~p"/api/v1/app/members/search?q=a")

      assert json_response(response, 400)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> get(~p"/api/v1/app/members/search?q=test")

      assert json_response(response, 401)
    end
  end
end

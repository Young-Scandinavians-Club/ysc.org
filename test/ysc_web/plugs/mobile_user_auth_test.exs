defmodule YscWeb.Plugs.MobileUserAuthTest do
  @moduledoc """
  Tests for the per-user bearer token authentication plug used by the
  admin/volunteer mobile app.
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias YscWeb.Plugs.MobileUserAuth

  describe "call/2 with a valid token" do
    test "assigns current_user for an admin", %{conn: conn} do
      user = user_fixture(%{role: :admin})
      token = Accounts.generate_user_mobile_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> MobileUserAuth.call([])

      refute conn.halted
      assert conn.assigns.current_user.id == user.id
    end

    test "assigns current_user for a volunteer", %{conn: conn} do
      user = user_fixture(%{role: :volunteer})
      token = Accounts.generate_user_mobile_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> MobileUserAuth.call([])

      refute conn.halted
      assert conn.assigns.current_user.id == user.id
    end
  end

  describe "call/2 with a plain member token" do
    test "returns 401 — members cannot use the admin/volunteer app", %{conn: conn} do
      user = user_fixture(%{role: :member})
      token = Accounts.generate_user_mobile_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> MobileUserAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "call/2 with missing or invalid token" do
    test "returns 401 when no Authorization header", %{conn: conn} do
      conn = MobileUserAuth.call(conn, [])

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "Unauthorized"}
    end

    test "returns 401 for non-Bearer schemes", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic sometoken")
        |> MobileUserAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "returns 401 for an unknown token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-a-real-token")
        |> MobileUserAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end
end

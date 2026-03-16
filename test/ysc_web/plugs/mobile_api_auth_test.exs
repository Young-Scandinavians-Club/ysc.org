defmodule YscWeb.Plugs.MobileAPIAuthTest do
  @moduledoc """
  Tests for the static bearer token authentication plug used by the kiosk API.
  """
  use YscWeb.ConnCase, async: false

  alias YscWeb.Plugs.MobileAPIAuth

  @test_token "test-kiosk-secret"

  setup do
    Application.put_env(:ysc, :kiosk_api_key, @test_token)

    on_exit(fn ->
      Application.put_env(:ysc, :kiosk_api_key, "dev-kiosk-key")
    end)

    :ok
  end

  describe "call/2 with valid token" do
    test "allows the request through", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@test_token}")
        |> MobileAPIAuth.call([])

      refute conn.halted
    end
  end

  describe "call/2 with missing token" do
    test "returns 401 when no Authorization header", %{conn: conn} do
      conn = MobileAPIAuth.call(conn, [])

      assert conn.halted
      assert conn.status == 401

      assert Jason.decode!(conn.resp_body) == %{
               "error" => "Missing authorization token"
             }
    end

    test "returns 401 for non-Bearer schemes", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic #{@test_token}")
        |> MobileAPIAuth.call([])

      assert conn.halted
      assert conn.status == 401

      assert Jason.decode!(conn.resp_body) == %{
               "error" => "Missing authorization token"
             }
    end
  end

  describe "call/2 with invalid token" do
    test "returns 401 for wrong token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong-token")
        |> MobileAPIAuth.call([])

      assert conn.halted
      assert conn.status == 401

      assert Jason.decode!(conn.resp_body) == %{
               "error" => "Invalid authorization token"
             }
    end

    test "returns 401 for empty Bearer value", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer ")
        |> MobileAPIAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "call/2 when kiosk API key not configured" do
    test "returns 401 when kiosk_api_key is nil", %{conn: conn} do
      Application.put_env(:ysc, :kiosk_api_key, nil)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@test_token}")
        |> MobileAPIAuth.call([])

      assert conn.halted
      assert conn.status == 401

      assert Jason.decode!(conn.resp_body) == %{
               "error" => "Kiosk API key not configured"
             }
    end

    test "returns 401 when kiosk_api_key is empty string", %{conn: conn} do
      Application.put_env(:ysc, :kiosk_api_key, "")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@test_token}")
        |> MobileAPIAuth.call([])

      assert conn.halted
      assert conn.status == 401

      assert Jason.decode!(conn.resp_body) == %{
               "error" => "Kiosk API key not configured"
             }
    end
  end
end

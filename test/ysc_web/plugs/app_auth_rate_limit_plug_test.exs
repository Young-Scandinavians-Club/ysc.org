defmodule YscWeb.Plugs.AppAuthRateLimitPlugTest do
  @moduledoc """
  IP rate limiting for `/api/v1/app/auth/*`. Reuses `Ysc.AuthRateLimit` but
  must return JSON (not the HTML login 429) so the Expo app can retry.
  """
  use YscWeb.ConnCase, async: false

  alias YscWeb.Plugs.AppAuthRateLimitPlug

  setup do
    token =
      Ysc.Test.AuthRateLimitHelper.capture!(
        ip_limit: 2,
        identifier_limit: 10_000
      )

    on_exit(fn -> Ysc.Test.AuthRateLimitHelper.restore!(token) end)

    :ok
  end

  describe "call/2" do
    test "allows requests under the IP limit" do
      ip = {10, 51, 0, 1}

      conn1 =
        build_conn()
        |> Map.put(:remote_ip, ip)
        |> AppAuthRateLimitPlug.call([])

      refute conn1.halted
      refute conn1.status == 429

      conn2 =
        build_conn()
        |> Map.put(:remote_ip, ip)
        |> AppAuthRateLimitPlug.call([])

      refute conn2.halted
      refute conn2.status == 429
    end

    test "returns JSON 429 with Retry-After when the IP limit is exceeded" do
      ip = {10, 51, 0, 2}

      build_conn() |> Map.put(:remote_ip, ip) |> AppAuthRateLimitPlug.call([])
      build_conn() |> Map.put(:remote_ip, ip) |> AppAuthRateLimitPlug.call([])

      conn =
        build_conn()
        |> Map.put(:remote_ip, ip)
        |> AppAuthRateLimitPlug.call([])

      assert conn.halted
      assert conn.status == 429
      [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) > 0
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/json"
      assert Jason.decode!(conn.resp_body) == %{"error" => "Too many requests"}
    end

    test "limits different IPs independently" do
      ip_a = {10, 51, 0, 3}
      ip_b = {10, 51, 0, 4}

      build_conn() |> Map.put(:remote_ip, ip_a) |> AppAuthRateLimitPlug.call([])
      build_conn() |> Map.put(:remote_ip, ip_a) |> AppAuthRateLimitPlug.call([])

      conn_other =
        build_conn()
        |> Map.put(:remote_ip, ip_b)
        |> AppAuthRateLimitPlug.call([])

      refute conn_other.halted
      refute conn_other.status == 429
    end
  end

  describe "POST /api/v1/app/auth/password" do
    test "returns JSON 429 once the shared auth IP limit is exceeded" do
      ip = {10, 51, 0, 5}

      params = %{
        "email" => "rate-limit-#{System.unique_integer([:positive])}@ysc.org",
        "password" => "not-the-password"
      }

      first =
        build_conn()
        |> Map.put(:remote_ip, ip)
        |> post(~p"/api/v1/app/auth/password", params)

      second =
        build_conn()
        |> Map.put(:remote_ip, ip)
        |> post(~p"/api/v1/app/auth/password", params)

      # Under the limit the controller still runs (401 for bad credentials).
      assert json_response(first, 401)
      assert json_response(second, 401)

      limited =
        build_conn()
        |> Map.put(:remote_ip, ip)
        |> post(~p"/api/v1/app/auth/password", params)

      assert json_response(limited, 429) == %{"error" => "Too many requests"}
      [retry_after] = get_resp_header(limited, "retry-after")
      assert String.to_integer(retry_after) > 0
    end
  end
end

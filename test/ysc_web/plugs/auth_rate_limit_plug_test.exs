defmodule YscWeb.Plugs.AuthRateLimitPlugTest do
  @moduledoc """
  Tests for IP-based auth rate limit plug. The same Ysc.AuthRateLimit.check_ip/1
  is used in LiveViews (e.g. UserResetPasswordLive, UserForgotPasswordLive) for
  WebSocket submissions; the plug covers HTTP auth endpoints (login, OAuth, etc.).
  """
  use YscWeb.ConnCase, async: false

  alias YscWeb.Plugs.AuthRateLimitPlug

  setup do
    Application.put_env(:ysc, Ysc.AuthRateLimit,
      ip_limit: 2,
      identifier_limit: 10_000
    )

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.AuthRateLimit,
        ip_limit: 10_000,
        identifier_limit: 10_000
      )
    end)

    :ok
  end

  describe "call/2" do
    test "allows requests under the IP limit" do
      ip = {127, 0, 0, 97}

      conn1 =
        build_conn() |> Map.put(:remote_ip, ip) |> AuthRateLimitPlug.call([])

      refute conn1.halted
      refute conn1.status == 429

      conn2 =
        build_conn() |> Map.put(:remote_ip, ip) |> AuthRateLimitPlug.call([])

      refute conn2.halted
      refute conn2.status == 429
    end

    test "returns 429 with Retry-After when IP limit exceeded" do
      ip = {127, 0, 0, 98}
      build_conn() |> Map.put(:remote_ip, ip) |> AuthRateLimitPlug.call([])
      build_conn() |> Map.put(:remote_ip, ip) |> AuthRateLimitPlug.call([])

      conn =
        build_conn() |> Map.put(:remote_ip, ip) |> AuthRateLimitPlug.call([])

      assert conn.halted
      assert conn.status == 429
      [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) > 0
      assert conn.resp_body =~ "Too many attempts"
      assert conn.resp_body =~ retry_after
    end

    test "different IPs are limited independently" do
      ip_a = {127, 0, 0, 96}
      ip_b = {127, 0, 0, 95}
      build_conn() |> Map.put(:remote_ip, ip_a) |> AuthRateLimitPlug.call([])
      build_conn() |> Map.put(:remote_ip, ip_a) |> AuthRateLimitPlug.call([])

      conn_other =
        build_conn() |> Map.put(:remote_ip, ip_b) |> AuthRateLimitPlug.call([])

      refute conn_other.halted
      refute conn_other.status == 429
    end
  end
end

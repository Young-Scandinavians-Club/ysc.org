defmodule YscWeb.Plugs.FlowrouteWebhookRateLimitPlugTest do
  use YscWeb.ConnCase, async: false

  alias YscWeb.Plugs.FlowrouteWebhookRateLimitPlug

  setup do
    Application.put_env(:ysc, Ysc.FlowrouteWebhookRateLimit, ip_limit: 2)

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.FlowrouteWebhookRateLimit, ip_limit: 60)
    end)

    :ok
  end

  describe "call/2" do
    test "allows requests under the IP limit" do
      ip = {127, 0, 0, 201}

      conn1 =
        build_conn() |> Map.put(:remote_ip, ip) |> FlowrouteWebhookRateLimitPlug.call([])

      refute conn1.halted
      refute conn1.status == 429

      conn2 =
        build_conn() |> Map.put(:remote_ip, ip) |> FlowrouteWebhookRateLimitPlug.call([])

      refute conn2.halted
      refute conn2.status == 429
    end

    test "returns 429 with Retry-After when IP limit exceeded" do
      ip = {127, 0, 0, 202}
      build_conn() |> Map.put(:remote_ip, ip) |> FlowrouteWebhookRateLimitPlug.call([])
      build_conn() |> Map.put(:remote_ip, ip) |> FlowrouteWebhookRateLimitPlug.call([])

      conn =
        build_conn() |> Map.put(:remote_ip, ip) |> FlowrouteWebhookRateLimitPlug.call([])

      assert conn.halted
      assert conn.status == 429
      [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) > 0
      assert conn.resp_body == "Too many requests"
    end

    test "different IPs are limited independently" do
      ip_a = {127, 0, 0, 203}
      ip_b = {127, 0, 0, 204}
      build_conn() |> Map.put(:remote_ip, ip_a) |> FlowrouteWebhookRateLimitPlug.call([])
      build_conn() |> Map.put(:remote_ip, ip_a) |> FlowrouteWebhookRateLimitPlug.call([])

      conn_other =
        build_conn() |> Map.put(:remote_ip, ip_b) |> FlowrouteWebhookRateLimitPlug.call([])

      refute conn_other.halted
      refute conn_other.status == 429
    end
  end
end

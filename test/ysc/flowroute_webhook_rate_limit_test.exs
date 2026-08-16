defmodule Ysc.FlowrouteWebhookRateLimitTest do
  use ExUnit.Case, async: false

  alias Ysc.FlowrouteWebhookRateLimit

  setup do
    Application.put_env(:ysc, Ysc.FlowrouteWebhookRateLimit, ip_limit: 2)

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.FlowrouteWebhookRateLimit, ip_limit: 60)
    end)

    :ok
  end

  describe "check_ip/1" do
    test "allows requests under the limit" do
      ip = "192.168.200.1"

      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip)
      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip)
    end

    test "denies requests over the limit" do
      ip = "192.168.200.2"

      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip)
      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip)

      assert {:error, :rate_limited, retry_after} =
               FlowrouteWebhookRateLimit.check_ip(ip)

      assert retry_after > 0
    end

    test "accepts IP as tuple" do
      ip_tuple = {192, 168, 200, 3}

      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip_tuple)
      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip_tuple)

      assert {:error, :rate_limited, _} =
               FlowrouteWebhookRateLimit.check_ip(ip_tuple)
    end

    test "isolates limits per IP" do
      ip1 = "192.168.200.4"
      ip2 = "192.168.200.5"

      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip1)
      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip1)
      assert {:error, :rate_limited, _} = FlowrouteWebhookRateLimit.check_ip(ip1)

      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip2)
      assert :ok = FlowrouteWebhookRateLimit.check_ip(ip2)
    end

    test "trims whitespace from IP strings" do
      assert :ok = FlowrouteWebhookRateLimit.check_ip("192.168.200.6")
      assert :ok = FlowrouteWebhookRateLimit.check_ip(" 192.168.200.6 ")
      assert {:error, :rate_limited, _} = FlowrouteWebhookRateLimit.check_ip("192.168.200.6")
    end
  end
end

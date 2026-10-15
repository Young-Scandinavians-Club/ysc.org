defmodule Ysc.PrintfulWebhookRateLimitTest do
  use ExUnit.Case, async: false

  alias Ysc.PrintfulWebhookRateLimit

  setup do
    Application.put_env(:ysc, Ysc.PrintfulWebhookRateLimit, ip_limit: 2)

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.PrintfulWebhookRateLimit, ip_limit: 60)
    end)

    :ok
  end

  test "allows requests under the limit and blocks the rest" do
    ip = "192.168.210.1"
    assert :ok = PrintfulWebhookRateLimit.check_ip(ip)
    assert :ok = PrintfulWebhookRateLimit.check_ip(ip)

    assert {:error, :rate_limited, retry_after} =
             PrintfulWebhookRateLimit.check_ip(ip)

    assert retry_after > 0
  end

  test "limits each IP separately and accepts tuples" do
    assert :ok = PrintfulWebhookRateLimit.check_ip({192, 168, 210, 2})
    assert :ok = PrintfulWebhookRateLimit.check_ip({192, 168, 210, 3})
  end
end

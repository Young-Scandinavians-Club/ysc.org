defmodule Ysc.HealthCheckRateLimitTest do
  use ExUnit.Case, async: false

  alias Ysc.HealthCheckRateLimit

  setup do
    Application.put_env(:ysc, Ysc.HealthCheckRateLimit, ip_limit: 2)

    on_exit(fn ->
      Application.delete_env(:ysc, Ysc.HealthCheckRateLimit)
    end)

    :ok
  end

  test "allows requests under the limit and blocks the rest" do
    ip = "192.168.211.1"
    assert :ok = HealthCheckRateLimit.check_ip(ip)
    assert :ok = HealthCheckRateLimit.check_ip(ip)

    assert {:error, :rate_limited, retry_after} =
             HealthCheckRateLimit.check_ip(ip)

    assert retry_after > 0
  end
end

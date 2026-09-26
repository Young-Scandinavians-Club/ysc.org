defmodule Ysc.RegistrationRateLimitTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ysc.RegistrationRateLimit

  # Unique IP per test so the shared ETS buckets don't collide.
  defp unique_test_ip do
    n = System.unique_integer([:positive])
    {10, rem(div(n, 256 * 256), 254) + 1, rem(div(n, 256), 256), rem(n, 256)}
  end

  defp exhaust!(ip) do
    for _ <- 1..RegistrationRateLimit.ip_limit() do
      assert :ok = RegistrationRateLimit.check_ip(ip)
    end
  end

  describe "ip_limit/0" do
    test "reads the configured limit" do
      # config/test.exs raises it so LiveView tests from 127.0.0.1 aren't limited.
      assert RegistrationRateLimit.ip_limit() == 10_000
    end
  end

  describe "check_ip/1" do
    test "allows submits up to the limit, then rate limits" do
      ip = unique_test_ip()
      exhaust!(ip)

      assert {:error, :rate_limited, retry_after_seconds} =
               RegistrationRateLimit.check_ip(ip)

      assert retry_after_seconds > 0
    end

    test "limits each IP separately" do
      ip = unique_test_ip()
      exhaust!(ip)

      assert {:error, :rate_limited, _} = RegistrationRateLimit.check_ip(ip)
      assert :ok = RegistrationRateLimit.check_ip(unique_test_ip())
    end

    test "accepts string IPs" do
      assert :ok =
               RegistrationRateLimit.check_ip("10.200.1.#{:rand.uniform(250)}")
    end

    test "logs a warning with the IP when over the limit" do
      ip = unique_test_ip()
      exhaust!(ip)

      log =
        capture_log(
          [format: "$message $metadata", metadata: [:ip, :limit]],
          fn -> RegistrationRateLimit.check_ip(ip) end
        )

      assert log =~ "Membership application rate limit exceeded by IP"
      assert log =~ "ip=#{:inet.ntoa(ip)}"
    end
  end
end

defmodule Ysc.AuthRateLimitTest do
  use ExUnit.Case, async: false

  alias Ysc.AuthRateLimit

  # Use low limits so we can hit them in tests. Each test uses unique IP/email to avoid cross-test pollution.
  setup do
    Application.put_env(:ysc, Ysc.AuthRateLimit,
      ip_limit: 2,
      identifier_limit: 2
    )

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.AuthRateLimit,
        ip_limit: 10_000,
        identifier_limit: 10_000
      )
    end)

    :ok
  end

  defp unique_test_ip do
    "127.0.#{rem(System.unique_integer([:positive]), 254) + 1}.#{rem(System.unique_integer([:positive]), 254) + 1}"
  end

  describe "check_ip/1" do
    test "allows requests under the limit" do
      ip = unique_test_ip()
      assert :ok = AuthRateLimit.check_ip(ip)
      assert :ok = AuthRateLimit.check_ip(ip)
    end

    test "returns rate_limited after exceeding limit" do
      ip = unique_test_ip()
      assert :ok = AuthRateLimit.check_ip(ip)
      assert :ok = AuthRateLimit.check_ip(ip)

      assert {:error, :rate_limited, retry_after_sec} =
               AuthRateLimit.check_ip(ip)

      assert is_integer(retry_after_sec)
      assert retry_after_sec > 0
    end

    test "accepts tuple IP (e.g. from conn.remote_ip)" do
      [_, b, c, _] =
        String.split(unique_test_ip(), ".") |> Enum.map(&String.to_integer/1)

      ip = {127, 0, b, c}
      assert :ok = AuthRateLimit.check_ip(ip)
      assert :ok = AuthRateLimit.check_ip(ip)
      assert {:error, :rate_limited, _} = AuthRateLimit.check_ip(ip)
    end

    test "different IPs have separate limits" do
      ip_a = unique_test_ip()
      ip_b = unique_test_ip()

      assert :ok = AuthRateLimit.check_ip(ip_a)
      assert :ok = AuthRateLimit.check_ip(ip_a)
      assert {:error, :rate_limited, _} = AuthRateLimit.check_ip(ip_a)

      # Different IP still has full limit
      assert :ok = AuthRateLimit.check_ip(ip_b)
      assert :ok = AuthRateLimit.check_ip(ip_b)
      assert {:error, :rate_limited, _} = AuthRateLimit.check_ip(ip_b)
    end
  end

  describe "check_identifier/1" do
    test "allows requests under the limit" do
      email = "under_limit_#{System.unique_integer([:positive])}@example.com"
      assert :ok = AuthRateLimit.check_identifier(email)
      assert :ok = AuthRateLimit.check_identifier(email)
    end

    test "returns rate_limited after exceeding limit" do
      email = "over_limit_#{System.unique_integer([:positive])}@example.com"
      assert :ok = AuthRateLimit.check_identifier(email)
      assert :ok = AuthRateLimit.check_identifier(email)

      assert {:error, :rate_limited, retry_after_sec} =
               AuthRateLimit.check_identifier(email)

      assert is_integer(retry_after_sec)
      assert retry_after_sec > 0
    end

    test "normalizes identifier (same bucket for different case)" do
      email = "SameEmail_#{System.unique_integer([:positive])}@Example.COM"
      assert :ok = AuthRateLimit.check_identifier(String.downcase(email))
      assert :ok = AuthRateLimit.check_identifier(String.upcase(email))

      # Third attempt (either form) is rate limited because they share the same normalized key
      assert {:error, :rate_limited, _} = AuthRateLimit.check_identifier(email)
    end

    test "different identifiers have separate limits" do
      e1 = "id_a_#{System.unique_integer([:positive])}@example.com"
      e2 = "id_b_#{System.unique_integer([:positive])}@example.com"
      assert :ok = AuthRateLimit.check_identifier(e1)
      assert :ok = AuthRateLimit.check_identifier(e1)
      assert {:error, :rate_limited, _} = AuthRateLimit.check_identifier(e1)

      assert :ok = AuthRateLimit.check_identifier(e2)
      assert :ok = AuthRateLimit.check_identifier(e2)
      assert {:error, :rate_limited, _} = AuthRateLimit.check_identifier(e2)
    end

    test "returns :ok for nil identifier" do
      assert :ok = AuthRateLimit.check_identifier(nil)
    end
  end
end

defmodule Ysc.RateLimitTest do
  use ExUnit.Case, async: false

  alias Ysc.AuthRateLimit
  alias Ysc.RateLimit

  describe "normalize_ip/1" do
    test "trims and downcases string IPs" do
      assert RateLimit.normalize_ip(" 127.0.0.1 ") == "127.0.0.1"
      assert RateLimit.normalize_ip("::FFFF:192.0.2.1") == "::ffff:192.0.2.1"
    end

    test "converts IPv4 tuples via inet.ntoa" do
      assert RateLimit.normalize_ip({127, 0, 0, 1}) == "127.0.0.1"
    end
  end

  describe "normalize_identifier/1" do
    test "trims and downcases emails and usernames" do
      assert RateLimit.normalize_identifier("  User@Example.COM ") ==
               "user@example.com"
    end
  end

  describe "check/4" do
    test "returns :ok under the limit and rate_limited after" do
      key = "rate_limit_test:check:#{System.unique_integer([:positive])}"

      assert :ok = RateLimit.check(&AuthRateLimit.hit/3, key, 60_000, 2)
      assert :ok = RateLimit.check(&AuthRateLimit.hit/3, key, 60_000, 2)

      assert {:error, :rate_limited, retry_after} =
               RateLimit.check(&AuthRateLimit.hit/3, key, 60_000, 2)

      assert is_integer(retry_after)
      assert retry_after >= 1
    end
  end

  describe "check_ok/4" do
    test "returns :rate_limited without a retry-after" do
      key = "rate_limit_test:check_ok:#{System.unique_integer([:positive])}"

      assert :ok = RateLimit.check_ok(&AuthRateLimit.hit/3, key, 60_000, 1)

      assert :rate_limited =
               RateLimit.check_ok(&AuthRateLimit.hit/3, key, 60_000, 1)
    end
  end

  describe "check_ip/5" do
    test "buckets tuple and string forms of the same IP together" do
      prefix = "rate_limit_test:ip:#{System.unique_integer([:positive])}:"
      ip_tuple = {10, 66, 0, 9}

      assert :ok =
               RateLimit.check_ip(
                 &AuthRateLimit.hit/3,
                 prefix,
                 ip_tuple,
                 60_000,
                 2
               )

      assert :ok =
               RateLimit.check_ip(
                 &AuthRateLimit.hit/3,
                 prefix,
                 " 10.66.0.9 ",
                 60_000,
                 2
               )

      assert {:error, :rate_limited, _} =
               RateLimit.check_ip(
                 &AuthRateLimit.hit/3,
                 prefix,
                 ip_tuple,
                 60_000,
                 2
               )
    end

    test "buckets mixed-case IPv6 strings together" do
      prefix = "rate_limit_test:ipv6:#{System.unique_integer([:positive])}:"

      assert :ok =
               RateLimit.check_ip(
                 &AuthRateLimit.hit/3,
                 prefix,
                 "  ::FFFF:192.0.2.1 ",
                 60_000,
                 1
               )

      assert {:error, :rate_limited, _} =
               RateLimit.check_ip(
                 &AuthRateLimit.hit/3,
                 prefix,
                 "::ffff:192.0.2.1",
                 60_000,
                 1
               )
    end
  end
end

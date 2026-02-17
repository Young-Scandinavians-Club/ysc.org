defmodule Ysc.NewsletterRateLimitTest do
  use ExUnit.Case, async: false

  alias Ysc.NewsletterRateLimit

  # Each test uses unique IPs and emails to avoid cross-test pollution
  # since rate limits persist for the duration of their time windows

  describe "check_ip/1" do
    test "allows requests under the limit" do
      ip = "192.168.100.1"

      # First 3 requests should succeed (limit is 3 per minute)
      assert :ok = NewsletterRateLimit.check_ip(ip)
      assert :ok = NewsletterRateLimit.check_ip(ip)
      assert :ok = NewsletterRateLimit.check_ip(ip)
    end

    test "denies requests over the limit" do
      ip = "192.168.100.2"

      # First 3 succeed
      assert :ok = NewsletterRateLimit.check_ip(ip)
      assert :ok = NewsletterRateLimit.check_ip(ip)
      assert :ok = NewsletterRateLimit.check_ip(ip)

      # 4th should be denied
      assert {:error, :rate_limited, retry_after} =
               NewsletterRateLimit.check_ip(ip)

      assert retry_after > 0
    end

    test "accepts IP as tuple" do
      ip_tuple = {192, 168, 100, 3}

      assert :ok = NewsletterRateLimit.check_ip(ip_tuple)
      assert :ok = NewsletterRateLimit.check_ip(ip_tuple)
      assert :ok = NewsletterRateLimit.check_ip(ip_tuple)

      # 4th should be denied
      assert {:error, :rate_limited, _} = NewsletterRateLimit.check_ip(ip_tuple)
    end

    test "isolates limits per IP" do
      ip1 = "192.168.100.4"
      ip2 = "192.168.100.5"

      # Use up ip1's limit
      assert :ok = NewsletterRateLimit.check_ip(ip1)
      assert :ok = NewsletterRateLimit.check_ip(ip1)
      assert :ok = NewsletterRateLimit.check_ip(ip1)
      assert {:error, :rate_limited, _} = NewsletterRateLimit.check_ip(ip1)

      # ip2 should still have full quota
      assert :ok = NewsletterRateLimit.check_ip(ip2)
      assert :ok = NewsletterRateLimit.check_ip(ip2)
      assert :ok = NewsletterRateLimit.check_ip(ip2)
    end

    test "normalizes IP addresses" do
      # These should be treated as the same IP
      assert :ok = NewsletterRateLimit.check_ip("192.168.100.6")
      assert :ok = NewsletterRateLimit.check_ip(" 192.168.100.6 ")
      assert :ok = NewsletterRateLimit.check_ip("192.168.100.6")

      # 4th should be denied (normalized to same IP)
      assert {:error, :rate_limited, _} =
               NewsletterRateLimit.check_ip("192.168.100.6")
    end
  end

  describe "check_email/1" do
    test "allows first request" do
      email = "user1@newsletter-test.com"
      assert :ok = NewsletterRateLimit.check_email(email)
    end

    test "denies second request within time window" do
      email = "user2@newsletter-test.com"

      # First request succeeds
      assert :ok = NewsletterRateLimit.check_email(email)

      # Second request within an hour should be denied
      assert {:error, :rate_limited, retry_after} =
               NewsletterRateLimit.check_email(email)

      assert retry_after > 0
    end

    test "normalizes email addresses" do
      # First with mixed case
      assert :ok = NewsletterRateLimit.check_email("User3@Newsletter-Test.com")

      # Second request with different casing/spacing should be denied
      assert {:error, :rate_limited, _} =
               NewsletterRateLimit.check_email(" user3@newsletter-test.com ")
    end

    test "isolates limits per email" do
      email1 = "user4@newsletter-test.com"
      email2 = "user5@newsletter-test.com"

      # Use up email1's limit
      assert :ok = NewsletterRateLimit.check_email(email1)

      assert {:error, :rate_limited, _} =
               NewsletterRateLimit.check_email(email1)

      # email2 should still have quota
      assert :ok = NewsletterRateLimit.check_email(email2)
    end

    test "returns :ok for non-string input" do
      assert :ok = NewsletterRateLimit.check_email(nil)
      assert :ok = NewsletterRateLimit.check_email(123)
    end
  end

  describe "check/2" do
    test "succeeds when both IP and email pass" do
      ip = "192.168.101.1"
      email = "success@newsletter-test.com"

      assert :ok = NewsletterRateLimit.check(ip, email)
    end

    test "fails when IP limit is exceeded" do
      ip = "192.168.101.2"
      email1 = "email1@newsletter-test.com"
      email2 = "email2@newsletter-test.com"
      email3 = "email3@newsletter-test.com"
      email4 = "email4@newsletter-test.com"

      # Use up IP limit with different emails
      assert :ok = NewsletterRateLimit.check(ip, email1)
      assert :ok = NewsletterRateLimit.check(ip, email2)
      assert :ok = NewsletterRateLimit.check(ip, email3)

      # 4th request from same IP should fail even with different email
      assert {:error, :rate_limited, _} = NewsletterRateLimit.check(ip, email4)
    end

    test "fails when email limit is exceeded" do
      ip1 = "192.168.101.3"
      ip2 = "192.168.101.4"
      email = "repeat@newsletter-test.com"

      # First request succeeds
      assert :ok = NewsletterRateLimit.check(ip1, email)

      # Second request from different IP but same email should fail
      assert {:error, :rate_limited, _} = NewsletterRateLimit.check(ip2, email)
    end

    test "properly chains both checks" do
      ip = "192.168.101.5"
      email = "chain@newsletter-test.com"

      # First request - both checks pass
      assert :ok = NewsletterRateLimit.check(ip, email)

      # Email limit exceeded (first to fail)
      assert {:error, :rate_limited, _} = NewsletterRateLimit.check(ip, email)

      # Even from different IP, email limit still applies
      assert {:error, :rate_limited, _} =
               NewsletterRateLimit.check("192.168.101.6", email)
    end
  end

  describe "retry_after calculation" do
    test "returns positive integer for retry time" do
      ip = "192.168.102.1"

      # Exhaust the limit
      NewsletterRateLimit.check_ip(ip)
      NewsletterRateLimit.check_ip(ip)
      NewsletterRateLimit.check_ip(ip)

      assert {:error, :rate_limited, retry_after} =
               NewsletterRateLimit.check_ip(ip)

      assert is_integer(retry_after)
      assert retry_after > 0
      # Should be close to 60 seconds (1 minute window)
      assert retry_after <= 60
    end
  end
end

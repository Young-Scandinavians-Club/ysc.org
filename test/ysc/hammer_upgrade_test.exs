defmodule Ysc.HammerUpgradeTest do
  @moduledoc """
  Guards the hammer 7.4.0 → 7.4.1 upgrade.

  7.4.1 is a patch: TokenBucket ETS refill uses millisecond resolution so
  `refill_rate > capacity` is not capped at `capacity` tokens/sec. We use
  `use Hammer, backend: :ets` with the default `:fix_window` algorithm and
  `hit/3` (scale + limit). No Elixir API breaks for our call sites.
  """
  use ExUnit.Case, async: false

  alias Ysc.AdminHelpRateLimit
  alias Ysc.AuthRateLimit
  alias Ysc.EmailVerificationRateLimit
  alias Ysc.FlowrouteWebhookRateLimit
  alias Ysc.MobileAPIRateLimit
  alias Ysc.NewsletterRateLimit
  alias Ysc.ScanRateLimit

  @rate_limiters [
    AuthRateLimit,
    NewsletterRateLimit,
    ScanRateLimit,
    EmailVerificationRateLimit,
    MobileAPIRateLimit,
    FlowrouteWebhookRateLimit,
    AdminHelpRateLimit
  ]

  describe "7.4.1 Hex lock and public APIs" do
    test "locks the Hex package to 7.4.1" do
      assert to_string(Application.spec(:hammer, :vsn)) == "7.4.1"
    end

    test "rate limiters still export fix_window hit/set/get/expires_at" do
      Enum.each(@rate_limiters, fn module ->
        assert function_exported?(module, :hit, 3)
        assert function_exported?(module, :hit, 4)
        assert function_exported?(module, :set, 3)
        assert function_exported?(module, :get, 2)
        # expires_at/2 is compiled only for :fix_window / :fix_window_per_key,
        # not TokenBucket — the algorithm 7.4.1 patched.
        assert function_exported?(module, :expires_at, 2)
      end)
    end
  end

  describe "7.4.1 hit/3 still returns allow and deny" do
    test "allows under the limit and denies with a millisecond retry" do
      key = "hammer-upgrade:#{System.unique_integer([:positive])}"
      scale_ms = :timer.minutes(1)
      limit = 2

      assert {:allow, 1} = AuthRateLimit.hit(key, scale_ms, limit)
      assert {:allow, 2} = AuthRateLimit.hit(key, scale_ms, limit)
      assert {:deny, retry_after_ms} = AuthRateLimit.hit(key, scale_ms, limit)
      assert is_integer(retry_after_ms)
      assert retry_after_ms > 0
    end

    test "check_ip still maps deny to {:error, :rate_limited, seconds}" do
      ip = "203.0.113.#{rem(System.unique_integer([:positive]), 254) + 1}"

      prev = Application.get_env(:ysc, AuthRateLimit, [])

      Application.put_env(:ysc, AuthRateLimit,
        ip_limit: 1,
        identifier_limit: Keyword.get(prev, :identifier_limit, 10_000)
      )

      on_exit(fn -> Application.put_env(:ysc, AuthRateLimit, prev) end)

      assert :ok = AuthRateLimit.check_ip(ip)

      assert {:error, :rate_limited, retry_after_sec} =
               AuthRateLimit.check_ip(ip)

      assert is_integer(retry_after_sec)
      assert retry_after_sec >= 1
    end
  end
end

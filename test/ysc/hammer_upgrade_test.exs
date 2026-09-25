defmodule Ysc.HammerUpgradeTest do
  @moduledoc """
  Guards the hammer 7.4.1 → 7.5.0 upgrade.

  7.5.0 is a minor: Atomic TokenBucket/LeakyBucket initialize the atomic
  before publishing the ETS row; TokenBucket ETS carries the sub-token
  remainder and returns a real wait on `{:deny, ms}` instead of a flat
  1000. `mix hammer.install` is an optional Igniter task.

  We use `use Hammer, backend: :ets` with the default `:fix_window`
  algorithm and `hit/3` (scale + limit). No Elixir API breaks for our
  call sites. TokenBucket deny rounding does not apply: `RateLimit.check/4`
  still maps `{:deny, retry_after_ms}` to seconds with `max(1, div/2)`.
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

  @token_bucket Path.expand(
                  "../../deps/hammer/lib/hammer/ets/token_bucket.ex",
                  __DIR__
                )
  @atomic_token_bucket Path.expand(
                         "../../deps/hammer/lib/hammer/atomic/token_bucket.ex",
                         __DIR__
                       )
  @install_task Path.expand(
                  "../../deps/hammer/lib/mix/tasks/hammer.install.ex",
                  __DIR__
                )

  describe "7.5.0 Hex lock and public APIs" do
    test "locks the Hex package to 7.5.0" do
      assert to_string(Application.spec(:hammer, :vsn)) == "7.5.0"
    end

    test "rate limiters still export fix_window hit/set/get/expires_at" do
      Enum.each(@rate_limiters, fn module ->
        assert {:module, _} = Code.ensure_loaded(module)
        assert function_exported?(module, :hit, 3)
        assert function_exported?(module, :hit, 4)
        assert function_exported?(module, :set, 3)
        assert function_exported?(module, :get, 2)
        # expires_at/2 is compiled only for :fix_window / :fix_window_per_key,
        # not TokenBucket — the algorithm 7.5.0 patched.
        assert function_exported?(module, :expires_at, 2)
        refute function_exported?(module, :hit, 5)
      end)
    end
  end

  describe "7.5.0 TokenBucket patches stay unused" do
    test "ETS TokenBucket deny uses ceiling wait instead of a flat 1000" do
      source = File.read!(@token_bucket)

      assert source =~
               "{:deny, max(div(deficit * 1000 + refill_rate - 1, refill_rate), 1)}"

      refute source =~ ~r/{:deny,\s*1000}/
    end

    test "Atomic TokenBucket initializes the atomic before the ETS insert" do
      source = File.read!(@atomic_token_bucket)

      assert source =~ "atomic = :atomics.new(2, signed: false)"
      assert source =~ ":ets.insert_new(table, {key, atomic})"

      refute source =~
               ~r/:ets\.insert_new\(table, \{key, atomic\}\).*atomic = :atomics\.new/s
    end

    test "optional mix hammer.install task ships with the package" do
      assert File.exists?(@install_task)
      source = File.read!(@install_task)
      assert source =~ "defmodule Mix.Tasks.Hammer.Install"
      assert source =~ "igniter"
    end
  end

  describe "7.5.0 hit/3 still returns allow and deny" do
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

      token =
        Ysc.Test.AuthRateLimitHelper.capture!(
          ip_limit: 1,
          identifier_limit: Keyword.get(prev, :identifier_limit, 10_000)
        )

      on_exit(fn -> Ysc.Test.AuthRateLimitHelper.restore!(token) end)

      assert :ok = AuthRateLimit.check_ip(ip)

      assert {:error, :rate_limited, retry_after_sec} =
               AuthRateLimit.check_ip(ip)

      assert is_integer(retry_after_sec)
      assert retry_after_sec >= 1
    end
  end
end

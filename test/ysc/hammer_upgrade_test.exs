defmodule Ysc.HammerUpgradeTest do
  @moduledoc """
  Guards the hammer 7.5.0 → 7.5.1 upgrade.

  7.5.1 is a patch for the SlidingWindow ETS backend only: denied hits
  no longer stay in the window (a client that keeps hitting after deny
  no longer extends its own block); concurrent hits in the same
  microsecond each get a unique ETS entry; empty-window deny returns
  `{:deny, 1}` instead of raising `Enum.EmptyError`.

  We use `use Hammer, backend: :ets` with the default `:fix_window`
  algorithm and `hit/3` (scale + limit). No Elixir API breaks for our
  call sites. SlidingWindow and TokenBucket patches do not apply:
  `RateLimit.check/4` still maps `{:deny, retry_after_ms}` to seconds
  with `max(1, div/2)`.
  """
  use ExUnit.Case, async: false

  alias Hammer.ETS.SlidingWindow
  alias Ysc.AdminHelpRateLimit
  alias Ysc.AuthRateLimit
  alias Ysc.EmailVerificationRateLimit
  alias Ysc.FlowrouteWebhookRateLimit
  alias Ysc.MobileAPIRateLimit
  alias Ysc.NewsletterRateLimit
  alias Ysc.PrintfulWebhookRateLimit
  alias Ysc.RegistrationRateLimit
  alias Ysc.ScanRateLimit

  @rate_limiters [
    AuthRateLimit,
    NewsletterRateLimit,
    ScanRateLimit,
    EmailVerificationRateLimit,
    MobileAPIRateLimit,
    FlowrouteWebhookRateLimit,
    AdminHelpRateLimit,
    PrintfulWebhookRateLimit,
    RegistrationRateLimit
  ]

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/hammer/CHANGELOG.md", __DIR__)
  @sliding_window Path.expand(
                    "../../deps/hammer/lib/hammer/ets/sliding_window.ex",
                    __DIR__
                  )
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
  @lib_root Path.expand("../../lib", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:hammer)
    {:module, Hammer} = Code.ensure_loaded(Hammer)
    {:module, Hammer.ETS} = Code.ensure_loaded(Hammer.ETS)
    {:module, SlidingWindow} = Code.ensure_loaded(SlidingWindow)
    :ok
  end

  describe "7.5.1 Hex lock and public APIs" do
    test "locks the Hex package to 7.5.1" do
      {:module, _} = Code.ensure_loaded(Hammer)
      assert to_string(Application.spec(:hammer, :vsn)) == "7.5.1"
    end

    test "mix.exs pins the 7.5.1 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:hammer, "~> 7.5.1"}|
    end

    test "companion lock is 7.5.1 and phoenix_template stays 1.0.4" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"hammer": {:hex, :hammer, "7.5.1"|
      refute lock =~ ~s|"hammer": {:hex, :hammer, "7.5.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
    end

    test "rate limiters still export fix_window hit/set/get/expires_at" do
      Enum.each(@rate_limiters, fn module ->
        assert {:module, _} = Code.ensure_loaded(module)
        assert function_exported?(module, :hit, 3)
        assert function_exported?(module, :hit, 4)
        assert function_exported?(module, :set, 3)
        assert function_exported?(module, :get, 2)
        # expires_at/2 is compiled only for :fix_window / :fix_window_per_key,
        # not SlidingWindow — the algorithm 7.5.1 patched.
        assert function_exported?(module, :expires_at, 2)
        refute function_exported?(module, :hit, 5)
      end)
    end

    test "app rate limiters stay on default :fix_window" do
      lib_files =
        Path.wildcard(Path.join(@lib_root, "**/*.ex"))

      Enum.each(lib_files, fn path ->
        source = File.read!(path)
        refute source =~ "algorithm: :sliding_window"
        refute source =~ "algorithm: :token_bucket"
        refute source =~ "algorithm: :leaky_bucket"
      end)
    end
  end

  describe "7.5.1 changelog" do
    test "documents SlidingWindow ETS deny, unique entries, and empty-window deny" do
      changelog = File.read!(@changelog)

      v151 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "7.5.1"))

      assert v151
      assert v151 =~ "7.5.1 - 2026-10-26"
      assert v151 =~ "counting denied hits"
      assert v151 =~ "removed from the window"
      assert v151 =~ "at most one hit per microsecond"
      assert v151 =~ "unique entry"
      assert v151 =~ "Enum.EmptyError"
      assert v151 =~ "{:deny, 1}"
      refute v151 =~ "Breaking"
    end
  end

  describe "7.5.1 SlidingWindow ETS patches" do
    test "denied hits are deleted instead of occupying the window" do
      source = File.read!(@sliding_window)
      assert source =~ ":ets.delete(table, {key, entry_id})"
      assert source =~ "Denied hits must not occupy the window"
    end

    test "each hit gets a unique ETS entry id, not just the microsecond" do
      source = File.read!(@sliding_window)
      assert source =~ "entry_id = {now, :erlang.unique_integer()}"
      assert source =~ ":ets.insert(table, {{key, entry_id}, expires_at})"
      refute source =~ ":ets.insert_new(table, {{key, now}, expires_at})"
    end

    test "empty-window deny uses Enum.min default instead of raising" do
      source = File.read!(@sliding_window)
      assert source =~ "Enum.min(fn -> now + 1_000 end)"
      refute source =~ ~r/:\ets\.select\(match_spec\) \|> Enum\.min\(\)/
    end

    test "denied hits do not stay in the window" do
      table = sliding_window_table()
      key = "hammer-upgrade-deny:#{System.unique_integer([:positive])}"
      scale = 60_000
      limit = 1

      assert {:allow, 1} = SlidingWindow.hit(table, key, scale, limit)

      assert {:deny, retry_after_ms} =
               SlidingWindow.hit(table, key, scale, limit)

      assert is_integer(retry_after_ms)
      assert retry_after_ms > 0
      assert SlidingWindow.get(table, key, scale) == 1

      assert {:deny, _} = SlidingWindow.hit(table, key, scale, limit)
      assert SlidingWindow.get(table, key, scale) == 1
    end

    test "concurrent hits in the same window are each recorded" do
      table = sliding_window_table()
      key = "hammer-upgrade-unique:#{System.unique_integer([:positive])}"
      scale = 60_000
      hits = 20

      results =
        1..hits
        |> Task.async_stream(
          fn _ -> SlidingWindow.hit(table, key, scale, hits) end,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:allow, _}, &1))
      assert SlidingWindow.get(table, key, scale) == hits
    end

    test "deny path does not raise Enum.EmptyError" do
      table = sliding_window_table()
      key = "hammer-upgrade-empty:#{System.unique_integer([:positive])}"
      scale = 60_000
      limit = 1

      assert {:allow, 1} = SlidingWindow.hit(table, key, scale, limit)

      for _ <- 1..20 do
        assert {:deny, retry_after_ms} =
                 SlidingWindow.hit(table, key, scale, limit)

        assert is_integer(retry_after_ms)
        assert retry_after_ms > 0
      end
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

  describe "7.5.1 hit/3 still returns allow and deny" do
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

  defp sliding_window_table do
    :ets.new(:hammer_sliding_window_upgrade, [
      :set,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true},
      {:decentralized_counters, true}
    ])
  end
end

defmodule Ysc.ObanUpgradeTest do
  @moduledoc """
  Guards the Oban 2.24.0 → 2.24.1 upgrade.

  2.24.1 is a patch: ack operations only apply while the job is still
  `executing` (and `attempted_at` still matches), notifier listeners live
  in `Oban.Notifier.Registry` so they survive a notifier crash, listen/
  notify callbacks return `{:error, _}` instead of exiting, and
  `dispatch_cooldown` is a valid `start_queue` option. We use
  `Oban.Engines.Basic` and `Oban.Notifiers.PG`. `AdminSettingsLive`
  still ignores `Oban.Notifier.listen/1`'s return (`:ok`).
  """
  use ExUnit.Case, async: true

  alias Ysc.VerificationCodeCleanupWorker

  @oban_config Application.compile_env!(:ysc, Oban)
  @prod_opts Keyword.delete(@oban_config, :testing)
  @basic_engine Path.expand(
                  "../../deps/oban/lib/oban/engines/basic.ex",
                  __DIR__
                )
  @notifier Path.expand("../../deps/oban/lib/oban/notifier.ex", __DIR__)
  @oban Path.expand("../../deps/oban/lib/oban.ex", __DIR__)

  describe "2.24.1 Hex lock" do
    test "locks oban to 2.24.1" do
      assert to_string(Application.spec(:oban, :vsn)) == "2.24.1"
    end
  end

  describe "top-level service config" do
    test "compile-time config uses 2.24 service keys instead of :plugins" do
      refute Keyword.has_key?(@oban_config, :plugins)
      refute Keyword.has_key?(@oban_config, :log)

      assert {Ysc.Repo, repo_opts} = Keyword.fetch!(@oban_config, :repo)
      assert repo_opts[:log] == false

      assert Keyword.fetch!(@oban_config, :pruner) == [max_age: {5, :days}]
      assert Keyword.fetch!(@oban_config, :reindexer) == Oban.Reindexer

      assert Keyword.fetch!(@oban_config, :lifeline) == [
               rescue_after: {3, :hours}
             ]

      crontab =
        @oban_config
        |> Keyword.fetch!(:cron)
        |> Keyword.fetch!(:crontab)

      assert {"*/15 * * * *", VerificationCodeCleanupWorker} in crontab
      assert {"0 3 * * *", YscWeb.Workers.WebhookRetryWorker} in crontab

      assert {"0 */6 * * *",
              YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker} in crontab
    end

    test "Oban.Config.validate/1 accepts the desugared production config" do
      assert Oban.Config.validate(@prod_opts) == :ok
    end

    test "Oban.Config.new/1 expands services into renamed plugin modules" do
      conf = Oban.Config.new(@prod_opts)

      plugin_modules =
        Enum.map(conf.plugins, fn
          {module, _opts} -> module
          module -> module
        end)

      assert Oban.Cron in plugin_modules
      assert Oban.Pruner in plugin_modules
      assert Oban.Lifeline in plugin_modules
      assert Oban.Reindexer in plugin_modules
      refute Oban.Plugins.Cron in plugin_modules
      refute Oban.Plugins.Pruner in plugin_modules
      refute Oban.Plugins.Lifeline in plugin_modules
      refute Oban.Plugins.Reindexer in plugin_modules

      assert conf.repo == Ysc.Repo
      assert conf.log == false

      assert {Oban.Pruner, pruner_opts} =
               Enum.find(conf.plugins, &match?({Oban.Pruner, _}, &1))

      assert pruner_opts[:max_age] == {5, :days}

      assert {Oban.Lifeline, lifeline_opts} =
               Enum.find(conf.plugins, &match?({Oban.Lifeline, _}, &1))

      assert lifeline_opts[:rescue_after] == {3, :hours}

      assert {Oban.Cron, cron_opts} =
               Enum.find(conf.plugins, &match?({Oban.Cron, _}, &1))

      assert {"0 1 * * *", Ysc.Ledgers.ReconciliationWorker} in cron_opts[
               :crontab
             ]
    end
  end

  describe "Period durations" do
    test "pruner max_age {5, :days} matches the previous 5-day second count" do
      assert Oban.Period.to_seconds({5, :days}) == 60 * 60 * 24 * 5
    end

    test "lifeline rescue_after {3, :hours} matches the previous :timer.hours(3)" do
      assert Oban.Period.to_milliseconds({3, :hours}) == :timer.hours(3)
    end
  end

  describe "schedule_in remains accepted" do
    test "legacy schedule_in still builds a future scheduled_at" do
      changeset = VerificationCodeCleanupWorker.new(%{}, schedule_in: 300)
      scheduled_at = Ecto.Changeset.get_change(changeset, :scheduled_at)

      assert %DateTime{} = scheduled_at
      assert DateTime.diff(scheduled_at, DateTime.utc_now()) in 290..310
    end

    test "scheduled_in is the documented alias and accepts period tuples" do
      changeset =
        VerificationCodeCleanupWorker.new(%{}, scheduled_in: {5, :minutes})

      scheduled_at = Ecto.Changeset.get_change(changeset, :scheduled_at)

      assert %DateTime{} = scheduled_at
      assert DateTime.diff(scheduled_at, DateTime.utc_now()) in 290..310
    end
  end

  describe "renamed plugin modules" do
    test "new modules load and legacy Oban.Plugins.* shims still delegate" do
      assert {:module, Oban.Cron} = Code.ensure_loaded(Oban.Cron)
      assert {:module, Oban.Pruner} = Code.ensure_loaded(Oban.Pruner)
      assert {:module, Oban.Lifeline} = Code.ensure_loaded(Oban.Lifeline)
      assert {:module, Oban.Reindexer} = Code.ensure_loaded(Oban.Reindexer)

      assert {:module, Oban.Plugins.Cron} =
               Code.ensure_loaded(Oban.Plugins.Cron)

      assert function_exported?(Oban.Plugins.Cron, :validate, 1)
      assert function_exported?(Oban.Cron, :validate, 1)
    end
  end

  describe "snooze API" do
    test "Worker still documents {:snooze, period} and Engine.snooze_job/3 exists" do
      assert function_exported?(Oban.Engine, :snooze_job, 3)
      assert function_exported?(Oban.Period, :to_seconds, 1)

      # Rate-limit snoozes in EmailNotifier / NewsletterSender stay {:snooze, seconds}.
      # 2.24 rolls back attempt and increments job.meta["snoozed"] instead of
      # consuming max_attempts — desired for SES pacing.
      assert Oban.Period.to_seconds(15) == 15
    end
  end

  describe "2.24.1 engine ack guards" do
    test "Basic engine acks only while executing with a matching attempted_at" do
      source = File.read!(@basic_engine)

      assert source =~ ~s(@acking_states ["executing"])
      assert source =~ "defp ack_query(%Job{} = job, states)"
      assert source =~ "j.attempted_at == ^job.attempted_at"
      assert source =~ "j.state in ^states"
    end
  end

  describe "2.24.1 notifier registry" do
    test "Oban.Application supervises Oban.Notifier.Registry" do
      assert {:module, Oban.Notifier.Registry} =
               Code.ensure_loaded(Oban.Notifier.Registry)

      assert Process.whereis(Oban.Notifier.Registry)
      assert Process.whereis(Oban.Application)
    end

    test "listen/1 still returns :ok for AdminSettingsLive channels" do
      assert :ok = Oban.Notifier.listen([:insert, :gossip])

      conf = Oban.config()

      assert self() in Oban.Notifier.Registry.listeners(conf, :insert)
      assert self() in Oban.Notifier.Registry.listeners(conf, :gossip)

      assert :ok = Oban.Notifier.unlisten([:insert, :gossip])
      refute self() in Oban.Notifier.Registry.listeners(conf, :insert)
      refute self() in Oban.Notifier.Registry.listeners(conf, :gossip)
    end

    test "notify/3 returns :ok or {:error, exception} without exiting" do
      result = Oban.Notifier.notify(:insert, %{probe: true})

      assert result == :ok or match?({:error, %_{}}, result)
    end

    test "listen still registers even when the notifier callback is wrapped" do
      source = File.read!(@notifier)

      assert source =~ "alias Oban.Notifier.Registry, as: Listeners"

      assert source =~
               "for channel <- channels, do: Listeners.register(conf, channel)"

      assert source =~ ":exit, reason ->"
      assert source =~ "notifier exited with"
    end
  end

  describe "2.24.1 dispatch_cooldown" do
    test "start_queue documents and validates dispatch_cooldown" do
      source = File.read!(@oban)

      assert String.contains?(
               source,
               "validate_queue_opts!(opts, ~w(dispatch_cooldown local_only node queue)a)"
             )

      assert_raise ArgumentError, ~r/dispatch_cooldown/, fn ->
        Oban.start_queue(queue: :upgrade_probe, limit: 1, dispatch_cooldown: 0)
      end
    end
  end
end

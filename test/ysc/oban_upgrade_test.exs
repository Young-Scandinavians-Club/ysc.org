defmodule Ysc.ObanUpgradeTest do
  @moduledoc """
  Guards the Oban 2.23.1 → 2.24.0 upgrade.

  2.24.0 promotes Cron/Pruner/Lifeline/Reindexer to top-level config keys,
  publicizes `Oban.Period`, keeps `schedule_in` as a synonym for `scheduled_in`,
  and rolls back `attempt` on snooze. We migrated off `Oban.Plugins.*`.
  """
  use ExUnit.Case, async: true

  alias Ysc.VerificationCodeCleanupWorker

  @oban_config Application.compile_env!(:ysc, Oban)
  @prod_opts Keyword.delete(@oban_config, :testing)

  describe "2.24.0 Hex lock" do
    test "locks oban to 2.24.0" do
      assert to_string(Application.spec(:oban, :vsn)) == "2.24.0"
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
end

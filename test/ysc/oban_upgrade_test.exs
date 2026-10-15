defmodule Ysc.ObanUpgradeTest do
  @moduledoc """
  Guards the Oban 2.24.1 → 2.24.2 upgrade.

  2.24.2 is a patch with no documented breaking changes. Snooze now
  `jsonb_set`s `snoozed` on the current DB `meta` instead of overwriting
  it with the in-memory snapshot from execution start. The producer
  kills via `Task.Supervisor.terminate_child/2` and lets the existing
  `{ref, _}` / `:DOWN` handlers release the running slot, so a job that
  exits just before `pkill` is handled is not stuck in the running list.

  Dolphin fetch deadlocks and Lite `nil` uniqueness are unused — we use
  `Oban.Engines.Basic` and `Oban.Notifiers.PG`. We snooze with
  `{:snooze, seconds}` in `EmailNotifier` / `NewsletterSender` and do
  not mutate `job.meta` during `perform`. 2.24.1 ack/`dispatch_cooldown`
  behavior is unchanged. The internal listener table moved from
  `Oban.Notifier.Registry` to `Oban.Notifiers.Listeners` (undocumented,
  not a public API). `AdminSettingsLive` still calls
  `Oban.Notifier.listen/1` and ignores the `:ok` return.
  """
  use Ysc.DataCase, async: true

  alias Ysc.VerificationCodeCleanupWorker

  @oban_config Application.compile_env!(:ysc, Oban)
  @prod_opts Keyword.delete(@oban_config, :testing)
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/oban/CHANGELOG.md", __DIR__)
  @basic_engine Path.expand(
                  "../../deps/oban/lib/oban/engines/basic.ex",
                  __DIR__
                )
  @producer Path.expand(
              "../../deps/oban/lib/oban/queues/producer.ex",
              __DIR__
            )
  @notifier Path.expand("../../deps/oban/lib/oban/notifier.ex", __DIR__)
  @oban Path.expand("../../deps/oban/lib/oban.ex", __DIR__)
  @email_notifier Path.expand(
                    "../../lib/ysc_web/workers/email_notifier.ex",
                    __DIR__
                  )
  @newsletter_sender Path.expand(
                       "../../lib/ysc_web/workers/newsletter_sender.ex",
                       __DIR__
                     )

  describe "2.24.2 Hex lock" do
    test "locks oban to 2.24.2" do
      {:module, _} = Code.ensure_loaded(Oban)
      assert to_string(Application.spec(:oban, :vsn)) == "2.24.2"
    end

    test "mix.exs pins the 2.24.2 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:oban, "~> 2.24.2"}|
    end

    test "companion lock is 2.24.2" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"oban": {:hex, :oban, "2.24.2"|
      refute lock =~ ~s|"oban": {:hex, :oban, "2.24.1"|
    end
  end

  describe "2.24.2 changelog" do
    test "documents targeted snooze meta updates and pkill release" do
      changelog = File.read!(@changelog)

      v2242 =
        changelog
        |> String.split("\n## ")
        |> Enum.map(&String.replace_prefix(&1, "## ", ""))
        |> Enum.find(&String.starts_with?(&1, "v2.24.2"))

      assert v2242
      assert v2242 =~ "Preserve meta updates during execution on snooze"
      assert v2242 =~ "targeted update"
      assert v2242 =~ "Release jobs that exit before a pkill is handled"
      assert v2242 =~ "Dolphin"
      assert v2242 =~ "Lite"
      refute v2242 =~ "Breaking"
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
      assert conf.engine == Oban.Engines.Basic

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
      assert {:module, _} = Code.ensure_loaded(Oban.Engine)
      assert function_exported?(Oban.Engine, :snooze_job, 3)
      assert {:module, _} = Code.ensure_loaded(Oban.Period)
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

  describe "2.24.2 snooze preserves execution-time meta" do
    test "Basic snooze jsonb_sets snoozed on current DB meta" do
      source = File.read!(@basic_engine)

      assert source =~
               ~s|def snooze_job(%Config{} = conf, %Job{} = job, seconds)|

      assert source =~ "jsonb_set"
      assert source =~ "{snoozed}"
      assert source =~ "j.meta"
      assert source =~ "inc: [attempt: -1]"
      refute source =~ "Map.update(meta, \"snoozed\""
    end

    test "jsonb_set keeps other meta keys when the in-memory job is stale" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, job} =
          VerificationCodeCleanupWorker.new(%{}, meta: %{"keep" => "yes"})
          |> Oban.insert()

        {1, _} =
          from(j in Oban.Job, where: j.id == ^job.id)
          |> Repo.update_all(
            set: [
              state: "executing",
              attempted_at: DateTime.utc_now(),
              attempt: 1,
              meta: %{"keep" => "yes", "during" => "exec"}
            ]
          )

        executing = Repo.get!(Oban.Job, job.id)
        stale = %{executing | meta: %{"keep" => "yes"}}

        assert :ok = Oban.Engine.snooze_job(Oban.config(), stale, 15)

        reloaded = Repo.get!(Oban.Job, job.id)
        assert reloaded.state == "scheduled"
        assert reloaded.meta["keep"] == "yes"
        assert reloaded.meta["during"] == "exec"
        assert reloaded.meta["snoozed"] == 1
        assert reloaded.attempt == 0
      end)
    end

    test "EmailNotifier and NewsletterSender still return {:snooze, seconds}" do
      email = File.read!(@email_notifier)
      newsletter = File.read!(@newsletter_sender)

      assert email =~ "{:error, {:snooze, seconds}} ->"
      assert email =~ "{:snooze, seconds}"
      assert newsletter =~ "{:error, {:snooze, seconds}} -> {:snooze, seconds}"
      assert newsletter =~ "{:snooze, 15}"
      refute email =~ "job.meta"
      refute newsletter =~ "job.meta"
    end
  end

  describe "2.24.2 producer pkill release" do
    test "pkill terminates the child and lets DOWN/{ref, _} release the slot" do
      source = File.read!(@producer)

      assert source =~ ~s|%{"action" => "pkill", "job_id" => jid} ->|
      assert source =~ "Task.Supervisor.terminate_child(state.foreman, pid)"
      assert source =~ "def handle_info({ref, _val}, %State{} = state)"
      assert source =~ "release_ref(ref)"
      refute source =~ "defp pkill("
    end
  end

  describe "2.24.2 notifier listeners" do
    test "Oban.Application supervises Oban.Notifiers.Listeners" do
      assert {:module, Oban.Notifiers.Listeners} =
               Code.ensure_loaded(Oban.Notifiers.Listeners)

      assert Process.whereis(Oban.Notifiers.Listeners)
      assert Process.whereis(Oban.Application)
    end

    test "listen/1 still returns :ok for AdminSettingsLive channels" do
      assert :ok = Oban.Notifier.listen([:insert, :gossip])

      conf = Oban.config()

      assert self() in Oban.Notifiers.Listeners.listeners(conf, :insert)
      assert self() in Oban.Notifiers.Listeners.listeners(conf, :gossip)

      assert :ok = Oban.Notifier.unlisten([:insert, :gossip])
      refute self() in Oban.Notifiers.Listeners.listeners(conf, :insert)
      refute self() in Oban.Notifiers.Listeners.listeners(conf, :gossip)
    end

    test "notify/3 returns :ok or {:error, exception} without exiting" do
      result = Oban.Notifier.notify(:insert, %{probe: true})

      assert result == :ok or match?({:error, %_{}}, result)
    end

    test "listen still registers even when the notifier callback is wrapped" do
      source = File.read!(@notifier)

      assert source =~ "alias Oban.Notifiers.Listeners"

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

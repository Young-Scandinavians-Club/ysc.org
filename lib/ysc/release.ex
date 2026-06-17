defmodule Ysc.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :ysc

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  # sobelow_skip ["RCE.CodeModule"]
  def seed do
    load_app()

    seeds_path = Path.join([:code.priv_dir(@app), "repo", "seeds_prod.exs"])

    if File.exists?(seeds_path) do
      for repo <- repos() do
        {:ok, _, _} =
          Ecto.Migrator.with_repo(repo, fn _repo ->
            Code.eval_file(seeds_path)
          end)
      end
    else
      IO.puts("Warning: seeds file not found at #{seeds_path}")
    end
  end

  @doc """
  Loads a WordPress migration export directory into the production database.

  The export must already exist on the machine (e.g. unpacked under `/data/wp_migration_export`).
  Run extract locally (`mix ysc.wp_extract`); production releases do not include Mix.

  Usage in production (one-off Fly machine or SSH session):

      bin/ysc eval 'Ysc.Release.wp_load("/data/wp_migration_export", dry_run: true)'
      bin/ysc eval 'Ysc.Release.wp_load("/data/wp_migration_export")'
      bin/ysc eval 'Ysc.Release.wp_load("/data/wp_migration_export", upload_media: false)'

  Options (keyword list as second argument):
  - `:dry_run` — log only, no DB or S3 writes (default: false)
  - `:upload_media` — upload media/ to Tigris and create Image records (default: true)
  - `:create_stripe_subscriptions` — create Stripe subs in the connected account (default: false; sandbox only)
  - `:only_emails` — load a single email or list of emails for targeted runs
  """
  def wp_load(export_dir, opts \\ []) when is_binary(export_dir) do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    dry_run = Keyword.get(opts, :dry_run, false)
    upload_media = Keyword.get(opts, :upload_media, true)

    create_stripe_subscriptions =
      Keyword.get(opts, :create_stripe_subscriptions, false)

    only_emails = Keyword.get(opts, :only_emails)

    require Ysc.Logging

    Ysc.Logging.info("WP migration load starting",
      export_dir: export_dir,
      dry_run: dry_run,
      upload_media: upload_media,
      create_stripe_subscriptions: create_stripe_subscriptions,
      only_emails: only_emails
    )

    load_opts = [
      export_dir: export_dir,
      dry_run: dry_run,
      upload_media: upload_media,
      create_stripe_subscriptions: create_stripe_subscriptions
    ]

    load_opts =
      if only_emails,
        do: Keyword.put(load_opts, :only_emails, only_emails),
        else: load_opts

    case Ysc.WpMigration.Load.run(load_opts) do
      {:ok, result} ->
        Ysc.Logging.info("WP migration load finished",
          users: map_size(result[:user_map] || %{}),
          images: map_size(result[:image_map] || %{}),
          dry_run: dry_run
        )

        {:ok, result}

      {:error, message} ->
        Ysc.Logging.error("WP migration load failed", error: message)
        {:error, message}
    end
  end

  @doc """
  Clears `wp_migration_active`, re-enabling Stripe webhook side effects (emails, QuickBooks, etc.).

  Run after migration load and validation are complete.

  Usage in production:

      bin/ysc eval "Ysc.Release.wp_migration_unlock()"
  """
  def wp_migration_unlock do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)
    require Ysc.Logging

    current = Ysc.Settings.get_setting_safe("wp_migration_active")

    if current == "true" do
      case Ysc.Settings.update_setting("wp_migration_active", "false") do
        {:ok, _} ->
          Ysc.Logging.info(
            "[WP Migration] Comms suppression DISABLED via Release.wp_migration_unlock"
          )

          :ok

        {:error, reason} ->
          Ysc.Logging.error("Failed to clear wp_migration_active",
            error: reason
          )

          {:error, reason}
      end
    else
      Ysc.Logging.info(
        "[WP Migration] wp_migration_active is already #{inspect(current)} — nothing to do"
      )

      :ok
    end
  end

  @doc """
  Re-queues all failed email messages.

  Usage in production:
      bin/ysc eval "Ysc.Release.requeue_failed_messages()"

  Or with options:
      bin/ysc eval "Ysc.Release.requeue_failed_messages(limit: 50)"
  """
  def requeue_failed_messages(opts \\ []) do
    load_app()

    result =
      for repo <- repos() do
        {:ok, _, result} =
          Ecto.Migrator.with_repo(repo, fn _repo ->
            require Ysc.Logging

            Ysc.Logging.info("Re-queuing failed email messages...")

            result = Ysc.Messages.Requeue.requeue_all(opts)

            Ysc.Logging.info("Summary:")
            Ysc.Logging.info("Total Found: #{result.total_found}")
            Ysc.Logging.info("Successfully Re-queued: #{result.successful}")
            Ysc.Logging.info("Failed to Re-queue: #{result.failed}")

            if result.failed > 0 do
              Ysc.Logging.warning(
                "Some jobs failed to re-queue. Check logs for details."
              )
            end

            result
          end)

        result
      end
      |> List.first()

    result || %{total_found: 0, successful: 0, failed: 0, results: []}
  end

  @doc """
  Shows statistics about failed email messages.

  Usage in production:
      bin/ysc eval "Ysc.Release.show_failed_message_stats()"
  """
  def show_failed_message_stats do
    load_app()

    stats =
      for repo <- repos() do
        {:ok, _, stats} =
          Ecto.Migrator.with_repo(repo, fn _repo ->
            require Ysc.Logging

            stats = Ysc.Messages.Requeue.get_stats()

            Ysc.Logging.info("")

            Ysc.Logging.info(
              "═══════════════════════════════════════════════════════════"
            )

            Ysc.Logging.info("  Failed Email Job Statistics")

            Ysc.Logging.info(
              "═══════════════════════════════════════════════════════════"
            )

            Ysc.Logging.info("")
            Ysc.Logging.info("  Total Failed:        #{stats.total_failed}")

            Ysc.Logging.info(
              "  ├─ Discarded:        #{stats.discarded} (exhausted retries)"
            )

            Ysc.Logging.info(
              "  └─ Retryable:        #{stats.retryable} (can still retry)"
            )

            Ysc.Logging.info("")

            Ysc.Logging.info(
              "  Recent Failures:     #{stats.recent_failures_24h} (last 24 hours)"
            )

            Ysc.Logging.info("")

            if not Enum.empty?(stats.by_template) do
              Ysc.Logging.info("  Breakdown by Template:")
              Ysc.Logging.info("")

              Enum.each(stats.by_template, fn {template, count} ->
                Ysc.Logging.info(
                  "    • #{String.pad_trailing(template, 40)} #{count}"
                )
              end)

              Ysc.Logging.info("")
            end

            Ysc.Logging.info(
              "═══════════════════════════════════════════════════════════"
            )

            Ysc.Logging.info("")

            stats
          end)

        stats
      end
      |> List.first()

    stats ||
      %{
        total_failed: 0,
        discarded: 0,
        retryable: 0,
        by_template: %{},
        recent_failures_24h: 0
      }
  end

  @doc """
  Re-queues a single failed email message by job ID.

  Usage in production:
      bin/ysc eval "Ysc.Release.requeue_failed_message(JOB_ID)"
  """
  def requeue_failed_message(job_id) do
    load_app()

    for repo <- repos() do
      {:ok, _, result} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          require Ysc.Logging

          Ysc.Logging.info("Re-queuing job: #{job_id}")

          case Ysc.Messages.Requeue.requeue_job_by_id(job_id) do
            {:ok, new_job} ->
              Ysc.Logging.info("✅ Successfully re-queued job #{job_id}")
              Ysc.Logging.info("New Job ID: #{new_job.id}")
              {:ok, new_job}

            {:error, :not_found} ->
              Ysc.Logging.error("❌ Job #{job_id} not found")
              {:error, :not_found}

            {:error, :not_an_email_job} ->
              Ysc.Logging.error("❌ Job #{job_id} is not an email job")
              {:error, :not_an_email_job}

            {:error, reason} ->
              Ysc.Logging.error(
                "❌ Failed to re-queue job #{job_id}: #{inspect(reason)}"
              )

              {:error, reason}
          end
        end)

      result
    end
    |> List.first()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end

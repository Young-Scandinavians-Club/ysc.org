defmodule Ysc.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :ysc

  # Fly Postgres (especially sandbox) can still be in recovery, or drop the
  # TCP connection, when the release_command Machine starts. Retry transient
  # errors instead of failing the deploy.
  @migrate_attempts 15
  @migrate_retry_delay_ms 2_000

  @transient_postgres_codes [
    :cannot_connect_now,
    :admin_shutdown,
    :crash_shutdown,
    :too_many_connections
  ]

  def migrate(opts \\ []) do
    load_app()

    attempts = Keyword.get(opts, :attempts, @migrate_attempts)
    delay_ms = Keyword.get(opts, :delay_ms, @migrate_retry_delay_ms)
    sleep = Keyword.get(opts, :sleep, &Process.sleep/1)
    migrator = Keyword.get(opts, :migrator, &run_migrations/1)

    for repo <- repos() do
      retry_transient_db(fn -> migrator.(repo) end, attempts, delay_ms, sleep)
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

  defp run_migrations(repo) do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  end

  defp retry_transient_db(fun, attempts_left, delay_ms, sleep) do
    fun.()
  rescue
    e ->
      if attempts_left > 1 and transient_db_error?(e) do
        remaining = attempts_left - 1

        IO.puts(
          "Database not ready (#{exception_text(e)}); retrying in #{delay_ms}ms (#{remaining} attempts left)"
        )

        sleep.(delay_ms)
        retry_transient_db(fun, remaining, delay_ms, sleep)
      else
        reraise e, __STACKTRACE__
      end
  end

  defp transient_db_error?(%DBConnection.ConnectionError{}), do: true

  defp transient_db_error?(%Postgrex.Error{postgres: %{code: code}})
       when code in @transient_postgres_codes,
       do: true

  defp transient_db_error?(_), do: false

  defp exception_text(e) do
    Exception.message(e)
  rescue
    _ -> inspect(e)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end

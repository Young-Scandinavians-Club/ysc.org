defmodule Mix.Tasks.Message.Requeue do
  @moduledoc """
  Mix task for re-queuing failed email messages.

  ## Examples:

      # List all failed email jobs
      mix message.requeue list

      # List failed email jobs with a limit
      mix message.requeue list --limit 20

      # Show statistics about failed email jobs
      mix message.requeue stats

      # Re-queue a specific job by ID
      mix message.requeue single JOB_ID

      # Re-queue all failed email jobs
      mix message.requeue all

      # Re-queue all failed email jobs with a limit
      mix message.requeue all --limit 50

      # Dry run - show what would be re-queued without actually re-queuing
      mix message.requeue all --dry-run

      # Re-queue jobs failed since a specific date
      mix message.requeue all --since "2025-01-01T00:00:00Z"
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Re-queue failed email messages"

  alias Ysc.Messages.Requeue

  def run(args) do
    # Start the application to ensure all dependencies are loaded
    Mix.Task.run("app.start")

    case args do
      ["list" | opts] ->
        list_failed_jobs(opts)

      ["stats"] ->
        show_stats()

      ["single", job_id] ->
        requeue_single_job(job_id)

      ["all" | opts] ->
        requeue_all_failed_jobs(opts)

      _ ->
        show_help()
    end
  end

  defp list_failed_jobs(opts) do
    opts = parse_opts(opts)

    Ysc.Logging.info("Listing failed email jobs...")

    failed_jobs = Requeue.list_failed_jobs(opts)

    if Enum.empty?(failed_jobs) do
      Ysc.Logging.info("No failed email jobs found.")
    else
      Ysc.Logging.info("Found #{length(failed_jobs)} failed email jobs:")
      Ysc.Logging.info("")

      Enum.each(failed_jobs, fn job ->
        recipient = get_in(job.args, ["recipient"]) || "unknown"
        template = get_in(job.args, ["template"]) || "unknown"

        Ysc.Logging.info("Job ID: #{job.id}")
        Ysc.Logging.info("  State: #{job.state}")
        Ysc.Logging.info("  Queue: #{job.queue}")
        Ysc.Logging.info("  Worker: #{job.worker}")
        Ysc.Logging.info("  Recipient: #{recipient}")
        Ysc.Logging.info("  Template: #{template}")
        Ysc.Logging.info("  Attempt: #{job.attempt}/#{job.max_attempts}")

        Ysc.Logging.info(
          "  Failed At: #{format_datetime(job.discarded_at || job.inserted_at)}"
        )

        Ysc.Logging.info("  Created At: #{format_datetime(job.inserted_at)}")

        if job.errors && job.errors != [] do
          last_error = List.last(job.errors)
          Ysc.Logging.info("  Last Error: #{inspect(last_error.message)}")
        end

        Ysc.Logging.info("")
      end)
    end
  end

  defp show_stats do
    Ysc.Logging.info("Failed email job statistics:")
    Ysc.Logging.info("")

    stats = Requeue.get_stats()

    Ysc.Logging.info("Total Failed: #{stats.total_failed}")
    Ysc.Logging.info("Discarded (exhausted retries): #{stats.discarded}")
    Ysc.Logging.info("Retryable (can still retry): #{stats.retryable}")
    Ysc.Logging.info("Recent Failures (24h): #{stats.recent_failures_24h}")
    Ysc.Logging.info("")

    if not Enum.empty?(stats.by_template) do
      Ysc.Logging.info("By Template:")

      Enum.each(stats.by_template, fn {template, count} ->
        Ysc.Logging.info("  #{template}: #{count}")
      end)

      Ysc.Logging.info("")
    end
  end

  defp requeue_single_job(job_id) do
    Ysc.Logging.info("Re-queuing job: #{job_id}")

    case Requeue.requeue_job_by_id(job_id) do
      {:ok, new_job} ->
        Ysc.Logging.info("✅ Successfully re-queued job #{job_id}")
        Ysc.Logging.info("New Job ID: #{new_job.id}")

      {:error, :not_found} ->
        Ysc.Logging.error("❌ Job #{job_id} not found")

      {:error, :not_an_email_job} ->
        Ysc.Logging.error("❌ Job #{job_id} is not an email job")

      {:error, reason} ->
        Ysc.Logging.error(
          "❌ Failed to re-queue job #{job_id}: #{inspect(reason)}"
        )
    end
  end

  defp requeue_all_failed_jobs(opts) do
    opts = parse_opts(opts)

    if opts[:dry_run] do
      Ysc.Logging.info("🔍 Dry run - showing what would be re-queued...")
    else
      Ysc.Logging.info("Re-queuing all failed email jobs...")
    end

    result = Requeue.requeue_all(opts)

    if result.total_found == 0 do
      Ysc.Logging.info("No failed email jobs found to re-queue.")
    else
      Ysc.Logging.info(
        "Found #{result.total_found} failed email jobs to re-queue."
      )

      Ysc.Logging.info("")

      if opts[:dry_run] do
        failed_jobs =
          Requeue.list_failed_jobs(
            limit: opts[:limit] || 100,
            since: opts[:since]
          )

        Enum.each(failed_jobs, fn job ->
          recipient = get_in(job.args, ["recipient"]) || "unknown"
          template = get_in(job.args, ["template"]) || "unknown"

          Ysc.Logging.info(
            "Would re-queue: Job #{job.id} - #{recipient} (#{template})"
          )
        end)
      end

      Ysc.Logging.info("")
      Ysc.Logging.info("Summary:")
      Ysc.Logging.info("Total Found: #{result.total_found}")

      if not opts[:dry_run] do
        Ysc.Logging.info("Successfully Re-queued: #{result.successful}")
        Ysc.Logging.info("Failed to Re-queue: #{result.failed}")

        if result.failed > 0 do
          Ysc.Logging.info("")
          Ysc.Logging.info("Failed job details:")

          Enum.each(result.results, fn
            {:ok, _} ->
              :ok

            {:error, job_id, reason} ->
              Ysc.Logging.error("  Job #{job_id}: #{inspect(reason)}")
          end)
        end
      end
    end
  end

  defp parse_opts(opts) do
    opts
    |> Enum.chunk_every(2)
    |> Enum.reduce([], fn
      ["--limit", limit], acc ->
        Keyword.put(acc, :limit, String.to_integer(limit))

      ["--since", since], acc ->
        since_dt =
          case DateTime.from_iso8601(since) do
            {:ok, dt, _} ->
              dt

            {:error, _} ->
              raise ArgumentError, "Invalid datetime format: #{since}"
          end

        Keyword.put(acc, :since, since_dt)

      ["--dry-run"], acc ->
        Keyword.put(acc, :dry_run, true)

      _, acc ->
        acc
    end)
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp show_help do
    Ysc.Logging.info("""
    Message Re-queue Tool

    Usage:
      mix message.requeue <command> [options]

    Commands:
      list                    List all failed email jobs
      stats                   Show statistics about failed email jobs
      single <job_id>         Re-queue a specific job by ID
      all                     Re-queue all failed email jobs

    Options:
      --limit <number>        Limit number of jobs to process (default: 100)
      --since <datetime>      Only process jobs failed since this datetime (ISO8601 format)
      --dry-run               Show what would be re-queued without actually re-queuing

    Examples:
      mix message.requeue list
      mix message.requeue list --limit 20
      mix message.requeue stats
      mix message.requeue single 12345
      mix message.requeue all --limit 50
      mix message.requeue all --dry-run
      mix message.requeue all --since "2025-01-01T00:00:00Z"
    """)
  end
end

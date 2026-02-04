defmodule Mix.Tasks.DebugEmails do
  @moduledoc """
  Debug script to check email queue status and recent jobs.

  Usage:
    mix debug_emails
    mix debug_emails --queue mailers
    mix debug_emails --recent 10
  """

  use Mix.Task
  require Logger

  @shortdoc "Debug email queue and Oban jobs"

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [queue: :string, recent: :integer])

    queue = Keyword.get(opts, :queue, "mailers")
    recent_count = Keyword.get(opts, :recent, 5)

    Mix.Task.run("app.start")

    Logger.info("=== Email Queue Debug Information ===")
    Logger.info("Queue: #{queue}")
    Logger.info("Recent jobs to show: #{recent_count}")
    Logger.info("")

    # Check Oban configuration
    oban_config = Application.get_env(:ysc, Oban)
    Logger.info("Oban Configuration:")
    Logger.info("  Repo: #{inspect(oban_config[:repo])}")
    Logger.info("  Queues: #{inspect(oban_config[:queues])}")
    Logger.info("  Log Level: #{inspect(oban_config[:log])}")
    Logger.info("")

    # Check recent jobs in the mailers queue
    Logger.info("=== Recent Jobs in #{queue} Queue ===")
    recent_jobs = get_recent_jobs(queue, recent_count)

    if Enum.empty?(recent_jobs) do
      Logger.info("No recent jobs found in #{queue} queue")
    else
      Enum.each(recent_jobs, fn job -> log_job_details(job) end)
    end

    # Check job counts by state
    Logger.info("=== Job Counts by State ===")
    job_counts = get_job_counts_by_state(queue)

    Enum.each(job_counts, fn {state, count} ->
      Logger.info("#{state}: #{count}")
    end)

    Logger.info("")

    # Check if Oban is running
    Logger.info("=== Oban Status ===")

    queues = Oban.check_all_queues()

    if is_list(queues) and queues != [] do
      Logger.info("Oban is running with #{length(queues)} queue(s)")

      Enum.each(queues, fn queue_status ->
        Logger.info("  Queue: #{queue_status.queue}")
        Logger.info("    Limit: #{queue_status.limit}")
        Logger.info("    Running: #{length(queue_status.running)}")
        Logger.info("    Paused: #{queue_status.paused}")
      end)
    else
      Logger.info("Oban is running (no queues found)")
    end
  end

  defp log_job_details(job) do
    Logger.info("Job ID: #{job.id}")
    Logger.info("  State: #{job.state}")
    Logger.info("  Queue: #{job.queue}")
    Logger.info("  Worker: #{job.worker}")
    Logger.info("  Attempt: #{job.attempt}/#{job.max_attempts}")
    Logger.info("  Scheduled at: #{job.scheduled_at}")
    Logger.info("  Inserted at: #{job.inserted_at}")

    if Map.has_key?(job, :processed_at) && job.processed_at do
      Logger.info("  Processed at: #{job.processed_at}")
    end

    if job.discarded_at do
      Logger.info("  Discarded at: #{job.discarded_at}")
    end

    if job.cancelled_at do
      Logger.info("  Cancelled at: #{job.cancelled_at}")
    end

    if job.errors do
      Logger.info("  Errors: #{inspect(job.errors)}")
    end

    Logger.info("  Args: #{inspect(job.args, limit: :infinity)}")
    Logger.info("")
  end

  defp get_recent_jobs(queue, limit) do
    import Ecto.Query

    Ysc.Repo.all(
      from j in Oban.Job,
        where: j.queue == ^queue,
        order_by: [desc: j.inserted_at],
        limit: ^limit
    )
  end

  defp get_job_counts_by_state(queue) do
    import Ecto.Query

    from(j in Oban.Job,
      where: j.queue == ^queue,
      group_by: j.state,
      select: {j.state, count(j.id)}
    )
    |> Ysc.Repo.all()
  end
end

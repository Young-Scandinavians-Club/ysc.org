defmodule Mix.Tasks.DebugEmails do
  @moduledoc """
  Debug script to check email queue status and recent jobs.

  Usage:
    mix debug_emails
    mix debug_emails --queue mailers
    mix debug_emails --recent 10
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Debug email queue and Oban jobs"

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [queue: :string, recent: :integer])

    queue = Keyword.get(opts, :queue, "mailers")
    recent_count = Keyword.get(opts, :recent, 5)

    Mix.Task.run("app.start")

    Ysc.Logging.info("=== Email Queue Debug Information ===")
    Ysc.Logging.info("Queue: #{queue}")
    Ysc.Logging.info("Recent jobs to show: #{recent_count}")
    Ysc.Logging.info("")

    # Check Oban configuration
    oban_config = Application.get_env(:ysc, Oban)
    Ysc.Logging.info("Oban Configuration:")
    Ysc.Logging.info("  Repo: #{inspect(oban_config[:repo])}")
    Ysc.Logging.info("  Queues: #{inspect(oban_config[:queues])}")
    Ysc.Logging.info("  Log Level: #{inspect(oban_config[:log])}")
    Ysc.Logging.info("")

    # Check recent jobs in the mailers queue
    Ysc.Logging.info("=== Recent Jobs in #{queue} Queue ===")
    recent_jobs = get_recent_jobs(queue, recent_count)

    if Enum.empty?(recent_jobs) do
      Ysc.Logging.info("No recent jobs found in #{queue} queue")
    else
      Enum.each(recent_jobs, fn job -> log_job_details(job) end)
    end

    # Check job counts by state
    Ysc.Logging.info("=== Job Counts by State ===")
    job_counts = get_job_counts_by_state(queue)

    Enum.each(job_counts, fn {state, count} ->
      Ysc.Logging.info("#{state}: #{count}")
    end)

    Ysc.Logging.info("")

    # Check if Oban is running
    Ysc.Logging.info("=== Oban Status ===")

    queues = Oban.check_all_queues()

    if is_list(queues) and queues != [] do
      Ysc.Logging.info("Oban is running with #{length(queues)} queue(s)")

      Enum.each(queues, fn queue_status ->
        Ysc.Logging.info("  Queue: #{queue_status.queue}")
        Ysc.Logging.info("    Limit: #{queue_status.limit}")
        Ysc.Logging.info("    Running: #{length(queue_status.running)}")
        Ysc.Logging.info("    Paused: #{queue_status.paused}")
      end)
    else
      Ysc.Logging.info("Oban is running (no queues found)")
    end
  end

  defp log_job_details(job) do
    Ysc.Logging.info("Job ID: #{job.id}")
    Ysc.Logging.info("  State: #{job.state}")
    Ysc.Logging.info("  Queue: #{job.queue}")
    Ysc.Logging.info("  Worker: #{job.worker}")
    Ysc.Logging.info("  Attempt: #{job.attempt}/#{job.max_attempts}")
    Ysc.Logging.info("  Scheduled at: #{job.scheduled_at}")
    Ysc.Logging.info("  Inserted at: #{job.inserted_at}")

    if Map.has_key?(job, :processed_at) && job.processed_at do
      Ysc.Logging.info("  Processed at: #{job.processed_at}")
    end

    if job.discarded_at do
      Ysc.Logging.info("  Discarded at: #{job.discarded_at}")
    end

    if job.cancelled_at do
      Ysc.Logging.info("  Cancelled at: #{job.cancelled_at}")
    end

    if job.errors do
      Ysc.Logging.info("  Errors: #{inspect(job.errors)}")
    end

    Ysc.Logging.info("  Args: #{inspect(job.args, limit: :infinity)}")
    Ysc.Logging.info("")
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

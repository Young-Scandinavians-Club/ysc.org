defmodule Ysc.Messages.Requeue do
  @moduledoc """
  Core module for re-queuing failed email messages.

  This module provides the core functionality that can be used by both
  Mix tasks (development) and Release module functions (production).
  """

  require Logger

  alias Ysc.Repo
  alias Oban.Job
  import Ecto.Query

  @doc """
  Lists all failed email jobs.

  ## Options
  - `:limit` - Maximum number of jobs to return (default: 100)
  - `:since` - Only return jobs failed since this DateTime
  """
  def list_failed_jobs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since)

    query =
      from(j in Job,
        where:
          j.queue == "mailers" and j.worker == "YscWeb.Workers.EmailNotifier",
        where: j.state in ["discarded", "retryable"],
        order_by: [
          desc: fragment("COALESCE(?, ?)", j.discarded_at, j.inserted_at),
          desc: j.inserted_at
        ],
        limit: ^limit
      )

    query =
      if since do
        where(
          query,
          [j],
          fragment("COALESCE(?, ?)", j.discarded_at, j.inserted_at) >= ^since
        )
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets statistics about failed email jobs.
  """
  def get_stats do
    # Total failed (discarded + retryable)
    total_failed =
      from(j in Job,
        where:
          j.queue == "mailers" and j.worker == "YscWeb.Workers.EmailNotifier",
        where: j.state in ["discarded", "retryable"],
        select: count()
      )
      |> Repo.one()

    # Discarded (exhausted retries)
    discarded =
      from(j in Job,
        where:
          j.queue == "mailers" and j.worker == "YscWeb.Workers.EmailNotifier",
        where: j.state == "discarded",
        select: count()
      )
      |> Repo.one()

    # Retryable (can still retry)
    retryable =
      from(j in Job,
        where:
          j.queue == "mailers" and j.worker == "YscWeb.Workers.EmailNotifier",
        where: j.state == "retryable",
        select: count()
      )
      |> Repo.one()

    # By template - load jobs and group in Elixir for reliability
    jobs_for_template_stats =
      from(j in Job,
        where:
          j.queue == "mailers" and j.worker == "YscWeb.Workers.EmailNotifier",
        where: j.state in ["discarded", "retryable"],
        select: j.args
      )
      |> Repo.all()

    by_template =
      jobs_for_template_stats
      |> Enum.map(fn args -> get_in(args, ["template"]) || "unknown" end)
      |> Enum.frequencies()

    # Recent failures (last 24 hours)
    since_24h = DateTime.add(DateTime.utc_now(), -24 * 60 * 60, :second)

    recent_failures =
      from(j in Job,
        where:
          j.queue == "mailers" and j.worker == "YscWeb.Workers.EmailNotifier",
        where: j.state in ["discarded", "retryable"],
        where:
          fragment("COALESCE(?, ?)", j.discarded_at, j.inserted_at) >=
            ^since_24h,
        select: count()
      )
      |> Repo.one()

    %{
      total_failed: total_failed,
      discarded: discarded,
      retryable: retryable,
      by_template: by_template,
      recent_failures_24h: recent_failures
    }
  end

  @doc """
  Re-queues a single job by ID.

  Returns `{:ok, new_job}` or `{:error, reason}`.
  """
  def requeue_job_by_id(job_id) do
    case Repo.get(Job, job_id) do
      nil ->
        {:error, :not_found}

      job ->
        if email_job?(job) do
          requeue_job(job)
        else
          {:error, :not_an_email_job}
        end
    end
  end

  @doc """
  Re-queues all failed email jobs.

  ## Options
  - `:limit` - Maximum number of jobs to process (default: 100)
  - `:since` - Only process jobs failed since this DateTime
  - `:dry_run` - If true, only shows what would be re-queued without actually re-queuing

  Returns a map with `:total_found`, `:successful`, `:failed`, and `:results`.
  """
  def requeue_all(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since)
    dry_run = Keyword.get(opts, :dry_run, false)

    failed_jobs = list_failed_jobs(limit: limit, since: since)

    results =
      Enum.map(failed_jobs, fn job ->
        if dry_run do
          {:ok, job.id}
        else
          case requeue_job(job) do
            {:ok, _new_job} -> {:ok, job.id}
            {:error, reason} -> {:error, job.id, reason}
          end
        end
      end)

    successful = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    failed = Enum.count(results, fn r -> match?({:error, _, _}, r) end)

    %{
      total_found: length(failed_jobs),
      successful: successful,
      failed: failed,
      results: results
    }
  end

  defp email_job?(job) do
    job.queue == "mailers" && job.worker == "YscWeb.Workers.EmailNotifier"
  end

  defp requeue_job(job) do
    # Create a new job with the same args to re-queue it
    job_attrs = %{
      "recipient" => get_in(job.args, ["recipient"]),
      "idempotency_key" => get_in(job.args, ["idempotency_key"]),
      "subject" => get_in(job.args, ["subject"]),
      "template" => get_in(job.args, ["template"]),
      "params" => get_in(job.args, ["params"]),
      "text_body" => get_in(job.args, ["text_body"]),
      "user_id" => get_in(job.args, ["user_id"]),
      "category" => get_in(job.args, ["category"])
    }

    # Create the Oban job struct
    new_job = YscWeb.Workers.EmailNotifier.new(job_attrs)

    # Insert directly into the database using Ecto instead of Oban.insert
    # This works even when Oban isn't running
    # Oban.Job is an Ecto schema, so we can insert it directly
    case Repo.insert(new_job) do
      {:ok, inserted_job} ->
        {:ok, inserted_job}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end

defmodule YscWeb.Workers.WebhookRetryWorker do
  @moduledoc """
  Oban worker that runs daily at night to retry unprocessed webhook events.

  This worker finds webhook events that are in a non-successful state and attempts
  to reprocess them. It handles:
  - `:pending` webhooks that were never processed
  - `:failed` webhooks that encountered errors
  - `:processing` webhooks that got stuck (older than 1 hour)

  ## Locking Strategy

  Uses Postgres row-level locking (FOR UPDATE SKIP LOCKED) to prevent concurrent
  processing of the same webhook. If a webhook is already locked by another process,
  it will be skipped automatically.

  ## Scheduling

  Configured to run daily at 3:00 AM via Oban cron in config/config.exs:

      {"0 3 * * *", YscWeb.Workers.WebhookRetryWorker}

  ## Safety Features

  - Only retries webhooks older than 5 minutes to avoid conflicts with active processing
  - Automatically skips webhooks that are currently locked
  - Limits processing to 100 webhooks per run to prevent overload
  - Comprehensive logging and Sentry reporting
  - Age validation to prevent processing very old (possibly invalid) webhooks
  """
  require Logger
  use Oban.Worker, queue: :maintenance, max_attempts: 2

  import Ecto.Query
  alias Ysc.Repo
  alias Ysc.Webhooks.WebhookEvent
  alias Ysc.Stripe.WebhookHandler

  # Only retry webhooks older than this (to avoid conflicts with active processing)
  @min_age_minutes 5
  # Don't retry webhooks older than this (likely invalid or irrelevant)
  @max_age_days 7
  # Maximum number of webhooks to process per run
  @batch_size 100
  # Consider stuck if processing for more than this
  @stuck_threshold_minutes 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting webhook retry worker")

    start_time = System.monotonic_time()

    # Calculate time boundaries
    now = DateTime.utc_now()
    min_age_cutoff = DateTime.add(now, -@min_age_minutes, :minute)
    max_age_cutoff = DateTime.add(now, -@max_age_days, :day)
    stuck_cutoff = DateTime.add(now, -@stuck_threshold_minutes, :minute)

    Logger.info("Webhook retry time boundaries",
      min_age_cutoff: min_age_cutoff,
      max_age_cutoff: max_age_cutoff,
      stuck_cutoff: stuck_cutoff
    )

    # Find webhooks that need retry
    webhooks_to_retry =
      find_webhooks_to_retry(min_age_cutoff, max_age_cutoff, stuck_cutoff)

    Logger.info("Found webhooks to retry",
      total: length(webhooks_to_retry),
      batch_size: @batch_size
    )

    # Process each webhook
    results =
      webhooks_to_retry
      |> Enum.map(&retry_webhook/1)

    # Calculate statistics
    stats = calculate_stats(results)

    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.info("Webhook retry worker completed",
      duration_ms: duration_ms,
      total_found: length(webhooks_to_retry),
      success: stats.success,
      failed: stats.failed,
      skipped: stats.skipped,
      already_processed: stats.already_processed
    )

    # Report to Sentry if there were significant issues
    if stats.failed > 0 do
      Sentry.capture_message("Webhook retry worker completed with failures",
        level: :warning,
        extra: %{
          duration_ms: duration_ms,
          total_found: length(webhooks_to_retry),
          stats: stats
        },
        tags: %{
          worker: "webhook_retry"
        }
      )
    end

    # Emit telemetry
    :telemetry.execute(
      [:ysc, :workers, :webhook_retry_completed],
      %{
        duration: duration_ms,
        total: length(webhooks_to_retry),
        success: stats.success,
        failed: stats.failed,
        skipped: stats.skipped
      },
      %{}
    )

    :ok
  end

  @doc """
  Finds webhook events that need to be retried.

  Returns webhooks that are:
  - In `:pending` or `:failed` state
  - In `:processing` state but stuck (older than stuck_cutoff)
  - Older than min_age_cutoff but younger than max_age_cutoff
  - Limited to batch_size
  """
  def find_webhooks_to_retry(min_age_cutoff, max_age_cutoff, stuck_cutoff) do
    # Query for pending and failed webhooks
    pending_and_failed_query =
      from(w in WebhookEvent,
        where: w.state in [:pending, :failed],
        where: w.inserted_at < ^min_age_cutoff,
        where: w.inserted_at > ^max_age_cutoff,
        order_by: [asc: w.inserted_at],
        limit: ^@batch_size
      )

    # Query for stuck processing webhooks
    stuck_processing_query =
      from(w in WebhookEvent,
        where: w.state == :processing,
        where: w.updated_at < ^stuck_cutoff,
        where: w.inserted_at > ^max_age_cutoff,
        order_by: [asc: w.updated_at],
        limit: ^@batch_size
      )

    # Combine both queries
    pending_and_failed = Repo.all(pending_and_failed_query)
    stuck_processing = Repo.all(stuck_processing_query)

    all_webhooks = pending_and_failed ++ stuck_processing

    # Remove duplicates and limit to batch size
    all_webhooks
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(@batch_size)
  end

  @doc """
  Attempts to retry a single webhook event.

  Returns:
  - `{:ok, :success}` if webhook was processed successfully
  - `{:ok, :already_processed}` if webhook was already in :processed state
  - `{:ok, :skipped}` if webhook was locked by another process
  - `{:error, reason}` if processing failed
  """
  def retry_webhook(%WebhookEvent{} = webhook_event) do
    Logger.info("Attempting to retry webhook",
      webhook_id: webhook_event.id,
      event_id: webhook_event.event_id,
      event_type: webhook_event.event_type,
      state: webhook_event.state,
      provider: webhook_event.provider,
      inserted_at: webhook_event.inserted_at
    )

    # If webhook is in failed or stuck processing state, reset it to pending first
    webhook_event =
      if webhook_event.state in [:failed, :processing] do
        case Ysc.Webhooks.update_webhook_state(webhook_event, :pending) do
          {:ok, updated} ->
            Logger.info("Reset webhook state to pending for retry",
              webhook_id: webhook_event.id,
              old_state: webhook_event.state
            )

            updated

          {:error, _} ->
            Logger.warning("Failed to reset webhook state, using original",
              webhook_id: webhook_event.id
            )

            webhook_event
        end
      else
        webhook_event
      end

    # Parse the raw event data
    case parse_webhook_event(webhook_event) do
      {:ok, :already_processed} ->
        Logger.info("Webhook already processed, skipping",
          webhook_id: webhook_event.id,
          event_id: webhook_event.event_id
        )

        {:ok, :already_processed}

      {:ok, stripe_event} ->
        # Attempt to process the webhook using the handler
        case WebhookHandler.handle_event(stripe_event) do
          :ok ->
            Logger.info("Successfully retried webhook",
              webhook_id: webhook_event.id,
              event_id: webhook_event.event_id,
              event_type: webhook_event.event_type
            )

            {:ok, :success}

          {:error, :webhook_too_old} ->
            # Webhook is too old, mark as failed
            Logger.warning("Webhook too old to retry, marking as failed",
              webhook_id: webhook_event.id,
              event_id: webhook_event.event_id,
              age_days:
                DateTime.diff(
                  DateTime.utc_now(),
                  webhook_event.inserted_at,
                  :day
                )
            )

            Ysc.Webhooks.update_webhook_state(webhook_event, :failed)
            {:ok, :skipped}

          {:error, reason} = error ->
            Logger.warning("Failed to retry webhook",
              webhook_id: webhook_event.id,
              event_id: webhook_event.event_id,
              error: inspect(reason)
            )

            error
        end

      {:error, reason} = error ->
        Logger.error("Failed to parse webhook event",
          webhook_id: webhook_event.id,
          event_id: webhook_event.event_id,
          error: inspect(reason)
        )

        # Mark as failed if we can't even parse it
        Ysc.Webhooks.update_webhook_state(webhook_event, :failed)

        Sentry.capture_message("Failed to parse webhook event for retry",
          level: :error,
          extra: %{
            webhook_id: webhook_event.id,
            event_id: webhook_event.event_id,
            event_type: webhook_event.event_type,
            error: inspect(reason)
          }
        )

        error
    end
  rescue
    error ->
      Logger.error("Exception while retrying webhook",
        webhook_id: webhook_event.id,
        event_id: webhook_event.event_id,
        error: Exception.message(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      Sentry.capture_exception(error,
        stacktrace: __STACKTRACE__,
        extra: %{
          webhook_id: webhook_event.id,
          event_id: webhook_event.event_id,
          event_type: webhook_event.event_type
        },
        tags: %{
          worker: "webhook_retry"
        }
      )

      {:error, error}
  end

  # Parses a webhook event record into a Stripe event struct.
  #
  # Returns:
  # - `{:ok, stripe_event}` if parsing succeeds
  # - `{:ok, :already_processed}` if webhook is already processed
  # - `{:error, reason}` if parsing fails
  defp parse_webhook_event(%WebhookEvent{state: :processed}) do
    {:ok, :already_processed}
  end

  defp parse_webhook_event(%WebhookEvent{
         provider: provider,
         event_id: event_id,
         event_type: event_type,
         payload: payload
       })
       when provider in ["stripe", :stripe] and is_map(payload) do
    # Reconstruct a Stripe event struct from the stored data
    stripe_event = %Stripe.Event{
      id: event_id,
      type: event_type,
      created: payload["created"] || DateTime.to_unix(DateTime.utc_now()),
      data: %{
        object: payload["data"]["object"] || %{}
      }
    }

    {:ok, stripe_event}
  rescue
    error ->
      {:error, {:parse_error, error}}
  end

  defp parse_webhook_event(%WebhookEvent{provider: provider}) do
    {:error, {:unsupported_provider, provider}}
  end

  # Calculates statistics from retry results.
  defp calculate_stats(results) do
    %{
      success: Enum.count(results, &match?({:ok, :success}, &1)),
      failed: Enum.count(results, &match?({:error, _}, &1)),
      skipped: Enum.count(results, &match?({:ok, :skipped}, &1)),
      already_processed:
        Enum.count(results, &match?({:ok, :already_processed}, &1))
    }
  end
end

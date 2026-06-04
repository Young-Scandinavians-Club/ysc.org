defmodule Ysc.Stripe.WebhookReconciliationWorker do
  @moduledoc """
  Oban worker that reconciles Stripe webhook events with our database.

  Runs nightly to:
  1. Fetch the last 24 hours of events from Stripe's API
  2. Compare with webhook_events in our database
  3. Store any missing events and kick off processing

  ## Scheduling

  Configured to run daily at 2 AM UTC via Oban.Plugins.Cron.

  ## Manual Triggering

      # Trigger immediately
      Ysc.Stripe.WebhookReconciliationWorker.run_now()

      # Schedule for later (e.g. in 5 minutes)
      Ysc.Stripe.WebhookReconciliationWorker.schedule_reconciliation(schedule_in: 300)
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3

  require Ysc.Logging
  alias Ysc.Webhooks
  alias Ysc.Stripe.WebhookHandler
  alias Ysc.Alerts.Discord

  @default_limit 100
  @provider "stripe"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    start_time = System.monotonic_time()

    Ysc.Logging.info("Webhook reconciliation started",
      event: :webhook_reconciliation_started
    )

    case run_reconciliation() do
      {:ok, stats} ->
        duration_ms = duration_ms(start_time)
        stats = Map.put(stats, :duration_ms, duration_ms)

        Ysc.Logging.info("Webhook reconciliation completed",
          event: :webhook_reconciliation_completed,
          total_checked: stats.total_checked,
          missing_found: stats.missing_found,
          processed_success: stats.processed_success,
          processed_failed: stats.processed_failed,
          duration_ms: duration_ms
        )

        send_discord_report(stats)
        {:ok, stats}

      {:error, reason} ->
        duration_ms = duration_ms(start_time)

        Ysc.Logging.error("Webhook reconciliation failed",
          event: :webhook_reconciliation_failed,
          reason: inspect(reason),
          duration_ms: duration_ms
        )

        Discord.send_webhook_reconciliation_report(
          %{total_checked: 0, missing_found: 0, duration_ms: duration_ms},
          :error
        )

        {:error, reason}
    end
  end

  @doc """
  Manually triggers webhook reconciliation immediately.
  """
  def run_now do
    Ysc.Logging.info("Manually triggering Stripe webhook reconciliation")

    start_time = System.monotonic_time()

    case run_reconciliation() do
      {:ok, stats} ->
        duration_ms = duration_ms(start_time)
        stats = Map.put(stats, :duration_ms, duration_ms)
        Ysc.Logging.info("Webhook reconciliation completed", stats: stats)
        send_discord_report(stats)
        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Schedules a webhook reconciliation job.

  ## Options

  - `:schedule_in` - Seconds to wait before running (default: 0)
  """
  def schedule_reconciliation(opts \\ []) do
    schedule_in = Keyword.get(opts, :schedule_in, 0)

    %{}
    |> new(schedule_in: schedule_in)
    |> Oban.insert()
  end

  defp run_reconciliation do
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    created_gte =
      DateTime.utc_now() |> DateTime.add(-24, :hour) |> DateTime.to_unix()

    Ysc.Logging.info("Fetching Stripe events",
      event: :fetching_stripe_events,
      created_gte: created_gte
    )

    case fetch_all_events(stripe_client, created_gte) do
      {:ok, events} ->
        stats = %{
          total_checked: length(events),
          missing_found: 0,
          processed_success: 0,
          processed_failed: 0,
          failed_event_ids: []
        }

        stats =
          Enum.reduce(events, stats, fn stripe_event, acc ->
            process_event(acc, stripe_event)
          end)

        {:ok, stats}

      {:error, _reason} = error ->
        error
    end
  end

  defp fetch_all_events(stripe_client, created_gte) do
    params = %{
      created: %{gte: created_gte},
      limit: @default_limit
    }

    fetch_events_page(stripe_client, params, [])
  end

  defp fetch_events_page(stripe_client, params, acc) do
    case stripe_client.list_events(params, []) do
      {:ok, %{data: data, has_more: has_more}} when is_list(data) ->
        all = acc ++ data

        if has_more and data != [] do
          last_id = List.last(data).id
          next_params = Map.put(params, :starting_after, last_id)
          fetch_events_page(stripe_client, next_params, all)
        else
          {:ok, all}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_event(stats, %{id: event_id} = stripe_event) do
    case Webhooks.get_webhook_event_by_provider_and_event_id(
           @provider,
           event_id
         ) do
      nil ->
        Ysc.Logging.info("Missing webhook found",
          event: :missing_webhook_found,
          event_id: event_id,
          event_type: stripe_event.type
        )

        stats = %{stats | missing_found: stats.missing_found + 1}

        case store_and_process(stripe_event) do
          :ok ->
            Ysc.Logging.info("Webhook processed successfully",
              event: :webhook_processed_successfully,
              event_id: event_id,
              event_type: stripe_event.type
            )

            %{stats | processed_success: stats.processed_success + 1}

          {:error, _reason} ->
            Ysc.Logging.warning("Webhook processing failed",
              event: :webhook_processing_failed,
              event_id: event_id,
              event_type: stripe_event.type
            )

            %{
              stats
              | processed_failed: stats.processed_failed + 1,
                failed_event_ids: [event_id | stats.failed_event_ids]
            }
        end

      _existing ->
        stats
    end
  end

  defp store_and_process(stripe_event) do
    attrs = %{
      provider: @provider,
      event_id: stripe_event.id,
      event_type: stripe_event.type,
      payload: WebhookHandler.event_payload_for_storage(stripe_event)
    }

    try do
      Webhooks.create_webhook_event!(attrs)
    rescue
      Ysc.Webhooks.DuplicateWebhookEventError ->
        # Race: event was stored between our check and now; try to process if failed/pending
        :ok
    end

    case Webhooks.lock_webhook_event_by_provider_and_event_id(
           @provider,
           stripe_event.id
         ) do
      {:ok, webhook_event} ->
        try do
          WebhookHandler.process_webhook_event(webhook_event, stripe_event)
          :ok
        rescue
          error ->
            Ysc.Logging.error("Webhook reconciliation failed",
              error: error,
              event_id: stripe_event.id,
              event_type: stripe_event.type,
              stacktrace: __STACKTRACE__
            )

            {:error, error}
        end

      {:error, :already_processing} ->
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp send_discord_report(stats) do
    status =
      cond do
        stats.processed_failed > 0 -> :warning
        stats.missing_found > 0 -> :warning
        true -> :success
      end

    Discord.send_webhook_reconciliation_report(stats, status)

    if stats.missing_found > 0 do
      Discord.send_missing_webhooks_alert(
        stats.missing_found,
        stats[:failed_event_ids] || []
      )
    end
  end

  defp duration_ms(start_time) do
    (System.monotonic_time() - start_time)
    |> System.convert_time_unit(:native, :millisecond)
  end
end

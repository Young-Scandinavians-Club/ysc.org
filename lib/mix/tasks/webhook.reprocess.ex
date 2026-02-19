defmodule Mix.Tasks.Webhook.Reprocess do
  @moduledoc """
  Mix task for re-processing failed webhook events and for reprocessing pending/processing (stuck) webhooks.

  ## Examples:

      # List all failed webhooks
      mix webhook.reprocess list

      # List failed webhooks for a specific provider
      mix webhook.reprocess list --provider stripe

      # List webhooks that are pending or stuck in processing (e.g. Stripe)
      mix webhook.reprocess list-pending --provider stripe

      # Re-process all Stripe webhooks that are :pending or :processing
      mix webhook.reprocess pending --provider stripe

      # Re-process with a limit and dry run
      mix webhook.reprocess pending --provider stripe --limit 10 --dry-run

      # Show statistics about failed webhooks
      mix webhook.reprocess stats

      # Re-process a specific webhook by ID
      mix webhook.reprocess single WEBHOOK_ID

      # Re-process all failed webhooks
      mix webhook.reprocess all

      # Reset a failed webhook to pending state
      mix webhook.reprocess reset WEBHOOK_ID
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Re-process failed webhook events"

  def run(args) do
    # Start the application to ensure all dependencies are loaded
    Mix.Task.run("app.start")

    case args do
      ["list" | opts] ->
        list_failed_webhooks(opts)

      ["list-pending" | opts] ->
        list_pending_or_processing_webhooks(opts)

      ["stats"] ->
        show_stats()

      ["single", webhook_id] ->
        reprocess_single_webhook(webhook_id)

      ["all" | opts] ->
        reprocess_all_webhooks(opts)

      ["pending" | opts] ->
        reprocess_pending_or_processing_webhooks(opts)

      ["reset", webhook_id] ->
        reset_webhook(webhook_id)

      _ ->
        show_help()
    end
  end

  defp list_failed_webhooks(opts) do
    opts = parse_opts(opts)

    Ysc.Logging.info("Listing failed webhook events...")

    failed_webhooks = Ysc.Webhooks.Reprocessor.list_failed_webhooks(opts)

    if Enum.empty?(failed_webhooks) do
      Ysc.Logging.info("No failed webhook events found.")
    else
      Ysc.Logging.info(
        "Found #{length(failed_webhooks)} failed webhook events:"
      )

      Ysc.Logging.info("")

      Enum.each(failed_webhooks, fn webhook ->
        Ysc.Logging.info("ID: #{webhook.id}")
        Ysc.Logging.info("  Provider: #{webhook.provider}")
        Ysc.Logging.info("  Event Type: #{webhook.event_type}")
        Ysc.Logging.info("  Event ID: #{webhook.event_id}")
        Ysc.Logging.info("  Failed At: #{webhook.updated_at}")
        Ysc.Logging.info("  Created At: #{webhook.inserted_at}")
        Ysc.Logging.info("")
      end)
    end
  end

  defp show_stats do
    Ysc.Logging.info("Failed webhook statistics:")
    Ysc.Logging.info("")

    stats = Ysc.Webhooks.Reprocessor.get_failed_webhook_stats()

    Ysc.Logging.info("Total Failed: #{stats.total_failed}")
    Ysc.Logging.info("Recent Failures (24h): #{stats.recent_failures_24h}")
    Ysc.Logging.info("")

    if not Enum.empty?(stats.by_provider) do
      Ysc.Logging.info("By Provider:")

      Enum.each(stats.by_provider, fn {provider, count} ->
        Ysc.Logging.info("  #{provider}: #{count}")
      end)

      Ysc.Logging.info("")
    end

    if not Enum.empty?(stats.by_event_type) do
      Ysc.Logging.info("By Event Type:")

      Enum.each(stats.by_event_type, fn {event_type, count} ->
        Ysc.Logging.info("  #{event_type}: #{count}")
      end)

      Ysc.Logging.info("")
    end
  end

  defp reprocess_single_webhook(webhook_id) do
    Ysc.Logging.info("Re-processing webhook: #{webhook_id}")

    case Ysc.Webhooks.Reprocessor.reprocess_webhook(webhook_id) do
      {:ok, result} ->
        Ysc.Logging.info("✅ Successfully re-processed webhook #{webhook_id}")
        Ysc.Logging.info("Result: #{inspect(result)}")

      {:error, :not_found} ->
        Ysc.Logging.error("❌ Webhook #{webhook_id} not found")

      {:error, {:not_failed, state}} ->
        Ysc.Logging.error(
          "❌ Webhook #{webhook_id} is not in failed state (current state: #{state})"
        )

      {:error, reason} ->
        Ysc.Logging.error(
          "❌ Failed to re-process webhook #{webhook_id}: #{inspect(reason)}"
        )
    end
  end

  defp reprocess_all_webhooks(opts) do
    opts = parse_opts(opts)

    if opts[:dry_run] do
      Ysc.Logging.info("🔍 Dry run - showing what would be processed...")
    else
      Ysc.Logging.info("Re-processing all failed webhook events...")
    end

    result = Ysc.Webhooks.Reprocessor.reprocess_all_failed_webhooks(opts)

    Ysc.Logging.info("")
    Ysc.Logging.info("Summary: #{result.summary}")
    Ysc.Logging.info("Total Found: #{result.total_found}")

    if not opts[:dry_run] do
      Ysc.Logging.info("Successful: #{result.successful}")
      Ysc.Logging.info("Failed: #{result.failed}")

      if result.failed > 0 do
        Ysc.Logging.info("")
        Ysc.Logging.info("Failed webhook details:")

        Enum.each(result.results, fn
          {:ok, _} -> :ok
          {:error, reason} -> Ysc.Logging.error("  #{inspect(reason)}")
        end)
      end
    end
  end

  defp list_pending_or_processing_webhooks(opts) do
    opts = parse_opts(opts)

    Ysc.Logging.info("Listing pending/processing webhook events...")

    webhooks =
      Ysc.Webhooks.Reprocessor.list_pending_or_processing_webhooks(opts)

    if Enum.empty?(webhooks) do
      Ysc.Logging.info("No pending or processing webhook events found.")
    else
      Ysc.Logging.info(
        "Found #{length(webhooks)} pending/processing webhook events:"
      )

      Ysc.Logging.info("")

      Enum.each(webhooks, fn webhook ->
        Ysc.Logging.info("ID: #{webhook.id}")
        Ysc.Logging.info("  Provider: #{webhook.provider}")
        Ysc.Logging.info("  Event Type: #{webhook.event_type}")
        Ysc.Logging.info("  Event ID: #{webhook.event_id}")
        Ysc.Logging.info("  State: #{webhook.state}")
        Ysc.Logging.info("  Updated At: #{webhook.updated_at}")
        Ysc.Logging.info("  Created At: #{webhook.inserted_at}")
        Ysc.Logging.info("")
      end)
    end
  end

  defp reprocess_pending_or_processing_webhooks(opts) do
    opts = parse_opts(opts)

    if opts[:dry_run] do
      Ysc.Logging.info("🔍 Dry run - showing what would be processed...")
    else
      Ysc.Logging.info("Re-processing all pending/processing webhook events...")
    end

    result =
      Ysc.Webhooks.Reprocessor.reprocess_all_pending_or_processing_webhooks(
        opts
      )

    Ysc.Logging.info("")
    Ysc.Logging.info("Summary: #{result.summary}")
    Ysc.Logging.info("Total Found: #{result.total_found}")

    if not opts[:dry_run] and Map.has_key?(result, :successful) do
      Ysc.Logging.info("Successful: #{result.successful}")
      Ysc.Logging.info("Failed: #{result.failed}")

      if result.failed > 0 do
        Ysc.Logging.info("")
        Ysc.Logging.info("Failed webhook details:")

        Enum.each(result.results, fn
          {:ok, _} -> :ok
          {:error, reason} -> Ysc.Logging.error("  #{inspect(reason)}")
        end)
      end
    end
  end

  defp reset_webhook(webhook_id) do
    Ysc.Logging.info("Resetting webhook #{webhook_id} to pending state...")

    case Ysc.Webhooks.Reprocessor.reset_webhook_to_pending(webhook_id) do
      {:ok, _webhook} ->
        Ysc.Logging.info(
          "✅ Successfully reset webhook #{webhook_id} to pending state"
        )

      {:error, :not_found} ->
        Ysc.Logging.error("❌ Webhook #{webhook_id} not found")

      {:error, {:not_failed, state}} ->
        Ysc.Logging.error(
          "❌ Webhook #{webhook_id} is not in failed state (current state: #{state})"
        )

      {:error, changeset} ->
        Ysc.Logging.error(
          "❌ Failed to reset webhook #{webhook_id}: #{inspect(changeset)}"
        )
    end
  end

  defp parse_opts(opts) do
    opts
    |> Enum.chunk_every(2)
    |> Enum.reduce([], fn
      ["--provider", provider], acc ->
        Keyword.put(acc, :provider, provider)

      ["--event-type", event_type], acc ->
        Keyword.put(acc, :event_type, event_type)

      ["--limit", limit], acc ->
        Keyword.put(acc, :limit, String.to_integer(limit))

      ["--dry-run"], acc ->
        Keyword.put(acc, :dry_run, true)

      _, acc ->
        acc
    end)
  end

  defp show_help do
    Ysc.Logging.info("""
    Webhook Re-processor

    Usage:
      mix webhook.reprocess <command> [options]

    Commands:
      list                    List all failed webhook events
      list-pending             List webhooks in :pending or :processing state
      stats                   Show statistics about failed webhooks
      single <webhook_id>     Re-process a specific failed webhook
      all                     Re-process all failed webhooks
      pending                 Re-process all :pending or :processing webhooks (e.g. stripe)
      reset <webhook_id>      Reset a failed webhook to pending state

    Options:
      --provider <provider>   Filter by provider (e.g., stripe)
      --event-type <type>     Filter by event type (e.g., invoice.payment_succeeded)
      --limit <number>        Limit number of webhooks (default: 50 for all/pending, 100 for list)
      --dry-run               Show what would be processed without actually processing

    Examples:
      mix webhook.reprocess list
      mix webhook.reprocess list-pending --provider stripe
      mix webhook.reprocess pending --provider stripe
      mix webhook.reprocess pending --provider stripe --limit 10 --dry-run
      mix webhook.reprocess stats
      mix webhook.reprocess single WEBHOOK_ID
      mix webhook.reprocess all --limit 10
      mix webhook.reprocess reset WEBHOOK_ID
    """)
  end
end

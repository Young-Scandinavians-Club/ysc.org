defmodule Mix.Tasks.Webhook.Reprocess do
  @moduledoc """
  Mix task for re-processing failed webhook events.

  ## Examples:

      # List all failed webhooks
      mix webhook.reprocess list

      # List failed webhooks for a specific provider
      mix webhook.reprocess list --provider stripe

      # List failed webhooks for a specific event type
      mix webhook.reprocess list --event-type invoice.payment_succeeded

      # Show statistics about failed webhooks
      mix webhook.reprocess stats

      # Re-process a specific webhook by ID
      mix webhook.reprocess single WEBHOOK_ID

      # Re-process all failed webhooks
      mix webhook.reprocess all

      # Re-process all failed webhooks with a limit
      mix webhook.reprocess all --limit 10

      # Re-process all failed Stripe invoice payment webhooks
      mix webhook.reprocess all --provider stripe --event-type invoice.payment_succeeded

      # Dry run - show what would be processed without actually processing
      mix webhook.reprocess all --dry-run

      # Reset a failed webhook to pending state
      mix webhook.reprocess reset WEBHOOK_ID
  """

  use Mix.Task
  require Logger

  @shortdoc "Re-process failed webhook events"

  def run(args) do
    # Start the application to ensure all dependencies are loaded
    Mix.Task.run("app.start")

    case args do
      ["list" | opts] ->
        list_failed_webhooks(opts)

      ["stats"] ->
        show_stats()

      ["single", webhook_id] ->
        reprocess_single_webhook(webhook_id)

      ["all" | opts] ->
        reprocess_all_webhooks(opts)

      ["reset", webhook_id] ->
        reset_webhook(webhook_id)

      _ ->
        show_help()
    end
  end

  defp list_failed_webhooks(opts) do
    opts = parse_opts(opts)

    Logger.info("Listing failed webhook events...")

    failed_webhooks = Ysc.Webhooks.Reprocessor.list_failed_webhooks(opts)

    if Enum.empty?(failed_webhooks) do
      Logger.info("No failed webhook events found.")
    else
      Logger.info("Found #{length(failed_webhooks)} failed webhook events:")
      Logger.info("")

      Enum.each(failed_webhooks, fn webhook ->
        Logger.info("ID: #{webhook.id}")
        Logger.info("  Provider: #{webhook.provider}")
        Logger.info("  Event Type: #{webhook.event_type}")
        Logger.info("  Event ID: #{webhook.event_id}")
        Logger.info("  Failed At: #{webhook.updated_at}")
        Logger.info("  Created At: #{webhook.inserted_at}")
        Logger.info("")
      end)
    end
  end

  defp show_stats do
    Logger.info("Failed webhook statistics:")
    Logger.info("")

    stats = Ysc.Webhooks.Reprocessor.get_failed_webhook_stats()

    Logger.info("Total Failed: #{stats.total_failed}")
    Logger.info("Recent Failures (24h): #{stats.recent_failures_24h}")
    Logger.info("")

    if not Enum.empty?(stats.by_provider) do
      Logger.info("By Provider:")

      Enum.each(stats.by_provider, fn {provider, count} ->
        Logger.info("  #{provider}: #{count}")
      end)

      Logger.info("")
    end

    if not Enum.empty?(stats.by_event_type) do
      Logger.info("By Event Type:")

      Enum.each(stats.by_event_type, fn {event_type, count} ->
        Logger.info("  #{event_type}: #{count}")
      end)

      Logger.info("")
    end
  end

  defp reprocess_single_webhook(webhook_id) do
    Logger.info("Re-processing webhook: #{webhook_id}")

    case Ysc.Webhooks.Reprocessor.reprocess_webhook(webhook_id) do
      {:ok, result} ->
        Logger.info("✅ Successfully re-processed webhook #{webhook_id}")
        Logger.info("Result: #{inspect(result)}")

      {:error, :not_found} ->
        Logger.error("❌ Webhook #{webhook_id} not found")

      {:error, {:not_failed, state}} ->
        Logger.error(
          "❌ Webhook #{webhook_id} is not in failed state (current state: #{state})"
        )

      {:error, reason} ->
        Logger.error(
          "❌ Failed to re-process webhook #{webhook_id}: #{inspect(reason)}"
        )
    end
  end

  defp reprocess_all_webhooks(opts) do
    opts = parse_opts(opts)

    if opts[:dry_run] do
      Logger.info("🔍 Dry run - showing what would be processed...")
    else
      Logger.info("Re-processing all failed webhook events...")
    end

    result = Ysc.Webhooks.Reprocessor.reprocess_all_failed_webhooks(opts)

    Logger.info("")
    Logger.info("Summary: #{result.summary}")
    Logger.info("Total Found: #{result.total_found}")

    if not opts[:dry_run] do
      Logger.info("Successful: #{result.successful}")
      Logger.info("Failed: #{result.failed}")

      if result.failed > 0 do
        Logger.info("")
        Logger.info("Failed webhook details:")

        Enum.each(result.results, fn
          {:ok, _} -> :ok
          {:error, reason} -> Logger.error("  #{inspect(reason)}")
        end)
      end
    end
  end

  defp reset_webhook(webhook_id) do
    Logger.info("Resetting webhook #{webhook_id} to pending state...")

    case Ysc.Webhooks.Reprocessor.reset_webhook_to_pending(webhook_id) do
      {:ok, _webhook} ->
        Logger.info(
          "✅ Successfully reset webhook #{webhook_id} to pending state"
        )

      {:error, :not_found} ->
        Logger.error("❌ Webhook #{webhook_id} not found")

      {:error, {:not_failed, state}} ->
        Logger.error(
          "❌ Webhook #{webhook_id} is not in failed state (current state: #{state})"
        )

      {:error, changeset} ->
        Logger.error(
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
    Logger.info("""
    Webhook Re-processor

    Usage:
      mix webhook.reprocess <command> [options]

    Commands:
      list                    List all failed webhook events
      stats                   Show statistics about failed webhooks
      single <webhook_id>     Re-process a specific webhook
      all                     Re-process all failed webhooks
      reset <webhook_id>      Reset a failed webhook to pending state

    Options:
      --provider <provider>   Filter by provider (e.g., stripe)
      --event-type <type>     Filter by event type (e.g., invoice.payment_succeeded)
      --limit <number>        Limit number of webhooks to process (default: 50 for all, 100 for list)
      --dry-run               Show what would be processed without actually processing

    Examples:
      mix webhook.reprocess list
      mix webhook.reprocess list --provider stripe
      mix webhook.reprocess stats
      mix webhook.reprocess single WEBHOOK_ID
      mix webhook.reprocess all --limit 10
      mix webhook.reprocess all --provider stripe --event-type invoice.payment_succeeded
      mix webhook.reprocess all --dry-run
      mix webhook.reprocess reset WEBHOOK_ID
    """)
  end
end

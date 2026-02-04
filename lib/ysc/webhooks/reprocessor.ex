defmodule Ysc.Webhooks.Reprocessor do
  @moduledoc """
  Utility module for re-processing failed webhook events.

  This module provides functions to:
  - List failed webhook events
  - Re-process individual failed webhooks
  - Re-process all failed webhooks
  - Get detailed information about webhook failures
  """

  alias Ysc.Webhooks.WebhookEvent
  alias Ysc.Webhooks
  alias Ysc.Stripe.WebhookHandler
  alias Ysc.ExpenseReports.QuickbooksWebhookHandler
  alias Ysc.Repo
  import Ecto.Query, warn: false

  @doc """
  Lists all failed webhook events.

  ## Options:
  - `:limit` - Maximum number of events to return (default: 100)
  - `:provider` - Filter by provider (e.g., "stripe")
  - `:event_type` - Filter by event type (e.g., "invoice.payment_succeeded")
  - `:since` - Only show events since this datetime
  """
  def list_failed_webhooks(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    provider = Keyword.get(opts, :provider)
    event_type = Keyword.get(opts, :event_type)
    since = Keyword.get(opts, :since)

    query =
      from(w in WebhookEvent,
        where: w.state == :failed,
        order_by: [desc: w.updated_at],
        limit: ^limit
      )

    query =
      if provider do
        where(query, [w], w.provider == ^provider)
      else
        query
      end

    query =
      if event_type do
        where(query, [w], w.event_type == ^event_type)
      else
        query
      end

    query =
      if since do
        where(query, [w], w.updated_at >= ^since)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets detailed information about a failed webhook event.
  """
  def get_failed_webhook_details(webhook_id) do
    case Repo.get(WebhookEvent, webhook_id) do
      nil ->
        {:error, :not_found}

      webhook_event ->
        {:ok, webhook_event}
    end
  end

  @doc """
  Re-processes a single failed webhook event.

  Returns:
  - `{:ok, result}` - If the webhook was successfully re-processed
  - `{:error, :not_found}` - If the webhook event doesn't exist
  - `{:error, :not_failed}` - If the webhook is not in failed state
  - `{:error, reason}` - If re-processing failed
  """
  def reprocess_webhook(webhook_id) do
    case Repo.get(WebhookEvent, webhook_id) do
      nil ->
        {:error, :not_found}

      %WebhookEvent{state: :failed} = webhook_event ->
        reprocess_webhook_event(webhook_event)

      %WebhookEvent{state: state} ->
        {:error, {:not_failed, state}}
    end
  end

  @doc """
  Re-processes all failed webhook events.

  ## Options:
  - `:limit` - Maximum number of events to process (default: 50)
  - `:provider` - Filter by provider (e.g., "stripe")
  - `:event_type` - Filter by event type (e.g., "invoice.payment_succeeded")
  - `:dry_run` - If true, only shows what would be processed without actually processing

  Returns a summary of the re-processing results.
  """
  def reprocess_all_failed_webhooks(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    provider = Keyword.get(opts, :provider)
    event_type = Keyword.get(opts, :event_type)
    dry_run = Keyword.get(opts, :dry_run, false)

    failed_webhooks =
      list_failed_webhooks(
        limit: limit,
        provider: provider,
        event_type: event_type
      )

    if dry_run do
      %{
        total_found: length(failed_webhooks),
        would_process: failed_webhooks,
        summary: "Dry run - no webhooks were actually processed"
      }
    else
      results = Enum.map(failed_webhooks, &reprocess_webhook_event/1)

      successful =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      failed = length(results) - successful

      %{
        total_found: length(failed_webhooks),
        successful: successful,
        failed: failed,
        results: results,
        summary:
          "Processed #{successful} webhooks successfully, #{failed} failed"
      }
    end
  end

  @doc """
  Re-processes failed webhooks for a specific provider and event type.

  This is useful for re-processing specific types of webhook failures,
  such as all failed Stripe invoice payment webhooks.
  """
  def reprocess_webhooks_by_type(provider, event_type, opts \\ []) do
    reprocess_all_failed_webhooks(
      Keyword.merge(opts, provider: provider, event_type: event_type)
    )
  end

  @doc """
  Gets statistics about failed webhooks.
  """
  def get_failed_webhook_stats do
    # Get total count of failed webhooks
    total_failed =
      from(w in WebhookEvent, where: w.state == :failed, select: count())
      |> Repo.one()

    # Get count by provider
    by_provider =
      from(w in WebhookEvent,
        where: w.state == :failed,
        group_by: w.provider,
        select: {w.provider, count()}
      )
      |> Repo.all()
      |> Enum.into(%{})

    # Get count by event type
    by_event_type =
      from(w in WebhookEvent,
        where: w.state == :failed,
        group_by: w.event_type,
        select: {w.event_type, count()}
      )
      |> Repo.all()
      |> Enum.into(%{})

    # Get recent failures (last 24 hours)
    since_24h = DateTime.add(DateTime.utc_now(), -24 * 60 * 60, :second)

    recent_failures =
      from(w in WebhookEvent,
        where: w.state == :failed and w.updated_at >= ^since_24h,
        select: count()
      )
      |> Repo.one()

    %{
      total_failed: total_failed,
      by_provider: by_provider,
      by_event_type: by_event_type,
      recent_failures_24h: recent_failures
    }
  end

  @doc """
  Resets a failed webhook to pending state so it can be re-processed by the normal webhook handler.
  """
  def reset_webhook_to_pending(webhook_id) do
    case Repo.get(WebhookEvent, webhook_id) do
      nil ->
        {:error, :not_found}

      %WebhookEvent{state: :failed} = webhook_event ->
        webhook_event
        |> Ecto.Changeset.change(%{state: :pending})
        |> Repo.update()

      %WebhookEvent{state: state} ->
        {:error, {:not_failed, state}}
    end
  end

  # Private function to actually re-process a webhook event
  defp reprocess_webhook_event(%WebhookEvent{} = webhook_event) do
    require Logger

    Logger.info("Re-processing failed webhook event",
      webhook_id: webhook_event.id,
      provider: webhook_event.provider,
      event_type: webhook_event.event_type,
      event_id: webhook_event.event_id
    )

    try do
      # Convert the stored payload back to a Stripe event-like structure
      # This is a simplified approach - in a real implementation, you might want
      # to store more structured data or have better deserialization
      case webhook_event.provider do
        provider when provider in ["stripe", :stripe] ->
          # For Stripe webhooks, we need to call the webhook handler directly
          # with the event type and data object from the payload
          result = process_stripe_webhook_from_payload(webhook_event)

          # Update the webhook state to processed
          case Webhooks.update_webhook_state(webhook_event, :processed) do
            {:ok, _updated_webhook} ->
              Logger.info("Successfully re-processed webhook event",
                webhook_id: webhook_event.id,
                event_type: webhook_event.event_type
              )

              {:ok, result}

            {:error, changeset} ->
              Logger.error(
                "Failed to update webhook state after successful re-processing",
                webhook_id: webhook_event.id,
                error: changeset
              )

              {:error, {:state_update_failed, changeset}}
          end

        provider when provider in ["quickbooks", :quickbooks] ->
          # For QuickBooks webhooks, call the webhook handler
          result = QuickbooksWebhookHandler.handle_webhook_event(webhook_event)

          # Update the webhook state to processed
          case Webhooks.update_webhook_state(webhook_event, :processed) do
            {:ok, _updated_webhook} ->
              Logger.info("Successfully re-processed QuickBooks webhook event",
                webhook_id: webhook_event.id,
                event_type: webhook_event.event_type
              )

              {:ok, result}

            {:error, changeset} ->
              Logger.error(
                "Failed to update webhook state after successful re-processing",
                webhook_id: webhook_event.id,
                error: changeset
              )

              {:error, {:state_update_failed, changeset}}
          end

        _ ->
          {:error, {:unsupported_provider, webhook_event.provider}}
      end
    rescue
      error ->
        Logger.error("Failed to re-process webhook event",
          webhook_id: webhook_event.id,
          error: Exception.message(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        {:error, {:processing_failed, Exception.message(error)}}
    end
  end

  # Private function to process Stripe webhook from stored payload
  defp process_stripe_webhook_from_payload(%WebhookEvent{
         payload: payload,
         event_type: event_type
       }) do
    require Logger

    # Extract the data object from the payload
    data_object = payload["data"]["object"]

    Logger.info("Processing Stripe webhook from payload",
      event_type: event_type,
      invoice_id: data_object["id"],
      customer_id: data_object["customer"],
      subscription_id: data_object["subscription"],
      amount_paid: data_object["amount_paid"]
    )

    # Call the webhook handler's handle function directly with the event type and data object
    # This bypasses the need to reconstruct the full Stripe.Event struct
    result =
      case event_type do
        "invoice.payment_succeeded" ->
          # Convert the data object to a Stripe.Invoice struct-like map
          invoice_data = convert_map_to_stripe_invoice(data_object)

          Logger.info("Calling webhook handler for invoice.payment_succeeded",
            invoice_id: invoice_data.id,
            customer_id: invoice_data.customer,
            subscription_id: invoice_data.subscription,
            amount_paid: invoice_data.amount_paid
          )

          WebhookHandler.handle_webhook_event(
            "invoice.payment_succeeded",
            invoice_data
          )

        "payment_intent.succeeded" ->
          # Convert the data object to a Stripe.PaymentIntent struct-like map
          payment_intent_data =
            convert_map_to_stripe_payment_intent(data_object)

          Logger.info("Calling webhook handler for payment_intent.succeeded",
            payment_intent_id: payment_intent_data.id,
            customer_id: payment_intent_data.customer,
            amount: payment_intent_data.amount
          )

          WebhookHandler.handle_webhook_event(
            "payment_intent.succeeded",
            payment_intent_data
          )

        _ ->
          # For other event types, try to call the handler with the raw data
          Logger.info("Calling webhook handler for unknown event type",
            event_type: event_type
          )

          WebhookHandler.handle_webhook_event(event_type, data_object)
      end

    Logger.info("Webhook handler result", result: result)
    result
  end

  # Helper function to convert map data to Stripe.Invoice-like structure
  defp convert_map_to_stripe_invoice(data) do
    # Create a struct-like map that matches what the webhook handler expects
    %{
      id: data["id"],
      customer: data["customer"],
      subscription: data["subscription"],
      amount_paid: data["amount_paid"],
      charge: data["charge"],
      description: data["description"],
      number: data["number"],
      metadata: data["metadata"] || %{}
    }
  end

  # Helper function to convert map data to Stripe.PaymentIntent-like structure
  defp convert_map_to_stripe_payment_intent(data) do
    %{
      id: data["id"],
      customer: data["customer"],
      amount: data["amount"],
      status: data["status"],
      description: data["description"],
      metadata: data["metadata"] || %{}
    }
  end
end

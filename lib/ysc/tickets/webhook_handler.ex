defmodule Ysc.Tickets.WebhookHandler do
  @moduledoc """
  Handles Stripe webhook events for ticket payments.

  This module processes:
  - payment_intent.succeeded: Complete ticket orders
  - payment_intent.payment_failed: Cancel ticket orders
  - payment_intent.canceled: Cancel ticket orders
  """

  require Logger

  alias Ysc.Tickets.StripeService

  @doc """
  Handles Stripe webhook events for ticket payments.
  """
  def handle_webhook_event(event_type, event_data) do
    case event_type do
      "payment_intent.succeeded" ->
        handle_payment_succeeded(event_data)

      "payment_intent.payment_failed" ->
        handle_payment_failed(event_data)

      "payment_intent.canceled" ->
        handle_payment_canceled(event_data)

      _ ->
        Logger.info("Unhandled ticket webhook event", event_type: event_type)
        :ok
    end
  end

  ## Private Functions

  defp handle_payment_succeeded(%{"id" => payment_intent_id}) do
    Logger.info("Processing successful ticket payment",
      payment_intent_id: payment_intent_id
    )

    case StripeService.process_successful_payment(payment_intent_id) do
      {:ok, ticket_order} ->
        Logger.info("Successfully processed ticket order payment",
          ticket_order_id: ticket_order.id,
          reference_id: ticket_order.reference_id,
          payment_intent_id: payment_intent_id
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to process ticket order payment",
          payment_intent_id: payment_intent_id,
          error: reason
        )

        :ok
    end
  end

  defp handle_payment_failed(%{"id" => payment_intent_id}) do
    Logger.info("Processing failed ticket payment",
      payment_intent_id: payment_intent_id
    )

    case StripeService.handle_failed_payment(
           payment_intent_id,
           "Payment failed"
         ) do
      {:ok, ticket_order} ->
        Logger.info("Successfully canceled ticket order due to payment failure",
          ticket_order_id: ticket_order.id,
          reference_id: ticket_order.reference_id,
          payment_intent_id: payment_intent_id
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to cancel ticket order after payment failure",
          payment_intent_id: payment_intent_id,
          error: reason
        )

        :ok
    end
  end

  defp handle_payment_canceled(%{"id" => payment_intent_id}) do
    Logger.info("Processing canceled ticket payment",
      payment_intent_id: payment_intent_id
    )

    case StripeService.handle_failed_payment(
           payment_intent_id,
           "Payment canceled"
         ) do
      {:ok, ticket_order} ->
        Logger.info(
          "Successfully canceled ticket order due to payment cancellation",
          ticket_order_id: ticket_order.id,
          reference_id: ticket_order.reference_id,
          payment_intent_id: payment_intent_id
        )

        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to cancel ticket order after payment cancellation",
          payment_intent_id: payment_intent_id,
          error: reason
        )

        :ok
    end
  end
end

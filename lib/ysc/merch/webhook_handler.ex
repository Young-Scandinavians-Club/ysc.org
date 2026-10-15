defmodule Ysc.Merch.WebhookHandler do
  @moduledoc """
  Handles Stripe PaymentIntent webhooks for merch orders (routed here by
  `Ysc.Stripe.WebhookHandler` when the Intent carries `merch_order_id`).

    * `payment_intent.succeeded` - fulfill the order
    * `payment_intent.canceled` - cancel the still-pending order
    * `payment_intent.payment_failed` - nothing: the member can retry on the
      same Intent, and the order stays pending until they do or it goes stale
  """
  require Ysc.Logging

  alias Ysc.Merch.{Fulfillment, Orders}

  def handle_webhook_event("payment_intent.succeeded", %{
        "id" => payment_intent_id
      }) do
    case Fulfillment.process_successful_payment(payment_intent_id) do
      {:ok, order} ->
        Ysc.Logging.info("Processed merch payment",
          order_id: order.id,
          reference_id: order.reference_id
        )

      {:error, reason} ->
        Ysc.Logging.warning("Could not process merch payment",
          payment_intent_id: payment_intent_id,
          error: inspect(reason)
        )
    end

    :ok
  end

  def handle_webhook_event("payment_intent.canceled", %{
        "id" => payment_intent_id
      }) do
    case Orders.get_order_by_payment_intent(payment_intent_id) do
      nil ->
        :ok

      order ->
        _ = Orders.cancel_pending(order, "Payment canceled")
        :ok
    end
  end

  def handle_webhook_event(event_type, _data) do
    Ysc.Logging.info("Unhandled merch webhook event", event_type: event_type)
    :ok
  end
end

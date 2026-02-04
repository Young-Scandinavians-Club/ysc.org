defmodule Ysc.Tickets.WebhookHandlerTest do
  @moduledoc """
  Tests for WebhookHandler module.

  These tests verify:
  - Webhook event routing
  - Event type handling
  - Error handling
  """
  use Ysc.DataCase, async: true

  import Mox

  alias Ysc.Tickets.WebhookHandler

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure StripeService to use the mock
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
    on_exit(fn -> Application.delete_env(:ysc, :stripe_client) end)
    :ok
  end

  describe "handle_webhook_event/2" do
    setup do
      # Configure StripeService to use the mock
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
      on_exit(fn -> Application.delete_env(:ysc, :stripe_client) end)
      :ok
    end

    test "handles payment_intent.succeeded event" do
      payment_intent_id = "pi_test_123"
      event_data = %{"id" => payment_intent_id}

      # Mock StripeService calls - return metadata without ticket_order_id to avoid ULID cast error
      # The handler will return :ok even if processing fails
      expect(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok, %{id: payment_intent_id, status: "succeeded", metadata: %{}}}
      end)

      result =
        WebhookHandler.handle_webhook_event(
          "payment_intent.succeeded",
          event_data
        )

      assert :ok == result
    end

    test "handles payment_intent.payment_failed event" do
      payment_intent_id = "pi_test_456"
      event_data = %{"id" => payment_intent_id}

      # Mock StripeService calls - return metadata without ticket_order_id to avoid ULID cast error
      expect(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok,
         %{
           id: payment_intent_id,
           status: "requires_payment_method",
           metadata: %{}
         }}
      end)

      result =
        WebhookHandler.handle_webhook_event(
          "payment_intent.payment_failed",
          event_data
        )

      assert :ok == result
    end

    test "handles payment_intent.canceled event" do
      payment_intent_id = "pi_test_789"
      event_data = %{"id" => payment_intent_id}

      # Mock StripeService calls - return metadata without ticket_order_id to avoid ULID cast error
      expect(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok, %{id: payment_intent_id, status: "canceled", metadata: %{}}}
      end)

      result =
        WebhookHandler.handle_webhook_event(
          "payment_intent.canceled",
          event_data
        )

      assert :ok == result
    end

    test "handles unknown event types" do
      # Verify the function returns :ok for unknown events
      result = WebhookHandler.handle_webhook_event("unknown.event", %{})
      assert :ok == result
    end

    test "returns :ok even when StripeService returns error" do
      payment_intent_id = "pi_test_error"
      event_data = %{"id" => payment_intent_id}

      # Mock StripeService to return error
      expect(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:error,
         %Stripe.Error{
           message: "Payment intent not found",
           source: :api,
           code: "resource_missing"
         }}
      end)

      # The handler should return :ok even if processing fails
      # This prevents webhook retries for non-retryable errors
      result =
        WebhookHandler.handle_webhook_event(
          "payment_intent.succeeded",
          event_data
        )

      assert :ok == result
    end
  end
end

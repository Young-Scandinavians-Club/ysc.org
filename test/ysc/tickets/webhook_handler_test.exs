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

  import Ysc.TicketsFixtures

  alias Ysc.Repo
  alias Ysc.Tickets.TicketOrder
  alias Ysc.Tickets.WebhookHandler

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure StripeService to use the mock
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    pin_stripe_mock!()
    :ok
  end

  defp pin_stripe_mock! do
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
  end

  describe "handle_webhook_event/2" do
    setup do
      # Configure StripeService to use the mock
      original_stripe_client = Application.get_env(:ysc, :stripe_client)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, original_stripe_client)
      end)

      pin_stripe_mock!()
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

      pin_stripe_mock!()

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

      pin_stripe_mock!()

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

      pin_stripe_mock!()

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
      pin_stripe_mock!()

      result =
        WebhookHandler.handle_webhook_event(
          "payment_intent.succeeded",
          event_data
        )

      assert :ok == result
    end

    test "payment_intent.payment_failed cancels ticket order when metadata references order" do
      Ysc.Ledgers.ensure_basic_accounts()

      Oban.Testing.with_testing_mode(:manual, fn ->
        ticket_order = ticket_order_fixture()
        payment_intent_id = "pi_failed_with_order_#{ticket_order.id}"

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
          assert id == payment_intent_id

          {:ok,
           %{
             id: id,
             status: "requires_payment_method",
             metadata: %{"ticket_order_id" => ticket_order.id}
           }}
        end)

        pin_stripe_mock!()

        assert :ok =
                 WebhookHandler.handle_webhook_event(
                   "payment_intent.payment_failed",
                   %{"id" => payment_intent_id}
                 )

        assert %TicketOrder{status: :cancelled} =
                 Repo.get!(TicketOrder, ticket_order.id)
      end)
    end

    test "payment_intent.canceled cancels ticket order when metadata references order" do
      Ysc.Ledgers.ensure_basic_accounts()

      Oban.Testing.with_testing_mode(:manual, fn ->
        ticket_order = ticket_order_fixture()
        payment_intent_id = "pi_canceled_with_order_#{ticket_order.id}"

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
          assert id == payment_intent_id

          {:ok,
           %{
             id: id,
             status: "canceled",
             metadata: %{"ticket_order_id" => ticket_order.id}
           }}
        end)

        pin_stripe_mock!()

        assert :ok =
                 WebhookHandler.handle_webhook_event(
                   "payment_intent.canceled",
                   %{"id" => payment_intent_id}
                 )

        assert %TicketOrder{status: :cancelled} =
                 Repo.get!(TicketOrder, ticket_order.id)
      end)
    end
  end
end

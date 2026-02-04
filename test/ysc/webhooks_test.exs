defmodule Ysc.WebhooksTest do
  @moduledoc """
  Tests for the Ysc.Webhooks context module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Webhooks

  describe "create_webhook_event!/1" do
    test "creates a webhook event" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_test123",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      event = Webhooks.create_webhook_event!(attrs)
      assert event.provider == :stripe
      assert event.event_id == "evt_test123"
      assert event.state == :pending
    end

    test "raises error for duplicate event" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_duplicate",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      Webhooks.create_webhook_event!(attrs)

      assert_raise Ysc.Webhooks.DuplicateWebhookEventError, fn ->
        Webhooks.create_webhook_event!(attrs)
      end
    end
  end

  describe "get_webhook_event/1" do
    test "returns webhook event by id" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_get",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      event = Webhooks.create_webhook_event!(attrs)
      found = Webhooks.get_webhook_event(event.id)
      assert found.id == event.id
    end

    test "returns nil for non-existent event" do
      assert Webhooks.get_webhook_event(Ecto.ULID.generate()) == nil
    end
  end

  describe "get_webhook_event_by_provider_and_event_id/2" do
    test "returns webhook event by provider and event_id" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_provider",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      event = Webhooks.create_webhook_event!(attrs)

      found =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          :stripe,
          "evt_provider"
        )

      assert found.id == event.id
    end

    test "returns nil for non-existent event" do
      assert Webhooks.get_webhook_event_by_provider_and_event_id(
               :stripe,
               "evt_nonexistent"
             ) ==
               nil
    end
  end

  describe "list_pending_webhook_events/1" do
    test "returns pending webhook events" do
      attrs1 = %{
        provider: :stripe,
        event_id: "evt_pending1",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      attrs2 = %{
        provider: :stripe,
        event_id: "evt_pending2",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test456"},
        state: :pending
      }

      _event1 = Webhooks.create_webhook_event!(attrs1)
      _event2 = Webhooks.create_webhook_event!(attrs2)

      events = Webhooks.list_pending_webhook_events()
      assert length(events) >= 2
    end

    test "respects limit parameter" do
      for i <- 1..5 do
        attrs = %{
          provider: :stripe,
          event_id: "evt_limit#{i}",
          event_type: "payment_intent.succeeded",
          payload: %{"id" => "pi_test#{i}"},
          state: :pending
        }

        Webhooks.create_webhook_event!(attrs)
      end

      events = Webhooks.list_pending_webhook_events(2)
      assert length(events) <= 2
    end
  end

  describe "list_unprocessed_webhook_ids/0" do
    test "returns list of pending webhook event IDs" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_unprocessed",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      event = Webhooks.create_webhook_event!(attrs)
      ids = Webhooks.list_unprocessed_webhook_ids()
      assert Enum.member?(ids, event.id)
    end
  end

  describe "update_webhook_state/2" do
    test "updates webhook event state" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_update",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      event = Webhooks.create_webhook_event!(attrs)
      assert {:ok, updated} = Webhooks.update_webhook_state(event, :processing)
      assert updated.state == :processing
    end
  end

  describe "update_webhook_event_state/2" do
    test "updates webhook event state to processed" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_complete",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      event = Webhooks.create_webhook_event!(attrs)
      # Note: The function accepts :complete but enum only has :processed
      # Using :processed to match the enum definition
      assert {:ok, updated} =
               Webhooks.update_webhook_event_state(event.id, :processed)

      assert updated.state == :processed
    end

    test "updates webhook event state to failed" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_failed",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      event = Webhooks.create_webhook_event!(attrs)

      assert {:ok, updated} =
               Webhooks.update_webhook_event_state(event.id, :failed)

      assert updated.state == :failed
    end

    test "returns error for non-existent event" do
      assert {:error, :not_found} =
               Webhooks.update_webhook_event_state(
                 Ecto.ULID.generate(),
                 :processed
               )
    end
  end

  describe "lock_webhook_event/1" do
    test "locks pending webhook event for processing" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_lock",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      event = Webhooks.create_webhook_event!(attrs)
      assert {:ok, locked} = Webhooks.lock_webhook_event(event.id)
      assert locked.id == event.id
      # State should be updated to processing
      updated = Webhooks.get_webhook_event(event.id)
      assert updated.state == :processing
    end

    test "returns error for non-existent event" do
      assert {:error, :not_found} =
               Webhooks.lock_webhook_event(Ecto.ULID.generate())
    end

    test "returns error for already processing event" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_processing",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :processing
      }

      event = Webhooks.create_webhook_event!(attrs)

      assert {:error, :already_processing} =
               Webhooks.lock_webhook_event(event.id)
    end
  end

  describe "get_and_lock_webhook/1" do
    test "gets and locks webhook event" do
      attrs = %{
        provider: :stripe,
        event_id: "evt_getlock",
        event_type: "payment_intent.succeeded",
        payload: %{"id" => "pi_test123"},
        state: :pending
      }

      event = Webhooks.create_webhook_event!(attrs)
      assert {:ok, locked} = Webhooks.get_and_lock_webhook(event.id)
      assert locked.id == event.id
    end

    test "returns error for non-existent webhook" do
      assert {:error, :not_found} =
               Webhooks.get_and_lock_webhook(Ecto.ULID.generate())
    end
  end
end

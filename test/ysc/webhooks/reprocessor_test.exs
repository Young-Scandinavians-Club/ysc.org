defmodule Ysc.Webhooks.ReprocessorTest do
  use Ysc.DataCase

  alias Ysc.Webhooks.Reprocessor
  alias Ysc.Webhooks
  alias Ysc.Webhooks.WebhookEvent

  describe "reprocess_webhook/1" do
    test "successfully reprocesses a failed stripe webhook" do
      # Create a failed webhook event
      webhook =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "test.event",
          payload: %{"data" => %{"object" => %{"id" => "obj_123"}}},
          state: :failed
        })

      # Verify it's failed
      assert webhook.state == :failed

      # Reprocess
      assert {:ok, :ok} = Reprocessor.reprocess_webhook(webhook.id)

      # Verify it's now processed
      updated_webhook = Repo.get(WebhookEvent, webhook.id)
      assert updated_webhook.state == :processed
    end

    test "returns error if webhook not found" do
      assert {:error, :not_found} =
               Reprocessor.reprocess_webhook(Ecto.ULID.generate())
    end

    test "returns error if webhook is not failed" do
      webhook =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "test.event",
          payload: %{"data" => %{"object" => %{"id" => "obj_456"}}},
          state: :pending
        })

      assert {:error, {:not_failed, :pending}} =
               Reprocessor.reprocess_webhook(webhook.id)
    end
  end

  describe "list_failed_webhooks/1" do
    test "lists failed webhooks with filters" do
      # Create failed webhooks
      w1 =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "type_a",
          payload: %{},
          state: :failed,
          updated_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        })

      w2 =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "type_b",
          payload: %{},
          state: :failed,
          updated_at: DateTime.utc_now()
        })

      # Create processed webhook (should be ignored)
      Webhooks.create_webhook_event!(%{
        provider: "stripe",
        event_id: "evt_#{Ecto.UUID.generate()}",
        event_type: "type_a",
        payload: %{},
        state: :processed
      })

      # Test listing all
      failed = Reprocessor.list_failed_webhooks()
      failed_ids = Enum.map(failed, & &1.id)
      assert w1.id in failed_ids
      assert w2.id in failed_ids
      assert length(failed) == 2

      # Test filter by provider
      stripe_failed = Reprocessor.list_failed_webhooks(provider: "stripe")
      assert length(stripe_failed) == 2

      # Test filter by event_type
      type_a_failed = Reprocessor.list_failed_webhooks(event_type: "type_a")
      type_a_ids = Enum.map(type_a_failed, & &1.id)
      assert w1.id in type_a_ids
      assert length(type_a_failed) == 1

      # Test limit
      limited = Reprocessor.list_failed_webhooks(limit: 1)
      assert length(limited) == 1
    end
  end

  describe "reprocess_all_failed_webhooks/1" do
    test "reprocesses all failed webhooks matching criteria" do
      # Create failed webhooks
      w1 =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "test.event",
          payload: %{"data" => %{"object" => %{"id" => "obj_1"}}},
          state: :failed
        })

      w2 =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "test.event",
          payload: %{"data" => %{"object" => %{"id" => "obj_2"}}},
          state: :failed
        })

      # Filter by specific event_type is not reliable if we reuse "test.event".
      # But since sandbox is used, it should be fine.

      result = Reprocessor.reprocess_all_failed_webhooks()

      assert result.total_found == 2
      assert result.successful == 2
      assert result.failed == 0

      # Check states
      assert Repo.get(WebhookEvent, w1.id).state == :processed
      assert Repo.get(WebhookEvent, w2.id).state == :processed
    end

    test "dry run does not change states" do
      unique_type = "dry.run.#{Ecto.UUID.generate()}"

      w1 =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: unique_type,
          payload: %{"data" => %{"object" => %{"id" => "obj_1"}}},
          state: :failed
        })

      result =
        Reprocessor.reprocess_all_failed_webhooks(
          dry_run: true,
          event_type: unique_type
        )

      assert result.total_found == 1
      assert result.summary =~ "Dry run"

      # Check state unchanged
      assert Repo.get(WebhookEvent, w1.id).state == :failed
    end
  end

  describe "get_failed_webhook_stats/0" do
    test "returns correct statistics" do
      Webhooks.create_webhook_event!(%{
        provider: "stripe",
        event_id: "evt_#{Ecto.UUID.generate()}",
        event_type: "type_a",
        payload: %{},
        state: :failed
      })

      Webhooks.create_webhook_event!(%{
        provider: "stripe",
        event_id: "evt_#{Ecto.UUID.generate()}",
        event_type: "type_b",
        payload: %{},
        state: :failed
      })

      stats = Reprocessor.get_failed_webhook_stats()

      assert stats.total_failed == 2
      # EctoEnum returns atoms for provider
      assert stats.by_provider[:stripe] == 2
      assert stats.by_event_type["type_a"] == 1
      assert stats.by_event_type["type_b"] == 1
      assert stats.recent_failures_24h == 2
    end
  end

  describe "reset_webhook_to_pending/1" do
    test "resets failed webhook to pending" do
      webhook =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "test.event",
          payload: %{},
          state: :failed
        })

      assert {:ok, updated} = Reprocessor.reset_webhook_to_pending(webhook.id)
      assert updated.state == :pending
    end
  end
end

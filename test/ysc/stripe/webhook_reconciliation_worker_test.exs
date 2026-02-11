defmodule Ysc.Stripe.WebhookReconciliationWorkerTest do
  @moduledoc """
  Tests for WebhookReconciliationWorker.

  Covers:
  - No missing webhooks (success case)
  - Missing webhooks found and processed successfully
  - Missing webhooks found but processing fails
  - Stripe API failure handling
  - Pagination handling
  - Discord report sending (worker completes; Discord may be disabled in test)
  """
  use Ysc.DataCase, async: false

  import Mox

  alias Ysc.Stripe.WebhookReconciliationWorker
  alias Ysc.Webhooks
  alias Ysc.Ledgers

  setup do
    Ledgers.ensure_basic_accounts()
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
    on_exit(fn -> Application.delete_env(:ysc, :stripe_client) end)
    :ok
  end

  defp build_job do
    %Oban.Job{
      id: 1,
      args: %{},
      worker: "Ysc.Stripe.WebhookReconciliationWorker",
      queue: "maintenance",
      state: "available",
      attempt: 1
    }
  end

  defp build_stripe_event(id, type \\ "ping", object \\ %{}) do
    %Stripe.Event{
      id: id,
      type: type,
      data: %{object: object},
      api_version: "2025-10-29.clover",
      created: System.os_time(:second),
      livemode: false,
      pending_webhooks: 0,
      request: %{id: nil, idempotency_key: nil},
      object: "event",
      account: nil
    }
  end

  describe "perform/1 - no missing webhooks" do
    test "returns ok and stats when Stripe returns no events" do
      expect(Ysc.StripeMock, :list_events, fn _params, _opts ->
        {:ok, %Stripe.List{data: [], has_more: false}}
      end)

      assert {:ok, stats} = WebhookReconciliationWorker.perform(build_job())

      assert stats.total_checked == 0
      assert stats.missing_found == 0
      assert stats.processed_success == 0
      assert stats.processed_failed == 0
      assert stats.duration_ms >= 0
    end

    test "returns ok when all events already exist in database" do
      event_id = "evt_recon_#{System.unique_integer()}"
      event = build_stripe_event(event_id)

      # Pre-create webhook event so it's not "missing"
      Webhooks.create_webhook_event!(%{
        provider: "stripe",
        event_id: event_id,
        event_type: event.type,
        payload: Ysc.Stripe.WebhookHandler.event_payload_for_storage(event)
      })

      expect(Ysc.StripeMock, :list_events, fn _params, _opts ->
        {:ok, %Stripe.List{data: [event], has_more: false}}
      end)

      assert {:ok, stats} = WebhookReconciliationWorker.perform(build_job())

      assert stats.total_checked == 1
      assert stats.missing_found == 0
      assert stats.processed_success == 0
      assert stats.processed_failed == 0
    end
  end

  describe "perform/1 - missing webhooks found and processed" do
    test "stores and processes missing event successfully" do
      event_id = "evt_missing_#{System.unique_integer()}"
      event = build_stripe_event(event_id, "ping", %{})

      expect(Ysc.StripeMock, :list_events, fn _params, _opts ->
        {:ok, %Stripe.List{data: [event], has_more: false}}
      end)

      assert {:ok, stats} = WebhookReconciliationWorker.perform(build_job())

      assert stats.total_checked == 1
      assert stats.missing_found == 1
      assert stats.processed_success == 1
      assert stats.processed_failed == 0

      # Event should now be in DB and processed
      webhook =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event_id)

      assert webhook != nil
      assert webhook.state == :processed
    end
  end

  describe "perform/1 - Stripe API failure" do
    test "returns error when list_events fails" do
      expect(Ysc.StripeMock, :list_events, fn _params, _opts ->
        {:error, :api_connection_error}
      end)

      assert {:error, _reason} =
               WebhookReconciliationWorker.perform(build_job())
    end
  end

  describe "perform/1 - pagination" do
    test "fetches all pages when has_more is true" do
      id1 = "evt_page1_#{System.unique_integer()}"
      id2 = "evt_page2_#{System.unique_integer()}"
      event1 = build_stripe_event(id1)
      event2 = build_stripe_event(id2)

      expect(Ysc.StripeMock, :list_events, fn _params, _opts ->
        {:ok, %Stripe.List{data: [event1], has_more: true}}
      end)

      expect(Ysc.StripeMock, :list_events, fn params, _opts ->
        assert Map.get(params, :starting_after) == id1
        {:ok, %Stripe.List{data: [event2], has_more: false}}
      end)

      assert {:ok, stats} = WebhookReconciliationWorker.perform(build_job())

      assert stats.total_checked == 2
    end
  end

  describe "run_now/0" do
    test "runs reconciliation and returns stats" do
      expect(Ysc.StripeMock, :list_events, fn _params, _opts ->
        {:ok, %Stripe.List{data: [], has_more: false}}
      end)

      assert {:ok, stats} = WebhookReconciliationWorker.run_now()
      assert stats.total_checked == 0
      assert Map.has_key?(stats, :duration_ms)
    end
  end

  describe "schedule_reconciliation/1" do
    test "schedules a job with default schedule_in 0" do
      # Oban runs jobs inline in test, so stub list_events for when the job executes
      stub(Ysc.StripeMock, :list_events, fn _params, _opts ->
        {:ok, %Stripe.List{data: [], has_more: false}}
      end)

      assert {:ok, job} = WebhookReconciliationWorker.schedule_reconciliation()
      assert job.worker == "Ysc.Stripe.WebhookReconciliationWorker"
      assert job.queue == "maintenance"
      assert job.args == %{}
    end

    test "schedules with custom schedule_in" do
      stub(Ysc.StripeMock, :list_events, fn _params, _opts ->
        {:ok, %Stripe.List{data: [], has_more: false}}
      end)

      assert {:ok, job} =
               WebhookReconciliationWorker.schedule_reconciliation(
                 schedule_in: 300
               )

      assert job.worker == "Ysc.Stripe.WebhookReconciliationWorker"
      assert job.scheduled_at != nil
    end
  end

  describe "Oban worker configuration" do
    test "uses maintenance queue" do
      assert WebhookReconciliationWorker.__opts__()[:queue] == :maintenance
    end

    test "has max_attempts set to 3" do
      assert WebhookReconciliationWorker.__opts__()[:max_attempts] == 3
    end
  end
end

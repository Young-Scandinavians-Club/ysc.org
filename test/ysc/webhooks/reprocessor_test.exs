defmodule Ysc.Webhooks.ReprocessorTest do
  use Ysc.DataCase, async: true

  alias Ysc.Webhooks.Reprocessor
  alias Ysc.Webhooks
  alias Ysc.Webhooks.WebhookEvent

  describe "reprocess_webhook/1 — Stripe event variants" do
    test "reprocesses invoice.payment_succeeded when invoice is not for a subscription" do
      webhook =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "invoice.payment_succeeded",
          payload: %{
            "data" => %{
              "object" => %{
                "id" => "in_#{System.unique_integer([:positive])}",
                "customer" => "cus_test",
                "subscription" => nil
              }
            }
          },
          state: :failed
        })

      assert {:ok, :ok} = Reprocessor.reprocess_webhook(webhook.id)
      assert Repo.get!(WebhookEvent, webhook.id).state == :processed
    end

    test "reprocesses payment_intent.succeeded" do
      webhook =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "payment_intent.succeeded",
          payload: %{
            "data" => %{
              "object" => %{
                "id" => "pi_#{System.unique_integer([:positive])}",
                "customer" => "cus_test",
                "amount" => 1000,
                "status" => "succeeded",
                "metadata" => %{}
              }
            }
          },
          state: :failed
        })

      assert {:ok, _} = Reprocessor.reprocess_webhook(webhook.id)
      assert Repo.get!(WebhookEvent, webhook.id).state == :processed
    end

    test "reprocesses generic Stripe event type via handler fallback" do
      webhook =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "customer.updated",
          payload: %{
            "data" => %{
              "object" => %{"id" => "cus_#{System.unique_integer([:positive])}"}
            }
          },
          state: :failed
        })

      assert {:ok, _} = Reprocessor.reprocess_webhook(webhook.id)
      assert Repo.get!(WebhookEvent, webhook.id).state == :processed
    end

    test "reprocess_all_failed_webhooks returns empty summary when no events match filters" do
      unique_type = "no.such.type.#{System.unique_integer([:positive])}"

      result =
        Reprocessor.reprocess_all_failed_webhooks(
          provider: "stripe",
          event_type: unique_type,
          limit: 20
        )

      assert result.total_found == 0
      assert result.successful == 0
      assert result.failed == 0
      assert result.results == []
    end
  end

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

    test "returns {:error, :not_found} for unknown id" do
      assert Reprocessor.reset_webhook_to_pending(Ecto.ULID.generate()) ==
               {:error, :not_found}
    end

    test "returns {:error, {:not_failed, state}} when webhook is not failed" do
      webhook =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "test.event",
          payload: %{},
          state: :processed
        })

      assert Reprocessor.reset_webhook_to_pending(webhook.id) ==
               {:error, {:not_failed, :processed}}
    end
  end

  describe "get_failed_webhook_details/1" do
    test "returns {:ok, event} or {:error, :not_found}" do
      w =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "detail.event",
          payload: %{},
          state: :failed
        })

      assert {:ok, fetched} = Reprocessor.get_failed_webhook_details(w.id)
      assert fetched.id == w.id

      assert Reprocessor.get_failed_webhook_details(Ecto.ULID.generate()) ==
               {:error, :not_found}
    end
  end

  describe "list_failed_webhooks/1 :since filter" do
    test "includes webhook when since is before its updated_at" do
      w =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "since.recent",
          payload: %{},
          state: :failed
        })

      since = DateTime.add(DateTime.utc_now(), -3600, :second)

      recent =
        Reprocessor.list_failed_webhooks(
          since: since,
          event_type: "since.recent",
          limit: 50
        )

      assert Enum.any?(recent, &(&1.id == w.id))
    end

    test "only includes webhooks updated on or after since" do
      old =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "since.old",
          payload: %{},
          state: :failed
        })

      old_ts =
        DateTime.utc_now()
        |> DateTime.add(-7200, :second)
        |> DateTime.truncate(:second)

      {:ok, _} =
        old
        |> Ecto.Changeset.change(%{updated_at: old_ts})
        |> Repo.update()

      since = DateTime.add(DateTime.utc_now(), -3600, :second)

      recent =
        Reprocessor.list_failed_webhooks(
          since: since,
          event_type: "since.old",
          limit: 50
        )

      refute Enum.any?(recent, &(&1.id == old.id))
    end
  end

  describe "reprocess_webhooks_by_type/3" do
    test "passes provider and event_type to listing" do
      et = "qb.type.#{Ecto.UUID.generate()}"

      Webhooks.create_webhook_event!(%{
        provider: "quickbooks",
        event_id: "evt_#{Ecto.UUID.generate()}",
        event_type: et,
        payload: %{"eventNotifications" => []},
        state: :failed
      })

      result =
        Reprocessor.reprocess_webhooks_by_type("quickbooks", et,
          limit: 5,
          dry_run: true
        )

      assert result.total_found >= 1
    end
  end

  describe "list_pending_or_processing_webhooks/1 and reset_processing_to_pending/1" do
    test "lists pending and processing; reset moves processing to pending" do
      Webhooks.create_webhook_event!(%{
        provider: "stripe",
        event_id: "evt_#{Ecto.UUID.generate()}",
        event_type: "pend.e",
        payload: %{},
        state: :pending
      })

      proc =
        Webhooks.create_webhook_event!(%{
          provider: "quickbooks",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "proc.e",
          payload: %{},
          state: :processing
        })

      listed = Reprocessor.list_pending_or_processing_webhooks(limit: 100)
      assert Enum.any?(listed, &(&1.id == proc.id))

      assert {:ok, reset} = Reprocessor.reset_processing_to_pending(proc.id)
      assert reset.state == :pending

      assert Reprocessor.reset_processing_to_pending(proc.id) ==
               {:error, {:not_processing, :pending}}
    end

    test "reset_processing_to_pending returns not_found for unknown id" do
      assert Reprocessor.reset_processing_to_pending(Ecto.ULID.generate()) ==
               {:error, :not_found}
    end
  end

  describe "reprocess_pending_or_processing_webhook/1" do
    test "returns not_found when webhook id does not exist" do
      assert {:error, :not_found} =
               Reprocessor.reprocess_pending_or_processing_webhook(
                 Ecto.ULID.generate()
               )
    end

    test "resets processing state to pending then reprocesses Stripe webhook" do
      ev =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "customer.updated",
          payload: %{
            "data" => %{
              "object" => %{"id" => "cus_#{System.unique_integer([:positive])}"}
            }
          },
          state: :processing
        })

      assert {:ok, _} =
               Reprocessor.reprocess_pending_or_processing_webhook(ev.id)

      assert Repo.get!(WebhookEvent, ev.id).state == :processed
    end

    test "reprocesses pending QuickBooks webhook with empty notifications" do
      ev =
        Webhooks.create_webhook_event!(%{
          provider: "quickbooks",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "qb.empty",
          payload: %{"eventNotifications" => []},
          state: :pending
        })

      assert {:ok, :ok} =
               Reprocessor.reprocess_pending_or_processing_webhook(ev.id)

      assert Repo.get!(WebhookEvent, ev.id).state == :processed
    end

    test "returns {:error, {:not_pending_or_processing, :processed}} for processed" do
      ev =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "done.e",
          payload: %{},
          state: :processed
        })

      assert Reprocessor.reprocess_pending_or_processing_webhook(ev.id) ==
               {:error, {:not_pending_or_processing, :processed}}
    end
  end

  describe "reprocess_all_pending_or_processing_webhooks/1" do
    test "dry_run returns would_process without updating state" do
      ev =
        Webhooks.create_webhook_event!(%{
          provider: "quickbooks",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "dry.pend",
          payload: %{"eventNotifications" => []},
          state: :pending
        })

      summary =
        Reprocessor.reprocess_all_pending_or_processing_webhooks(
          dry_run: true,
          provider: "quickbooks",
          limit: 20
        )

      assert summary.total_found >= 1
      assert Enum.any?(summary.would_process, &(&1.id == ev.id))
      assert Repo.get!(WebhookEvent, ev.id).state == :pending
    end

    test "reprocesses matching webhooks and returns a summary of the results" do
      webhooks =
        for n <- 1..2 do
          Webhooks.create_webhook_event!(%{
            provider: "quickbooks",
            event_id: "evt_#{Ecto.UUID.generate()}",
            event_type: "bulk.ok.#{n}",
            payload: %{"eventNotifications" => []},
            state: :pending
          })
        end

      # Wrong provider: excluded by the :provider filter.
      other_provider =
        Webhooks.create_webhook_event!(%{
          provider: "stripe",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "bulk.wrong_provider",
          payload: %{"data" => %{"object" => %{}}},
          state: :pending
        })

      # Wrong state: excluded by list_pending_or_processing_webhooks/1's state filter.
      already_processed =
        Webhooks.create_webhook_event!(%{
          provider: "quickbooks",
          event_id: "evt_#{Ecto.UUID.generate()}",
          event_type: "bulk.already_done",
          payload: %{"eventNotifications" => []},
          state: :processed
        })

      summary =
        Reprocessor.reprocess_all_pending_or_processing_webhooks(
          provider: "quickbooks",
          limit: 20
        )

      assert summary.total_found == 2
      assert summary.successful == 2
      assert summary.failed == 0
      assert length(summary.results) == 2
      assert Enum.all?(summary.results, &match?({:ok, _}, &1))
      assert summary.summary == "Processed 2 webhooks successfully, 0 failed"

      Enum.each(webhooks, fn w ->
        assert Repo.get!(WebhookEvent, w.id).state == :processed
      end)

      assert Repo.get!(WebhookEvent, other_provider.id).state == :pending
      assert Repo.get!(WebhookEvent, already_processed.id).state == :processed
    end
  end
end

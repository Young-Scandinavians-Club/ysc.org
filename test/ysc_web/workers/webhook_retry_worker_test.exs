defmodule YscWeb.Workers.WebhookRetryWorkerTest do
  use Ysc.DataCase

  alias YscWeb.Workers.WebhookRetryWorker
  alias Ysc.Webhooks.WebhookEvent

  import Ecto.Query

  describe "find_webhooks_to_retry/3" do
    test "finds pending webhooks older than min age" do
      # Create a pending webhook older than 5 minutes
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      webhook =
        insert_webhook_event(%{
          state: :pending,
          inserted_at: old_time,
          updated_at: old_time
        })

      now = DateTime.utc_now()
      min_age_cutoff = DateTime.add(now, -5, :minute)
      max_age_cutoff = DateTime.add(now, -7, :day)
      stuck_cutoff = DateTime.add(now, -60, :minute)

      webhooks =
        WebhookRetryWorker.find_webhooks_to_retry(
          min_age_cutoff,
          max_age_cutoff,
          stuck_cutoff
        )

      assert length(webhooks) == 1
      assert hd(webhooks).id == webhook.id
    end

    test "finds failed webhooks older than min age" do
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      webhook =
        insert_webhook_event(%{
          state: :failed,
          inserted_at: old_time,
          updated_at: old_time
        })

      now = DateTime.utc_now()
      min_age_cutoff = DateTime.add(now, -5, :minute)
      max_age_cutoff = DateTime.add(now, -7, :day)
      stuck_cutoff = DateTime.add(now, -60, :minute)

      webhooks =
        WebhookRetryWorker.find_webhooks_to_retry(
          min_age_cutoff,
          max_age_cutoff,
          stuck_cutoff
        )

      assert length(webhooks) == 1
      assert hd(webhooks).id == webhook.id
    end

    test "finds stuck processing webhooks" do
      # Create a processing webhook that's been stuck for over an hour
      old_time = DateTime.add(DateTime.utc_now(), -90, :minute)

      webhook =
        insert_webhook_event(%{
          state: :processing,
          inserted_at: old_time,
          updated_at: old_time
        })

      now = DateTime.utc_now()
      min_age_cutoff = DateTime.add(now, -5, :minute)
      max_age_cutoff = DateTime.add(now, -7, :day)
      stuck_cutoff = DateTime.add(now, -60, :minute)

      webhooks =
        WebhookRetryWorker.find_webhooks_to_retry(
          min_age_cutoff,
          max_age_cutoff,
          stuck_cutoff
        )

      assert length(webhooks) == 1
      assert hd(webhooks).id == webhook.id
    end

    test "ignores webhooks younger than min age" do
      # Create a pending webhook that's only 2 minutes old
      recent_time = DateTime.add(DateTime.utc_now(), -2, :minute)

      insert_webhook_event(%{
        state: :pending,
        inserted_at: recent_time,
        updated_at: recent_time
      })

      now = DateTime.utc_now()
      min_age_cutoff = DateTime.add(now, -5, :minute)
      max_age_cutoff = DateTime.add(now, -7, :day)
      stuck_cutoff = DateTime.add(now, -60, :minute)

      webhooks =
        WebhookRetryWorker.find_webhooks_to_retry(
          min_age_cutoff,
          max_age_cutoff,
          stuck_cutoff
        )

      assert webhooks == []
    end

    test "ignores webhooks older than max age" do
      # Create a webhook that's 10 days old (too old)
      very_old_time = DateTime.add(DateTime.utc_now(), -10, :day)

      insert_webhook_event(%{
        state: :pending,
        inserted_at: very_old_time,
        updated_at: very_old_time
      })

      now = DateTime.utc_now()
      min_age_cutoff = DateTime.add(now, -5, :minute)
      max_age_cutoff = DateTime.add(now, -7, :day)
      stuck_cutoff = DateTime.add(now, -60, :minute)

      webhooks =
        WebhookRetryWorker.find_webhooks_to_retry(
          min_age_cutoff,
          max_age_cutoff,
          stuck_cutoff
        )

      assert webhooks == []
    end

    test "ignores processed webhooks" do
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      insert_webhook_event(%{
        state: :processed,
        inserted_at: old_time,
        updated_at: old_time
      })

      now = DateTime.utc_now()
      min_age_cutoff = DateTime.add(now, -5, :minute)
      max_age_cutoff = DateTime.add(now, -7, :day)
      stuck_cutoff = DateTime.add(now, -60, :minute)

      webhooks =
        WebhookRetryWorker.find_webhooks_to_retry(
          min_age_cutoff,
          max_age_cutoff,
          stuck_cutoff
        )

      assert webhooks == []
    end

    test "limits results to batch size" do
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      # Create 150 webhooks (more than the batch size of 100)
      for _ <- 1..150 do
        insert_webhook_event(%{
          state: :pending,
          inserted_at: old_time,
          updated_at: old_time
        })
      end

      now = DateTime.utc_now()
      min_age_cutoff = DateTime.add(now, -5, :minute)
      max_age_cutoff = DateTime.add(now, -7, :day)
      stuck_cutoff = DateTime.add(now, -60, :minute)

      webhooks =
        WebhookRetryWorker.find_webhooks_to_retry(
          min_age_cutoff,
          max_age_cutoff,
          stuck_cutoff
        )

      assert length(webhooks) == 100
    end

    test "returns oldest webhooks first" do
      # Create webhooks at different times
      oldest_time = DateTime.add(DateTime.utc_now(), -60, :minute)
      middle_time = DateTime.add(DateTime.utc_now(), -30, :minute)
      recent_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      oldest_webhook =
        insert_webhook_event(%{
          state: :pending,
          inserted_at: oldest_time,
          updated_at: oldest_time
        })

      _middle_webhook =
        insert_webhook_event(%{
          state: :pending,
          inserted_at: middle_time,
          updated_at: middle_time
        })

      _recent_webhook =
        insert_webhook_event(%{
          state: :pending,
          inserted_at: recent_time,
          updated_at: recent_time
        })

      now = DateTime.utc_now()
      min_age_cutoff = DateTime.add(now, -5, :minute)
      max_age_cutoff = DateTime.add(now, -7, :day)
      stuck_cutoff = DateTime.add(now, -60, :minute)

      webhooks =
        WebhookRetryWorker.find_webhooks_to_retry(
          min_age_cutoff,
          max_age_cutoff,
          stuck_cutoff
        )

      assert length(webhooks) == 3
      # First webhook should be the oldest
      assert hd(webhooks).id == oldest_webhook.id
    end
  end

  describe "retry_webhook/1" do
    test "successfully retries a pending webhook" do
      webhook =
        insert_webhook_event(%{
          state: :pending,
          event_type: "customer.created",
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => %{
              "object" => %{
                "id" => "cus_test",
                "email" => "test@example.com"
              }
            }
          }
        })

      result = WebhookRetryWorker.retry_webhook(webhook)

      assert {:ok, :success} = result

      # Verify webhook was marked as processed
      updated = Repo.get!(WebhookEvent, webhook.id)
      assert updated.state == :processed
    end

    test "skips already processed webhook" do
      webhook =
        insert_webhook_event(%{
          state: :processed,
          event_type: "customer.created",
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => %{"object" => %{}}
          }
        })

      result = WebhookRetryWorker.retry_webhook(webhook)

      assert {:ok, :already_processed} = result
    end

    test "handles webhook with invalid payload data" do
      webhook =
        insert_webhook_event(%{
          state: :pending,
          event_type: "customer.created",
          # Invalid - nil payload
          payload: nil
        })

      result = WebhookRetryWorker.retry_webhook(webhook)

      # Should handle gracefully and mark as failed
      assert match?({:error, _}, result)

      # Verify webhook was marked as failed
      updated = Repo.get!(WebhookEvent, webhook.id)
      assert updated.state == :failed
    end
  end

  describe "perform/1" do
    test "processes multiple pending webhooks" do
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      # Create 3 pending webhooks
      for i <- 1..3 do
        insert_webhook_event(%{
          state: :pending,
          event_id: "evt_test_#{i}",
          event_type: "customer.created",
          inserted_at: old_time,
          updated_at: old_time,
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => %{
              "object" => %{
                "id" => "cus_test_#{i}",
                "email" => "test#{i}@example.com"
              }
            }
          }
        })
      end

      # Execute worker
      job = %Oban.Job{args: %{}}
      assert :ok = WebhookRetryWorker.perform(job)

      # Verify all webhooks were processed
      pending_count =
        WebhookEvent
        |> where([w], w.state == :pending)
        |> Repo.aggregate(:count)

      assert pending_count == 0

      processed_count =
        WebhookEvent
        |> where([w], w.state == :processed)
        |> Repo.aggregate(:count)

      assert processed_count == 3
    end

    test "handles mix of pending and failed webhooks" do
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      # Create 2 pending and 2 failed webhooks
      for i <- 1..2 do
        insert_webhook_event(%{
          state: :pending,
          event_id: "evt_pending_#{i}",
          event_type: "customer.created",
          inserted_at: old_time,
          updated_at: old_time,
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => %{"object" => %{}}
          }
        })
      end

      for i <- 1..2 do
        insert_webhook_event(%{
          state: :failed,
          event_id: "evt_failed_#{i}",
          event_type: "customer.created",
          inserted_at: old_time,
          updated_at: old_time,
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => %{"object" => %{}}
          }
        })
      end

      # Execute worker
      job = %Oban.Job{args: %{}}
      assert :ok = WebhookRetryWorker.perform(job)

      # Verify all were processed
      processed_count =
        WebhookEvent
        |> where([w], w.state == :processed)
        |> Repo.aggregate(:count)

      assert processed_count == 4
    end

    test "ignores recent webhooks" do
      # Create a webhook that's only 2 minutes old
      recent_time = DateTime.add(DateTime.utc_now(), -2, :minute)

      insert_webhook_event(%{
        state: :pending,
        inserted_at: recent_time,
        updated_at: recent_time,
        payload: %{
          "created" => DateTime.to_unix(DateTime.utc_now()),
          "data" => %{"object" => %{}}
        }
      })

      # Execute worker
      job = %Oban.Job{args: %{}}
      assert :ok = WebhookRetryWorker.perform(job)

      # Verify webhook was not processed (still pending)
      pending_count =
        WebhookEvent
        |> where([w], w.state == :pending)
        |> Repo.aggregate(:count)

      assert pending_count == 1
    end

    test "processes stuck webhooks" do
      # Create a webhook that's been processing for 90 minutes (stuck)
      old_time = DateTime.add(DateTime.utc_now(), -90, :minute)

      insert_webhook_event(%{
        state: :processing,
        event_type: "customer.created",
        inserted_at: old_time,
        updated_at: old_time,
        payload: %{
          "created" => DateTime.to_unix(DateTime.utc_now()),
          "data" => %{"object" => %{}}
        }
      })

      # Execute worker
      job = %Oban.Job{args: %{}}
      assert :ok = WebhookRetryWorker.perform(job)

      # Verify webhook was processed
      processing_count =
        WebhookEvent
        |> where([w], w.state == :processing)
        |> Repo.aggregate(:count)

      assert processing_count == 0

      processed_count =
        WebhookEvent
        |> where([w], w.state == :processed)
        |> Repo.aggregate(:count)

      assert processed_count == 1
    end
  end

  # Helper function to insert a webhook event with custom attributes
  defp insert_webhook_event(attrs) do
    default_attrs = %{
      provider: "stripe",
      event_id: "evt_test_#{System.unique_integer([:positive])}",
      event_type: "customer.created",
      state: :pending,
      payload: %{
        "created" => DateTime.to_unix(DateTime.utc_now()),
        "data" => %{"object" => %{}}
      }
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    # Handle inserted_at and updated_at separately if provided
    {inserted_at, merged_attrs} = Map.pop(merged_attrs, :inserted_at)
    {updated_at, merged_attrs} = Map.pop(merged_attrs, :updated_at)

    changeset =
      %WebhookEvent{}
      |> WebhookEvent.changeset(merged_attrs)

    # Manually set timestamps if provided (truncate to remove microseconds)
    changeset =
      if inserted_at do
        Ecto.Changeset.put_change(
          changeset,
          :inserted_at,
          DateTime.truncate(inserted_at, :second)
        )
      else
        changeset
      end

    changeset =
      if updated_at do
        Ecto.Changeset.put_change(
          changeset,
          :updated_at,
          DateTime.truncate(updated_at, :second)
        )
      else
        changeset
      end

    Repo.insert!(changeset)
  end
end

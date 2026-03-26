defmodule YscWeb.Workers.WebhookRetryWorkerTest do
  use Ysc.DataCase, async: false

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

      require Logger
      Logger.put_module_level(WebhookRetryWorker, :none)
      result = WebhookRetryWorker.retry_webhook(webhook)
      Logger.put_module_level(WebhookRetryWorker, :error)

      # Should handle gracefully and mark as failed
      assert match?({:error, _}, result)

      # Verify webhook was marked as failed
      updated = Repo.get!(WebhookEvent, webhook.id)
      assert updated.state == :failed
    end

    test "marks webhook failed and skips when Stripe event is too old to process" do
      old_created =
        DateTime.to_unix(DateTime.add(DateTime.utc_now(), -600, :second))

      webhook =
        insert_webhook_event(%{
          state: :pending,
          event_type: "customer.created",
          payload: %{
            "created" => old_created,
            "data" => %{"object" => %{"id" => "cus_old"}}
          }
        })

      assert {:ok, :skipped} = WebhookRetryWorker.retry_webhook(webhook)
      updated = Repo.get!(WebhookEvent, webhook.id)
      assert updated.state == :failed
    end

    test "returns error for unsupported provider" do
      webhook =
        insert_webhook_event(%{
          state: :pending,
          provider: "quickbooks",
          payload: %{}
        })

      assert {:error, {:unsupported_provider, :quickbooks}} =
               WebhookRetryWorker.retry_webhook(webhook)
    end

    test "parses provider :stripe atom same as string" do
      webhook =
        insert_webhook_event(%{
          state: :pending,
          provider: :stripe,
          event_type: "customer.created",
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => %{"object" => %{}}
          }
        })

      assert {:ok, :success} = WebhookRetryWorker.retry_webhook(webhook)
    end

    test "returns parse error when payload shape cannot be converted to Stripe event" do
      webhook =
        insert_webhook_event(%{
          state: :pending,
          event_type: "customer.created",
          payload: %{"data" => 123}
        })

      require Logger
      Logger.put_module_level(WebhookRetryWorker, :none)

      assert {:error, {:parse_error, _}} =
               WebhookRetryWorker.retry_webhook(webhook)

      Logger.put_module_level(WebhookRetryWorker, :error)

      updated = Repo.get!(WebhookEvent, webhook.id)
      assert updated.state == :failed
    end

    test "resets failed state to pending before retrying" do
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      webhook =
        insert_webhook_event(%{
          state: :failed,
          inserted_at: old_time,
          updated_at: old_time,
          event_type: "customer.created",
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => %{
              "object" => %{"id" => "cus_retry_failed", "email" => "x@y.com"}
            }
          }
        })

      assert {:ok, :success} = WebhookRetryWorker.retry_webhook(webhook)
      assert Repo.get!(WebhookEvent, webhook.id).state == :processed
    end

    test "resets stuck processing state to pending before retrying" do
      old_time = DateTime.add(DateTime.utc_now(), -90, :minute)

      webhook =
        insert_webhook_event(%{
          state: :processing,
          inserted_at: old_time,
          updated_at: old_time,
          event_type: "invoice.payment_succeeded",
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => %{
              "object" => %{
                "id" => "in_retry_#{System.unique_integer([:positive])}",
                "customer" => "cus_x",
                "subscription" => nil,
                "amount_paid" => 1000
              }
            }
          }
        })

      assert {:ok, :success} = WebhookRetryWorker.retry_webhook(webhook)
      assert Repo.get!(WebhookEvent, webhook.id).state == :processed
    end

    test "retries payment_intent.succeeded payload shape" do
      webhook =
        insert_webhook_event(%{
          state: :pending,
          event_type: "payment_intent.succeeded",
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => %{
              "object" => %{
                "id" => "pi_#{System.unique_integer([:positive])}",
                "customer" => "cus_pi",
                "amount" => 2000,
                "status" => "succeeded",
                "metadata" => %{}
              }
            }
          }
        })

      assert {:ok, :success} = WebhookRetryWorker.retry_webhook(webhook)
      assert Repo.get!(WebhookEvent, webhook.id).state == :processed
    end
  end

  describe "perform/1" do
    test "emits webhook_retry_completed telemetry" do
      parent = self()

      ref =
        :telemetry.attach(
          "webhook-retry-telemetry-test",
          [:ysc, :workers, :webhook_retry_completed],
          fn event, measurements, meta, _ ->
            send(parent, {:telemetry_webhook_retry, event, measurements, meta})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert :ok = perform_job(WebhookRetryWorker, %{})

      assert_receive {:telemetry_webhook_retry,
                      [:ysc, :workers, :webhook_retry_completed], measurements,
                      meta}

      assert measurements.duration >= 0
      assert measurements.total == 0
      assert measurements.success == 0
      assert map_size(meta) == 0
    end

    test "telemetry includes failed count when parse or processing returns error" do
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)
      parent = self()

      insert_webhook_event(%{
        state: :pending,
        inserted_at: old_time,
        updated_at: old_time,
        event_type: "customer.created",
        payload: %{"data" => 123}
      })

      ref =
        :telemetry.attach(
          "webhook-retry-telemetry-failed",
          [:ysc, :workers, :webhook_retry_completed],
          fn _event, measurements, _meta, _ ->
            send(parent, {:telemetry_failed, measurements})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert :ok = perform_job(WebhookRetryWorker, %{})

      assert_receive {:telemetry_failed, measurements}
      assert measurements.failed >= 1
      assert measurements.total >= 1
    end

    test "completes with no webhooks to retry" do
      assert :ok = perform_job(WebhookRetryWorker, %{})

      pending =
        WebhookEvent
        |> where([w], w.state == :pending)
        |> Repo.aggregate(:count)

      assert pending == 0
    end

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
      assert :ok = perform_job(WebhookRetryWorker, %{})

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
      assert :ok = perform_job(WebhookRetryWorker, %{})

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
      assert :ok = perform_job(WebhookRetryWorker, %{})

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

  describe "retry_webhook/1 — parse and provider edge cases" do
    test "nil payload data navigates to empty object and processes (Elixir Access on nil)" do
      webhook =
        insert_webhook_event(%{
          state: :pending,
          event_type: "customer.created",
          payload: %{
            "created" => DateTime.to_unix(DateTime.utc_now()),
            "data" => nil
          }
        })

      assert {:ok, :success} = WebhookRetryWorker.retry_webhook(webhook)
      assert Repo.get!(WebhookEvent, webhook.id).state == :processed
    end

    test "telemetry counts skipped when webhook is too old for handler" do
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      old_created =
        DateTime.to_unix(DateTime.add(DateTime.utc_now(), -600, :second))

      insert_webhook_event(%{
        state: :pending,
        inserted_at: old_time,
        updated_at: old_time,
        event_type: "customer.created",
        payload: %{
          "created" => old_created,
          "data" => %{"object" => %{"id" => "cus_skip_telemetry"}}
        }
      })

      parent = self()

      ref =
        :telemetry.attach(
          "webhook-retry-skipped-telemetry",
          [:ysc, :workers, :webhook_retry_completed],
          fn _event, measurements, _meta, _ ->
            send(parent, {:telemetry_skipped, measurements})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert :ok = perform_job(WebhookRetryWorker, %{})

      assert_receive {:telemetry_skipped, measurements}
      assert measurements.skipped >= 1
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

  defmodule WebhooksReturnNilForDuplicateLookup do
    @moduledoc false
    def get_webhook_event_by_provider_and_event_id(provider, event_id) do
      if provider == "stripe" and
           event_id ==
             Application.get_env(:ysc, :webhook_retry_nil_lookup_event_id) do
        nil
      else
        Ysc.Webhooks.get_webhook_event_by_provider_and_event_id(
          provider,
          event_id
        )
      end
    end
  end

  describe "retry_webhook/1 — Stripe handler returns generic error" do
    test "returns webhook_not_found_after_duplicate when duplicate insert races with nil lookup" do
      require Logger
      event_id = "evt_dup_nil_#{System.unique_integer([:positive])}"
      old_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      insert_webhook_event(%{
        state: :pending,
        inserted_at: old_time,
        updated_at: old_time,
        event_id: event_id,
        event_type: "customer.created",
        payload: %{
          "created" => DateTime.to_unix(DateTime.utc_now()),
          "data" => %{"object" => %{"id" => "cus_dup_nil"}}
        }
      })

      Application.put_env(
        :ysc,
        :webhooks_context,
        WebhooksReturnNilForDuplicateLookup
      )

      Application.put_env(:ysc, :webhook_retry_nil_lookup_event_id, event_id)

      on_exit(fn ->
        Application.delete_env(:ysc, :webhooks_context)
        Application.delete_env(:ysc, :webhook_retry_nil_lookup_event_id)
      end)

      webhook = Repo.get_by!(WebhookEvent, event_id: event_id)

      Logger.put_module_level(WebhookRetryWorker, :none)

      assert {:error, :webhook_not_found_after_duplicate} =
               WebhookRetryWorker.retry_webhook(webhook)

      Logger.put_module_level(WebhookRetryWorker, :error)
    end

    test "parses Stripe payload when data key is omitted (object defaults to empty map)" do
      webhook =
        insert_webhook_event(%{
          state: :pending,
          event_type: "customer.created",
          payload: %{"created" => DateTime.to_unix(DateTime.utc_now())}
        })

      assert {:ok, :success} = WebhookRetryWorker.retry_webhook(webhook)
    end
  end
end

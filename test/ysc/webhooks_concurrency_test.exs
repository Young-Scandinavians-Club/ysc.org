defmodule Ysc.WebhooksConcurrencyTest do
  @moduledoc """
  Regression tests for webhook event locking under concurrent callers.

  PR #1015 fixed a TOCTOU race where `SELECT ... FOR UPDATE SKIP LOCKED` and the
  follow-up `:processing` state update ran as separate Repo calls, releasing the
  row lock before the update committed. These tests prove only one caller can win.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Webhooks

  describe "lock_webhook_event/1 concurrency" do
    test "allows only one concurrent caller to lock the same pending event",
         %{sandbox_owner: owner} do
      event =
        Webhooks.create_webhook_event!(%{
          provider: :stripe,
          event_id: "evt_concurrent_#{System.unique_integer([:positive])}",
          event_type: "payment_intent.succeeded",
          payload: %{"id" => "pi_concurrent"},
          state: :pending
        })

      results =
        1..10
        |> Task.async_stream(
          fn _ ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            Webhooks.lock_webhook_event(event.id)
          end,
          max_concurrency: 10,
          timeout: 5_000
        )
        |> Enum.to_list()

      successes = Enum.count(results, &match?({:ok, {:ok, _}}, &1))

      already_processing =
        Enum.count(results, &match?({:ok, {:error, :already_processing}}, &1))

      assert successes == 1
      assert already_processing == 9
      assert Webhooks.get_webhook_event(event.id).state == :processing
    end
  end

  describe "lock_webhook_event_by_provider_and_event_id/2 concurrency" do
    test "allows only one concurrent caller to lock the same pending event",
         %{sandbox_owner: owner} do
      provider_event_id =
        "evt_provider_concurrent_#{System.unique_integer([:positive])}"

      _event =
        Webhooks.create_webhook_event!(%{
          provider: :stripe,
          event_id: provider_event_id,
          event_type: "charge.succeeded",
          payload: %{"id" => "ch_concurrent"},
          state: :pending
        })

      results =
        1..10
        |> Task.async_stream(
          fn _ ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            Webhooks.lock_webhook_event_by_provider_and_event_id(
              :stripe,
              provider_event_id
            )
          end,
          max_concurrency: 10,
          timeout: 5_000
        )
        |> Enum.to_list()

      successes = Enum.count(results, &match?({:ok, {:ok, _}}, &1))

      already_processing =
        Enum.count(results, &match?({:ok, {:error, :already_processing}}, &1))

      assert successes == 1
      assert already_processing == 9

      assert Webhooks.get_webhook_event_by_provider_and_event_id(
               :stripe,
               provider_event_id
             ).state == :processing
    end
  end
end

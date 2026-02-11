defmodule Ysc.Repo.Migrations.AddWebhookRetryIndices do
  use Ecto.Migration

  @moduledoc """
  Adds composite indices to optimize the webhook retry worker queries.

  The WebhookRetryWorker performs the following queries:
  1. Find pending/failed webhooks filtered by state and inserted_at range
  2. Find stuck processing webhooks filtered by state and updated_at range

  These composite indices allow efficient index-only scans for these queries.
  """

  def change do
    # Composite index for pending/failed webhook queries
    # Supports: WHERE state IN ('pending', 'failed') AND inserted_at < ? AND inserted_at > ?
    # ORDER BY inserted_at ASC
    create index(:webhook_events, [:state, :inserted_at],
             name: :webhook_events_state_inserted_at_idx
           )

    # Composite index for stuck processing webhook queries
    # Supports: WHERE state = 'processing' AND updated_at < ?
    # ORDER BY updated_at ASC
    create index(:webhook_events, [:state, :updated_at],
             name: :webhook_events_state_updated_at_idx
           )
  end
end

defmodule Ysc.Repo.Migrations.OptimizeTicketOrdersTimeoutQuery do
  @moduledoc """
  Optimizes the Tickets.TimeoutWorker query performance by adding a composite
  partial index on ticket_orders.

  ## Problem
  The TimeoutWorker runs every 5 minutes (288x per day) with this query:
    WHERE status = 'pending' AND expires_at < now()
    ORDER BY expires_at
    LIMIT 100

  Currently has separate indices on [:status] and [:expires_at], forcing
  PostgreSQL to choose between:
  1. Use status index → filter → sort by expires_at (requires sorting)
  2. Use expires_at index → already sorted → filter by status (sequential scan on subset)

  ## Solution
  Create a composite partial index [:status, :expires_at] that:
  - Filters only 'pending' status in the index (smaller, faster)
  - Includes expires_at for ordering without additional sort
  - Allows index-only scans for this critical query

  ## Performance Impact
  - Expected 2-5x improvement on a query running 288x per day
  - Index will be smaller due to partial condition
  - No impact on writes (only pending orders, typically <1% of total)

  ## Testing
  After migration, verify with:
    mix run priv/repo/scripts/analyze_ticket_timeout_query.exs

  Expected EXPLAIN output should show:
    Index Scan using ticket_orders_pending_timeout_lookup
  """
  use Ecto.Migration

  def up do
    # Create composite partial index optimized for timeout worker
    create index(:ticket_orders, [:status, :expires_at],
             where: "status = 'pending'",
             name: :ticket_orders_pending_timeout_lookup,
             comment: "Optimizes Tickets.TimeoutWorker query (runs every 5min)"
           )
  end

  def down do
    drop index(:ticket_orders, [:status, :expires_at],
           name: :ticket_orders_pending_timeout_lookup
         )
  end
end

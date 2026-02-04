#!/usr/bin/env elixir
# Performance analysis script for Tickets.TimeoutWorker query
#
# Usage: mix run priv/repo/scripts/analyze_ticket_timeout_query.exs
#
# This script analyzes the query used by Tickets.TimeoutWorker to identify
# expired ticket orders. Run this before and after the index migration to
# compare performance.

alias Ysc.Repo
alias Ysc.Tickets.TicketOrder
import Ecto.Query

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Ticket Orders Timeout Query Performance Analysis")
IO.puts(String.duplicate("=", 80))

# Get table statistics
result = Ecto.Adapters.SQL.query!(Repo, """
  SELECT
    COUNT(*) as total_orders,
    COUNT(*) FILTER (WHERE status = 'pending') as pending_orders,
    COUNT(*) FILTER (WHERE status = 'pending' AND expires_at < NOW()) as expired_pending
  FROM ticket_orders
""", [])

if result.num_rows > 0 do
  [total, pending, expired] = hd(result.rows)
  IO.puts("\n=== Table Statistics ===")
  IO.puts("Total ticket orders: #{total}")
  IO.puts("Pending orders: #{pending}")
  IO.puts("Expired pending orders: #{expired}")
end

# Show available indices
IO.puts("\n=== Available Indices on ticket_orders ===")
indices = Ecto.Adapters.SQL.query!(Repo, """
  SELECT
    indexname,
    indexdef
  FROM pg_indexes
  WHERE tablename = 'ticket_orders'
  ORDER BY indexname
""", [])

Enum.each(indices.rows, fn [name, definition] ->
  IO.puts("\n#{name}:")
  IO.puts("  #{definition}")
end)

# Build the actual worker query
now = DateTime.utc_now()

query = from(t in TicketOrder,
  where: t.status == :pending and t.expires_at < ^now,
  order_by: [asc: t.expires_at],
  limit: 100
)

{sql, params} = Repo.to_sql(:all, query)

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Query SQL")
IO.puts(String.duplicate("=", 80))
IO.puts(sql)

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("EXPLAIN (ANALYZE, BUFFERS)")
IO.puts(String.duplicate("=", 80))

explain_query = "EXPLAIN (ANALYZE, BUFFERS, VERBOSE) " <> sql
result = Ecto.Adapters.SQL.query!(Repo, explain_query, params)

Enum.each(result.rows, fn [row] -> IO.puts(row) end)

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Analysis")
IO.puts(String.duplicate("=", 80))

explain_text = Enum.map_join(result.rows, "\n", fn [row] -> row end)

cond do
  String.contains?(explain_text, "ticket_orders_pending_timeout_lookup") ->
    IO.puts("✓ OPTIMIZED: Using composite partial index 'ticket_orders_pending_timeout_lookup'")
    IO.puts("  This is the expected result after running the optimization migration.")

  String.contains?(explain_text, "Index Scan") or String.contains?(explain_text, "Index Only Scan") ->
    IO.puts("⚠ USING INDEX: Query is using an index, but not the optimized one.")
    IO.puts("  Consider running the optimization migration:")
    IO.puts("  mix ecto.migrate")

  String.contains?(explain_text, "Seq Scan") ->
    IO.puts("⚠ SEQUENTIAL SCAN: Query is doing a full table scan!")
    IO.puts("  This is inefficient. Run the optimization migration:")
    IO.puts("  mix ecto.migrate")

  true ->
    IO.puts("? UNKNOWN: Unable to determine query plan type.")
    IO.puts("  Review the EXPLAIN output above.")
end

# Show index usage statistics if available
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Index Usage Statistics (if available)")
IO.puts(String.duplicate("=", 80))

stats = Ecto.Adapters.SQL.query!(Repo, """
  SELECT
    indexrelname as index_name,
    idx_scan as times_used,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
  FROM pg_stat_user_indexes
  WHERE schemaname = 'public'
    AND relname = 'ticket_orders'
  ORDER BY idx_scan DESC
""", [])

if stats.num_rows > 0 do
  IO.puts("\n#{String.pad_trailing("Index Name", 45)} | Times Used | Tuples Read | Size")
  IO.puts(String.duplicate("-", 80))

  Enum.each(stats.rows, fn [name, scans, reads, fetches, size] ->
    IO.puts("#{String.pad_trailing(name, 45)} | #{String.pad_leading("#{scans || 0}", 10)} | #{String.pad_leading("#{reads || 0}", 11)} | #{size}")
  end)
else
  IO.puts("No statistics available. Indices may be newly created.")
end

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Complete")
IO.puts(String.duplicate("=", 80) <> "\n")

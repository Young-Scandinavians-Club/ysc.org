#!/usr/bin/env elixir
# Performance analysis script for Subscriptions.ExpirationWorker query
#
# Usage: mix run priv/repo/scripts/analyze_subscription_expiration_query.exs
#
# This script analyzes the query used by Subscriptions.ExpirationWorker to
# identify expired subscriptions. Run this before and after the index migration
# to compare performance.

alias Ysc.Repo
alias Ysc.Subscriptions.Subscription
import Ecto.Query

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Subscriptions Expiration Query Performance Analysis")
IO.puts(String.duplicate("=", 80))

# Get table statistics
result = Ecto.Adapters.SQL.query!(Repo, """
  SELECT
    COUNT(*) as total_subscriptions,
    COUNT(*) FILTER (WHERE stripe_status IN ('active', 'trialing')) as active_trialing,
    COUNT(*) FILTER (WHERE ends_at IS NULL) as no_end_date,
    COUNT(*) FILTER (WHERE ends_at IS NOT NULL) as has_end_date,
    COUNT(*) FILTER (
      WHERE stripe_status IN ('active', 'trialing')
        AND ((current_period_end < NOW() AND ends_at IS NULL)
             OR (ends_at < NOW() AND ends_at IS NOT NULL))
    ) as potentially_expired
  FROM subscriptions
""", [])

if result.num_rows > 0 do
  [total, active, no_end, has_end, expired] = hd(result.rows)
  IO.puts("\n=== Table Statistics ===")
  IO.puts("Total subscriptions: #{total}")
  IO.puts("Active/trialing: #{active}")
  IO.puts("  - Without end date (renewals): #{no_end}")
  IO.puts("  - With end date (cancelled): #{has_end}")
  IO.puts("Potentially expired: #{expired}")
end

# Show available indices
IO.puts("\n=== Available Indices on subscriptions ===")
indices = Ecto.Adapters.SQL.query!(Repo, """
  SELECT
    indexname,
    indexdef
  FROM pg_indexes
  WHERE tablename = 'subscriptions'
  ORDER BY indexname
""", [])

Enum.each(indices.rows, fn [name, definition] ->
  IO.puts("\n#{name}:")
  IO.puts("  #{definition}")
end)

# Build the actual worker query
now = DateTime.utc_now()

query = from(s in Subscription,
  where: s.stripe_status in ["active", "trialing"],
  where:
    (not is_nil(s.current_period_end) and s.current_period_end < ^now) or
    (not is_nil(s.ends_at) and s.ends_at < ^now),
  preload: [:user]
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

renewal_optimized = String.contains?(explain_text, "subscriptions_active_renewal_lookup")
cancellation_optimized = String.contains?(explain_text, "subscriptions_cancelled_expiration_lookup")

cond do
  renewal_optimized and cancellation_optimized ->
    IO.puts("✓ FULLY OPTIMIZED: Using both partial indices!")
    IO.puts("  - subscriptions_active_renewal_lookup (for renewals)")
    IO.puts("  - subscriptions_cancelled_expiration_lookup (for cancellations)")
    IO.puts("  This is the expected result after running both optimization migrations.")

  renewal_optimized ->
    IO.puts("⚠ PARTIALLY OPTIMIZED: Using renewal index only.")
    IO.puts("  - Found: subscriptions_active_renewal_lookup")
    IO.puts("  - Missing: subscriptions_cancelled_expiration_lookup")
    IO.puts("  Run the cancellation optimization migration:")
    IO.puts("  mix ecto.migrate")

  String.contains?(explain_text, "Index Scan") or String.contains?(explain_text, "Index Only Scan") ->
    IO.puts("⚠ USING INDEX: Query is using an index, but not the optimized ones.")
    IO.puts("  Consider running the optimization migrations:")
    IO.puts("  mix ecto.migrate")

  String.contains?(explain_text, "Seq Scan") ->
    IO.puts("⚠ SEQUENTIAL SCAN: Query is doing a full table scan!")
    IO.puts("  This is inefficient. Run the optimization migrations:")
    IO.puts("  mix ecto.migrate")

  true ->
    IO.puts("? UNKNOWN: Unable to determine query plan type.")
    IO.puts("  Review the EXPLAIN output above.")
end

# Show index usage statistics
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
    AND relname = 'subscriptions'
  ORDER BY idx_scan DESC
""", [])

if stats.num_rows > 0 do
  IO.puts("\n#{String.pad_trailing("Index Name", 50)} | Times Used | Tuples Read | Size")
  IO.puts(String.duplicate("-", 90))

  Enum.each(stats.rows, fn [name, scans, reads, fetches, size] ->
    IO.puts("#{String.pad_trailing(name, 50)} | #{String.pad_leading("#{scans || 0}", 10)} | #{String.pad_leading("#{reads || 0}", 11)} | #{size}")
  end)
else
  IO.puts("No statistics available. Indices may be newly created.")
end

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Recommendation")
IO.puts(String.duplicate("=", 80))

IO.puts("""
Consider refactoring the ExpirationWorker to use two separate queries instead
of a single query with OR condition:

1. Query for active renewals:
   WHERE stripe_status IN ('active', 'trialing')
     AND ends_at IS NULL
     AND current_period_end < NOW()

2. Query for cancelled subscriptions:
   WHERE stripe_status IN ('active', 'trialing')
     AND ends_at IS NOT NULL
     AND ends_at < NOW()

This approach gives PostgreSQL clearer query plans and allows better use of
the partial indices. The OR condition can sometimes confuse the query planner.
""")

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Complete")
IO.puts(String.duplicate("=", 80) <> "\n")

# Query Optimization Guide

This document identifies complex queries that should be profiled and optimized, along with guidance on how to profile them.

## Complex Queries Identified

### 1. Event List Queries with Aggregations

**Location**: `lib/ysc/events.ex` - `list_upcoming_events/1`, `list_past_events/1`

**Complexity**:
- Multiple LEFT JOINs (Ticket, TicketTier)
- GROUP BY with aggregations (count)
- Fragment-based calculations (`selling_fast`)
- Complex ORDER BY with CASE statements

**Recommendations**:
- Profile with `Ecto.Adapters.SQL.explain/3` to check index usage
- Consider materialized view for event statistics if queries are slow
- Verify indexes on `tickets.event_id`, `tickets.status`, `tickets.inserted_at`
- Consider denormalizing `recent_tickets_count` to events table if frequently accessed

**Profiling Code**:
```elixir
query = from(e in Event, ...) # full query
Ecto.Adapters.SQL.explain(Ysc.Repo, :all, query)
```

### 2. User List Queries with Membership Filtering

**Location**: `lib/ysc/accounts.ex` - `list_paginated_users/2` with membership filters

**Complexity**:
- Multiple LEFT JOINs (Subscription, primary User, primary Subscriptions)
- Complex WHERE clauses with OR conditions
- Post-query filtering and sorting in Elixir

**Recommendations**:
- Profile to verify index usage on `users.state`, `subscriptions.user_id`, `subscriptions.stripe_status`
- Consider adding composite index on `(user_id, stripe_status)` for subscriptions
- Consider denormalizing membership status to users table if filtering is frequent
- Move membership filtering to database level if possible

### 3. Revenue Statistics Aggregations

**Location**: `lib/ysc_web/live/admin/admin_dashboard_live.ex` - `calculate_all_revenue_stats/0`

**Complexity**:
- Multiple date range queries
- Aggregations across multiple ledger accounts
- Complex date calculations

**Recommendations**:
- Profile to check if indexes on `ledger_entries.account_id`, `ledger_entries.inserted_at` are used
- Consider caching results with short TTL (5-10 minutes)
- Consider materialized view for daily/monthly revenue summaries
- Use database functions for date calculations instead of Elixir

### 4. Booking Availability Calculations

**Location**: `lib/ysc/bookings.ex` - `get_available_rooms/3`, `get_clear_lake_daily_availability/2`, `get_tahoe_daily_availability/2`

**Complexity**:
- Date range queries with overlaps
- Multiple table joins (Bookings, PropertyInventory, RoomInventory, Blackouts)
- In-memory processing of date ranges

**Recommendations**:
- Profile to verify index usage on date columns
- Consider database-level availability calculation functions
- Cache results aggressively (1-2 minute TTL)
- Consider denormalizing availability flags

### 5. User Exporter Query

**Location**: `lib/ysc_web/workers/user_exporter.ex` - `build_csv/2`

**Complexity**:
- Multiple LEFT JOINs (Subscription, primary User, primary Subscriptions)
- Complex WHERE clauses with OR conditions
- Subquery for counting

**Recommendations**:
- Profile to verify index usage
- Consider using database views for subscribed users
- Batch processing for large exports
- Add indexes on `users.primary_user_id` if missing

### 6. Search Queries with SIMILARITY

**Location**: `lib/ysc/search.ex` - `global_search/2`

**Complexity**:
- Multiple separate queries across different tables
- SIMILARITY functions (requires pg_trgm extension)
- ILIKE pattern matching

**Recommendations**:
- Verify pg_trgm extension is enabled and indexes are created
- Profile each search query separately
- Consider full-text search indexes (GIN indexes on text columns)
- Consider using PostgreSQL's full-text search instead of SIMILARITY for better performance

## Profiling Tools and Techniques

### 1. Using Ecto.Adapters.SQL.explain

```elixir
# In IEx or a test
query = from(e in Event, where: e.state == :published)
Ecto.Adapters.SQL.explain(Ysc.Repo, :all, query)
```

This will show the query plan including:
- Index usage
- Join algorithms
- Estimated row counts
- Execution cost

### 2. Enable Query Logging

Add to `config/dev.exs`:
```elixir
config :ysc, Ysc.Repo,
  log: :info,
  log_slow_queries: 100  # Log queries taking > 100ms
```

### 3. Use pg_stat_statements

The application already has `pg_stat_statements` enabled (see migration `20250119000000_enable_pg_stat_statements.exs`).

Query slow statements:
```sql
SELECT
  query,
  calls,
  total_exec_time,
  mean_exec_time,
  max_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;
```

### 4. Monitor in Production

- Use Sentry or similar for slow query alerts
- Monitor database CPU usage
- Track query execution times in logs

## Index Verification

After adding indexes, verify they're being used:

```sql
-- Check index usage
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
```

## Optimization Strategies

### 1. Add Missing Indexes
- Foreign keys used in WHERE clauses
- Date columns used for filtering
- Composite indexes for common filter combinations

### 2. Denormalization
- Consider denormalizing frequently calculated values
- Example: Store `recent_tickets_count` on events table, update via triggers

### 3. Materialized Views
- For complex aggregations that don't need real-time data
- Refresh periodically (e.g., every 5-15 minutes)

### 4. Query Restructuring
- Move filtering to database level instead of Elixir
- Use database functions for calculations
- Batch multiple queries into single queries where possible

### 5. Caching
- Cache expensive query results
- Use appropriate TTLs based on data freshness requirements
- Implement cache invalidation strategies

## Next Steps

1. Run `Ecto.Adapters.SQL.explain/3` on identified complex queries
2. Check `pg_stat_statements` in production for actual slow queries
3. Verify indexes are being used (not just created)
4. Implement optimizations based on profiling results
5. Monitor query performance after optimizations

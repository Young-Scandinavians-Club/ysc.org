# Database Performance Analysis Scripts

This directory contains scripts for analyzing and verifying database query performance, particularly for batch and async workers.

## Available Scripts

### 1. analyze_ticket_timeout_query.exs

Analyzes the `Tickets.TimeoutWorker` query performance.

**Worker**: Runs every 5 minutes (288x per day)
**Query**: Finds pending ticket orders that have exceeded their timeout
**Index**: `ticket_orders_pending_timeout_lookup`

**Usage**:
```bash
# Run before migration to see baseline performance
mix run priv/repo/scripts/analyze_ticket_timeout_query.exs

# Run migration
mix ecto.migrate

# Run again to verify improvement
mix run priv/repo/scripts/analyze_ticket_timeout_query.exs
```

**What to look for**:
- ✓ Should show "Using composite partial index 'ticket_orders_pending_timeout_lookup'"
- Index scan should be faster than sequential scan
- Check "Planning Time" and "Execution Time" in output

---

### 2. analyze_subscription_expiration_query.exs

Analyzes the `Subscriptions.ExpirationWorker` query performance.

**Worker**: Runs every 15 minutes (96x per day)
**Query**: Finds expired subscriptions (both renewals and cancellations)
**Indices**:
- `subscriptions_active_renewal_lookup` (existing)
- `subscriptions_cancelled_expiration_lookup` (new)

**Usage**:
```bash
# Run before migration to see baseline performance
mix run priv/repo/scripts/analyze_subscription_expiration_query.exs

# Run migration
mix ecto.migrate

# Run again to verify improvement
mix run priv/repo/scripts/analyze_subscription_expiration_query.exs
```

**What to look for**:
- ✓ Should show usage of both partial indices
- Watch for "Bitmap Index Scan" or "Index Scan" on both query paths
- Consider the refactoring recommendation if OR condition is still problematic

---

## Understanding the Output

### Table Statistics
Shows current data distribution:
- Total records in the table
- How many match the worker's filter conditions
- Helps estimate index efficiency

### Available Indices
Lists all indices on the table with their definitions. Verify that the optimization indices exist after migration.

### Query SQL
The actual SQL query being executed by the worker. This is what Ecto generates.

### EXPLAIN ANALYZE
PostgreSQL's query execution plan showing:
- **Planning Time**: How long to plan the query
- **Execution Time**: How long to run the query
- **Index Scan vs Seq Scan**: Whether indices are being used
- **Rows**: How many rows were examined vs returned
- **Buffers**: Memory usage statistics

### Analysis
Automated interpretation of the query plan:
- ✓ Optimized: Using the correct index
- ⚠ Partial: Using some but not all optimizations
- ⚠ Sequential Scan: Not using indices (slow)

### Index Usage Statistics
Real-world statistics from production:
- **Times Used**: How many times the index has been used
- **Tuples Read**: How many index entries were read
- **Size**: Index storage size

---

## Performance Baselines

Expected improvements after optimization:

| Worker | Frequency | Before | After | Improvement |
|--------|-----------|--------|-------|-------------|
| TimeoutWorker | Every 5min | ~50-100ms | ~10-20ms | 2-5x faster |
| ExpirationWorker | Every 15min | ~30-80ms | ~10-25ms | 2-4x faster |

*Actual results depend on table size and data distribution*

---

## Troubleshooting

### "No statistics available"
Index usage stats are collected over time. Run the worker a few times, then check again:
```bash
# Manually trigger the worker
iex -S mix
> Ysc.Tickets.TimeoutWorker.perform(%Oban.Job{})
```

### "Sequential Scan" after migration
1. Verify migration ran: `mix ecto.migrations`
2. Check index exists: Look for index name in "Available Indices" section
3. Run ANALYZE: `ANALYZE ticket_orders;` in psql
4. Check table size: Small tables (<1000 rows) may not use indices

### "Wrong index being used"
PostgreSQL's query planner may choose different indices based on statistics. Run:
```sql
ANALYZE ticket_orders;
ANALYZE subscriptions;
```

---

## Additional Monitoring

For ongoing performance monitoring in production:

### Check slow queries
```sql
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE query LIKE '%ticket_orders%'
   OR query LIKE '%subscriptions%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### Monitor index usage
```sql
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

### Index bloat check
```sql
SELECT
  indexname,
  pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND tablename IN ('ticket_orders', 'subscriptions')
ORDER BY pg_relation_size(indexrelid) DESC;
```

---

## Related Migrations

- `20260203195528_add_subscriptions_renewal_index.exs` - Subscriptions renewal lookup (existing)
- `20260203210518_optimize_ticket_orders_timeout_query.exs` - Ticket timeout optimization (new)
- `20260203210534_optimize_subscriptions_cancellation_lookup.exs` - Subscriptions cancellation optimization (new)

---

## Contact

For questions about these performance optimizations, refer to the migration files which contain detailed documentation about the problem, solution, and expected impact.

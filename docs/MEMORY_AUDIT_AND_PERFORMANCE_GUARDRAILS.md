# Memory Audit and Performance Guardrails

## Date
January 27, 2026

## Overview

This document summarizes the memory audit findings and performance guardrails implemented for the YSC application to prevent memory bloat in LiveView processes.

## Golden Signals - Performance Guardrails

The following metrics have been added to `lib/ysc_web/telemetry.ex` for monitoring:

### 1. Latency
- **Metric**: `phoenix.live_view.mount.stop.duration`
- **Event**: `[:phoenix, :live_view, :mount, :stop]`
- **Alert Threshold**: P95 > 200ms
- **Purpose**: Track LiveView mount performance to identify slow page loads

### 2. Traffic
- **Metric**: `phoenix.endpoint.stop.duration` (summary)
- **Metric**: `phoenix.endpoint.stop` (counter with status tags)
- **Event**: `[:phoenix, :endpoint, :stop]`
- **Alert Threshold**: Spike in 4xx/5xx responses
- **Purpose**: Track request volume and error rates

### 3. Errors
- **Metric**: `phoenix.error_rendered`
- **Event**: `[:phoenix, :error_rendered]`
- **Alert Threshold**: Any non-zero count
- **Purpose**: Immediate alerting on error page renders

### 4. Saturation
- **Metrics**: 
  - `vm.memory.total`
  - `vm.memory.processes_used`
  - `vm.memory.processes`
- **Event**: `[:vm, :memory, :*]`
- **Alert Threshold**: > 80% total RAM
- **Purpose**: Monitor memory usage to prevent OOM kills

## Memory Multipliers Audit

### ✅ Already Optimized

1. **Payments List** (`user_settings_live.ex`)
   - ✅ Uses `stream(:payments, ...)` for paginated payments
   - ✅ Properly resets stream on pagination/filtering

2. **Ticket Orders** (`user_tickets_live.ex`)
   - ✅ Uses `stream(:ticket_orders, ...)` for ticket order lists

3. **Admin Views**
   - ✅ Many admin LiveViews already use streams (admin_users_live, admin_media_live, admin_posts_live, events_live)

### ⚠️ Memory Concerns Identified

1. **Event Attendees List** (`event_details_live.ex`)
   - **Location**: `assign(:attendees_list, attendees_list)`
   - **Risk**: High - Events can have hundreds of attendees (max_attendees can be large)
   - **Current Behavior**: Loaded during async data loading, kept in memory for entire session
   - **Recommendation**: 
     - Option A: Load on-demand when modal opens (`handle_event("show-attendees-modal")`)
     - Option B: Use `temporary_assigns: [attendees_list: nil]` to clear after render
     - **Priority**: Medium - Only affects events with many attendees

2. **Agendas List** (`event_details_live.ex`)
   - **Location**: `assign(:agendas, agendas)`
   - **Risk**: Low-Medium - Typically small (1-5 agendas per event)
   - **Current Behavior**: Loaded and kept in memory
   - **Recommendation**: Monitor - Only optimize if events with many agendas become common

3. **File Uploads** (`expense_report_live.ex`, `admin_media_live.ex`)
   - **Location**: Multiple LiveViews with file uploads
   - **Risk**: Medium - Large binaries can be pinned in memory
   - **Current Behavior**: Files are consumed and uploaded to S3, but upload metadata may persist
   - **Recommendation**: 
     - Ensure `consume_uploaded_entry` is called promptly
     - Clear upload metadata after successful S3 upload
     - **Status**: ✅ Already using `consume_uploaded_entry` correctly

4. **Admin Bookings Lists** (`admin_bookings_live.ex`)
   - **Location**: Multiple list assigns (room_bookings, buyout_bookings, etc.)
   - **Risk**: Low-Medium - Admin-only, typically filtered/paginated
   - **Current Behavior**: Lists are assigned but may be filtered
   - **Recommendation**: Consider streams if lists grow large

## Recommendations

### Immediate Actions

1. **Monitor Golden Signals**
   - Set up alerts in Fly.io Grafana for:
     - LiveView mount P95 > 200ms
     - 4xx/5xx error rate spikes
     - VM memory > 80% total RAM
     - Any error page renders

2. **Load Attendees On-Demand**
   - Refactor `event_details_live.ex` to load `attendees_list` only when modal opens
   - This prevents loading potentially hundreds of attendees for every event page view

### Future Optimizations

1. **Convert Large Lists to Streams**
   - Review any lists that could grow > 50 items
   - Convert to streams if they're displayed in paginated/scrollable views

2. **Add Temporary Assigns for Modal Data**
   - Use `temporary_assigns` for data only needed in modals
   - Clear after modal closes to free memory

3. **Projection Queries**
   - Use `select` in Ecto queries to fetch only needed fields
   - Reduces memory footprint of large collections

## Monitoring

All metrics are exposed at `/metrics` endpoint and scraped by Fly.io's VictoriaMetrics/Prometheus.

### Key Metrics to Watch

- `phoenix_live_view_mount_duration_milliseconds` - P95 should be < 200ms
- `phoenix_endpoint_stop_total{status=~"4..|5.."}` - Error rate
- `vm_memory_total` - Should stay < 80% of available RAM
- `phoenix_error_rendered_total` - Should be 0

### Alert Configuration

Configure alerts in Fly.io Grafana:

```promql
# High mount latency
histogram_quantile(0.95, phoenix_live_view_mount_duration_milliseconds) > 200

# High error rate
rate(phoenix_endpoint_stop_total{status=~"4..|5.."}[5m]) > 0.1

# High memory usage
vm_memory_total / vm_memory_limit > 0.8

# Any errors
phoenix_error_rendered_total > 0
```

## Files Modified

- `lib/ysc_web/telemetry.ex` - Added Golden Signals metrics
- `lib/ysc/prom_ex.ex` - Custom business metrics (already implemented)

## Next Steps

1. Deploy and monitor Golden Signals metrics
2. Set up Grafana dashboards in Fly.io
3. Configure alerts for critical thresholds
4. Monitor production metrics for 1-2 weeks
5. Optimize `attendees_list` loading based on production data

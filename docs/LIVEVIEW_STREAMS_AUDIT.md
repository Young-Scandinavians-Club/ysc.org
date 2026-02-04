# LiveView Streams Memory Optimization Audit

This document identifies opportunities to use Phoenix LiveView Streams to reduce memory usage in LiveView processes.

## Already Using Streams ✅

The following LiveViews already use streams correctly:

1. **`admin_events_live.ex`** - Uses streams for events list ✅
2. **`admin_bookings_live.ex`** - Uses streams for reservations list ✅
3. **`admin_users_live.ex`** - Uses streams for users list ✅
4. **`admin_media_live.ex`** - Uses streams for images with pagination ✅
5. **`news_live.ex`** - Uses streams for posts with infinite scroll ✅
6. **`post_live.ex`** - Uses streams for comments ✅
7. **`events_live.ex`** (via component) - Uses streams for events ✅

## Opportunities for Streams 🔧

### High Priority (Unbounded Collections)

#### 1. `user_tickets_live.ex` - Ticket Orders List
**Issue**: Loads ALL ticket orders without pagination
**Location**: `lib/ysc_web/live/user_tickets_live.ex:135`
**Function**: `Tickets.list_user_ticket_orders/1` loads all orders
**Impact**: Could grow unbounded as users accumulate orders over time
**Recommendation**: Convert to streams with pagination or limit

#### 2. `home_live.ex` - Future Bookings
**Issue**: Loads ALL future bookings without limit
**Location**: `lib/ysc_web/live/home_live.ex:469-492`
**Function**: `get_future_active_bookings/1` loads all future bookings
**Impact**: Users with many bookings will consume excessive memory
**Recommendation**: Add limit (e.g., show only next 10 bookings) or use streams

#### 3. `home_live.ex` - Upcoming Tickets
**Issue**: Loads ALL upcoming tickets without limit
**Location**: `lib/ysc_web/live/home_live.ex:420-450`
**Function**: `get_upcoming_tickets/1` loads all upcoming tickets
**Impact**: Users with many tickets will consume excessive memory
**Recommendation**: Add limit (e.g., show only next 10 events) or use streams

#### 4. `tahoe_booking_live.ex` - Active Bookings
**Issue**: Loads all active bookings without limit
**Location**: `lib/ysc_web/live/tahoe_booking_live.ex:266`
**Impact**: Users with many active bookings will consume memory
**Recommendation**: Add limit or use streams

#### 5. `clear_lake_booking_live.ex` - Active Bookings
**Issue**: Similar to Tahoe - loads all active bookings
**Recommendation**: Add limit or use streams

### Medium Priority (Potentially Large Collections)

#### 6. `event_details_live.ex` - Agendas and Agenda Items
**Issue**: Loads all agendas and agenda items for an event
**Location**: `lib/ysc_web/live/event_details_live.ex:221-223`
**Impact**: Events with many agendas/items could be large
**Recommendation**: Consider streams if events regularly have 50+ agenda items

### Low Priority (Small Collections)

These are likely fine as-is since they're typically small:
- Ticket tiers in event details (usually < 10)
- Selected tickets (user selection, not persisted)
- Room lists (usually < 20 rooms)

## Completed Optimizations ✅

### 1. `user_tickets_live.ex` - Converted to Streams
**Status**: ✅ Completed
**Changes**:
- Converted `@ticket_orders` assign to use `stream(:ticket_orders, ...)`
- Added `phx-update="stream"` to container div
- Changed template to use `@streams.ticket_orders` with `{id, ticket_order}` pattern
- Added `limit: -50` to keep only last 50 orders in memory
- Updated cancel-order handler to use `stream(..., reset: true)`
- **Fixed empty state handling**: Replaced `Enum.empty?(@streams.ticket_orders)` with CSS `:only-child` selector pattern
- Added `only:` variant to Tailwind config for proper empty state display

**Memory Impact**: Reduced from unbounded to ~2.5MB max (50 orders × 50KB)

### 2. `home_live.ex` - Added Limits
**Status**: ✅ Completed
**Changes**:
- Added `limit \\ 10` parameter to `get_future_active_bookings/2`
- Added `limit: ^limit` to database query
- Added `Enum.take(limit)` after filtering
- Added `limit \\ 10` parameter to `get_upcoming_tickets/2`
- Added `Enum.take(limit)` after sorting

**Memory Impact**: Reduced from unbounded to ~500KB max (10 bookings + 10 tickets)

### 3. `tahoe_booking_live.ex` - Added Limits
**Status**: ✅ Completed
**Changes**:
- Added `limit \\ 10` parameter to `get_active_bookings/2`
- Added `limit: ^limit` to database query
- Added `Enum.take(limit)` after filtering

**Memory Impact**: Reduced from unbounded to ~300KB max (10 bookings)

## Implementation Recommendations

### For Unbounded Collections

1. **Add Limits**: For collections that should show a limited view (like home page), add a limit:
   ```elixir
   # Instead of loading all
   future_bookings = get_future_active_bookings(user_id)

   # Load with limit
   future_bookings = get_future_active_bookings(user_id, limit: 10)
   ```

2. **Use Streams with Pagination**: For collections that should be browsable:
   ```elixir
   # In mount/3
   socket
   |> assign(:page, 1)
   |> assign(:per_page, 20)
   |> paginate_ticket_orders(1)

   # Helper function
   defp paginate_ticket_orders(socket, page) do
     %{per_page: per_page} = socket.assigns
     orders = Tickets.list_user_ticket_orders_paginated(
       socket.assigns.current_user.id,
       page,
       per_page
     )
     socket
     |> assign(:page, page)
     |> assign(:end_of_timeline?, length(orders) < per_page)
     |> stream(:ticket_orders, orders, reset: true)
   end
   ```

3. **Use Streams with Limits**: For collections that should show recent items:
   ```elixir
   socket
   |> stream(:future_bookings, bookings, limit: -10)  # Keep last 10
   ```

## Memory Impact Analysis

### Current Memory Usage (Estimated)

- **user_tickets_live**: ~50KB per order × N orders (unbounded)
- **home_live**: ~30KB per booking × N bookings + ~20KB per ticket × M tickets (unbounded)
- **tahoe_booking_live**: ~30KB per booking × N bookings (unbounded)

### After Optimization

- **user_tickets_live**: ~50KB × 20 orders = ~1MB (fixed)
- **home_live**: ~30KB × 10 bookings + ~20KB × 10 tickets = ~500KB (fixed)
- **tahoe_booking_live**: ~30KB × 10 bookings = ~300KB (fixed)

**Estimated memory reduction**: 80-95% for users with many bookings/tickets

## Priority Order

1. ✅ **user_tickets_live.ex** - Highest impact, unbounded growth
2. ✅ **home_live.ex** - High impact, shown on every page load
3. ✅ **tahoe_booking_live.ex** - Medium impact, shown when booking
4. ✅ **clear_lake_booking_live.ex** - Medium impact, shown when booking
5. ⚠️ **event_details_live.ex** - Low priority, typically small collections


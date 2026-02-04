# Caching Opportunities

This document identifies additional caching opportunities for frequently accessed data to improve performance.

## Existing Caching Infrastructure

The application already has excellent caching infrastructure using Cachex:

- **SeasonCache** - Caches season lookups per property/date (10 min TTL)
- **PricingRuleCache** - Caches pricing rules with version-based invalidation
- **RefundPolicyCache** - Caches refund policies with version-based invalidation
- **MembershipCache** - Caches user membership data (5 min TTL)
- **Settings Cache** - Caches site settings on startup

## Identified Caching Opportunities

### 1. User Profile Data Cache

**Location**: `lib/ysc/accounts.ex` - `get_user!/2`, `get_user/2`

**Issue**: User data is frequently accessed in LiveView mount functions and event handlers, but not cached.

**Frequency**: High - accessed on every page load for authenticated users

**Recommendation**:
- Cache user data with a short TTL (2-5 minutes)
- Invalidate on user updates (email, profile changes)
- Cache key: `user:profile:{user_id}`

**Impact**: Medium - reduces database queries for frequently accessed user data

### 2. Event Pricing Calculations

**Location**: `lib/ysc/events.ex` - `add_pricing_info_batch/1`

**Issue**: Event pricing calculations involve multiple queries for ticket tiers and ticket counts.

**Frequency**: High - calculated for every event list display

**Recommendation**:
- Cache event pricing info with short TTL (5-10 minutes)
- Invalidate when ticket tiers change or tickets are purchased
- Cache key: `event:pricing:{event_id}`

**Impact**: High - reduces complex queries for event listings

### 3. Room Availability Checks

**Location**: `lib/ysc/bookings.ex` - `get_available_rooms/3`, `get_clear_lake_daily_availability/2`, `get_tahoe_daily_availability/2`

**Issue**: Availability calculations are expensive and frequently accessed during booking flows.

**Frequency**: Very High - checked on every calendar view update

**Recommendation**:
- Cache availability data with very short TTL (1-2 minutes)
- Invalidate immediately when bookings are created/cancelled
- Cache key: `availability:{property}:{start_date}:{end_date}`

**Impact**: Very High - significantly reduces database load during booking flows

### 4. Room List Cache

**Location**: `lib/ysc/bookings.ex` - `list_rooms/1`

**Issue**: Room lists are loaded frequently but change infrequently.

**Frequency**: High - loaded in admin bookings page and booking flows

**Recommendation**:
- Cache room lists per property with version-based invalidation
- Invalidate when rooms are created/updated/deleted
- Cache key: `rooms:list:{property}`

**Impact**: Medium - reduces queries for relatively static data

### 5. Blackout List Cache

**Location**: `lib/ysc/bookings.ex` - `list_blackouts/3`

**Issue**: Blackouts are checked frequently but change infrequently.

**Frequency**: High - checked in availability calculations

**Recommendation**:
- Cache blackout lists with version-based invalidation
- Invalidate when blackouts are created/updated/deleted
- Cache key: `blackouts:{property}`

**Impact**: Medium - reduces queries for relatively static data

### 6. Ticket Order Status Cache

**Location**: `lib/ysc/tickets.ex` - Various ticket order lookups

**Issue**: Ticket order status is checked frequently but changes infrequently after completion.

**Frequency**: Medium - checked in user tickets page and event details

**Recommendation**:
- Cache completed ticket order status (longer TTL - 1 hour)
- Don't cache pending/expired orders (short-lived)
- Cache key: `ticket_order:status:{order_id}`

**Impact**: Low-Medium - reduces queries for completed orders

## Implementation Priority

### High Priority (Immediate Impact)
1. **Room Availability Checks** - Very high frequency, expensive calculations
2. **Event Pricing Calculations** - High frequency, complex queries

### Medium Priority (Good ROI)
3. **User Profile Data Cache** - High frequency, simple implementation
4. **Room List Cache** - High frequency, relatively static data
5. **Blackout List Cache** - High frequency, relatively static data

### Low Priority (Nice to Have)
6. **Ticket Order Status Cache** - Lower frequency, less impact

## Implementation Notes

- Use Cachex for all caching (already configured)
- Implement version-based invalidation for data that changes infrequently
- Use TTL-based caching for data that changes frequently
- Always provide database fallback for cache misses
- Log cache hits/misses for monitoring
- Consider cache warming for critical paths

## Cache Invalidation Strategy

- **Immediate invalidation**: Booking creation/cancellation, room updates
- **Version-based invalidation**: Room lists, blackouts, pricing rules
- **TTL-based expiration**: User profiles, availability data
- **PubSub events**: Use existing PubSub infrastructure for distributed cache invalidation

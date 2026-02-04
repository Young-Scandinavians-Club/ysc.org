# Concurrency Testing for Booking Systems

This document explains the comprehensive concurrency testing strategy implemented to prevent data races and overbooking in both ticket sales and cabin bookings.

## Overview

The booking systems use PostgreSQL row-level locking (`FOR UPDATE`) within database transactions to prevent race conditions. These tests verify that the locking mechanisms work correctly under high-concurrency scenarios.

## Testing Strategy

### 1. Concurrency Simulation

We use Elixir's `Task.async_stream/3` to simulate multiple users attempting to book simultaneously. This creates true concurrent database operations that test the locking mechanisms.

**Key Techniques:**
- **High Concurrency**: Tests run with 20-120 concurrent booking attempts
- **Real Database Transactions**: All tests use actual database transactions (not mocks)
- **Capacity Boundary Testing**: Tests specifically target capacity limits (e.g., 50 tickets, 12 guests)
- **Mixed Scenarios**: Tests combine different booking types and patterns

### 2. Test Coverage

#### Ticket Booking Tests (`test/ysc/tickets/booking_locker_concurrency_test.exs`)

**Tier Capacity Limits:**
- ✅ Concurrent bookings for same tier (60 users, 50 capacity)
- ✅ Multiple tiers simultaneously
- ✅ Multiple tickets per booking
- ✅ Pending tickets count against capacity

**Event Capacity Limits:**
- ✅ Event-level max_attendees respected across tiers
- ✅ Mixed tier bookings don't exceed event capacity

**Edge Cases:**
- ✅ Unlimited tiers allow all bookings
- ✅ Rapid sequential bookings
- ✅ Same user multiple bookings

**Transaction Isolation:**
- ✅ FOR UPDATE locks prevent race conditions
- ✅ No duplicate bookings
- ✅ Serialized transaction execution

#### Cabin Booking Tests (`test/ysc/bookings/booking_locker_concurrency_test.exs`)

**Tahoe Room Bookings:**
- ✅ Same room, same dates (only 1 succeeds)
- ✅ Different rooms (all succeed)
- ✅ Overlapping dates prevented
- ✅ Non-overlapping dates allowed

**Clear Lake Per-Guest Bookings:**
- ✅ Capacity limits enforced (12 guests max)
- ✅ Mixed guest counts
- ✅ Multiple guests per booking

**Buyout Bookings:**
- ✅ Only one buyout per property/date range
- ✅ Buyout prevents room bookings
- ✅ Room bookings prevent buyout
- ✅ Per-guest bookings prevented when buyout active

**Hold Management:**
- ✅ New bookings prevented while hold active
- ✅ New bookings allowed after hold released

**Transaction Isolation:**
- ✅ FOR UPDATE locks work correctly
- ✅ No double-booking possible

## How the Tests Work

### Example: Ticket Booking Test

```elixir
test "prevents overbooking when multiple users book same tier simultaneously" do
  # Setup: Create event with tier capacity of 50
  # 60 users try to book 1 ticket each simultaneously

  results =
    concurrent_users
    |> Task.async_stream(
      fn user ->
        BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 1})
      end,
      max_concurrency: 60,
      timeout: 10_000
    )
    |> Enum.to_list()

  # Verify exactly 50 succeeded, 10 failed
  successful_bookings = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
  assert successful_bookings == 50
end
```

**What This Tests:**
1. **Concurrency**: 60 simultaneous booking attempts
2. **Locking**: Only one transaction can lock the tier at a time
3. **Capacity**: Exactly 50 bookings succeed (tier capacity)
4. **Failures**: 10 bookings correctly fail with capacity exceeded

### Example: Cabin Booking Test

```elixir
test "prevents double-booking same room for same dates" do
  # 20 users try to book the same room for the same dates

  results =
    concurrent_users
    |> Task.async_stream(
      fn user ->
        BookingLocker.create_room_booking(
          user.id,
          [room.id],
          checkin_date,
          checkout_date,
          2
        )
      end,
      max_concurrency: 20
    )
    |> Enum.to_list()

  # Only one should succeed
  assert successful_bookings == 1
end
```

**What This Tests:**
1. **Room Locking**: FOR UPDATE locks on RoomInventory rows
2. **Date Range Locking**: All days in range are locked
3. **Conflict Detection**: Overlapping bookings are prevented
4. **Atomicity**: Either all days are booked or none

## Database Locking Mechanism

### Ticket Bookings

```elixir
# In BookingLocker.atomic_booking/3
Repo.transaction(fn ->
  # Lock event row
  event = Event
    |> where([e], e.id == ^event_id)
    |> lock("FOR UPDATE")
    |> Repo.one()

  # Lock all ticket tiers
  tiers = TicketTier
    |> where([tt], tt.event_id == ^event_id)
    |> lock("FOR UPDATE")
    |> Repo.all()

  # Check availability (within lock)
  # Create tickets (within same transaction)
end)
```

**Why This Works:**
- `FOR UPDATE` locks rows until transaction commits
- Only one transaction can hold the lock at a time
- Availability is checked AFTER acquiring locks
- Tickets are created BEFORE releasing locks

### Cabin Bookings

```elixir
# In BookingLocker.create_room_booking/5
Repo.transaction(fn ->
  # Lock room inventory for all days
  locked_room_inv = RoomInventory
    |> where([ri], ri.room_id in ^room_ids)
    |> where([ri], ri.day >= ^checkin_date and ri.day < ^checkout_date)
    |> lock("FOR UPDATE")
    |> Repo.all()

  # Check availability (within lock)
  # Update inventory (within same transaction)
end)
```

**Why This Works:**
- All days in date range are locked atomically
- Property inventory is also locked for buyout checks
- Updates happen within the locked transaction
- No other transaction can see intermediate state

## Test Execution

### Prerequisites

**IMPORTANT**: These tests require a running PostgreSQL database because:
- `FOR UPDATE` locks are PostgreSQL-specific database features
- `Ecto.Adapters.SQL.Sandbox` wraps a real database connection
- The tests use actual database transactions, not mocks

**Setup Options:**

1. **Local PostgreSQL** (recommended for development):
   ```bash
   # Ensure PostgreSQL is running locally
   # The test database will be created automatically
   make tests
   ```

2. **Docker Compose** (if using docker-compose.yml):
   ```bash
   docker-compose -f etc/docker/docker-compose.yml up -d postgres
   make tests
   ```

3. **Manual Setup**:
   ```bash
   # Create test database manually if needed
   MIX_ENV=test mix ecto.create
   MIX_ENV=test mix ecto.migrate
   mix test
   ```

The test suite will automatically:
- Create the test database (`ysc_test`) if it doesn't exist
- Run migrations
- Run test seeds
- Execute tests with proper cleanup

### Running the Tests

```bash
# Run all concurrency tests
mix test test/ysc/tickets/booking_locker_concurrency_test.exs
mix test test/ysc/bookings/booking_locker_concurrency_test.exs

# Run specific test
mix test test/ysc/tickets/booking_locker_concurrency_test.exs:45

# Run with verbose output
mix test --trace test/ysc/tickets/booking_locker_concurrency_test.exs

# Run via Makefile (handles DB setup automatically)
make tests
```

### Test Performance

- **Concurrency Level**: 20-120 concurrent operations
- **Timeout**: 10-15 seconds per test
- **Database**: Uses Ecto SQL Sandbox for isolation (requires real PostgreSQL)
- **Async**: Tests run with `async: false` to ensure database isolation
- **Pool Size**: Configured for 20 connections (see `config/test.exs`)

## What These Tests Guarantee

### ✅ No Overbooking
- Capacity limits are never exceeded
- Pending bookings count against capacity
- Event-level limits are respected

### ✅ No Data Races
- FOR UPDATE locks serialize transactions
- Availability checks happen within locked transactions
- No two transactions see the same availability count

### ✅ Atomic Operations
- All-or-nothing booking creation
- Inventory updates are atomic
- Failed bookings don't leave partial state

### ✅ Correct Failure Handling
- Capacity exceeded errors are returned correctly
- Failed bookings don't consume inventory
- Error messages are accurate

## Edge Cases Covered

1. **Boundary Conditions**: Exactly at capacity, one over capacity
2. **Mixed Patterns**: Different booking types simultaneously
3. **Rapid Sequential**: Not truly concurrent but tests sequential logic
4. **Same User Multiple**: User booking multiple times
5. **Hold Expiration**: Hold release and re-booking
6. **Overlapping Dates**: Various overlap scenarios
7. **Mixed Guest Counts**: Different guest counts in same booking window

## Future Enhancements

Potential additional tests:
- [ ] Network partition scenarios
- [ ] Database connection pool exhaustion
- [ ] Very long-running transactions
- [ ] Concurrent confirmations and releases
- [ ] Payment processing race conditions
- [ ] Timeout handling under load

## Conclusion

These tests provide comprehensive coverage of concurrency scenarios and verify that the database locking mechanisms prevent all forms of overbooking and data races. The tests are designed to be:

- **Realistic**: Simulate real-world concurrent booking scenarios
- **Thorough**: Cover edge cases and boundary conditions
- **Reliable**: Use actual database transactions, not mocks
- **Fast**: Complete in reasonable time (< 15 seconds per test)

By running these tests regularly, we ensure that the booking systems maintain data integrity under high-concurrency conditions.


# Test Suite Documentation

## Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/ysc_web/live/events_live_test.exs

# Run specific test by line number
mix test test/ysc_web/live/events_live_test.exs:165

# Run with coverage
mix test --cover
```

## Expected Log Messages

During test runs, you may see some database connection messages like:

```
Postgrex.Protocol disconnected: ** (DBConnection.ConnectionError) owner/client #PID<...> exited
```

**These are expected and not errors!**

These messages occur during test cleanup when:
1. A test finishes and its process exits
2. Async database operations (from LiveView `start_async`) are still completing
3. The Ecto SQL Sandbox connection is being cleaned up

These messages appear during the teardown phase and don't indicate test failures. They're a normal part of how Elixir's async operations interact with test isolation.

### Why We Can't Completely Suppress Them

The messages come from the `db_connection` application during process cleanup, which happens after the test completes. While we've configured the logger to filter most of these, some still appear due to timing - they're logged during a window where the logger is being torn down along with the test process.

## Test Utilities

### TestDataFactory

The `Ysc.TestDataFactory` module provides reusable test data creation:

```elixir
# Import in your test
import Ysc.TestDataFactory

# Create user with lifetime membership
user = user_with_membership(:lifetime)

# Create family with sub-accounts
family = family_with_sub_accounts(2)
# Returns: %{primary: user, sub_accounts: [user1, user2]}

# Create event in different states
event = event_with_state(:upcoming)
event = event_with_state(:past, with_image: true)

# Create event with tickets
event = event_with_tickets(tier_count: 3)

# Create complete ticket order scenario
%{user: user, event: event, order: order, tickets: tickets} =
  complete_ticket_order(ticket_count: 2, status: :confirmed)
```

### Async Database Operations

When testing LiveViews that use async database operations, the `YscWeb.Live.AsyncHelpers` module ensures proper sandbox access:

```elixir
# In LiveView modules
import YscWeb.Live.AsyncHelpers

# Use instead of Task.async_stream
results =
  tasks
  |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end)
  |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc -> Map.put(acc, key, value) end)
```

This automatically handles Ecto SQL Sandbox permissions for spawned tasks in tests.

## Test Coverage

Current coverage: **2695 tests, 0 failures**

Recently added comprehensive test coverage for:
- EventsLive (32 tests)
- EventDetailsLive (28 tests)
- ContactLive (30 tests)
- VolunteerLive (38 tests)
- OrderConfirmationLive (35 tests)

## Writing New Tests

### LiveView Tests

Follow these patterns for LiveView tests:

```elixir
defmodule YscWeb.MyLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory  # For test data utilities

  describe "mount/3 - unauthenticated" do
    test "loads page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/my-route")
      assert html =~ "Expected Content"
    end
  end

  describe "mount/3 - authenticated" do
    test "shows user-specific content", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/my-route")
      assert html =~ user.first_name
    end
  end

  describe "async data loading" do
    test "loads data after connection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/my-route")

      # Wait for async operations
      :timer.sleep(200)

      html = render(view)
      assert html =~ "Async Loaded Content"
    end
  end
end
```

### Key Testing Patterns

1. **Integration over Unit**: Test user-visible behavior, not implementation details
2. **Render Assertions**: Assert on HTML content users see, not internal state
3. **Async Handling**: Use `:timer.sleep()` for async operations, not state inspection
4. **Test Utilities**: Use TestDataFactory for consistent test data
5. **Accessibility**: Include tests for ARIA labels, heading hierarchy, keyboard nav

## Troubleshooting

### Tests Hanging

If tests hang, it's usually due to:
- Async operations not completing
- Database locks from improper sandbox usage
- Missing `start_owner!` in custom test setup

Solution: Ensure `use YscWeb.ConnCase, async: true` is present and check for proper sandbox setup.

### Flaky Tests

Common causes:
- Race conditions in async operations (add sleep or proper synchronization)
- Shared database state (ensure proper test isolation)
- Time-sensitive assertions (use relative dates, not absolute)

### Connection Errors

If you see legitimate connection errors (not the expected cleanup ones):
- Check database is running: `mix ecto.setup`
- Verify test database exists: `mix ecto.create`
- Reset database if corrupted: `mix ecto.reset`

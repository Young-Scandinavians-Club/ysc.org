# Test Suite Documentation

## Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/ysc_web/live/events_live_test.exs

# Run specific test by line number
mix test test/ysc_web/live/events_live_test.exs:165

# Run only previously failed tests
mix test --failed

# Run with coverage
mix test --cover
```

## Expected Log Messages

During test runs, you may see some database connection messages like:

```
Postgrex.Protocol disconnected: ** (DBConnection.ConnectionError) owner/client #PID<...> exited
```

**These are expected and not errors.**

These messages occur during test cleanup when:
1. A test finishes and its process exits
2. Async database operations (from LiveView `start_async`) are still completing
3. The Ecto SQL Sandbox connection is being cleaned up

They appear during the teardown phase and don't indicate test failures. They're a normal part of how Elixir's async operations interact with test isolation.

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

---

## Writing New Tests

### LiveView Tests

#### Waiting for async data (`start_async` / `assign_async`)

Many LiveViews load data asynchronously after the WebSocket connects using
`start_async` or `assign_async`. **Always** use `render_async/2` from
`Phoenix.LiveViewTest` to wait for those tasks — never use `:timer.sleep`.

```elixir
defmodule YscWeb.MyLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory

  describe "async data loading" do
    test "loads data after connection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/my-route")

      # render_async/2 polls until all start_async/assign_async tasks finish.
      # It returns the rendered HTML once everything is settled.
      render_async(view)

      html = render(view)
      assert html =~ "Async Loaded Content"
    end
  end
end
```

`render_async(view)` takes an optional timeout in milliseconds (default 5000ms):

```elixir
render_async(view)          # default 5 s timeout
render_async(view, 1_000)   # 1 s timeout — for faster feedback on failures
```

#### PubSub and handle_info events

After broadcasting a PubSub message, you do **not** need `render_async` or any
sleep. `render(view)` already synchronises with the LiveView process — by the
time it returns, all pending messages (including PubSub) have been handled:

```elixir
test "receives availability update via PubSub", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
  render_async(view)  # wait for initial async load

  Phoenix.PubSub.broadcast(Ysc.PubSub, "events:#{event.id}", %TicketAvailabilityUpdated{
    event_id: event.id
  })

  # render/1 synchronises — no sleep needed
  html = render(view)
  assert html =~ "Sold Out"
end
```

#### Complete LiveView test skeleton

```elixir
defmodule YscWeb.MyLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory

  setup %{conn: conn} do
    user = user_with_membership(:lifetime)
    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "mount" do
    test "loads page for authenticated user", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/my-route")
      # html here is from the static (disconnected) render — fast, no async needed
      assert html =~ "Page Title"
    end
  end

  describe "async data loading" do
    test "populates data after connection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/my-route")
      render_async(view)

      assert has_element?(view, "#data-section")
    end
  end

  describe "user interactions" do
    test "responds to button click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/my-route")
      render_async(view)

      render_click(view, "my-event", %{"param" => "value"})

      # render_click is synchronous — no sleep needed after it
      assert has_element?(view, "#result")
    end
  end
end
```

---

## Anti-Patterns to Avoid

> **These patterns are enforced by Credo checks `EX9001` and `EX9002`.**
> Running `mix precommit` will catch them before they reach CI.

### ❌ Using `:timer.sleep` / `Process.sleep` instead of `render_async`

```elixir
# BAD — arbitrary delay, adds hundreds of ms per test, still fragile
{:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
:timer.sleep(300)
html = render(view)
```

```elixir
# GOOD — waits exactly as long as needed, zero waste
{:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
render_async(view)
html = render(view)
```

### ❌ Sleeping between inserts for timestamp ordering

```elixir
# BAD — 2 seconds wasted just to get different inserted_at values
{:ok, invite1} = FamilyInvites.create_invite(user, email1)
:timer.sleep(1000)
{:ok, invite2} = FamilyInvites.create_invite(user, email2)
:timer.sleep(1000)
{:ok, invite3} = FamilyInvites.create_invite(user, email3)
```

```elixir
# GOOD — backdate the older records explicitly, no sleep
now = DateTime.utc_now() |> DateTime.truncate(:second)

{:ok, invite1} = FamilyInvites.create_invite(user, email1)
{:ok, invite1} =
  invite1
  |> Ecto.Changeset.change(%{inserted_at: DateTime.add(now, -120, :second)})
  |> Repo.update()

{:ok, invite2} = FamilyInvites.create_invite(user, email2)
{:ok, invite2} =
  invite2
  |> Ecto.Changeset.change(%{inserted_at: DateTime.add(now, -60, :second)})
  |> Repo.update()

{:ok, invite3} = FamilyInvites.create_invite(user, email3)
# invite3 has the most recent inserted_at naturally
```

### ❌ Sleeping to wait for record expiry

```elixir
# BAD — sleeps 2 real seconds so a timestamp can pass
{:ok, order} = Repo.insert(%TicketOrder{
  expires_at: DateTime.add(DateTime.utc_now(), 1, :second),
  ...
})
:timer.sleep(2000)  # wait for it to "expire"
```

```elixir
# GOOD — create it already expired
{:ok, order} = Repo.insert(%TicketOrder{
  expires_at: DateTime.add(DateTime.utc_now(), -5, :second),
  status: :expired,
  ...
})
```

### ❌ Real external URLs in test config

```elixir
# BAD — makes real HTTPS requests to Discord in every test run
config :ysc, Ysc.Alerts.Discord,
  webhook_url: "https://discord.com/api/webhooks/test/fake_token",
  enabled: true
```

```elixir
# GOOD option 1 — disable entirely (no network I/O)
config :ysc, Ysc.Alerts.Discord,
  webhook_url: nil,
  enabled: false

# GOOD option 2 — use localhost for immediate connection-refused (tests that
# verify error-handling still exercise the HTTP code path, but fail instantly)
config :ysc, Ysc.Alerts.Discord,
  webhook_url: "http://localhost:1",
  enabled: true
```

---

## Linting & Enforcement

Two custom Credo checks enforce the above rules automatically:

| ID | Check | What it catches |
|----|-------|-----------------|
| `EX9001` | `Ysc.Credo.NoSleepInTests` | Any `:timer.sleep/1` or `Process.sleep/1` in `test/` files |
| `EX9002` | `Ysc.Credo.NoExternalUrlsInTestConfig` | Real external service URLs (Discord, Stripe, SendGrid, …) in `config/test.exs` |
| `EX9003` | `Ysc.Credo.DateFieldSchemaTypes` | Ambiguous date fields (`start_date`, `checkin_date`, …) missing `Ysc.Ecto.DateKind` |
| `EX9004` | `Ysc.Credo.DateFieldConversions` | `shift_zone` / browser-TZ formatters on California calendar fields |

Run them as part of the precommit alias:

```bash
mix precommit
```

Or individually:

```bash
mix credo --strict
mix credo explain EX9001  # full guidance with alternatives
mix credo explain EX9002
```

Source: `dev/ysc/credo/no_sleep_in_tests.ex` and `dev/ysc/credo/no_external_urls_in_test_config.ex`.

---

## Troubleshooting

### Tests Hanging

If tests hang, it's usually due to:
- Async operations not completing (use `render_async` rather than a timeout)
- Database locks from improper sandbox usage
- Missing `start_owner!` in custom test setup

Ensure `use YscWeb.ConnCase, async: true` is present and check for proper sandbox setup.

### Flaky Tests

Common causes:
- **Race conditions** — replace `:timer.sleep` with `render_async`, `assert_receive`, or explicit backdating (see anti-patterns above)
- **Shared database state** — ensure proper test isolation; each test runs in a transaction that is rolled back
- **Time-sensitive assertions** — use relative dates, not absolute timestamps

### Connection Errors

If you see legitimate connection errors (not the expected cleanup ones):
- Check database is running: `mix ecto.setup`
- Verify test database exists: `mix ecto.create`
- Reset database if corrupted: `mix ecto.reset`

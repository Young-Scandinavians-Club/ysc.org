# Query EXPLAIN CI

Pull requests that change Ecto query code under `lib/` can receive a sticky GitHub comment with rendered SQL and PostgreSQL `EXPLAIN` output (plus an optional LLM summary when `OPENROUTER_API_KEY` is set).

## How CI selects targets

1. **Heuristic** — the diff adds query-shaped lines (`from(`, `join(`, `fragment(`, etc.) under `lib/**/*.ex` (excluding `*_test.exs`).
2. **Changed files** — `git diff --name-only` lists touched `lib/*.ex` files.
3. **Targets** — union of:
   - **Registered** rows in `priv/ci/query_explain_targets.exs` whose `source_paths` intersect changed files.
   - **Auto-discovered** public `*_query` or `base_query/0` functions in changed modules where `apply(module, function, [])` returns `%Ecto.Query{}` (default arguments are fine).

If the heuristic matches but no targets run, CI posts the “Targets run: 0” opt-in message.

## Writing analyzable queries

### Do

1. **Extract the query** into a public function named `something_query` (suffix `_query`) or `base_query/0`.
2. **Return `%Ecto.Query{}` only** — no `Repo.all`, `Repo.one`, preloads, or side effects in the `*_query` function.
3. **Use stable inputs** — `DateTime.utc_now()`, `Date.utc_today()`, small literal limits, or fixture IDs / ULIDs for foreign keys.
4. **Keep execution separate**:

```elixir
@doc false
def my_list_query(opts \\ []) do
  limit = Keyword.get(opts, :limit, 50)
  now = DateTime.utc_now()

  from(r in MySchema,
    where: r.status == :active and r.starts_at > ^now,
    order_by: [asc: r.starts_at],
    limit: ^limit
  )
end

def my_list(opts \\ []) do
  opts
  |> my_list_query()
  |> Repo.all()
end
```

5. **Register** queries that need real arguments without defaults in `lib/ysc/ci/query_explain.ex` (fixture wrapper) plus `priv/ci/query_explain_targets.exs`.
6. **List every trigger path** in `source_paths` when the query lives in a context module but LiveViews or workers also change.

### Don't

- Leave queries only inline inside `def list_*`, LiveViews, or workers.
- Perform side effects inside `*_query` (HTTP, Oban enqueue, `Repo.insert`).
- Require runtime-only values (session token, current user id) without defaults or a CI wrapper.

## Registry example

```elixir
%{
  id: "booking_locker_active_reservations",
  source_paths: ["lib/ysc/tickets/booking_locker.ex"],
  mfa: {Ysc.Ci.QueryExplain, :booking_locker_active_reservations_query, []}
}
```

Fixture wrapper:

```elixir
# lib/ysc/ci/query_explain.ex
def booking_locker_active_reservations_query do
  BookingLocker.active_reservations_for_event_ordered_query(
    Ecto.ULID.generate(),
    Ecto.ULID.generate()
  )
end
```

## Local commands

| Command | Purpose |
|---------|---------|
| `make query-explain-staged` | Explain targets for staged `lib/*.ex` changes |
| `make query-explain-main` | Explain targets for branch vs `origin/main` |
| `mix ci.query_explain.suggest` | List modules missing explain coverage |
| `mix ci.query_explain.suggest lib/ysc/foo.ex` | Check specific files |

Output: `.query-explain/result.json` and `.query-explain/comment.md`.

## LLM checklist

When adding or changing Ecto queries under `lib/`:

- [ ] Public `*_query` or `base_query/0` returning `%Ecto.Query{}`?
- [ ] Callable via `apply(Module, :fn, [])` or registered `mfa` in `query_explain_targets.exs`?
- [ ] `Repo.*` execution in a separate function?
- [ ] `source_paths` updated if the PR touches callers in other files?
- [ ] `make query-explain-staged` shows **Targets run** > 0?

## When auto-discovery is not enough

| Situation | Fix |
|-----------|-----|
| Query needs IDs, tokens, user | `Ysc.Ci.QueryExplain` wrapper + registry row |
| Query in context, PR edits LiveView | Add LiveView path to `source_paths` |
| Multiple query shapes in one module | Multiple `*_query` functions or registry rows |
| `update_all` / `delete_all` | Not supported yet; extract an equivalent `from` for review |

## Related

- [Query Optimization Guide](QUERY_OPTIMIZATION_GUIDE.md) — profiling and index strategies
- `lib/mix/tasks/ci/query_explain.ex` — task implementation
- `.github/workflows/ci.yml` — `query_explain_pr` job

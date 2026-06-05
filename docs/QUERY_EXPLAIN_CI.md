# Query EXPLAIN CI

Pull requests that change Ecto query code under `lib/` can receive a sticky GitHub comment with rendered SQL and PostgreSQL `EXPLAIN` output (plus an optional LLM summary when `OPENROUTER_API_KEY` is set).

## `lib/ysc` coverage

Every `lib/ysc/**/*.ex` module with a discoverable query function is included in the registry. When **any** `lib/ysc` file changes in a PR, CI runs **all** `Ysc.*` explain targets (~60+ query shapes today).

The registry is built at runtime by `Ysc.Ci.QueryExplain.Registry.all_targets()` (see `priv/ci/query_explain_targets.exs`).

### Standard entry point: `ci_query_explain_query/0`

Each `lib/ysc` context module with Ecto queries should define:

```elixir
@doc false
def ci_query_explain_query do
  # returns %Ecto.Query{} — representative shape for this module
end
```

Use `Ysc.Ci.QueryExplain.Fixtures` for stable IDs (`ulid/0`, `uuid/0`, `user/0`, `ip/0`, etc.). Match column types (UUID columns need `Ecto.UUID.bingenerate()` or `Fixtures.uuid/0` for string UUID fields).

Additional shapes: `ci_query_explain_<name>_query/0` (e.g. `Ysc.Search` has separate events/tickets/users queries).

Existing `*_query/1` helpers with defaults and `base_query/0` are also discovered automatically.

## How CI selects targets

1. **Heuristic** — the diff adds query-shaped lines under `lib/**/*.ex` (excluding `*_test.exs`).
2. **Changed files** — `git diff --name-only` lists touched `lib/**/*.ex` files.
3. **Targets**:
   - **Any `lib/ysc` change** → all `Ysc.*` registry targets.
   - **Other `lib/` changes** → registry rows whose `source_paths` intersect changed files, plus auto-discovery on changed modules.

## Writing analyzable queries

### Do

1. Add `ci_query_explain_query/0` (or `*_query` / `base_query/0`) returning `%Ecto.Query{}` only.
2. Use stable inputs — `DateTime.utc_now()`, fixture IDs, small limits.
3. Keep `Repo.*` execution in separate functions.
4. Use correct types for `where` bindings (Ecto enums as atoms, UUID columns as `Ecto.UUID.bingenerate()` when required).

### Don't

- Leave queries only inline in LiveViews (`lib/ysc_web`) without a matching `lib/ysc` `ci_query_explain_query/0`.
- Perform side effects inside explain functions.
- Pass ULID strings into UUID columns (or string enum values into `Ecto.Enum` fields).

## Local commands

| Command | Purpose |
|---------|---------|
| `make query-explain-staged` | Explain targets for staged `lib/*.ex` changes |
| `make query-explain-main` | Explain targets for branch vs `origin/main` |
| `make query-explain-suggest` | List modules missing explain coverage |
| `mix ci.query_explain --all-targets` | Run every registry target |

Output: `.query-explain/result.json` and `.query-explain/comment.md`.

## LLM checklist

When adding or changing Ecto queries under `lib/ysc`:

- [ ] `ci_query_explain_query/0` returns `%Ecto.Query{}` with representative filters/joins?
- [ ] Fixture types match schema (`Fixtures`, `Ecto.UUID.bingenerate()`, enum atoms)?
- [ ] `make query-explain-staged` shows **Targets run** > 0 for `lib/ysc` edits?

## Related

- [Query Optimization Guide](QUERY_OPTIMIZATION_GUIDE.md)
- `lib/ysc/ci/query_explain/registry.ex`
- `.github/workflows/ci.yml` — `query_explain_pr` job

# Query Console Deployment

Standalone Phoenix LiveView SQL console deployed separately from the main YSC app.

## Topology (current)

- **Metadata DB** (`DATABASE_URL`): writable database for shadow users, workbooks, run history, schema snapshots, and the global query lease.
- **Analytics DB** (`ANALYTICS_DATABASE_URL` or preferred `ANALYTICS_REPLICA_DATABASE_URL`): read path for SQL execution and schema introspection.

**Do not** rewrite Postgres ports to `5433` to “find” a replica. Always set the analytics URL explicitly.

### Isolation caveats

The interim setup may point analytics credentials at the **MPG primary** using a Postgres **Reader** role. Reader permissions prevent writes but **do not isolate CPU/I/O**. Concurrency limits (global lease, pool size 2), statement timeouts, and result caps reduce risk but cannot guarantee zero impact on primary traffic.

**Future cutover:** set `ANALYTICS_REPLICA_DATABASE_URL` to a true replica or isolated analytics copy. No application code changes are required.

## Fly apps and CI

| Env | Fly app | Hostname | Config | When |
|-----|---------|----------|--------|------|
| Sandbox | `ysc-query-console-sandbox` | `ysc-query-console-sandbox.fly.dev` | `fly.sandbox.toml` | Push to `main` (after CI) and as gate on `v*` releases |
| Production | `ysc-query-console` | `query.ysc.org` | `fly.prod.toml` | `v*` tag push (after sandbox gate) |

GitHub Actions reuse the existing Fly tokens:

| GitHub secret | Used for |
|---------------|----------|
| `FLY_SANDBOX_API_TOKEN` (or `FLY_API_TOKEN`) | Deploy sandbox app |
| `FLY_PROD_API_TOKEN` | Deploy production app |

No new GitHub secrets are required if those tokens can already see the new Fly apps in their orgs. After creating the apps, confirm:

```bash
FLY_API_TOKEN=… bash etc/scripts/fly_verify_app_access.sh ysc-query-console-sandbox
FLY_API_TOKEN=… bash etc/scripts/fly_verify_app_access.sh ysc-query-console
```

## Create apps (one-time)

```bash
cd query_console
fly apps create ysc-query-console-sandbox   # sandbox org
fly apps create ysc-query-console           # prod org
```

Allocate a **separate metadata Postgres** for each env (do not share the YSC app database for writes). Point `ANALYTICS_DATABASE_URL` at the matching YSC MPG with the Reader role.

## Fly app secrets (required on each query-console app)

Set these on **both** `ysc-query-console-sandbox` and `ysc-query-console` (values differ per env):

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | Metadata Postgres (writable) |
| `ANALYTICS_DATABASE_URL` | Analytics/read Postgres (Reader role) |
| `ANALYTICS_REPLICA_DATABASE_URL` | Optional override when a replica exists |
| `SECRET_KEY_BASE` | Phoenix cookie signing (`mix phx.gen.secret`) |
| `YSC_SSO_AUTHORIZE_URL` | YSC authorize URL |
| `YSC_SSO_TOKEN_URL` | YSC token URL |
| `YSC_SSO_LOGOUT_URL` | Optional; defaults from authorize host `/oauth/logout` |
| `YSC_SSO_CLIENT_ID` | Confidential client id |
| `YSC_SSO_CLIENT_SECRET` | Confidential client secret |
| `YSC_SSO_REDIRECT_URI` | Exact callback URL for this Fly app |
| `YSC_SSO_POST_LOGOUT_REDIRECT_URI` | Exact signed-out page URL (defaults to `{BASE}/auth/signed-out`) |
| `QUERY_CONSOLE_BASE_URL` | Public base URL of this Fly app |
| `SHUTDOWN_WHEN_INACTIVE_MS` | Optional idle exit (default `600000`; `0` disables) |
| `PHX_HOST` | Optional; already set in `fly.*.toml` `[env]` |

### Sandbox example

```bash
cd query_console
fly secrets set -a ysc-query-console-sandbox \
  DATABASE_URL='postgres://…' \
  ANALYTICS_DATABASE_URL='postgres://ysc-query-console-reader:…@…/…?sslmode=require' \
  SECRET_KEY_BASE='…' \
  YSC_SSO_AUTHORIZE_URL='https://ysc-sandbox.fly.dev/oauth/authorize' \
  YSC_SSO_TOKEN_URL='https://ysc-sandbox.fly.dev/oauth/token' \
  YSC_SSO_LOGOUT_URL='https://ysc-sandbox.fly.dev/oauth/logout' \
  YSC_SSO_CLIENT_ID='query_console_sandbox' \
  YSC_SSO_CLIENT_SECRET='…' \
  YSC_SSO_REDIRECT_URI='https://ysc-query-console-sandbox.fly.dev/auth/ysc/callback' \
  YSC_SSO_POST_LOGOUT_REDIRECT_URI='https://ysc-query-console-sandbox.fly.dev/auth/signed-out' \
  QUERY_CONSOLE_BASE_URL='https://ysc-query-console-sandbox.fly.dev'
```

### Production example

Public hostname: **`https://query.ysc.org`** (custom domain on Fly app `ysc-query-console`).

```bash
# One-time DNS / TLS (after creating a CNAME or A/AAAA at your DNS provider):
fly certs add query.ysc.org -a ysc-query-console

fly secrets set -a ysc-query-console \
  DATABASE_URL='postgres://…' \
  ANALYTICS_DATABASE_URL='postgres://ysc-query-console-reader:…@…/…?sslmode=require' \
  SECRET_KEY_BASE='…' \
  YSC_SSO_AUTHORIZE_URL='https://ysc.org/oauth/authorize' \
  YSC_SSO_TOKEN_URL='https://ysc.org/oauth/token' \
  YSC_SSO_LOGOUT_URL='https://ysc.org/oauth/logout' \
  YSC_SSO_CLIENT_ID='query_console_prod' \
  YSC_SSO_CLIENT_SECRET='…' \
  YSC_SSO_REDIRECT_URI='https://query.ysc.org/auth/ysc/callback' \
  YSC_SSO_POST_LOGOUT_REDIRECT_URI='https://query.ysc.org/auth/signed-out' \
  QUERY_CONSOLE_BASE_URL='https://query.ysc.org'
```

`PHX_HOST` is set to `query.ysc.org` in `fly.prod.toml` / `fly.toml`.

## YSC SSO secrets (on the main YSC Fly apps)

Set on **`ysc-sandbox`** and **`ysc-prod`** so the provider accepts the query console clients:

| Variable | Purpose |
|----------|---------|
| `QUERY_CONSOLE_SSO_CLIENT_ID` | Must match `YSC_SSO_CLIENT_ID` on the query console app |
| `QUERY_CONSOLE_SSO_CLIENT_SECRET` | Must match `YSC_SSO_CLIENT_SECRET` |
| `QUERY_CONSOLE_SSO_REDIRECT_URIS` | Comma-separated exact callbacks (include the matching query-console callback) |
| `QUERY_CONSOLE_SSO_POST_LOGOUT_REDIRECT_URIS` | Comma-separated exact signed-out URLs allowlisted for front-channel logout |

Sandbox YSC example:

```bash
fly secrets set -a ysc-sandbox \
  QUERY_CONSOLE_SSO_CLIENT_ID='query_console_sandbox' \
  QUERY_CONSOLE_SSO_CLIENT_SECRET='…' \
  QUERY_CONSOLE_SSO_REDIRECT_URIS='https://ysc-query-console-sandbox.fly.dev/auth/ysc/callback' \
  QUERY_CONSOLE_SSO_POST_LOGOUT_REDIRECT_URIS='https://ysc-query-console-sandbox.fly.dev/auth/signed-out'
```

Production YSC example:

```bash
fly secrets set -a ysc-prod \
  QUERY_CONSOLE_SSO_CLIENT_ID='query_console_prod' \
  QUERY_CONSOLE_SSO_CLIENT_SECRET='…' \
  QUERY_CONSOLE_SSO_REDIRECT_URIS='https://query.ysc.org/auth/ysc/callback' \
  QUERY_CONSOLE_SSO_POST_LOGOUT_REDIRECT_URIS='https://query.ysc.org/auth/signed-out'
```

## Reader role checklist

Production role (created): **`ysc-query-console-reader`** — read-only on the Fly MPG database.

1. Role has `CONNECT` on the database and `SELECT` / `USAGE` on schemas only.
2. No `CREATE`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `TRIGGER`, etc.
3. Confirm `CREATE TEMP TABLE` fails for the role (temp objects can still stress shared resources).
4. Point `ANALYTICS_DATABASE_URL` at this role’s connection string, e.g.:

   ```text
   postgres://ysc-query-console-reader:<PASSWORD>@<mpg-host>:<port>/<database>?sslmode=require
   ```

   Prefer `ANALYTICS_REPLICA_DATABASE_URL` when a true replica endpoint exists; until then use the same MPG host with this Reader user. **Do not** rewrite the port to `5433`.

## Manual deploy

```bash
cd query_console
fly deploy -a ysc-query-console-sandbox -c fly.sandbox.toml
fly deploy -a ysc-query-console -c fly.prod.toml
```

### Scale-to-zero

`fly.*.toml` sets `min_machines_running = 0`, `auto_stop_machines = "stop"`, and
`auto_start_machines = true`. In production the app also shuts down the BEAM after
**10 minutes** with no Bandit/Thousand Island HTTP/LiveView connections (Bandit
adaptation of the [idle Phoenix recipe](https://fly.io/phoenix-files/shut-down-idle-phoenix-app/)),
so stopped Machines only incur storage cost until the next visit.

- Open console tabs keep the Machine awake (LiveView websocket).
- Cold start adds a few seconds on first request after idle.
- Override with `SHUTDOWN_WHEN_INACTIVE_MS` (milliseconds), or `0` to disable.

## SSO provider (YSC)

YSC exposes a generic first-party OAuth provider:

- `GET /oauth/authorize` (browser; eligibility is per registered client)
- `POST /oauth/token` (confidential client + PKCE)
- `GET /oauth/logout` (front-channel logout; allowlisted `post_logout_redirect_uri`)

`/oauth/query-console/*` routes remain as aliases.

**Sign-out flow:** Query Console clears its own session, then redirects the browser to
YSC `/oauth/logout`. YSC drops the admin session and redirects back to the console’s
`/auth/signed-out` page. Without the YSC logout hop, SSO would silently re-authenticate.

Clients live in `:ysc, :oauth_clients` (map keyed by `client_id`). Query Console is
registered via `QUERY_CONSOLE_SSO_*` on the YSC app. To add another app, add another
map entry with its own `client_secret`, `redirect_uris`, `post_logout_redirect_uris`,
`roles`, and `states`.

Token response shape:

```json
{
  "token_type": "bearer",
  "expires_in": 0,
  "user": {
    "id": "<ulid>",
    "email": "...",
    "display_name": "First Last",
    "role": "admin",
    "state": "active"
  }
}
```

## Load-budget note

Before production enablement, load-test representative worst-case reads while normal
site traffic runs and set timeouts/concurrency from measured latency. This validates
limits but does **not** make the MPG primary an isolated workload; a real replica or
separate analytics copy is required for that guarantee.

Suggested baseline budgets (tune after measurement):

| Control | Default in app | Notes |
|---------|----------------|-------|
| Global active queries | 1 (metadata lease) | Across all Machines |
| Active runs per user | 1 | Enforced in runner |
| `statement_timeout` | 30s | Transaction-local |
| `lock_timeout` | 5s | Transaction-local |
| Max result rows | 10_000 | Streaming hard cap |
| Max result bytes | ~5MB | Serialized cell budget |
| Analytics pool size | 2 | Admission + cancel control |

Record observed p95/p99 for representative heavy `SELECT`s under concurrent site traffic
and adjust timeouts/caps before enabling the Fly app for all admins.

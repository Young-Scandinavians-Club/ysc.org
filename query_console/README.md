# YSC Query Console

Standalone Phoenix app that mounts **Lotus Web** as the SQL console UI, behind YSC SSO.
Independently deployable; does not import any `Ysc.*` modules.

## Local setup

Prerequisites: Elixir 1.20+, Postgres on `localhost:5432` (`postgres`/`postgres`), and the main YSC `ysc_dev` / `ysc_test` databases (used for analytics schema introspection).

```bash
cd query_console

export SSL_CERT_FILE=/tmp/erlang_cacerts.pem
export ERL_SSL_CACERTFILE=/tmp/erlang_cacerts.pem
export HEX_CACERTS_PATH=/tmp/erlang_cacerts.pem

mix deps.get
cd assets && npm install && cd ..
mix ecto.create
mix ecto.migrate
mix phx.server
```

The app listens on **http://localhost:4001** (YSC uses 4000). After SSO, `/` is Lotus Web
(queries, schema browser, saved queries). **Admin** links back to YSC `/admin`; **Sign out**
clears the local session and ends the YSC OAuth session.

### Databases

| Repo | Dev DB | Test DB | Role |
|------|--------|---------|------|
| `QueryConsole.Repo` | `query_console_dev` | `query_console_test` | Metadata (writable) |
| `QueryConsole.AnalyticsRepo` | `ysc_dev` | `ysc_test` | Analytics reads |

### SSO (dev)

By default the app redirects to `http://localhost:4000/oauth/authorize`.
YSC must be running on port 4000 with matching SSO config (`query_console_dev` /
`dev_secret_change_me`). Override with:

- `YSC_SSO_AUTHORIZE_URL` (default `…/oauth/authorize`)
- `YSC_SSO_TOKEN_URL` (default `…/oauth/token`)
- `YSC_SSO_CLIENT_ID` (default `query_console_dev`)
- `YSC_SSO_CLIENT_SECRET` (default `dev_secret_change_me`)
- `YSC_SSO_REDIRECT_URI` (default `http://localhost:4001/auth/ysc/callback`)
- `QUERY_CONSOLE_BASE_URL`

### AI assistant (optional)

Lotus AI is enabled when `OPENROUTER_API_KEY` is set (model defaults to
`openrouter:moonshotai/kimi-k3`; override with `LOTUS_AI_MODEL`). Cap completion
size with `LOTUS_AI_MAX_TOKENS` (default `4096`) so kimi-k3’s catalog output limit
does not fill the entire context window. In the editor use **Cmd/Ctrl+K**.

```bash
export OPENROUTER_API_KEY=sk-or-...
mix phx.server
```

### Tests

```bash
mix test
```

### Production

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for Fly apps, CI hooks, and secrets.

- Sandbox: `ysc-query-console-sandbox` on push to `main`
- Production: `ysc-query-console` at **https://query.ysc.org** on `v*` release tags

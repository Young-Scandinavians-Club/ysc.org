# YSC.org

Club management platform for memberships, events, cabin bookings, payments, and communications. Built with Elixir and Phoenix.

**New here?** See the [New Developer Guide](docs/NEW_DEVELOPER_GUIDE.md) for full setup, architecture, and documentation index. Daily commands: [QUICKREF.md](QUICKREF.md).

## Quick start

```bash
# Terminal 1 — Stripe webhooks (required for payments)
stripe listen --forward-to localhost:4000/webhooks/stripe

# Terminal 2 — app (first time: see Getting started below)
make dev
```

Open [http://localhost:4000](http://localhost:4000). Seeded admin: `admin@ysc.org` / `very_secure_password`.

## Getting started

### Prerequisites

- [Docker](https://www.docker.com/products/docker-desktop) (PostgreSQL, MinIO)
- Elixir & Erlang via [asdf](https://asdf-vm.com/) (`asdf install` in repo root; versions in `.tool-versions`)
- [Stripe CLI](https://stripe.com/docs/stripe-cli) (`stripe login`, then webhook forwarding above)
- `shellcheck`, `shfmt`, and `dprint` (for `make preflight`)

Install steps per OS: [New Developer Guide → Prerequisites](docs/NEW_DEVELOPER_GUIDE.md#detailed-prerequisites).

### Configure & run

```bash
cp .env.example .env
# Edit .env: STRIPE_SECRET, STRIPE_PUBLIC_KEY, STRIPE_WEBHOOK_SECRET
#   (keys from Stripe Dashboard test mode; webhook secret from `stripe listen`)

make dev-setup    # deps, Docker, migrate, seed
make dev          # in a second terminal, with stripe listen running
```

| Service | URL |
| --- | --- |
| App | http://localhost:4000 |
| Dev email inbox | http://localhost:4000/dev/mailbox |
| Notification previews | http://localhost:4000/dev/notifications |
| MinIO console | http://localhost:9001 |

Email/SMS template previews, sample data, and PR screenshots: [EMAIL_TESTING_GUIDE.md](docs/EMAIL_TESTING_GUIDE.md).

**Issues?** [Troubleshooting](docs/TROUBLESHOOTING.md) · **Seed data details:** [SEED_DATA_REFERENCE.md](docs/SEED_DATA_REFERENCE.md)

## Stack

- **Phoenix / LiveView** — web UI (`lib/ysc_web`)
- **Contexts** — business logic (`lib/ysc`)
- **PostgreSQL / Ecto** — data
- **Oban** — background jobs
- **Integrations** — Stripe, QuickBooks, S3 (MinIO locally), Flowroute (SMS)

Architecture diagrams and ports: [DEVELOPMENT_ARCHITECTURE.md](docs/DEVELOPMENT_ARCHITECTURE.md).

## Features (overview)

| Area | Capabilities |
| --- | --- |
| **Accounts** | Email/password, passkeys, Google/Facebook OAuth, re-auth for sensitive changes |
| **Membership** | Applications & admin review, Stripe subscriptions, family accounts, renewals |
| **Events** | Ticket tiers, paid/free registration, donations, Partiful integration |
| **Bookings** | Tahoe & Clear Lake cabins — seasons, rooms, day passes, buyouts |
| **Finance** | Stripe payments, ledger, QuickBooks sync, reconciliation |
| **Content** | News/posts, media, member comments |
| **Comms** | Newsletter subscriptions, transactional email (Swoosh), SMS alerts |
| **Support** | Ticketing, search, admin tools |
| **Query console** | Standalone LiveView SQL workbench under [`query_console/`](query_console/) (separate Fly app; YSC admin SSO) — see [`query_console/docs/DEPLOYMENT.md`](query_console/docs/DEPLOYMENT.md) |

Deeper docs live under `docs/` (e.g. [LEDGER_SYSTEM_README.md](docs/LEDGER_SYSTEM_README.md), [TICKET_SYSTEM_README.md](docs/TICKET_SYSTEM_README.md)).

## Contributing

1. Branch from `main`: `YOUR_NAME/short-description`
2. Change + tests
3. `make preflight` before push
4. Open PR to `main`; link Linear ticket if applicable

Details: [Life of a Changeset](docs/LIFE_OF_A_CHANGESET.md).

```bash
make help        # all Make targets
make preflight   # format, credo, tests, etc.
make test
```

Optional local QuickBooks testing: set vars in `.env.example` (commented block) — see [New Developer Guide](docs/NEW_DEVELOPER_GUIDE.md#optional-integrations).

## Deployment

| Environment | Notes |
| --- | --- |
| **Development** | `make dev` — hot reload, local Docker |
| **Sandbox** | https://ysc-sandbox.fly.dev — `make deploy-sandbox`; Stripe test + QB sandbox |
| **Production** | Fly.io; tag `v*` on `main` triggers [.github/workflows/fly-deploy-prod.yml](.github/workflows/fly-deploy-prod.yml) |

Production deploy secrets: `FLY_PROD_API_TOKEN`, `OPENROUTER_API_KEY` (release notes), `RESEND_API_KEY` (committee email on release).

## Environment variables

**Required for local dev** (see `.env.example`):

- `STRIPE_SECRET`, `STRIPE_PUBLIC_KEY`, `STRIPE_WEBHOOK_SECRET`

Everything else has defaults or is only needed for optional integrations (QuickBooks, Radar maps, custom email addresses). Full list: `.env.example` and [New Developer Guide](docs/NEW_DEVELOPER_GUIDE.md#environment-variables).

Never commit `.env`.

## License

Non-Profit Open Software License (NPOSL) 3.0 — see [LICENSE](LICENSE). For-profit use requires a different license; contact maintainers.

# WordPress migration — production runbook (Fly.io)

Step-by-step guide for migrating WordPress data into the Phoenix app on Fly.io.

**Related docs**

- Local / dev testing: [WP_MIGRATION_TESTING.md](WP_MIGRATION_TESTING.md)
- Strategic context: [MIGRATION_EPIC.md](MIGRATION_EPIC.md)

---

## Architecture

The migration is split into two phases on purpose:

| Phase | Where to run | Tools | Output |
|-------|----------------|-------|--------|
| **Prepare** | Your laptop or any machine with disk + RAM | Mix (`ysc.wp_to_duckdb`, `ysc.wp_extract`, `ysc.wp_validate`) | `wp_migration_export/` tarball |
| **Load** | One-off Fly machine (recommended) or local + DB proxy | Release (`Ysc.Release.wp_load/1`) | Rows in prod Postgres + media in Tigris |

**Do not** copy the raw MySQL dump or full `wp-content/uploads` tree onto production Fly app machines. They use 1 GB VMs, ephemeral disk, and no Mix.

```
WordPress backup (SQL + uploads)
        │
        ▼  [local] mix ysc.wp_to_duckdb
        ▼  [local] mix ysc.wp_extract
        ▼  [local] mix ysc.wp_validate
        │
        ▼  tar + upload to Tigris (staging prefix)
        │
        ▼  [Fly one-off machine] download + unpack
        ▼  [Fly] bin/ysc eval Ysc.Release.wp_load(...)
        ▼  validate + bin/ysc eval Ysc.Release.wp_migration_unlock()
```

During load, `wp_migration_active` is set to `true`, which suppresses Stripe webhook side effects (emails, QuickBooks sync, etc.) until you call `wp_migration_unlock`.

---

## Prerequisites

### Access

- Fly CLI authenticated for **both** orgs (sandbox and prod are separate accounts — see `Makefile` `FLY_SANDBOX_ACCESS_TOKEN` / `FLY_PROD_ACCESS_TOKEN`)
- `make fly-verify-sandbox` and `make fly-verify-prod` succeed
- SSH access to WordPress server for final backup
- Tigris/S3 credentials (already configured as Fly secrets on `ysc-prod`)

### Local tooling

- Elixir 1.20 + deps (`mix deps.get`)
- Enough disk for `wp_backup/` + `wp_migration_export/` (often 5–50+ GB depending on media)
- `aws` CLI (or similar) for Tigris uploads using `AWS_ENDPOINT_URL_S3=https://fly.storage.tigris.dev`

### WordPress backup layout

```
wp_backup/
  backup.sql              # mysqldump of WordPress DB
  files/                  # wp-content tree (at least uploads/)
    wp-content/uploads/
```

Table prefix defaults to `wp0h`. Override with `--table-prefix` on `ysc.wp_to_duckdb` if different.

### Apps

| App | Config | Purpose |
|-----|--------|---------|
| `ysc-sandbox` | `etc/fly/fly-sandbox.toml` | Full dry run |
| `ysc-prod` | `etc/fly/fly-prod.toml` | Production load |

---

## Phase 0 — Sandbox dry run (required)

Run the **entire** pipeline against sandbox before production. Record timings.

### 0.1 Prepare export locally

```bash
# From repo root; paths are gitignored
mix ysc.wp_to_duckdb --sql wp_backup/backup.sql --db wp_backup/wp.duckdb
mix ysc.wp_validate --db wp_backup/wp.duckdb

mix ysc.wp_extract \
  --db wp_backup/wp.duckdb \
  --export-dir wp_migration_export \
  --wp-files wp_backup/files

mix ysc.wp_validate --db wp_backup/wp.duckdb --export-dir wp_migration_export
```

Optional spot checks:

```bash
mix ysc.wp_sample --db wp_backup/wp.duckdb --limit 5
```

### 0.2 Load into sandbox

**Option A — local load with sandbox DB** (simplest for iteration):

```bash
# Terminal 1: proxy Postgres (get connection string from fly postgres / app secrets)
fly proxy 15432:5432 -a <ysc-sandbox-postgres-app>

# Terminal 2: point at sandbox
export DATABASE_URL="postgresql://..."
export MIX_ENV=dev   # or prod with full runtime config

mix ysc.wp_load --export-dir wp_migration_export --dry-run
mix ysc.wp_load --export-dir wp_migration_export
# Optional in sandbox only — creates real Stripe test subs:
# mix ysc.wp_load --export-dir wp_migration_export --create-stripe-subscriptions
```

**Option B — load on Fly** (closer to prod):

1. Tar and upload export (see [Staging the export](#staging-the-export)).
2. Start a one-off sandbox machine (same steps as prod below, but `-a ysc-sandbox`).
3. Run `Ysc.Release.wp_load/1` via `bin/ysc eval`.

### 0.3 Sandbox validation

- [ ] User count matches `ysc.wp_validate` report
- [ ] Spot-check 10 random users in admin UI (`make shell-sandbox` if needed)
- [ ] Posts and media render
- [ ] Bookings imported (if `bookings.json` present in export)
- [ ] Stripe customer IDs linked (no `--create-stripe-subscriptions` in prod)
- [ ] Note wall-clock time for each load phase (users, media, posts, bookings)

Fill in the [timing worksheet](#timing-worksheet) at the bottom.

---

## Phase 1 — Pre-migration (T-1 week to T-1 day)

- [ ] Sandbox dry run complete; issues fixed
- [ ] Production runbook reviewed by second engineer
- [ ] Maintenance window scheduled; user comms sent (see `MIGRATION_EPIC.md`)
- [ ] DNS TTL lowered if cutting over hostname same day
- [ ] Confirm prod Fly image is current (`make deploy-prod` or verify CI deploy)
- [ ] Identify rollback owner and decision time (e.g. +4 h from start)

---

## Phase 2 — Maintenance window start (T-0)

### 2.1 Freeze WordPress

- [ ] Enable WP maintenance mode (no new orders, signups, or content changes)
- [ ] Send “migration in progress” email
- [ ] Verify site returns maintenance page to anonymous users

### 2.2 Final backup

On the WordPress server:

```bash
mysqldump -u ... -p wordpress_db > backup_final_$(date +%Y%m%d_%H%M%S).sql
tar -czf wp_uploads_final_$(date +%Y%m%d_%H%M%S).tar.gz /path/to/wp-content/uploads
```

- [ ] Copy `backup.sql` and uploads into local `wp_backup/`
- [ ] Upload raw backups to secure archival storage (separate from migration staging)
- [ ] Verify dump opens / row counts sane (`mix ysc.wp_validate --db wp_backup/wp.duckdb` after `wp_to_duckdb`)

### 2.3 Prepare final export (local)

Same commands as sandbox dry run, using the **final** backup only:

```bash
mix ysc.wp_to_duckdb --sql wp_backup/backup.sql --db wp_backup/wp.duckdb --force
mix ysc.wp_extract --db wp_backup/wp.duckdb --export-dir wp_migration_export --wp-files wp_backup/files
mix ysc.wp_validate --db wp_backup/wp.duckdb --export-dir wp_migration_export
```

- [ ] Validation report: all counts match
- [ ] Create tarball:

```bash
tar -czf wp_migration_export_$(date +%Y%m%d_%H%M%S).tar.gz wp_migration_export
```

### 2.4 Staging the export

Upload to a **non-public** prefix on a prod bucket (credentials from Fly secrets):

```bash
export AWS_ENDPOINT_URL_S3=https://fly.storage.tigris.dev
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY from fly secrets (or run on Fly machine)

aws s3 cp wp_migration_export_*.tar.gz \
  s3://ysc-prod-assets/migration/wp_migration_export_latest.tar.gz
```

Record the exact S3 key — you will need it on the load machine.

### 2.5 Production database backup

- [ ] Snapshot / backup prod Postgres before load (Fly Postgres backup or `pg_dump`)
- [ ] Confirm you can restore if rollback is required

---

## Phase 3 — Production load

Use a **dedicated one-off Fly machine**, not a live web instance serving traffic.

### 3.1 Why not the existing app machines?

| Risk on `ysc-prod` app VMs | Detail |
|----------------------------|--------|
| Disk | Ephemeral root; export + media may not fit |
| RAM | 1 GB default; media upload phase is heavy |
| Mix | Not in release image |
| Traffic | `min_machines_running = 2`; SSH to one machine does not isolate load |
| SSH | Long jobs may drop sessions |

### 3.2 Launch a one-off machine

```bash
make fly-verify-prod

# Current deployment image (verify output)
fly image show -a ysc-prod

# Run a idle machine with more memory (adjust size as needed; 2 GB is a reasonable start)
fly machine run "$(fly image show -a ysc-prod -j | jq -r '.[0].Tag')" \
  -a ysc-prod \
  --region sjc \
  --vm-memory 2048 \
  --vm-cpus 1 \
  --name wp-migration \
  --entrypoint "/bin/sh" \
  -- -lc "mkdir -p /data && sleep infinity"
```

Note the machine ID from `fly machines list -a ysc-prod`.

**Optional:** attach a volume if the export is very large:

```bash
fly volumes create wp_migration_data --size 50 --region sjc -a ysc-prod
# Attach when creating/cloning the machine (see fly.io docs for your CLI version)
```

### 3.3 SSH into the one-off machine

```bash
fly ssh console -a ysc-prod --machine <MACHINE_ID>
```

### 3.4 Download and unpack export

Inside the machine (Tigris env vars are already set from app secrets):

```bash
cd /data
aws s3 cp s3://ysc-prod-assets/migration/wp_migration_export_latest.tar.gz .
tar -xzf wp_migration_export_latest.tar.gz
ls wp_migration_export   # users.json, applications.json, posts.json, media/, ...
```

### 3.5 Dry run

```bash
/app/bin/ysc eval 'Ysc.Release.wp_load("/data/wp_migration_export", dry_run: true)'
```

- [ ] Logs show expected user/post/booking counts
- [ ] No errors

### 3.6 Real load

```bash
/app/bin/ysc eval 'Ysc.Release.wp_load("/data/wp_migration_export")'
```

Phases logged in order: Users → Applications → Media → Posts → Stripe customers → Subscriptions → Bookings.

**Production flags:**

- Do **not** pass `create_stripe_subscriptions: true` (sandbox/dev only)
- Use `upload_media: false` only if you intentionally defer media (requires a second pass)

**Targeted retry** (single user):

```bash
/app/bin/ysc eval 'Ysc.Release.wp_load("/data/wp_migration_export", only_emails: "user@example.com")'
```

### 3.7 Alternative — load from laptop via proxy

If you prefer not to use a Fly machine:

```bash
fly proxy 15432:5432 -a <ysc-prod-postgres-app>
export DATABASE_URL="postgresql://..."
# Export full prod runtime env (Stripe, Tigris, etc.) or use release locally

mix ysc.wp_load --export-dir wp_migration_export --dry-run
mix ysc.wp_load --export-dir wp_migration_export
```

Downside: long media uploads depend on your uplink; prod secrets on a laptop.

### 3.8 Tear down one-off machine

After successful validation:

```bash
fly machine destroy <MACHINE_ID> -a ysc-prod --force
```

---

## Phase 4 — Validation and cutover

### 4.1 Automated counts (local, against final DuckDB + export)

```bash
mix ysc.wp_validate --db wp_backup/wp.duckdb --export-dir wp_migration_export
```

### 4.2 Production checks

- [ ] `fly logs -a ysc-prod` — no load errors
- [ ] Admin: spot-check users, applications, posts, bookings
- [ ] Media URLs resolve (`https://assets.ysc.org/...`)
- [ ] Stripe customer IDs present on migrated users (Dashboard sample)
- [ ] Test login for 2–3 known accounts (password reset flow if needed)

### 4.3 Re-enable webhook comms

Only after validation:

```bash
fly ssh console -a ysc-prod -C '/app/bin/ysc eval "Ysc.Release.wp_migration_unlock()"'
```

Or from `make shell-prod`:

```elixir
Ysc.Release.wp_migration_unlock()
```

Locally (if you loaded via Mix):

```bash
mix ysc.wp_migration_unlock
```

### 4.4 Go live

- [ ] Point DNS / `PHX_HOST` if cutting over hostname
- [ ] Disable WordPress maintenance (or decommission WP)
- [ ] Send “migration complete” email
- [ ] Monitor Sentry, logs, Stripe webhooks for 24 h

---

## Rollback

There is no automatic “un-load”. Rollback options:

1. **Restore Postgres** from pre-migration snapshot (cleanest if load failed mid-way)
2. **Selective delete** — only practical for partial/`only_emails` test loads
3. **Keep WordPress** running until validation passes; only cut DNS after Phase 4

Decision point: if load is not complete within planned window + buffer, stop and restore DB rather than half-migrating.

---

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|----------------|--------|
| `Export directory not found` | Wrong path on Fly | `ls /data/wp_migration_export`; use absolute path |
| OOM on media phase | VM too small | Recreate machine with `--vm-memory 4096` |
| `wp_to_duckdb` slow / fails | Huge SQL dump | Run locally; ensure enough disk; try `--table-prefix` |
| Validate mismatches | Extract filter / HPOS tables | Run `mix ysc.wp_sample`; check validate report details |
| Duplicate users on re-run | Re-loaded same export | Restore DB snapshot; load is not fully idempotent |
| Webhooks firing during load | `wp_migration_active` | Should be set automatically; verify in admin settings |
| Mix task on Fly | Release has no Mix | Use `Ysc.Release.wp_load/1` only |

---

## Command reference

### Local (Mix)

| Task | Command |
|------|---------|
| SQL → DuckDB | `mix ysc.wp_to_duckdb --sql wp_backup/backup.sql --db wp_backup/wp.duckdb` |
| Extract | `mix ysc.wp_extract --db wp_backup/wp.duckdb --export-dir wp_migration_export` |
| Validate | `mix ysc.wp_validate --db wp_backup/wp.duckdb --export-dir wp_migration_export` |
| Load (dev/sandbox) | `mix ysc.wp_load --export-dir wp_migration_export` |
| Unlock comms | `mix ysc.wp_migration_unlock` |

### Production (Release)

| Task | Command |
|------|---------|
| Dry run | `bin/ysc eval 'Ysc.Release.wp_load("/data/wp_migration_export", dry_run: true)'` |
| Load | `bin/ysc eval 'Ysc.Release.wp_load("/data/wp_migration_export")'` |
| Skip media | `bin/ysc eval 'Ysc.Release.wp_load("/data/wp_migration_export", upload_media: false)'` |
| Unlock comms | `bin/ysc eval "Ysc.Release.wp_migration_unlock()"` |
| Remote console | `make shell-prod` |

### Fly helpers

| Task | Command |
|------|---------|
| Verify prod access | `make fly-verify-prod` |
| Prod console | `make shell-prod` |
| App logs | `fly logs -a ysc-prod` |
| Machines | `fly machines list -a ysc-prod` |

---

## Timing worksheet

Record during sandbox dry run; use for production planning.

| Step | Sandbox time | Prod estimate | Notes |
|------|--------------|---------------|-------|
| `wp_to_duckdb` | | | Local only |
| `wp_extract` | | | Local only |
| Upload export to Tigris | | | |
| `wp_load` — users | | | |
| `wp_load` — applications | | | |
| `wp_load` — media | | | Often longest |
| `wp_load` — posts | | | |
| `wp_load` — stripe | | | |
| `wp_load` — bookings | | | |
| Validation | | | |
| **Total** | | | Add 50% buffer |

---

## Production migration checklist (printable)

```
Date: ___________  Lead: ___________  Backup engineer: ___________

PRE-FLIGHT
□ Sandbox dry run passed
□ Prod DB backup taken
□ Final WP backup on laptop
□ Export validated (wp_validate)
□ Export tarball on Tigris
□ One-off Fly machine sized and ready

T-0
□ WP maintenance mode ON
□ Final export built from final backup
□ One-off machine: export downloaded
□ wp_load dry_run OK
□ wp_load complete
□ Spot checks passed
□ wp_migration_unlock run
□ DNS / go-live
□ WP maintenance OFF or site retired
□ One-off machine destroyed
```

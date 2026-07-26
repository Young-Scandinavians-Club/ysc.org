# WordPress migration – how to test

**Production cutover:** see [WP_MIGRATION_RUNBOOK.md](WP_MIGRATION_RUNBOOK.md).

Generate data from your WordPress backup and load it into the app in three steps.

## Prerequisites

- **Backup SQL dump**: e.g. `wp_backup/backup.sql` (MySQL dump of the WordPress DB).
- **Uploads on disk**: `wp_backup/files/` with `wp-content/uploads/` (same layout as your live WP files).

Table prefix is assumed to be `wp0h`. Override with `--table-prefix` on `ysc.wp_to_duckdb` if your dump uses a different prefix.

---

## Step 1: SQL dump → DuckDB

Convert the MySQL dump into a DuckDB file:

```bash
mix ysc.wp_to_duckdb --sql wp_backup/backup.sql --db wp_backup/wp.duckdb
```

Validate source counts:

```bash
mix ysc.wp_validate --db wp_backup/wp.duckdb
```

---

## Step 2: Extract (Phase 1)

Read the DuckDB file and uploads folder; write a single export directory (JSON + media):

```bash
mix ysc.wp_extract --db wp_backup/wp.duckdb --export-dir wp_migration_export --wp-files wp_backup/files
```

Lean extract (users/memberships/bookings only — skip news + media):

```bash
mix ysc.wp_extract --db wp_backup/wp.duckdb --export-dir wp_migration_export --no-posts --no-media
mix ysc.wp_reconcile_csvs --export-dir wp_migration_export --csv-dir wp_export_csvs
```

Optional:

- `--dry-run` – only log what would be written, do not create files.
- `--wp-files` defaults to `wp_backup/files` if omitted.
- `--no-posts` – write empty `posts.json` (skip news).
- `--no-media` – skip copying `media/` uploads.

Compare export counts to source:

```bash
mix ysc.wp_validate --db wp_backup/wp.duckdb --export-dir wp_migration_export
```

Result:

- `wp_migration_export/users.json`
- `wp_migration_export/applications.json`
- `wp_migration_export/posts.json`
- `wp_migration_export/stripe_customer_lookup.json`
- `wp_migration_export/bookings.json` (when present)
- `wp_migration_export/media/<wp_attachment_id>/` (file + optional `meta.json`)

---

## Step 3: Load (Phase 2)

Load the export directory into the app database (and optionally upload media to S3):

```bash
mix ysc.wp_load --export-dir wp_migration_export
```

Lean load (no news/media; create Stripe subscriptions for remaining active members):

```bash
mix ysc.wp_load --export-dir wp_migration_export --no-upload-media --skip-posts --create-stripe-subscriptions
```

Optional:

- `--dry-run` – no DB or S3 writes; only logs what would be done.
- `--no-upload-media` – do not upload media or create `Image` records.
- `--skip-posts` – skip loading news posts.
- `--create-stripe-subscriptions` – create Stripe trial subscriptions for active members without an importable Stripe sub.

Ensure the app is configured (DB, S3/Tigris if you use media) and run against a dev or staging DB first.

---

## Quick test (no backup.sql)

If you don’t have a real dump yet, use fixture data from tests or build a minimal DuckDB via `mix ysc.wp_to_duckdb` on a small SQL snippet, then run Steps 2–3 with `--dry-run` first.

---

## Troubleshooting

- **DuckDB build fails**: The SQL parser expects standard `INSERT INTO \`wp0h_*\`` dumps. Very large or non-standard dumps may need preprocessing.
- **Load fails on users**: Check that `users.json` has `email` and that the app allows registration without password (migration uses `require_password: false`).
- **Media**: Uploads require a configured S3/Tigris bucket and a migration uploader (first admin or first user). Use `--no-upload-media` to skip media and still load users, applications, and posts.

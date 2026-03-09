# WordPress migration – how to test

Generate data from your WordPress backup and load it into the app in three steps.

## Prerequisites

- **Backup SQL dump**: e.g. `wp_backup/backup.sql` (MySQL dump of the WordPress DB).
- **Uploads on disk**: `wp_backup/files/` with `wp-content/uploads/` (same layout as your live WP files).

Table prefix is assumed to be `wp0h` (tables: `wp0h_users`, `wp0h_usermeta`, `wp0h_posts`, `wp0h_postmeta`). If your prefix is different, export CSV with that prefix or adjust the code.

---

## Step 1: SQL dump → CSV

Convert the MySQL dump into CSV files so the extract step can read them:

```bash
mix ysc.wp_sql_to_csv --sql path/to/backup.sql --csv-dir wp_backup/csv
```

This writes:

- `wp_backup/csv/wp0h_users.csv`
- `wp_backup/csv/wp0h_usermeta.csv`
- `wp_backup/csv/wp0h_posts.csv`
- `wp_backup/csv/wp0h_postmeta.csv`

If you already have these CSVs (e.g. from MySQL `SELECT ... INTO OUTFILE` or another tool), skip to Step 2.

---

## Step 2: Extract (Phase 1)

Read the CSV directory and the uploads folder, write a single export directory (JSON + media):

```bash
mix ysc.wp_extract --csv-dir wp_backup/csv --export-dir wp_migration_export --wp-files wp_backup/files
```

Optional:

- `--dry-run` – only log what would be written, do not create files.
- `--wp-files` defaults to `wp_backup/files` if omitted.

Result:

- `wp_migration_export/users.json`
- `wp_migration_export/applications.json`
- `wp_migration_export/posts.json`
- `wp_migration_export/stripe_customer_lookup.json`
- `wp_migration_export/media/<wp_attachment_id>/` (file + optional `meta.json`)

---

## Step 3: Load (Phase 2)

Load the export directory into the app database (and optionally upload media to S3):

```bash
mix ysc.wp_load --export-dir wp_migration_export
```

Optional:

- `--dry-run` – no DB or S3 writes; only logs what would be done.
- `--no-upload-media` – load users, applications, posts, and Stripe IDs only; do not upload media or create `Image` records.

Ensure the app is configured (DB, S3/Tigris if you use media) and run against a dev or staging DB first.

---

## Quick test (no backup.sql)

If you don’t have a real dump yet:

1. Create minimal CSVs in `wp_backup/csv/` with headers:  
   `wp0h_users.csv`, `wp0h_usermeta.csv`, `wp0h_posts.csv`, `wp0h_postmeta.csv`.
2. Run Step 2 with `--dry-run`, then without.
3. Run Step 3 with `--dry-run`, then without (and optionally `--no-upload-media` if S3 isn’t set up).

---

## Troubleshooting

- **Missing CSV file**: Ensure all four `wp0h_*.csv` files exist in `--csv-dir` and have a header row.
- **SQL to CSV fails**: The parser expects `INSERT INTO \`wp0h_*\` VALUES (...);` (or with an explicit column list). Very large or non-standard dumps may need to be exported to CSV from MySQL instead.
- **Load fails on users**: Check that `users.json` has `email` and that the app allows registration without password (migration uses `require_password: false`).
- **Media**: Uploads require a configured S3/Tigris bucket and a migration uploader (first admin or first user). Use `--no-upload-media` to skip media and still load users, applications, and posts.

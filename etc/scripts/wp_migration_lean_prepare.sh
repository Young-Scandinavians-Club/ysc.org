#!/usr/bin/env bash
# Prepare a lean WordPress migration export (users, memberships, bookings; no news/media).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SQL="${WP_SQL:-wp_backup/backup.sql}"
DB="${WP_DB:-wp_backup/wp.duckdb}"
EXPORT_DIR="${WP_EXPORT_DIR:-wp_migration_export}"
CSV_DIR="${WP_CSV_DIR:-wp_export_csvs}"
WP_FILES="${WP_FILES:-wp_backup/files}"

mix ysc.wp_to_duckdb --sql "$SQL" --db "$DB" --force
mix ysc.wp_validate --db "$DB" || true
mix ysc.wp_extract \
  --db "$DB" \
  --export-dir "$EXPORT_DIR" \
  --wp-files "$WP_FILES" \
  --no-posts \
  --no-media
mix ysc.wp_validate --db "$DB" --export-dir "$EXPORT_DIR" || true

if [[ -d "$CSV_DIR" ]]; then
  mix ysc.wp_reconcile_csvs --export-dir "$EXPORT_DIR" --csv-dir "$CSV_DIR"
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
TARBALL="wp_migration_export_${STAMP}.tar.gz"
tar -czf "$TARBALL" "$EXPORT_DIR"
echo "Prepared lean export tarball: $TARBALL"

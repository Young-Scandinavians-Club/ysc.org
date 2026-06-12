#!/usr/bin/env bash
# Capture ghost preview pages as PNGs for print/PDF layouts.
# Requires: dev server on BASE_URL (default http://localhost:4000), npx + playwright.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
OUT_DIR="priv/static/images/admin-help"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ -z "${ADMIN_EMAIL:-}" || -z "${ADMIN_PASSWORD:-}" ]]; then
  if [[ "${CAPTURE_USE_SEED_LOGIN:-}" == "1" && "${MIX_ENV:-dev}" == "dev" ]]; then
    # Local dev only — matches priv/repo/seeds.exs (see docs/SEED_DATA_REFERENCE.md).
    EMAIL="admin@ysc.org"
    PASSWORD="very_secure_password"
  else
    echo "ADMIN_EMAIL and ADMIN_PASSWORD must be set (no embedded defaults)." >&2
    echo "For local dev: CAPTURE_USE_SEED_LOGIN=1 MIX_ENV=dev $0" >&2
    exit 1
  fi
else
  EMAIL="$ADMIN_EMAIL"
  PASSWORD="$ADMIN_PASSWORD"
fi

cd "$ROOT_DIR"
mkdir -p "$OUT_DIR"

TARGETS_JSON="$(
  mix run --no-start -e '
    targets = YscWeb.AdminHelp.Ghost.Registry.capture_targets()
    IO.puts(Jason.encode!(targets))
  '
)"

CAPTURE_DIR="$(cd "$(dirname "$0")/admin-help-capture" && pwd)"

if [[ ! -d "$CAPTURE_DIR/node_modules/playwright" ]]; then
  echo "Installing Playwright (first run)…" >&2
  (cd "$CAPTURE_DIR" && npm install --silent && npx playwright install chromium)
fi

BASE_URL="$BASE_URL" \
  OUT_DIR="$OUT_DIR" \
  ADMIN_EMAIL="$EMAIL" \
  ADMIN_PASSWORD="$PASSWORD" \
  TARGETS_JSON="$TARGETS_JSON" \
  node "$CAPTURE_DIR/capture.mjs"

#!/usr/bin/env bash
# sync_geoip_database.sh — Download GeoLite2-City from MaxMind and upload to Tigris.
#
# Intended to run weekly from GitHub Actions (and via workflow_dispatch for bootstrap).
# Deployed app machines only read this object; they never contact MaxMind.
#
# Environment:
#   MAXMIND_LICENSE_KEY                 (required)  MaxMind license key
#   AWS_ACCESS_KEY_ID                   (required)  Tigris access key with write access
#   AWS_SECRET_ACCESS_KEY               (required)  Tigris secret key
#   AWS_ENDPOINT_URL_S3                 (optional)  default https://fly.storage.tigris.dev
#   AWS_REGION                          (optional)  default auto
#   APP_RESOURCES_BUCKET_NAME           (optional)  default ysc-app-resources
#   GEOIP_S3_KEY                        (optional)  default geoip/GeoLite2-City.tar.gz
#   DRY_RUN                             (optional)  if 1, download + checksum only (no upload)
#
# Usage:
#   etc/scripts/sync_geoip_database.sh

set -euo pipefail

MAXMIND_LICENSE_KEY="${MAXMIND_LICENSE_KEY:-}"
AWS_ENDPOINT_URL_S3="${AWS_ENDPOINT_URL_S3:-https://fly.storage.tigris.dev}"
AWS_REGION="${AWS_REGION:-auto}"
APP_RESOURCES_BUCKET_NAME="${APP_RESOURCES_BUCKET_NAME:-ysc-app-resources}"
GEOIP_S3_KEY="${GEOIP_S3_KEY:-geoip/GeoLite2-City.tar.gz}"
DRY_RUN="${DRY_RUN:-0}"
EDITION_ID="GeoLite2-City"

if [ -z "$MAXMIND_LICENSE_KEY" ]; then
  echo "MAXMIND_LICENSE_KEY is required." >&2
  exit 1
fi

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  if [ "$DRY_RUN" != "1" ]; then
    echo "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are required unless DRY_RUN=1." >&2
    exit 1
  fi
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi

if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "sha256sum or shasum is required." >&2
  exit 1
fi

if [ "$DRY_RUN" != "1" ] && ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required unless DRY_RUN=1." >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ysc-geoip.XXXXXX")"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

ARCHIVE_PATH="${WORKDIR}/${EDITION_ID}.tar.gz"
CHECKSUM_PATH="${WORKDIR}/${EDITION_ID}.tar.gz.sha256"
DOWNLOAD_BASE="https://download.maxmind.com/app/geoip_download"

echo "Downloading ${EDITION_ID} from MaxMind..."
curl -fsSL -G "$DOWNLOAD_BASE" \
  --data-urlencode "edition_id=${EDITION_ID}" \
  --data-urlencode "license_key=${MAXMIND_LICENSE_KEY}" \
  --data-urlencode "suffix=tar.gz" \
  -o "$ARCHIVE_PATH"

echo "Downloading checksum..."
curl -fsSL -G "$DOWNLOAD_BASE" \
  --data-urlencode "edition_id=${EDITION_ID}" \
  --data-urlencode "license_key=${MAXMIND_LICENSE_KEY}" \
  --data-urlencode "suffix=tar.gz.sha256" \
  -o "$CHECKSUM_PATH"

EXPECTED_SHA="$(awk '{print $1}' "$CHECKSUM_PATH" | tr -d '[:space:]')"
if [ -z "$EXPECTED_SHA" ]; then
  echo "Failed to parse MaxMind checksum file." >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA="$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')"
else
  ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
fi

if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "Checksum mismatch for ${EDITION_ID}.tar.gz" >&2
  echo "  expected: ${EXPECTED_SHA}" >&2
  echo "  actual:   ${ACTUAL_SHA}" >&2
  exit 1
fi

echo "Checksum OK (${ACTUAL_SHA})."

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN=1 — skipping upload to s3://${APP_RESOURCES_BUCKET_NAME}/${GEOIP_S3_KEY}"
  exit 0
fi

echo "Uploading to s3://${APP_RESOURCES_BUCKET_NAME}/${GEOIP_S3_KEY} ..."
export AWS_ENDPOINT_URL_S3
export AWS_REGION
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

aws s3 cp "$ARCHIVE_PATH" "s3://${APP_RESOURCES_BUCKET_NAME}/${GEOIP_S3_KEY}" \
  --content-type "application/gzip"

echo "GeoIP database synced successfully."

#!/usr/bin/env bash
# Ensure a Fly app has at least N machines in "started" state for rolling deploys.
# If below the target, runs `fly scale count N` (non-interactive) and polls until ready.
#
# Usage:
#   FLY_API_TOKEN=... ./fly_ensure_min_started_machines.sh <app_name> <min_started>
#
# Optional env:
#   FLY_ENSURE_WAIT_SECS — max seconds to wait after scaling (default: 600)
#
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/fly_verify_min_started_machines.sh"

APP="${1:?Usage: $0 <fly_app_name> <min_started>}"
MIN_STARTED="${2:?Usage: $0 <fly_app_name> <min_started>}"
WAIT_SECS="${FLY_ENSURE_WAIT_SECS:-600}"

if ! [[ "$MIN_STARTED" =~ ^[0-9]+$ ]] || [ "$MIN_STARTED" -lt 1 ]; then
  echo "min_started must be a positive integer (got: $MIN_STARTED)" >&2
  exit 1
fi

if command -v fly >/dev/null 2>&1; then
  FLY_BIN=fly
elif command -v flyctl >/dev/null 2>&1; then
  FLY_BIN=flyctl
else
  echo "fly / flyctl not found (install: https://fly.io/docs/hands-on/install-flyctl/)" >&2
  exit 1
fi

if bash "$VERIFY_SCRIPT" "$APP" "$MIN_STARTED"; then
  exit 0
fi

echo "Scaling Fly app '$APP' to $MIN_STARTED machine(s) (non-interactive)..." >&2
if ! "$FLY_BIN" scale count "$MIN_STARTED" -a "$APP" -y; then
  echo "fly scale count failed for app '$APP'." >&2
  exit 1
fi

wait_start=$SECONDS
while true; do
  if bash "$VERIFY_SCRIPT" "$APP" "$MIN_STARTED"; then
    exit 0
  fi
  if [ "$((SECONDS - wait_start))" -ge "$WAIT_SECS" ]; then
    echo "Timed out after ${WAIT_SECS}s waiting for $MIN_STARTED started machine(s) on '$APP'." >&2
    exit 1
  fi
  echo "Waiting for machines to reach 'started' state..." >&2
  sleep 10
done

#!/usr/bin/env bash
# Ensure a Fly app has at least N machines in "started" state for rolling deploys.
# With auto_stop_machines, Fly may leave machines in "stopped" while scale count stays
# at N — so we start stopped machines first, then `fly scale count N` if still short.
#
# Usage:
#   FLY_API_TOKEN=... ./fly_ensure_min_started_machines.sh <app_name> <min_started>
#
# Optional env:
#   FLY_ENSURE_WAIT_SECS — max seconds to wait after scale/start (default: 600)
#   FLY_ENSURE_START_WAIT_SECS — max seconds to poll after starting stopped machines (default: 180)
#
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/fly_verify_min_started_machines.sh"

APP="${1:?Usage: $0 <fly_app_name> <min_started>}"
MIN_STARTED="${2:?Usage: $0 <fly_app_name> <min_started>}"
WAIT_SECS="${FLY_ENSURE_WAIT_SECS:-600}"
START_WAIT_SECS="${FLY_ENSURE_START_WAIT_SECS:-180}"

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

start_stopped_machines() {
  local list_json tmp
  if ! list_json=$("$FLY_BIN" machines list -a "$APP" --json 2>/dev/null); then
    echo "fly machines list failed for app '$APP' while looking for stopped machines." >&2
    return 1
  fi

  tmp=$(mktemp)
  printf '%s' "$list_json" >"$tmp"

  local -a stopped_ids=()
  mapfile -t stopped_ids < <(
    python3 - "$tmp" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    raw = json.load(f)

machines = raw if isinstance(raw, list) else []


def machine_state(m):
    return (m.get("state") or m.get("State") or "").lower()


for m in machines:
    mid = m.get("id")
    if mid and machine_state(m) == "stopped":
        print(mid)
PY
  )
  rm -f "$tmp"

  if [ "${#stopped_ids[@]}" -eq 0 ]; then
    return 0
  fi

  echo "Starting ${#stopped_ids[@]} stopped machine(s) on '$APP'..." >&2
  if ! "$FLY_BIN" machine start "${stopped_ids[@]}" -a "$APP"; then
    echo "fly machine start failed for app '$APP' (continuing; may still need scale)." >&2
  fi
}

if bash "$VERIFY_SCRIPT" "$APP" "$MIN_STARTED"; then
  exit 0
fi

echo "Below $MIN_STARTED started machine(s); waking stopped machines if any..." >&2
start_stopped_machines || true

wait_start=$SECONDS
while true; do
  if bash "$VERIFY_SCRIPT" "$APP" "$MIN_STARTED"; then
    exit 0
  fi
  if [ "$((SECONDS - wait_start))" -ge "$START_WAIT_SECS" ]; then
    break
  fi
  echo "Waiting for started machines after wake..." >&2
  sleep 5
done

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

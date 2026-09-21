#!/usr/bin/env bash
# Fail unless the Fly app has at least N machines in "started" state.
# Rolling deploys need spare capacity so one machine can update while others serve traffic.
#
# Usage:
#   FLY_API_TOKEN=... ./fly_verify_min_started_machines.sh <app_name> <min_started>
#
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

APP="${1:?Usage: $0 <fly_app_name> <min_started>}"
MIN_STARTED="${2:?Usage: $0 <fly_app_name> <min_started>}"

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

if ! LIST_JSON=$("$FLY_BIN" machines list -a "$APP" --json 2>/dev/null); then
  echo "fly machines list failed for app '$APP'. Check Fly credentials and app name." >&2
  exit 1
fi

tmp=$(mktemp)
cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT
printf '%s' "$LIST_JSON" >"$tmp"

if ! python3 - "$MIN_STARTED" "$APP" "$tmp" <<'PY'; then
import json, sys

min_started = int(sys.argv[1])
app = sys.argv[2]
path = sys.argv[3]

with open(path, encoding="utf-8") as f:
    raw = json.load(f)

machines = raw if isinstance(raw, list) else []


def machine_state(m):
    return (m.get("state") or m.get("State") or "").lower()


started = [m for m in machines if machine_state(m) == "started"]
n = len(started)

if n < min_started:
    print(
        f"Fly app '{app}' has {n} machine(s) in 'started' state; need at least {min_started} for a rolling deploy.",
        file=sys.stderr,
    )
    print("Scale up before releasing, e.g. `fly scale count 2 -a " + app + "` (or add machines in the Fly dashboard).", file=sys.stderr)
    sys.exit(1)

print(f"OK: Fly app '{app}' has {n} started machine(s) (minimum {min_started}).")
PY
  exit 1
fi

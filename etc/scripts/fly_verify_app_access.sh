#!/usr/bin/env bash
# Verify the current Fly CLI auth (FLY_API_TOKEN and/or fly auth login) can access
# an app, and optionally that it lives in the expected organization slug.
#
# Uses `fly apps list --json` so we only consider apps visible to the active credential.
#
# Usage:
#   FLY_API_TOKEN=... ./fly_verify_app_access.sh <app_name> [expected_org_slug]
#   ./fly_verify_app_access.sh <app_name>   # uses fly auth login session only
#
# If FLY_API_TOKEN is set in your environment, flyctl prefers it over `fly auth login`.
# For sandbox make targets without FLY_SANDBOX_ACCESS_TOKEN, the Makefile unsets
# FLY_API_TOKEN so your interactive login is used.
#
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

APP="${1:?Usage: $0 <fly_app_name> [expected_org_slug]}"
EXPECT_ORG="${2:-}"

fly_hint_env() {
  if [ -n "${FLY_API_TOKEN:-}" ]; then
    echo "FLY_API_TOKEN is set; flyctl uses it instead of 'fly auth login'. Run 'unset FLY_API_TOKEN' or export the correct token for this app." >&2
  fi
}

if ! command -v fly >/dev/null 2>&1; then
  echo "fly CLI not found (install: https://fly.io/docs/hands-on/install-flyctl/)" >&2
  exit 1
fi

if ! LIST_JSON=$(fly apps list --json 2>/dev/null); then
  echo "fly apps list failed. Check Fly credentials." >&2
  fly_hint_env
  exit 1
fi

tmp=$(mktemp)
cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT
printf '%s' "$LIST_JSON" >"$tmp"

if ! python3 - "$APP" "$EXPECT_ORG" "$tmp" <<'PY'; then
import json, sys

app_name = sys.argv[1]
expect_org = sys.argv[2] or None
if expect_org == "":
    expect_org = None
path = sys.argv[3]

with open(path, encoding="utf-8") as f:
    raw = json.load(f)

apps = raw if isinstance(raw, list) else raw.get("apps") or raw.get("Apps") or []


def org_slug(a):
    o = a.get("Organization") or a.get("organization")
    if isinstance(o, str):
        return o
    if isinstance(o, dict):
        return o.get("Slug") or o.get("slug") or ""
    return ""


found = None
for a in apps:
    name = a.get("Name") or a.get("name") or a.get("ID") or a.get("Id")
    if name == app_name:
        found = a
        break

if not found:
    print(
        f"Cannot see Fly app '{app_name}' with the current credentials (wrong account, wrong token, or typo).",
        file=sys.stderr,
    )
    print(f"Try: fly apps list | grep -i {app_name}", file=sys.stderr)
    sys.exit(1)

if expect_org:
    slug = org_slug(found)
    if slug != expect_org:
        print(
            f"Fly app '{app_name}' is in organization '{slug}', but expected '{expect_org}'.",
            file=sys.stderr,
        )
        sys.exit(1)

suffix = f" (org {expect_org})" if expect_org else ""
print(f"OK: Fly credentials can access app '{app_name}'{suffix}.")
PY
  fly_hint_env
  exit 1
fi

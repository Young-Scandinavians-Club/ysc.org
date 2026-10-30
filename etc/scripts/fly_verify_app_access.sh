#!/usr/bin/env bash
# Verify the current Fly CLI auth (FLY_API_TOKEN and/or fly auth login) can access
# an app, and optionally that it lives in the expected organization slug.
#
# Uses `fly apps list --json` so we only consider apps visible to the active credential.
#
# v2.51.0 Deploy Production (run 40961012848 / job 123754475932) failed here
# for ysc-query-console-sandbox. Tests on the same commit passed. Sibling
# ysc-sandbox gate used the same FLY_API_TOKEN and flyctl v0.5.1 and succeeded
# eight seconds later. Fly's flyctl_releases API was 503ing at the same time;
# `fly apps list --json` returned empty/non-JSON with exit 0. Python then
# crashed (`JSONDecodeError: Expecting value: line 1 column 1`) because this
# script discarded stderr (`2>/dev/null`) and did not retry.
#
# Usage:
#   FLY_API_TOKEN=... ./fly_verify_app_access.sh <app_name> [expected_org_slug]
#   ./fly_verify_app_access.sh <app_name>   # uses fly auth login session only
#   ./fly_verify_app_access.sh --self-test
#
# If FLY_API_TOKEN is set in your environment, flyctl prefers it over `fly auth login`.
# For sandbox make targets without FLY_SANDBOX_ACCESS_TOKEN, the Makefile unsets
# FLY_API_TOKEN so your interactive login is used.
#
# FLY_APPS_LIST_CMD overrides `fly apps list --json` (self-test / ExUnit).
#
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

FLY_VERIFY_ATTEMPTS="${FLY_VERIFY_ATTEMPTS:-4}"
FLY_VERIFY_RETRY_DELAY_SECONDS="${FLY_VERIFY_RETRY_DELAY_SECONDS:-5}"

APP=""
EXPECT_ORG=""
FLY_BIN=""

retry() {
  local max_attempts="${1}"
  shift
  local seconds="${1}"
  shift
  local attempt_num=1

  until "$@"; do
    if [ "${attempt_num}" -eq "${max_attempts}" ]; then
      echo "fly_verify_app_access.sh: attempt ${attempt_num} failed and there are no more attempts left" >&2
      return 1
    fi
    echo "fly_verify_app_access.sh: attempt ${attempt_num} failed; retrying in ${seconds}s..." >&2
    attempt_num=$((attempt_num + 1))
    if [ "${seconds}" -gt 0 ]; then
      sleep "${seconds}"
    fi
  done
}

usage() {
  echo "Usage: $0 <fly_app_name> [expected_org_slug]" >&2
  echo "       $0 --self-test" >&2
}

fly_hint_env() {
  if [ -n "${FLY_API_TOKEN:-}" ]; then
    echo "FLY_API_TOKEN is set; flyctl uses it instead of 'fly auth login'. Run 'unset FLY_API_TOKEN' or export the correct token for this app." >&2
  fi
}

resolve_fly_bin() {
  if command -v fly >/dev/null 2>&1; then
    FLY_BIN=fly
  elif command -v flyctl >/dev/null 2>&1; then
    FLY_BIN=flyctl
  else
    echo "fly / flyctl not found (install: https://fly.io/docs/hands-on/install-flyctl/)" >&2
    return 1
  fi
}

parse_args() {
  if [ "$#" -lt 1 ]; then
    echo "fly_verify_app_access.sh: app name is required" >&2
    usage
    return 1
  fi
  APP="${1}"
  EXPECT_ORG="${2:-}"
}

dump_cmd_stderr() {
  local err="${1}"
  if [ -s "${err}" ]; then
    cat "${err}" >&2
  fi
}

# Fetches `fly apps list --json` into $1 (stdout file) and $2 (stderr file).
# Empty or non-zero flyctl output is a retryable failure — Fly GraphQL 5xx
# can exit 0 with no JSON (run 40961012848).
fetch_apps_list_json() {
  local out="${1}"
  local err="${2}"
  local status=0

  : >"${out}"
  : >"${err}"

  if [ -n "${FLY_APPS_LIST_CMD:-}" ]; then
    bash -c "${FLY_APPS_LIST_CMD}" >"${out}" 2>"${err}" || status=$?
  else
    "${FLY_BIN}" apps list --json >"${out}" 2>"${err}" || status=$?
  fi

  if [ "${status}" -ne 0 ]; then
    echo "fly apps list failed (exit ${status}). Check Fly credentials." >&2
    dump_cmd_stderr "${err}"
    return 1
  fi

  if [ ! -s "${out}" ]; then
    echo "fly apps list --json returned empty output." >&2
    dump_cmd_stderr "${err}"
    return 1
  fi
}

app_in_list() {
  local path="${1}"

  python3 - "${APP}" "${EXPECT_ORG}" "${path}" <<'PY'
import json, sys

app_name = sys.argv[1]
expect_org = sys.argv[2] or None
if expect_org == "":
    expect_org = None
path = sys.argv[3]


def load_apps(raw_text):
    text = raw_text.strip()
    if not text:
        raise json.JSONDecodeError("empty", text, 0)
    try:
        raw = json.loads(text)
    except json.JSONDecodeError:
        apps_nl = []
        for line in text.splitlines():
            line = line.strip()
            if line:
                apps_nl.append(json.loads(line))
        return apps_nl
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        if raw.get("Name") or raw.get("name"):
            return [raw]
        return raw.get("apps") or raw.get("Apps") or []
    return []


with open(path, encoding="utf-8") as f:
    raw_text = f.read()

try:
    apps = load_apps(raw_text)
except json.JSONDecodeError as exc:
    preview = raw_text[:200].replace("\n", "\\n")
    print(
        f"fly apps list --json returned non-JSON output: {exc}",
        file=sys.stderr,
    )
    print(f"First 200 chars: {preview!r}", file=sys.stderr)
    sys.exit(1)


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
}

verify_access() {
  local tmp err status
  tmp="$(mktemp)"
  err="$(mktemp)"
  status=0
  fetch_apps_list_json "${tmp}" "${err}" || status=$?
  if [ "${status}" -eq 0 ]; then
    app_in_list "${tmp}" || status=$?
  fi
  rm -f "${tmp}" "${err}"
  return "${status}"
}

self_test() {
  local tmp n out tmpdir

  tmp="$(mktemp)"
  echo 0 >"${tmp}"
  fail_twice() {
    n="$(cat "${tmp}")"
    n=$((n + 1))
    echo "${n}" >"${tmp}"
    [ "${n}" -ge 3 ]
  }
  retry 5 0 fail_twice
  n="$(cat "${tmp}")"
  rm -f "${tmp}"
  if [ "${n}" -ne 3 ]; then
    echo "fly_verify_app_access.sh: retry helper expected 3 attempts, got ${n}" >&2
    return 1
  fi

  if out="$(parse_args 2>&1)"; then
    echo "fly_verify_app_access.sh: expected missing app name to fail" >&2
    return 1
  fi
  if [[ "${out}" != *"app name is required"* ]]; then
    echo "fly_verify_app_access.sh: unexpected missing-arg error: ${out}" >&2
    return 1
  fi

  parse_args ysc-query-console-sandbox
  tmpdir="$(mktemp -d)"
  echo 0 >"${tmpdir}/n"
  FLY_APPS_LIST_CMD="n=\$(cat '${tmpdir}/n'); n=\$((n+1)); echo \"\$n\" >'${tmpdir}/n'; if [ \"\$n\" -lt 3 ]; then exit 0; fi; printf '%s\n' '[{\"Name\":\"ysc-query-console-sandbox\"}]'"
  retry 5 0 verify_access
  n="$(cat "${tmpdir}/n")"
  rm -rf "${tmpdir}"
  unset FLY_APPS_LIST_CMD
  if [ "${n}" -ne 3 ]; then
    echo "fly_verify_app_access.sh: expected 3 list attempts after empty JSON, got ${n}" >&2
    return 1
  fi

  parse_args ysc-query-console-sandbox
  if FLY_APPS_LIST_CMD="true" retry 2 0 verify_access; then
    echo "fly_verify_app_access.sh: expected empty JSON to fail" >&2
    return 1
  fi

  parse_args ysc-query-console-sandbox
  if FLY_APPS_LIST_CMD="printf '%s\n' 'not-json'" retry 2 0 verify_access; then
    echo "fly_verify_app_access.sh: expected non-JSON list output to fail" >&2
    return 1
  fi

  parse_args ysc-query-console-sandbox
  if FLY_APPS_LIST_CMD="printf '%s\n' '[{\"Name\":\"other-app\"}]'" retry 2 0 verify_access; then
    echo "fly_verify_app_access.sh: expected missing app to fail" >&2
    return 1
  fi

  parse_args ysc-query-console-sandbox acme-org
  FLY_APPS_LIST_CMD="printf '%s\n' '[{\"Name\":\"ysc-query-console-sandbox\",\"Organization\":{\"Slug\":\"acme-org\"}}]'"
  verify_access
  unset FLY_APPS_LIST_CMD

  echo "fly_verify_app_access.sh: self-test passed"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  "")
    usage
    exit 1
    ;;
  *)
    parse_args "$@"
    if [ -z "${FLY_APPS_LIST_CMD:-}" ]; then
      resolve_fly_bin
    fi
    if ! retry "${FLY_VERIFY_ATTEMPTS}" "${FLY_VERIFY_RETRY_DELAY_SECONDS}" verify_access; then
      fly_hint_env
      exit 1
    fi
    ;;
esac

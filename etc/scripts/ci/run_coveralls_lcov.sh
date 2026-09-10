#!/usr/bin/env bash
# Run mix coveralls.lcov with a stderr heartbeat so GitHub Actions keeps
# receiving logs if ExUnit/coverage output is fully buffered (no TTY).
#
# Usage:
#   MIX_ENV=test ./etc/scripts/ci/run_coveralls_lcov.sh
#   COVERALLS_CMD="mix coveralls.lcov" ./etc/scripts/ci/run_coveralls_lcov.sh
#   ./etc/scripts/ci/run_coveralls_lcov.sh --self-test
set -euo pipefail

COVERALLS_CMD="${COVERALLS_CMD:-mix coveralls.lcov}"
HEARTBEAT_SECONDS="${HEARTBEAT_SECONDS:-60}"

parse_heartbeat_seconds() {
  local seconds="${1}"
  if [[ ! "${seconds}" =~ ^[1-9][0-9]*$ ]]; then
    echo "run_coveralls_lcov.sh: HEARTBEAT_SECONDS must be a positive integer, got '${seconds}'" >&2
    return 1
  fi
  echo "${seconds}"
}

mem_available_kib() {
  awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo unknown
}

heartbeat() {
  local seconds="${1}"
  while true; do
    sleep "${seconds}"
    echo "run_coveralls_lcov.sh: still running $(date -u +%Y-%m-%dT%H:%M:%SZ) MemAvailable=$(mem_available_kib) kB" >&2
  done
}

run_coveralls() {
  local seconds hb_pid status
  seconds="$(parse_heartbeat_seconds "${HEARTBEAT_SECONDS}")"

  heartbeat "${seconds}" &
  hb_pid=$!
  cleanup() {
    kill "${hb_pid}" 2>/dev/null || true
    wait "${hb_pid}" 2>/dev/null || true
  }
  trap cleanup EXIT

  status=0
  bash -c "${COVERALLS_CMD}" || status=$?
  cleanup
  trap - EXIT
  return "${status}"
}

self_test() {
  local out status

  if out="$(HEARTBEAT_SECONDS=0 parse_heartbeat_seconds 0 2>&1)"; then
    echo "run_coveralls_lcov.sh: expected HEARTBEAT_SECONDS=0 to fail" >&2
    return 1
  fi
  if [[ "${out}" != *"positive integer"* ]]; then
    echo "run_coveralls_lcov.sh: unexpected error for HEARTBEAT_SECONDS=0: ${out}" >&2
    return 1
  fi

  out="$(parse_heartbeat_seconds 60)"
  if [ "${out}" != "60" ]; then
    echo "run_coveralls_lcov.sh: expected parse_heartbeat_seconds 60 to return 60, got ${out}" >&2
    return 1
  fi

  COVERALLS_CMD="true" HEARTBEAT_SECONDS=1 run_coveralls
  status=$?
  if [ "${status}" -ne 0 ]; then
    echo "run_coveralls_lcov.sh: expected COVERALLS_CMD=true to succeed, got ${status}" >&2
    return 1
  fi

  if COVERALLS_CMD="false" HEARTBEAT_SECONDS=1 run_coveralls; then
    echo "run_coveralls_lcov.sh: expected COVERALLS_CMD=false to fail" >&2
    return 1
  fi

  out="$(COVERALLS_CMD="sleep 2" HEARTBEAT_SECONDS=1 run_coveralls 2>&1)"
  if [[ "${out}" != *"still running"* ]]; then
    echo "run_coveralls_lcov.sh: expected heartbeat on stderr, got: ${out}" >&2
    return 1
  fi

  echo "run_coveralls_lcov.sh: self-test passed"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  "")
    run_coveralls
    ;;
  *)
    echo "Usage: $0 [--self-test]" >&2
    exit 1
    ;;
esac

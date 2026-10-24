#!/usr/bin/env bash
# Retry mix deps.get for transient hex.pm registry 5xx errors.
#
# Production Docker build on v2.49.1 (run 40112796404 / job 120929589166,
# 2026-10-24) failed in `mix deps.get --only prod`:
#   Failed to fetch record for passbook from registry
#   Internal Server Error
#   ** (Mix) Unknown package passbook in lockfile
# Hex.pm returned 500 for one locked package; the sandbox job built the
# same Dockerfile about eight minutes earlier.
#
# Mix also reports a registry 500 as "Unknown package in lockfile", so this
# retries any mix deps.get failure rather than matching a single phrase.
#
# Usage:
#   ./etc/scripts/mix_deps_get_retry.sh --only prod
#   ./etc/scripts/mix_deps_get_retry.sh --self-test
set -euo pipefail

MIX_DEPS_GET_ATTEMPTS="${MIX_DEPS_GET_ATTEMPTS:-4}"
MIX_DEPS_GET_RETRY_DELAY_SECONDS="${MIX_DEPS_GET_RETRY_DELAY_SECONDS:-15}"

DEPS_GET_ARGS=()

retry() {
  local max_attempts="${1}"
  shift
  local seconds="${1}"
  shift
  local attempt_num=1

  until "$@"; do
    if [ "${attempt_num}" -eq "${max_attempts}" ]; then
      echo "mix_deps_get_retry.sh: attempt ${attempt_num} failed and there are no more attempts left" >&2
      return 1
    fi
    echo "mix_deps_get_retry.sh: attempt ${attempt_num} failed; retrying in ${seconds}s..." >&2
    attempt_num=$((attempt_num + 1))
    if [ "${seconds}" -gt 0 ]; then
      sleep "${seconds}"
    fi
  done
}

usage() {
  echo "Usage: $0 [mix deps.get args...]" >&2
  echo "       $0 --self-test" >&2
}

parse_args() {
  DEPS_GET_ARGS=("$@")
}

# Fills the nameref array with the mix deps.get argv (no execution).
deps_get_argv() {
  local -n _argv="${1}"
  _argv=(mix deps.get "${DEPS_GET_ARGS[@]}")
}

format_deps_get_cmd() {
  local argv
  deps_get_argv argv
  printf '%q ' "${argv[@]}"
  printf '\n'
}

deps_get() {
  local argv
  if [ -n "${MIX_DEPS_GET_CMD:-}" ]; then
    bash -c "${MIX_DEPS_GET_CMD}"
    return
  fi
  if ! command -v mix >/dev/null 2>&1; then
    echo "mix_deps_get_retry.sh: mix not found; cannot fetch dependencies" >&2
    return 1
  fi
  deps_get_argv argv
  "${argv[@]}"
}

self_test() {
  local tmp n out

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
    echo "mix_deps_get_retry.sh: retry helper expected 3 attempts, got ${n}" >&2
    return 1
  fi

  parse_args --only prod
  out="$(format_deps_get_cmd)"
  if [[ "${out}" != *"mix deps.get"* ]] ||
    [[ "${out}" != *"--only"* ]] ||
    [[ "${out}" != *"prod"* ]]; then
    echo "mix_deps_get_retry.sh: unexpected deps.get command: ${out}" >&2
    return 1
  fi

  tmp="$(mktemp -d)"
  MIX_DEPS_GET_CMD="echo deps.get >>'${tmp}/deps'; [ \"\$(wc -l <'${tmp}/deps' | tr -d ' ')\" -ge 3 ]" \
    retry 5 0 deps_get
  n="$(wc -l <"${tmp}/deps" | tr -d ' ')"
  rm -rf "${tmp}"
  if [ "${n}" -ne 3 ]; then
    echo "mix_deps_get_retry.sh: expected 3 deps.get attempts, got ${n}" >&2
    return 1
  fi

  if MIX_DEPS_GET_CMD="false" retry 2 0 deps_get; then
    echo "mix_deps_get_retry.sh: expected exhausted retries to fail" >&2
    return 1
  fi

  echo "mix_deps_get_retry.sh: self-test passed"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  *)
    parse_args "$@"
    retry "${MIX_DEPS_GET_ATTEMPTS}" "${MIX_DEPS_GET_RETRY_DELAY_SECONDS}" deps_get
    ;;
esac

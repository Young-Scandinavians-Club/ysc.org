#!/usr/bin/env bash
# Add swap on GitHub-hosted runners so mix coveralls.lcov memory spikes do not
# kill the runner process. When that happens GitHub reports:
#   "The hosted runner lost communication with the server"
# with no test logs (run 34416092041 / job 102682478724, 2026-09-09).
#
# Usage:
#   ./etc/scripts/ci/enable_runner_swap.sh
#   SWAP_FILE=/swapfile SWAP_SIZE_GIB=8 ./etc/scripts/ci/enable_runner_swap.sh
#   ./etc/scripts/ci/enable_runner_swap.sh --self-test
set -euo pipefail

SWAP_FILE="${SWAP_FILE:-/swapfile}"
SWAP_SIZE_GIB="${SWAP_SIZE_GIB:-8}"
SWAP_SWAPPINESS="${SWAP_SWAPPINESS:-10}"

parse_size_gib() {
  local size="${1}"
  if [[ ! "${size}" =~ ^[1-9][0-9]*$ ]]; then
    echo "enable_runner_swap.sh: SWAP_SIZE_GIB must be a positive integer, got '${size}'" >&2
    return 1
  fi
  echo "${size}"
}

current_swap_kib() {
  local kib
  kib="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
  if [[ "${kib}" =~ ^[0-9]+$ ]]; then
    echo "${kib}"
  else
    echo 0
  fi
}

enable_swap() {
  local size_gib path
  size_gib="$(parse_size_gib "${SWAP_SIZE_GIB}")"
  path="${SWAP_FILE}"

  if [ -r /proc/meminfo ]; then
    echo "enable_runner_swap.sh: memory before swap:"
    free -h || true
  fi

  if [ "$(current_swap_kib)" -ge $((size_gib * 1024 * 1024)) ]; then
    echo "enable_runner_swap.sh: swap already >= ${size_gib}GiB, leaving it in place"
    return 0
  fi

  if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    echo "enable_runner_swap.sh: need root or passwordless sudo to enable swap" >&2
    return 1
  fi

  run() {
    if [ "$(id -u)" -eq 0 ]; then
      "$@"
    else
      sudo "$@"
    fi
  }

  run swapoff "${path}" 2>/dev/null || true
  run rm -f "${path}"
  run fallocate -l "${size_gib}G" "${path}"
  run chmod 600 "${path}"
  run mkswap "${path}"
  run swapon "${path}"
  run sysctl "vm.swappiness=${SWAP_SWAPPINESS}"

  echo "enable_runner_swap.sh: enabled ${size_gib}GiB swap at ${path}"
  free -h || true
}

self_test() {
  local out

  if out="$(SWAP_SIZE_GIB=0 parse_size_gib 0 2>&1)"; then
    echo "enable_runner_swap.sh: expected SWAP_SIZE_GIB=0 to fail" >&2
    return 1
  fi
  if [[ "${out}" != *"positive integer"* ]]; then
    echo "enable_runner_swap.sh: unexpected error for SWAP_SIZE_GIB=0: ${out}" >&2
    return 1
  fi

  if out="$(parse_size_gib abc 2>&1)"; then
    echo "enable_runner_swap.sh: expected SWAP_SIZE_GIB=abc to fail" >&2
    return 1
  fi

  out="$(parse_size_gib 8)"
  if [ "${out}" != "8" ]; then
    echo "enable_runner_swap.sh: expected parse_size_gib 8 to return 8, got ${out}" >&2
    return 1
  fi

  if [ ! -r /proc/meminfo ]; then
    echo "enable_runner_swap.sh: /proc/meminfo missing; skip SwapTotal parse" >&2
  else
    current_swap_kib >/dev/null
  fi

  echo "enable_runner_swap.sh: self-test passed"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  "")
    enable_swap
    ;;
  *)
    echo "Usage: $0 [--self-test]" >&2
    exit 1
    ;;
esac

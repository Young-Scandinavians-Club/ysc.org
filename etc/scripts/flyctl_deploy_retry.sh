#!/usr/bin/env bash
# Retry flyctl deploy for transient Fly registry 5xx errors.
#
# Two cooperating Fly registry flakes:
#
# 1. docker_buildx_push_retry.sh already retries image *pushes*. flyctl deploy
#    --image still queries registry.fly.io for the image digest (run 38945847545 /
#    jobs 117134155073 and 117134155035, 2026-10-16):
#      Error: failed to fetch an image or build from source: ...
#      Bad gateway for registry: registry.fly.io
#      server returned a non-200 status code: 500
#
# 2. flyctl deploy --dockerfile --local-only builds on the runner, then pushes
#    to registry.fly.io. v2.52.0 production (run 41090055389 / job 124185686654)
#    compiled successfully, then failed the push:
#      Error: failed to fetch an image or build from source: error rendering
#      push status stream: unknown: failed to copy: unexpected status from PUT
#      request to https://registry.fly.io/v2/ysc-prod/blobs/uploads/...: 502
#      Bad Gateway
#    Docker layer cache makes a retry cheap; the next flyctl process also
#    re-auths so a 10-minute cold build cannot leave a stale registry token.
#
# Query-console --local-only deploys must run with cwd query_console/ (and
# -c fly.sandbox.toml / fly.prod.toml). flyctl uses the process cwd as the
# Docker build context; running from the repo root copies the main app
# mix.exs, which path-deps vendor/blurhash the console image does not have
# (v2.53.0/v2.53.1, runs 41118049812 and 41131633952).
#
# Usage:
#   ./etc/scripts/flyctl_deploy_retry.sh \
#     --image registry.fly.io/ysc-sandbox:version \
#     -a ysc-sandbox \
#     -c etc/fly/fly-sandbox.toml \
#     --image-label version
#   ./etc/scripts/flyctl_deploy_retry.sh \
#     --dockerfile etc/docker/Dockerfile \
#     -a ysc-prod \
#     -c etc/fly/fly-prod.toml \
#     --local-only \
#     --build-arg BUILD_VERSION=version \
#     --image-label version
#   ../etc/scripts/flyctl_deploy_retry.sh \
#     -a ysc-query-console-sandbox \
#     -c fly.sandbox.toml \
#     --local-only \
#     --build-arg BUILD_VERSION=version \
#     --image-label version
#   ./etc/scripts/flyctl_deploy_retry.sh --self-test
set -euo pipefail

FLYCTL_DEPLOY_ATTEMPTS="${FLYCTL_DEPLOY_ATTEMPTS:-4}"
FLYCTL_DEPLOY_RETRY_DELAY_SECONDS="${FLYCTL_DEPLOY_RETRY_DELAY_SECONDS:-30}"

DEPLOY_ARGS=()

retry() {
  local max_attempts="${1}"
  shift
  local seconds="${1}"
  shift
  local attempt_num=1

  until "$@"; do
    if [ "${attempt_num}" -eq "${max_attempts}" ]; then
      echo "flyctl_deploy_retry.sh: attempt ${attempt_num} failed and there are no more attempts left" >&2
      return 1
    fi
    echo "flyctl_deploy_retry.sh: attempt ${attempt_num} failed; retrying in ${seconds}s..." >&2
    attempt_num=$((attempt_num + 1))
    if [ "${seconds}" -gt 0 ]; then
      sleep "${seconds}"
    fi
  done
}

usage() {
  echo "Usage: $0 [flyctl deploy args...]" >&2
  echo "       $0 --self-test" >&2
}

parse_args() {
  if [ "$#" -eq 0 ]; then
    echo "flyctl_deploy_retry.sh: flyctl deploy arguments are required" >&2
    usage
    return 1
  fi
  DEPLOY_ARGS=("$@")
}

# Fills the nameref array with the flyctl deploy argv (no execution).
deploy_argv() {
  local -n _argv="${1}"
  _argv=(flyctl deploy "${DEPLOY_ARGS[@]}")
}

format_deploy_cmd() {
  local argv
  deploy_argv argv
  printf '%q ' "${argv[@]}"
  printf '\n'
}

deploy_image() {
  local argv
  if [ -n "${FLYCTL_DEPLOY_CMD:-}" ]; then
    bash -c "${FLYCTL_DEPLOY_CMD}"
    return
  fi
  if ! command -v flyctl >/dev/null 2>&1; then
    echo "flyctl_deploy_retry.sh: flyctl not found; cannot deploy" >&2
    return 1
  fi
  deploy_argv argv
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
    echo "flyctl_deploy_retry.sh: retry helper expected 3 attempts, got ${n}" >&2
    return 1
  fi

  if out="$(parse_args 2>&1)"; then
    echo "flyctl_deploy_retry.sh: expected missing deploy args to fail" >&2
    return 1
  fi
  if [[ "${out}" != *"flyctl deploy arguments are required"* ]]; then
    echo "flyctl_deploy_retry.sh: unexpected missing-arg error: ${out}" >&2
    return 1
  fi

  parse_args --image registry.example/app:1 -a app -c fly.toml --image-label 1
  out="$(format_deploy_cmd)"
  if [[ "${out}" != *"flyctl deploy"* ]] ||
    [[ "${out}" != *"registry.example/app:1"* ]] ||
    [[ "${out}" != *"-a"* ]] ||
    [[ "${out}" != *"fly.toml"* ]] ||
    [[ "${out}" != *"--image-label"* ]]; then
    echo "flyctl_deploy_retry.sh: unexpected deploy command: ${out}" >&2
    return 1
  fi

  parse_args --dockerfile etc/docker/Dockerfile -a ysc-prod \
    -c etc/fly/fly-prod.toml --local-only --build-arg BUILD_VERSION=1 \
    --image-label 1
  out="$(format_deploy_cmd)"
  if [[ "${out}" != *"flyctl deploy"* ]] ||
    [[ "${out}" != *"--dockerfile"* ]] ||
    [[ "${out}" != *"etc/docker/Dockerfile"* ]] ||
    [[ "${out}" != *"ysc-prod"* ]] ||
    [[ "${out}" != *"etc/fly/fly-prod.toml"* ]] ||
    [[ "${out}" != *"--local-only"* ]] ||
    [[ "${out}" != *"BUILD_VERSION=1"* ]]; then
    echo "flyctl_deploy_retry.sh: unexpected local-only deploy command: ${out}" >&2
    return 1
  fi

  parse_args -a ysc-query-console-sandbox -c fly.sandbox.toml \
    --local-only --build-arg BUILD_VERSION=1 --image-label 1
  out="$(format_deploy_cmd)"
  if [[ "${out}" != *"ysc-query-console-sandbox"* ]] ||
    [[ "${out}" != *"fly.sandbox.toml"* ]] ||
    [[ "${out}" == *"query_console/fly.sandbox.toml"* ]] ||
    [[ "${out}" != *"--local-only"* ]]; then
    echo "flyctl_deploy_retry.sh: unexpected query-console deploy command: ${out}" >&2
    return 1
  fi

  tmp="$(mktemp -d)"
  FLYCTL_DEPLOY_CMD="echo deploy >>'${tmp}/deploy'; [ \"\$(wc -l <'${tmp}/deploy' | tr -d ' ')\" -ge 3 ]" \
    retry 5 0 deploy_image
  n="$(wc -l <"${tmp}/deploy" | tr -d ' ')"
  rm -rf "${tmp}"
  if [ "${n}" -ne 3 ]; then
    echo "flyctl_deploy_retry.sh: expected 3 deploy attempts, got ${n}" >&2
    return 1
  fi

  if FLYCTL_DEPLOY_CMD="false" retry 2 0 deploy_image; then
    echo "flyctl_deploy_retry.sh: expected exhausted retries to fail" >&2
    return 1
  fi

  echo "flyctl_deploy_retry.sh: self-test passed"
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
    retry "${FLYCTL_DEPLOY_ATTEMPTS}" "${FLYCTL_DEPLOY_RETRY_DELAY_SECONDS}" deploy_image
    ;;
esac

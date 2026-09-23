#!/usr/bin/env bash
# Push a Docker image with retries for transient Fly registry 5xx errors.
#
# `docker/build-push-action` / BuildKit already retries blob PUTs with 1s/2s/4s
# backoff, but registry.fly.io can 502 for several minutes (run 35878712096 /
# job 107251701228, 2026-09-23). An outer retry re-runs `flyctl auth docker`
# (tokens expire after 5 minutes) and waits longer between full push attempts.
#
# Usage:
#   ./etc/scripts/docker_buildx_push_retry.sh \
#     --file etc/docker/Dockerfile \
#     --tag registry.fly.io/ysc-sandbox:version \
#     --build-arg BUILD_VERSION=version \
#     --cache-scope main-app
#   ./etc/scripts/docker_buildx_push_retry.sh --self-test
set -euo pipefail

DOCKER_BUILDX_PUSH_ATTEMPTS="${DOCKER_BUILDX_PUSH_ATTEMPTS:-4}"
DOCKER_BUILDX_PUSH_RETRY_DELAY_SECONDS="${DOCKER_BUILDX_PUSH_RETRY_DELAY_SECONDS:-30}"

CONTEXT="."
FILE=""
TAG=""
CACHE_SCOPE=""
BUILD_ARGS=()

retry() {
  local max_attempts="${1}"
  shift
  local seconds="${1}"
  shift
  local attempt_num=1

  until "$@"; do
    if [ "${attempt_num}" -eq "${max_attempts}" ]; then
      echo "docker_buildx_push_retry.sh: attempt ${attempt_num} failed and there are no more attempts left" >&2
      return 1
    fi
    echo "docker_buildx_push_retry.sh: attempt ${attempt_num} failed; retrying in ${seconds}s..." >&2
    attempt_num=$((attempt_num + 1))
    if [ "${seconds}" -gt 0 ]; then
      sleep "${seconds}"
    fi
  done
}

usage() {
  echo "Usage: $0 --file FILE --tag TAG [--context DIR] [--cache-scope SCOPE] [--build-arg KEY=VAL]..." >&2
  echo "       $0 --self-test" >&2
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "${1}" in
      --file)
        FILE="${2:-}"
        shift 2
        ;;
      --tag)
        TAG="${2:-}"
        shift 2
        ;;
      --context)
        CONTEXT="${2:-}"
        shift 2
        ;;
      --cache-scope)
        CACHE_SCOPE="${2:-}"
        shift 2
        ;;
      --build-arg)
        BUILD_ARGS+=("${2:-}")
        shift 2
        ;;
      -h | --help)
        usage
        return 2
        ;;
      *)
        echo "docker_buildx_push_retry.sh: unknown argument: ${1}" >&2
        usage
        return 1
        ;;
    esac
  done

  if [ -z "${FILE}" ] || [ -z "${TAG}" ]; then
    echo "docker_buildx_push_retry.sh: --file and --tag are required" >&2
    usage
    return 1
  fi
}

# Fills the nameref array with the docker buildx argv (no execution).
buildx_push_argv() {
  local -n _argv="${1}"
  _argv=(docker buildx build --push --provenance=false --sbom=false
    --file "${FILE}" --tag "${TAG}")
  local arg
  for arg in "${BUILD_ARGS[@]}"; do
    _argv+=(--build-arg "${arg}")
  done
  if [ -n "${CACHE_SCOPE}" ]; then
    _argv+=(--cache-from "type=gha,scope=${CACHE_SCOPE},ignore-error=true")
  fi
  _argv+=("${CONTEXT}")
}

format_buildx_push_cmd() {
  local argv
  buildx_push_argv argv
  printf '%q ' "${argv[@]}"
  printf '\n'
}

auth_docker() {
  if [ -n "${FLYCTL_AUTH_DOCKER_CMD:-}" ]; then
    bash -c "${FLYCTL_AUTH_DOCKER_CMD}"
    return
  fi
  if ! command -v flyctl >/dev/null 2>&1; then
    echo "docker_buildx_push_retry.sh: flyctl not found; cannot log in to the Fly registry" >&2
    return 1
  fi
  flyctl auth docker
}

push_image() {
  local argv
  auth_docker
  if [ -n "${DOCKER_BUILDX_PUSH_CMD:-}" ]; then
    bash -c "${DOCKER_BUILDX_PUSH_CMD}"
    return
  fi
  buildx_push_argv argv
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
    echo "docker_buildx_push_retry.sh: retry helper expected 3 attempts, got ${n}" >&2
    return 1
  fi

  if out="$(parse_args 2>&1)"; then
    echo "docker_buildx_push_retry.sh: expected missing --file/--tag to fail" >&2
    return 1
  fi
  if [[ "${out}" != *"--file and --tag are required"* ]]; then
    echo "docker_buildx_push_retry.sh: unexpected missing-arg error: ${out}" >&2
    return 1
  fi

  parse_args --file etc/docker/Dockerfile --tag registry.example/app:1 \
    --context . --cache-scope main-app --build-arg BUILD_VERSION=1
  out="$(format_buildx_push_cmd)"
  if [[ "${out}" != *"docker buildx build"* ]] ||
    [[ "${out}" != *"--push"* ]] ||
    [[ "${out}" != *"--provenance=false"* ]] ||
    [[ "${out}" != *"etc/docker/Dockerfile"* ]] ||
    [[ "${out}" != *"registry.example/app:1"* ]] ||
    [[ "${out}" != *"BUILD_VERSION=1"* ]] ||
    [[ "${out}" != *"scope=main-app"* ]]; then
    echo "docker_buildx_push_retry.sh: unexpected buildx command: ${out}" >&2
    return 1
  fi

  tmp="$(mktemp -d)"
  FLYCTL_AUTH_DOCKER_CMD="echo auth >>'${tmp}/auth'" \
    DOCKER_BUILDX_PUSH_CMD="echo push >>'${tmp}/push'; [ \"\$(wc -l <'${tmp}/push' | tr -d ' ')\" -ge 3 ]" \
    retry 5 0 push_image
  n="$(wc -l <"${tmp}/auth" | tr -d ' ')"
  if [ "${n}" -ne 3 ]; then
    echo "docker_buildx_push_retry.sh: expected 3 auth attempts, got ${n}" >&2
    rm -rf "${tmp}"
    return 1
  fi
  n="$(wc -l <"${tmp}/push" | tr -d ' ')"
  rm -rf "${tmp}"
  if [ "${n}" -ne 3 ]; then
    echo "docker_buildx_push_retry.sh: expected 3 push attempts, got ${n}" >&2
    return 1
  fi

  if FLYCTL_AUTH_DOCKER_CMD="true" DOCKER_BUILDX_PUSH_CMD="false" \
    retry 2 0 push_image; then
    echo "docker_buildx_push_retry.sh: expected exhausted retries to fail" >&2
    return 1
  fi

  echo "docker_buildx_push_retry.sh: self-test passed"
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
    retry "${DOCKER_BUILDX_PUSH_ATTEMPTS}" "${DOCKER_BUILDX_PUSH_RETRY_DELAY_SECONDS}" push_image
    ;;
esac

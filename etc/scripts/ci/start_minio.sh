#!/usr/bin/env bash
# Start MinIO for GitHub Actions Tests jobs and create S3 buckets.
#
# GitHub-hosted runners get "pull access denied" for minio/minio on
# Docker Hub (exit 125, run 34650037512 / job 103431213495, 2026-09-11).
# The same pinned digests are still on quay.io. Pull with retries,
# preferring quay.io then docker.io.
#
# Usage:
#   ./etc/scripts/ci/start_minio.sh
#   ./etc/scripts/ci/start_minio.sh --self-test
#
# Image refs must stay in sync with etc/docker/docker-compose.yml.
set -euo pipefail

MINIO_TAG="${MINIO_TAG:-RELEASE.2025-03-12T18-04-18Z}"
MC_TAG="${MC_TAG:-RELEASE.2025-03-12T17-29-24Z}"
MINIO_DIGEST="${MINIO_DIGEST:-sha256:46b3009bf7041eefbd90bd0d2b38c6ddc24d20a35d609551a1802c558c1c958f}"
MC_DIGEST="${MC_DIGEST:-sha256:470f5546b596e16c7816b9c3fa7a78ce4076bb73c2c73f7faeec0c8043923123}"
MINIO_PULL_ATTEMPTS="${MINIO_PULL_ATTEMPTS:-8}"
MINIO_RETRY_DELAY_SECONDS="${MINIO_RETRY_DELAY_SECONDS:-2}"
MINIO_HEALTH_ATTEMPTS="${MINIO_HEALTH_ATTEMPTS:-60}"
MINIO_CONTAINER_NAME="${MINIO_CONTAINER_NAME:-minio_ci}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://127.0.0.1:9000}"

retry() {
  local max_attempts="${1}"
  shift
  local seconds="${1}"
  shift
  local attempt_num=1

  until "$@"; do
    if [ "${attempt_num}" -eq "${max_attempts}" ]; then
      echo "start_minio.sh: attempt ${attempt_num} failed and there are no more attempts left" >&2
      return 1
    fi
    echo "start_minio.sh: attempt ${attempt_num} failed; retrying in ${seconds}s..." >&2
    attempt_num=$((attempt_num + 1))
    if [ "${seconds}" -gt 0 ]; then
      sleep "${seconds}"
    fi
  done
}

minio_image_refs() {
  printf '%s\n' \
    "quay.io/minio/minio:${MINIO_TAG}@${MINIO_DIGEST}" \
    "docker.io/minio/minio:${MINIO_TAG}@${MINIO_DIGEST}"
}

mc_image_refs() {
  printf '%s\n' \
    "quay.io/minio/mc:${MC_TAG}@${MC_DIGEST}" \
    "docker.io/minio/mc:${MC_TAG}@${MC_DIGEST}"
}

docker_pull() {
  docker pull "$1" >&2
}

pull_from_registries() {
  local refs_fn="${1}"
  local pulled=""

  try_all() {
    local ref
    while IFS= read -r ref; do
      echo "start_minio.sh: pulling ${ref}" >&2
      if docker_pull "${ref}"; then
        pulled="${ref}"
        return 0
      fi
    done < <("${refs_fn}")
    return 1
  }

  if ! retry "${MINIO_PULL_ATTEMPTS}" "${MINIO_RETRY_DELAY_SECONDS}" try_all; then
    echo "start_minio.sh: failed to pull image via ${refs_fn}" >&2
    return 1
  fi
  printf '%s\n' "${pulled}"
}

wait_healthy() {
  local attempt=1
  while [ "${attempt}" -le "${MINIO_HEALTH_ATTEMPTS}" ]; do
    if curl -sf "${MINIO_ENDPOINT}/minio/health/live" >/dev/null; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
  curl -sf "${MINIO_ENDPOINT}/minio/health/live" >/dev/null
}

create_buckets() {
  local mc_ref="${1}"
  docker run --rm --network host --entrypoint /bin/sh \
    "${mc_ref}" \
    -c "
      mc alias set local ${MINIO_ENDPOINT} minioadmin minioadmin &&
      mc mb local/media --ignore-existing &&
      mc mb local/expense-reports --ignore-existing &&
      mc mb local/app-resources --ignore-existing &&
      mc mb local/avatars --ignore-existing &&
      mc anonymous set public local/media &&
      mc anonymous set public local/avatars
    "
}

start_minio() {
  local minio_ref mc_ref

  minio_ref="$(pull_from_registries minio_image_refs)"
  mc_ref="$(pull_from_registries mc_image_refs)"

  docker rm -f "${MINIO_CONTAINER_NAME}" 2>/dev/null || true
  docker run -d --name "${MINIO_CONTAINER_NAME}" -p 9000:9000 \
    -e MINIO_ROOT_USER=minioadmin \
    -e MINIO_ROOT_PASSWORD=minioadmin \
    "${minio_ref}" \
    server /data --console-address ":9001"

  wait_healthy
  create_buckets "${mc_ref}"
  echo "start_minio.sh: MinIO ready at ${MINIO_ENDPOINT} (image ${minio_ref})"
}

self_test() {
  local tmp n out first second refs

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
    echo "start_minio.sh: retry helper expected 3 attempts, got ${n}" >&2
    return 1
  fi

  mapfile -t refs < <(minio_image_refs)
  first="${refs[0]}"
  second="${refs[1]}"
  if [[ "${first}" != quay.io/minio/minio:*@${MINIO_DIGEST} ]]; then
    echo "start_minio.sh: expected quay.io minio ref first, got ${first}" >&2
    return 1
  fi
  if [[ "${second}" != docker.io/minio/minio:*@${MINIO_DIGEST} ]]; then
    echo "start_minio.sh: expected docker.io minio ref second, got ${second}" >&2
    return 1
  fi

  mapfile -t refs < <(mc_image_refs)
  first="${refs[0]}"
  second="${refs[1]}"
  if [[ "${first}" != quay.io/minio/mc:*@${MC_DIGEST} ]]; then
    echo "start_minio.sh: expected quay.io mc ref first, got ${first}" >&2
    return 1
  fi
  if [[ "${second}" != docker.io/minio/mc:*@${MC_DIGEST} ]]; then
    echo "start_minio.sh: expected docker.io mc ref second, got ${second}" >&2
    return 1
  fi

  docker_pull() {
    case "$1" in
      quay.io/minio/minio:*) return 0 ;;
      docker.io/*)
        echo "start_minio.sh: should not fall back to docker.io when quay succeeds" >&2
        return 1
        ;;
      *) return 1 ;;
    esac
  }
  out="$(MINIO_PULL_ATTEMPTS=2 MINIO_RETRY_DELAY_SECONDS=0 pull_from_registries minio_image_refs)"
  if [[ "${out}" != quay.io/minio/minio:*@${MINIO_DIGEST} ]]; then
    echo "start_minio.sh: expected quay.io pull to win, got ${out}" >&2
    return 1
  fi

  docker_pull() {
    case "$1" in
      quay.io/*) return 1 ;;
      docker.io/minio/minio:*) return 0 ;;
      *) return 1 ;;
    esac
  }
  out="$(MINIO_PULL_ATTEMPTS=2 MINIO_RETRY_DELAY_SECONDS=0 pull_from_registries minio_image_refs)"
  if [[ "${out}" != docker.io/minio/minio:*@${MINIO_DIGEST} ]]; then
    echo "start_minio.sh: expected docker.io fallback, got ${out}" >&2
    return 1
  fi

  docker_pull() {
    return 1
  }
  if MINIO_PULL_ATTEMPTS=2 MINIO_RETRY_DELAY_SECONDS=0 pull_from_registries minio_image_refs >/dev/null; then
    echo "start_minio.sh: expected pull_from_registries to fail when every registry fails" >&2
    return 1
  fi

  echo "start_minio.sh: self-test passed"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  "")
    start_minio
    ;;
  *)
    echo "Usage: $0 [--self-test]" >&2
    exit 1
    ;;
esac

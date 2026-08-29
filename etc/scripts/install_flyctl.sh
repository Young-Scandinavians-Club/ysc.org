#!/usr/bin/env bash
# Install flyctl for GitHub Actions and local use.
#
# The official superfly/flyctl-actions/setup-flyctl action runs on Node 24 and
# can fail in ~1s with no logs (GitHub Actions runtime flake). This installer
# uses curl with retries instead, matching Fly's release API:
#   https://api.fly.io/app/flyctl_releases/<platform>/<arch>/<version>
#
# Usage:
#   ./etc/scripts/install_flyctl.sh
#   FLYCTL_VERSION=0.4.95 ./etc/scripts/install_flyctl.sh
#   FLYCTL_INSTALL_DIR=/tmp/fly ./etc/scripts/install_flyctl.sh
#   ./etc/scripts/install_flyctl.sh --resolve-only
#   ./etc/scripts/install_flyctl.sh --self-test
#
# In GitHub Actions, the binary directory is appended to $GITHUB_PATH.
set -euo pipefail

FLYCTL_VERSION="${FLYCTL_VERSION:-latest}"
FLYCTL_INSTALL_DIR="${FLYCTL_INSTALL_DIR:-${HOME}/.fly}"
FLYCTL_BIN_DIR="${FLYCTL_INSTALL_DIR}/bin"
FLYCTL_ATTEMPTS="${FLYCTL_ATTEMPTS:-8}"
FLYCTL_RETRY_DELAY_SECONDS="${FLYCTL_RETRY_DELAY_SECONDS:-2}"

retry() {
  local max_attempts="${1}"
  shift
  local seconds="${1}"
  shift
  local attempt_num=1

  until "$@"; do
    if [ "${attempt_num}" -eq "${max_attempts}" ]; then
      echo "install_flyctl.sh: attempt ${attempt_num} failed and there are no more attempts left" >&2
      return 1
    fi
    echo "install_flyctl.sh: attempt ${attempt_num} failed; retrying in ${seconds}s..." >&2
    attempt_num=$((attempt_num + 1))
    if [ "${seconds}" -gt 0 ]; then
      sleep "${seconds}"
    fi
  done
}

flyctl_platform() {
  case "$(uname -s)" in
    Linux) echo Linux ;;
    Darwin) echo macOS ;;
    *)
      echo "install_flyctl.sh: unsupported OS $(uname -s)" >&2
      return 1
      ;;
  esac
}

flyctl_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) echo x86_64 ;;
    aarch64 | arm64) echo arm64 ;;
    *)
      echo "install_flyctl.sh: unsupported architecture $(uname -m)" >&2
      return 1
      ;;
  esac
}

resolved_version_from_url() {
  local url="${1}"
  if [[ "${url}" =~ /download/v([0-9]+\.[0-9]+\.[0-9]+)/ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  echo "install_flyctl.sh: could not parse flyctl version from ${url}" >&2
  return 1
}

curl_get() {
  # Retry timeouts / 429 / 5xx. Do not use --retry-all-errors: that retries 404s.
  curl --fail --silent --show-error --location \
    --retry 5 --retry-delay 2 \
    --connect-timeout 15 --max-time 120 \
    --user-agent "ysc-install-flyctl" \
    "$@"
}

resolve_release_url() {
  local platform arch version_spec url
  platform="$(flyctl_platform)"
  arch="$(flyctl_arch)"
  version_spec="${FLYCTL_VERSION#v}"
  url="$(curl_get "https://api.fly.io/app/flyctl_releases/${platform}/${arch}/${version_spec}")" || return 1
  if [ -z "${url}" ]; then
    echo "install_flyctl.sh: empty response from Fly flyctl_releases API" >&2
    return 1
  fi
  printf '%s\n' "${url}"
}

self_test() {
  local tmp n url version

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
    echo "install_flyctl.sh: retry helper expected 3 attempts, got ${n}" >&2
    return 1
  fi

  url="https://github.com/superfly/flyctl/releases/download/v0.4.95/flyctl_0.4.95_Linux_x86_64.tar.gz"
  version="$(resolved_version_from_url "${url}")"
  if [ "${version}" != "0.4.95" ]; then
    echo "install_flyctl.sh: expected parsed version 0.4.95, got ${version}" >&2
    return 1
  fi

  echo "install_flyctl.sh: self-test passed"
}

install_flyctl() {
  local url version tmp

  url="$(resolve_release_url)" || return 1
  version="$(resolved_version_from_url "${url}")" || return 1
  echo "install_flyctl.sh: downloading flyctl v${version} from ${url}"

  tmp="$(mktemp -d)"
  if ! (
    curl_get --output "${tmp}/flyctl.tar.gz" "${url}"
    tar -xzf "${tmp}/flyctl.tar.gz" -C "${tmp}"
    [ -f "${tmp}/flyctl" ]
  ); then
    rm -rf "${tmp}"
    echo "install_flyctl.sh: failed to download or extract flyctl" >&2
    return 1
  fi

  mkdir -p "${FLYCTL_BIN_DIR}"
  install -m 755 "${tmp}/flyctl" "${FLYCTL_BIN_DIR}/flyctl"
  rm -rf "${tmp}"
  "${FLYCTL_BIN_DIR}/flyctl" version

  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "${FLYCTL_BIN_DIR}" >>"${GITHUB_PATH}"
  fi
  export PATH="${FLYCTL_BIN_DIR}:${PATH}"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  --resolve-only)
    resolve_release_url
    ;;
  "" | --install)
    retry "${FLYCTL_ATTEMPTS}" "${FLYCTL_RETRY_DELAY_SECONDS}" install_flyctl
    ;;
  *)
    echo "Usage: $0 [--install|--resolve-only|--self-test]" >&2
    exit 1
    ;;
esac

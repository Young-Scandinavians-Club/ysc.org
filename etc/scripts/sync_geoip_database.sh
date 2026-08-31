#!/usr/bin/env bash
# sync_geoip_database.sh — Download GeoLite2-City from MaxMind and upload to Tigris.
#
# Intended to run weekly from GitHub Actions (and via workflow_dispatch for bootstrap).
# Deployed app machines only read this object; they never contact MaxMind.
#
# Environment:
#   MAXMIND_LICENSE_KEY                 (required)  MaxMind license key, or
#                                                   "account_id:license_key"
#   MAXMIND_ACCOUNT_ID                  (optional)  MaxMind account ID (Basic Auth).
#                                                   Required for accounts that no
#                                                   longer accept the legacy
#                                                   /app/geoip_download query-param URL.
#   AWS_ACCESS_KEY_ID                   (required)  Tigris access key with write access
#   AWS_SECRET_ACCESS_KEY               (required)  Tigris secret key
#   AWS_ENDPOINT_URL_S3                 (optional)  default https://fly.storage.tigris.dev
#   AWS_REGION                          (optional)  default auto
#   APP_RESOURCES_BUCKET_NAME           (optional)  default ysc-app-resources
#   DRY_RUN                             (optional)  if 1, download + checksum only (no upload)
#   MAXMIND_ATTEMPTS                    (optional)  download retries (default 8)
#   MAXMIND_RETRY_DELAY_SECONDS         (optional)  delay between retries (default 2)
#
# Object key is fixed to geoip/GeoLite2-City.tar.gz to match
# Ysc.GeoIP.DatabaseFetcher.object_key/0 (single source of truth in the app).
#
# Usage:
#   etc/scripts/sync_geoip_database.sh
#   etc/scripts/sync_geoip_database.sh --self-test

set -euo pipefail

MAXMIND_LICENSE_KEY="${MAXMIND_LICENSE_KEY:-}"
MAXMIND_ACCOUNT_ID="${MAXMIND_ACCOUNT_ID:-}"
AWS_ENDPOINT_URL_S3="${AWS_ENDPOINT_URL_S3:-https://fly.storage.tigris.dev}"
AWS_REGION="${AWS_REGION:-auto}"
APP_RESOURCES_BUCKET_NAME="${APP_RESOURCES_BUCKET_NAME:-ysc-app-resources}"
# Keep in sync with Ysc.GeoIP.DatabaseFetcher.object_key/0
GEOIP_S3_KEY="geoip/GeoLite2-City.tar.gz"
DRY_RUN="${DRY_RUN:-0}"
EDITION_ID="GeoLite2-City"
MAXMIND_ATTEMPTS="${MAXMIND_ATTEMPTS:-8}"
MAXMIND_RETRY_DELAY_SECONDS="${MAXMIND_RETRY_DELAY_SECONDS:-2}"
CURL_USER_AGENT="${CURL_USER_AGENT:-ysc-sync-geoip (https://github.com/Young-Scandinavians-Club/ysc.org)}"
LEGACY_DOWNLOAD_BASE="https://download.maxmind.com/app/geoip_download"
PERMALINK_DOWNLOAD_BASE="https://download.maxmind.com/geoip/databases"

retry() {
  local max_attempts="${1}"
  shift
  local seconds="${1}"
  shift
  local attempt_num=1

  until "$@"; do
    if [ "${attempt_num}" -eq "${max_attempts}" ]; then
      echo "sync_geoip_database.sh: attempt ${attempt_num} failed and there are no more attempts left" >&2
      return 1
    fi
    echo "sync_geoip_database.sh: attempt ${attempt_num} failed; retrying in ${seconds}s..." >&2
    attempt_num=$((attempt_num + 1))
    if [ "${seconds}" -gt 0 ]; then
      sleep "${seconds}"
    fi
  done
}

# Sets ACCOUNT_ID_RESOLVED and LICENSE_KEY_RESOLVED.
# Accepts MAXMIND_ACCOUNT_ID plus MAXMIND_LICENSE_KEY, or a single
# MAXMIND_LICENSE_KEY of the form "account_id:license_key".
parse_maxmind_credentials() {
  local license_key="${1:-}"
  local account_id="${2:-}"

  ACCOUNT_ID_RESOLVED=""
  LICENSE_KEY_RESOLVED=""

  if [ -z "${license_key}" ]; then
    echo "MAXMIND_LICENSE_KEY is required." >&2
    return 1
  fi

  if [ -n "${account_id}" ]; then
    ACCOUNT_ID_RESOLVED="${account_id}"
    LICENSE_KEY_RESOLVED="${license_key}"
    return 0
  fi

  if [[ "${license_key}" == *:* ]]; then
    ACCOUNT_ID_RESOLVED="${license_key%%:*}"
    LICENSE_KEY_RESOLVED="${license_key#*:}"
    if [ -z "${ACCOUNT_ID_RESOLVED}" ] || [ -z "${LICENSE_KEY_RESOLVED}" ]; then
      echo "MAXMIND_LICENSE_KEY account_id:license_key form is missing a part." >&2
      return 1
    fi
    return 0
  fi

  LICENSE_KEY_RESOLVED="${license_key}"
}

permalink_url() {
  local edition_id="${1}"
  local suffix="${2}"
  printf '%s/%s/download?suffix=%s\n' "${PERMALINK_DOWNLOAD_BASE}" "${edition_id}" "${suffix}"
}

legacy_url() {
  local edition_id="${1}"
  local suffix="${2}"
  local license_key="${3}"
  local encoded_key encoded_edition encoded_suffix
  encoded_key="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${license_key}")"
  encoded_edition="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${edition_id}")"
  encoded_suffix="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${suffix}")"
  printf '%s?edition_id=%s&license_key=%s&suffix=%s\n' \
    "${LEGACY_DOWNLOAD_BASE}" "${encoded_edition}" "${encoded_key}" "${encoded_suffix}"
}

print_http_error() {
  local http_code="${1}"
  local path="${2}"

  echo "MaxMind download failed with HTTP ${http_code}." >&2
  if [ "${http_code}" = "403" ] || [ "${http_code}" = "401" ]; then
    echo "This is usually an auth/account issue, not a transient flake." >&2
    echo "Confirm the GeoLite2 license in the MaxMind account portal, and set" >&2
    echo "MAXMIND_ACCOUNT_ID (or MAXMIND_LICENSE_KEY=account_id:license_key)" >&2
    echo "so downloads use Basic Auth against /geoip/databases/.../download." >&2
  fi
  if [ -f "${path}" ]; then
    echo "Response body (truncated):" >&2
    head -c 500 "${path}" >&2 || true
    echo >&2
  fi
}

# Download one MaxMind object to dest. Retries 429 / 5xx / connection errors.
# Does not retry 401/403 (auth). Follows redirects to R2 presigned URLs without
# forwarding Basic Auth to the redirected host.
curl_download() {
  local dest="${1}"
  local url="${2}"
  local account_id="${3:-}"
  local license_key="${4:-}"
  local http_code
  local curl_args=(
    --silent --show-error --location
    --retry "${MAXMIND_ATTEMPTS}"
    --retry-delay "${MAXMIND_RETRY_DELAY_SECONDS}"
    --retry-connrefused
    --connect-timeout 15
    --max-time 300
    --user-agent "${CURL_USER_AGENT}"
    --output "${dest}"
    --write-out "%{http_code}"
  )

  if [ -n "${account_id}" ]; then
    curl_args+=(--user "${account_id}:${license_key}")
  fi

  http_code="$(curl "${curl_args[@]}" "${url}")" || http_code="000"

  if [ "${http_code}" != "200" ]; then
    print_http_error "${http_code}" "${dest}"
    return 1
  fi

  if [ ! -s "${dest}" ]; then
    echo "MaxMind download succeeded but wrote an empty file." >&2
    return 1
  fi
}

sha256_file() {
  local path="${1}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
  else
    shasum -a 256 "${path}" | awk '{print $1}'
  fi
}

verify_checksum() {
  local archive_path="${1}"
  local checksum_path="${2}"
  local expected_sha actual_sha

  expected_sha="$(awk '{print $1}' "${checksum_path}" | tr -d '[:space:]')"
  if [ -z "${expected_sha}" ]; then
    echo "Failed to parse MaxMind checksum file." >&2
    return 1
  fi

  actual_sha="$(sha256_file "${archive_path}")"
  if [ "${actual_sha}" != "${expected_sha}" ]; then
    echo "Checksum mismatch for ${EDITION_ID}.tar.gz" >&2
    echo "  expected: ${expected_sha}" >&2
    echo "  actual:   ${actual_sha}" >&2
    return 1
  fi

  echo "Checksum OK (${actual_sha})."
}

download_edition() {
  local archive_path="${1}"
  local checksum_path="${2}"
  local account_id="${3}"
  local license_key="${4}"
  local archive_url checksum_url

  if [ -n "${account_id}" ]; then
    echo "Downloading ${EDITION_ID} from MaxMind (permalink + Basic Auth)..."
    archive_url="$(permalink_url "${EDITION_ID}" "tar.gz")"
    checksum_url="$(permalink_url "${EDITION_ID}" "tar.gz.sha256")"
    curl_download "${archive_path}" "${archive_url}" "${account_id}" "${license_key}"
    echo "Downloading checksum..."
    curl_download "${checksum_path}" "${checksum_url}" "${account_id}" "${license_key}"
  else
    echo "Downloading ${EDITION_ID} from MaxMind (legacy license_key URL)..."
    echo "Set MAXMIND_ACCOUNT_ID to use the supported permalink API." >&2
    archive_url="$(legacy_url "${EDITION_ID}" "tar.gz" "${license_key}")"
    checksum_url="$(legacy_url "${EDITION_ID}" "tar.gz.sha256" "${license_key}")"
    curl_download "${archive_path}" "${archive_url}"
    echo "Downloading checksum..."
    curl_download "${checksum_path}" "${checksum_url}"
  fi
}

require_commands() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required." >&2
    return 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required." >&2
    return 1
  fi

  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "sha256sum or shasum is required." >&2
    return 1
  fi

  if [ "${DRY_RUN}" != "1" ] && ! command -v aws >/dev/null 2>&1; then
    echo "aws CLI is required unless DRY_RUN=1." >&2
    return 1
  fi
}

sync_database() {
  parse_maxmind_credentials "${MAXMIND_LICENSE_KEY}" "${MAXMIND_ACCOUNT_ID}"

  if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    if [ "${DRY_RUN}" != "1" ]; then
      echo "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are required unless DRY_RUN=1." >&2
      return 1
    fi
  fi

  require_commands

  local workdir archive_path checksum_path
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/ysc-geoip.XXXXXX")"
  cleanup() {
    rm -rf "${workdir}"
  }
  trap cleanup EXIT

  archive_path="${workdir}/${EDITION_ID}.tar.gz"
  checksum_path="${workdir}/${EDITION_ID}.tar.gz.sha256"

  download_edition "${archive_path}" "${checksum_path}" \
    "${ACCOUNT_ID_RESOLVED}" "${LICENSE_KEY_RESOLVED}"
  verify_checksum "${archive_path}" "${checksum_path}"

  if [ "${DRY_RUN}" = "1" ]; then
    echo "DRY_RUN=1 — skipping upload to s3://${APP_RESOURCES_BUCKET_NAME}/${GEOIP_S3_KEY}"
    return 0
  fi

  echo "Uploading to s3://${APP_RESOURCES_BUCKET_NAME}/${GEOIP_S3_KEY} ..."
  export AWS_ENDPOINT_URL_S3
  export AWS_REGION
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY

  aws s3 cp "${archive_path}" "s3://${APP_RESOURCES_BUCKET_NAME}/${GEOIP_S3_KEY}" \
    --content-type "application/gzip"

  echo "GeoIP database synced successfully."
}

start_test_http_server() {
  local mode="${1}"
  local port_file="${2}"
  exec python3 - "${mode}" "${port_file}" <<'PY'
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

mode = sys.argv[1]
port_file = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    hits = 0

    def do_GET(self):
        Handler.hits += 1
        if mode == "retry-429":
            if Handler.hits < 3:
                self.send_response(429)
                self.send_header("Retry-After", "0")
                self.end_headers()
                self.wfile.write(b"rate limited")
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok-after-retry")
            return
        if mode == "always-403":
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b'{"code":"PERMISSION_DENIED"}')
            return
        self.send_response(500)
        self.end_headers()

    def log_message(self, _format, *_args):
        return


class Server(ThreadingHTTPServer):
    allow_reuse_address = True


sock = socket.socket()
sock.bind(("127.0.0.1", 0))
host, port = sock.getsockname()
sock.close()
httpd = Server((host, port), Handler)
thread = threading.Thread(target=httpd.serve_forever, daemon=True)
thread.start()
with open(port_file, "w", encoding="utf-8") as handle:
    handle.write(str(port))
thread.join()
PY
}

wait_for_port_file() {
  local port_file="${1}"
  local attempts=0
  while [ "${attempts}" -lt 50 ]; do
    if [ -s "${port_file}" ]; then
      cat "${port_file}"
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.05
  done
  echo "test HTTP server did not publish a port" >&2
  return 1
}

self_test() {
  local tmp n url port_file dest pid port

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
    echo "sync_geoip_database.sh: retry helper expected 3 attempts, got ${n}" >&2
    return 1
  fi

  parse_maxmind_credentials "only-a-license-key" ""
  if [ -n "${ACCOUNT_ID_RESOLVED}" ] || [ "${LICENSE_KEY_RESOLVED}" != "only-a-license-key" ]; then
    echo "sync_geoip_database.sh: expected license-only credentials" >&2
    return 1
  fi

  parse_maxmind_credentials "abcd-license" "12345"
  if [ "${ACCOUNT_ID_RESOLVED}" != "12345" ] || [ "${LICENSE_KEY_RESOLVED}" != "abcd-license" ]; then
    echo "sync_geoip_database.sh: expected split account id + license key" >&2
    return 1
  fi

  parse_maxmind_credentials "999:combined-key" ""
  if [ "${ACCOUNT_ID_RESOLVED}" != "999" ] || [ "${LICENSE_KEY_RESOLVED}" != "combined-key" ]; then
    echo "sync_geoip_database.sh: expected account_id:license_key parse" >&2
    return 1
  fi

  url="$(permalink_url "GeoLite2-City" "tar.gz")"
  if [ "${url}" != "https://download.maxmind.com/geoip/databases/GeoLite2-City/download?suffix=tar.gz" ]; then
    echo "sync_geoip_database.sh: unexpected permalink ${url}" >&2
    return 1
  fi

  url="$(legacy_url "GeoLite2-City" "tar.gz" "key with space")"
  if [[ "${url}" != *"license_key=key%20with%20space"* ]]; then
    echo "sync_geoip_database.sh: legacy URL did not encode license key: ${url}" >&2
    return 1
  fi

  port_file="$(mktemp)"
  dest="$(mktemp)"
  rm -f "${port_file}"
  start_test_http_server "retry-429" "${port_file}" &
  pid=$!
  port="$(wait_for_port_file "${port_file}")"
  MAXMIND_ATTEMPTS=5 MAXMIND_RETRY_DELAY_SECONDS=0 \
    curl_download "${dest}" "http://127.0.0.1:${port}/db.tar.gz"
  if [ "$(cat "${dest}")" != "ok-after-retry" ]; then
    kill "${pid}" 2>/dev/null || true
    echo "sync_geoip_database.sh: expected 429 retries to succeed" >&2
    return 1
  fi
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  rm -f "${port_file}" "${dest}"

  port_file="$(mktemp)"
  dest="$(mktemp)"
  rm -f "${port_file}"
  start_test_http_server "always-403" "${port_file}" &
  pid=$!
  port="$(wait_for_port_file "${port_file}")"
  if MAXMIND_ATTEMPTS=2 MAXMIND_RETRY_DELAY_SECONDS=0 \
    curl_download "${dest}" "http://127.0.0.1:${port}/db.tar.gz" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
    echo "sync_geoip_database.sh: expected 403 download to fail" >&2
    return 1
  fi
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  rm -f "${port_file}" "${dest}"

  echo "sync_geoip_database.sh: self-test passed"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  "")
    sync_database
    ;;
  *)
    echo "Usage: $0 [--self-test]" >&2
    exit 1
    ;;
esac

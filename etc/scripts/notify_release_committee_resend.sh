#!/usr/bin/env bash
# notify_release_committee_resend.sh — After LLM GitHub release notes + prod deploy, email the committee.
#
# Environment:
#   GITHUB_REPOSITORY       (required) owner/name
#   GITHUB_REF_NAME         (required) tag e.g. v1.2.3
#   GITHUB_TOKEN or GH_TOKEN (required) for gh api (contents: read)
#   RESEND_API_KEY          (required) Resend API key
#   GITHUB_SHA              (optional) full SHA for Idempotency-Key — set in Actions; fallback: git rev-parse HEAD
#   DRY_RUN                 (optional) if 1, skip HTTP POST; print full From/To/Subject,
#                                  Idempotency-Key, plaintext body, and HTML body
#
# Depends on python3 (stdlib only) beside gh, jq, curl for linked HTML multipart email.
#
# Usage (from repo root): env ... bash etc/scripts/notify_release_committee_resend.sh
#
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMMITTEE_EMAIL="ysc-web-committee@googlegroups.com"
FROM_EMAIL="webtech@ysc.org"

EMAIL_BODY_INTRO=$'A new release is live in the production environment. See below for a changelog since last release.'

REPO="${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"
TAG="${GITHUB_REF_NAME:?Set GITHUB_REF_NAME}"
RESEND_KEY="${RESEND_API_KEY:?Set RESEND_API_KEY}"

GIT_SHA_FULL="${GITHUB_SHA:-}"
if [[ -z "$GIT_SHA_FULL" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_PKG}/../.." && pwd)"
  if git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    GIT_SHA_FULL="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  fi
fi
if [[ -z "$GIT_SHA_FULL" ]]; then
  echo "Error: Set GITHUB_SHA or run from a git checkout." >&2
  exit 1
fi

# Resend Idempotency-Key: ≤256 chars (repo + tag + SHA ⇒ one logical send per prod release retry).
_REPO_FLAT="${REPO//\//-}"
IDEMPOTENCY_KEY="${_REPO_FLAT}-committee-release-notes-${TAG}-${GIT_SHA_FULL}"
_MAX_IDEM=256
if [[ "${#IDEMPOTENCY_KEY}" -gt ${_MAX_IDEM} ]]; then
  IDEMPOTENCY_KEY="${IDEMPOTENCY_KEY:0:${_MAX_IDEM}}"
fi

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  export GH_TOKEN="$GITHUB_TOKEN"
elif [[ -n "${GH_TOKEN:-}" ]]; then
  export GH_TOKEN
else
  echo "Error: set GITHUB_TOKEN or GH_TOKEN." >&2
  exit 1
fi

release_json="$(gh api "repos/${REPO}/releases/tags/${TAG}")"

body="$(jq -r '.body // empty' <<<"$release_json")"
html_url="$(jq -r '.html_url' <<<"$release_json")"

subject="YSC production release ${TAG}"

if [[ -n "$body" ]]; then
  text="${EMAIL_BODY_INTRO}"$'\n\n'"${body}"$'\n\n---'$'\n'"GitHub release: ${html_url}"
else
  text="${EMAIL_BODY_INTRO}"$'\n\n'"(No release body.)"$'\n\n'"GitHub release: ${html_url}"
fi

export _CE_REPO="$REPO"
export _CE_INTRO="$EMAIL_BODY_INTRO"
export _CE_CHANGELOG="$body"
export _CE_RELEASE_URL="$html_url"

html_doc="$(
  PYTHONPATH="$SCRIPT_PKG" python3 -c '
import os
import sys
from release_notes_body_to_email_html import build_committee_release_email_html

sys.stdout.write(
    build_committee_release_email_html(
        os.environ["_CE_REPO"],
        os.environ["_CE_INTRO"],
        os.environ.get("_CE_CHANGELOG", ""),
        os.environ["_CE_RELEASE_URL"],
    ),
)
'

)"

payload="$(
  jq -n \
    --arg from "$FROM_EMAIL" \
    --arg to "$COMMITTEE_EMAIL" \
    --arg subject "$subject" \
    --arg text "$text" \
    --arg html "$html_doc" \
    '{from: $from, to: [$to], subject: $subject, text: $text, html: $html}'
)"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  cat <<EOF
======== DRY_RUN — email preview (no request to Resend) ========
From:    ${FROM_EMAIL}
To:      ${COMMITTEE_EMAIL}
Subject: ${subject}
Idempotency-Key: ${IDEMPOTENCY_KEY}

----- text body (plaintext) -----
EOF
  printf '%s\n' "${text}"
  echo "----- end text body -----"
  echo ""
  echo "----- html body -----"
  printf '%s\n' "${html_doc}"
  echo "----- end html -----"
  exit 0
fi

curl -fsS https://api.resend.com/emails \
  -H "Authorization: Bearer ${RESEND_KEY}" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: ${IDEMPOTENCY_KEY}" \
  -d "$payload"

echo "Release notification emailed to ${COMMITTEE_EMAIL}."

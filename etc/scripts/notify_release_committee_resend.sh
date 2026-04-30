#!/usr/bin/env bash
# notify_release_committee_resend.sh — After LLM GitHub release notes + prod deploy, email the committee.
#
# Environment:
#   GITHUB_REPOSITORY       (required) owner/name
#   GITHUB_REF_NAME         (required) tag e.g. v1.2.3
#   GITHUB_TOKEN or GH_TOKEN (required) for gh api (contents: read)
#   RESEND_API_KEY          (required) Resend API key
#   DRY_RUN                 (optional) if 1, skip HTTP POST and exit 0
#
# Usage (from repo root): env ... bash etc/scripts/notify_release_committee_resend.sh
#
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

COMMITTEE_EMAIL="ysc-web-committee@googlegroups.com"
FROM_EMAIL="webtech@ysc.org"

REPO="${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"
TAG="${GITHUB_REF_NAME:?Set GITHUB_REF_NAME}"
RESEND_KEY="${RESEND_API_KEY:?Set RESEND_API_KEY}"

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
  text="${body}"$'\n\n---'$'\n'"GitHub release: ${html_url}"
else
  text="(No release body.)"$'\n\n'"GitHub release: ${html_url}"
fi

payload="$(
  jq -n \
    --arg from "$FROM_EMAIL" \
    --arg to "$COMMITTEE_EMAIL" \
    --arg subject "$subject" \
    --arg text "$text" \
    '{from: $from, to: [$to], subject: $subject, text: $text}'
)"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN=1 — would send Resend email (subject: ${subject})"
  exit 0
fi

curl -fsS https://api.resend.com/emails \
  -H "Authorization: Bearer ${RESEND_KEY}" \
  -H "Content-Type: application/json" \
  -d "$payload"

echo "Release notification emailed to ${COMMITTEE_EMAIL}."

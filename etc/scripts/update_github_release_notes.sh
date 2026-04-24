#!/usr/bin/env bash
# update_github_release_notes.sh — Build a tag's GitHub release body from merged PRs since the
# previous v* tag, via OpenRouter (OpenAI-compatible chat), then create or update the release.
#
# Environment:
#   OPENROUTER_API_KEY  (required)  API key for https://openrouter.ai/
#   GITHUB_TOKEN or GH_TOKEN        (required)  token with repo / contents:write
#   GITHUB_REPOSITORY               (optional)  "owner/name"; inferred from `git remote` if unset
#   OPENROUTER_MODEL                (optional)  default: openai/gpt-4o-mini
#   OPENROUTER_REFERER              (optional)  HTTP-Referer for OpenRouter (default: this repo on GitHub)
#   DRY_RUN                         (optional)  if 1, print notes to stdout; skip GitHub release API
#
# Usage:
#   etc/scripts/update_github_release_notes.sh [TAG]
# TAG defaults to GITHUB_REF_NAME (Actions on tag push) or the latest tag at HEAD.
#
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=_colors.sh
. "$SCRIPT_DIR/_colors.sh"

DRY_RUN="${DRY_RUN:-0}"
OPENROUTER_MODEL="${OPENROUTER_MODEL:-openai/gpt-4o-mini}"
GITHUB_API="${GITHUB_API:-https://api.github.com}"
OPENROUTER_API="${OPENROUTER_API:-https://openrouter.ai/api/v1/chat/completions}"

usage() {
  echo "Usage: $0 [TAG]"
  echo "Requires OPENROUTER_API_KEY and GITHUB_TOKEN (or GH_TOKEN)."
  echo "Set DRY_RUN=1 to print the generated body without updating GitHub."
  exit 1
}

resolve_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    echo "$GITHUB_REPOSITORY"
    return 0
  fi
  local url
  url=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null) || {
    echo "${RED}Error: GITHUB_REPOSITORY not set and no origin remote.${RESET}" >&2
    exit 1
  }
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    return 0
  fi
  echo "${RED}Error: could not parse owner/name from origin: $url${RESET}" >&2
  exit 1
}

github_token() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "$GITHUB_TOKEN"
  elif [ -n "${GH_TOKEN:-}" ]; then
    echo "$GH_TOKEN"
  else
    echo "${RED}Error: set GITHUB_TOKEN or GH_TOKEN.${RESET}" >&2
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "${RED}Error: $1 is required (install $1 to run this script).${RESET}" >&2
    exit 1
  }
}

# Previous v* tag before TAG (version sort, newest first). Empty if TAG is the oldest v* tag.
find_previous_v_tag() {
  local current="$1"
  local prev=""
  local t
  while IFS= read -r t; do
    if [ "$t" = "$current" ]; then
      echo "$prev"
      return 0
    fi
    prev=$t
  done < <(git -C "$PROJECT_ROOT" tag -l 'v*' | LC_ALL=C sort -Vr)
  echo "${RED}Error: tag $current not found among v* tags.${RESET}" >&2
  exit 1
}

# ISO-8601 timestamp of the commit a ref points to.
ref_timestamp() {
  git -C "$PROJECT_ROOT" log -1 --format=%aI "$1"
}

# Oldest root commit (for bounding first release PR search).
root_timestamp() {
  git -C "$PROJECT_ROOT" log --reverse -1 --format=%aI
}

# Return JSON array of merged PRs in the time window, using GitHub search (paginated, max 1000).
# Merges pages via temp files — jq --argjson on a large growing string exceeds argv (ARG_MAX) in CI.
search_merged_prs() {
  local repo="$1"
  local t_start_inclusive="${2:-}" # empty => use root; else merged > this (exclusive lower)
  local t_end_inclusive="${3:-}"
  local q
  if [ -n "$t_start_inclusive" ]; then
    q="repo:${repo} is:pr is:merged merged:>${t_start_inclusive} merged:<=${t_end_inclusive}"
  else
    t_start_inclusive=$(root_timestamp)
    q="repo:${repo} is:pr is:merged merged:>${t_start_inclusive} merged:<=${t_end_inclusive}"
  fi

  local accf pagef
  accf=$(mktemp)
  pagef=$(mktemp)
  sc_search_rm() { rm -f "$accf" "$pagef" "${accf}.m" 2>/dev/null; }

  echo '[]' >"$accf"
  local page=1
  local cap=1000
  while [ "$page" -le 20 ]; do
    local enc resp n total_in_acc
    enc=$(printf '%s' "$q" | jq -sRr @uri) || {
      sc_search_rm
      return 1
    }
    resp=$(
      curl -fsS \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $(github_token)" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API}/search/issues?q=${enc}&per_page=100&page=${page}"
    ) || {
      sc_search_rm
      return 1
    }
    echo "$resp" | jq '.items // []' >"$pagef" || {
      sc_search_rm
      return 1
    }
    n=$(jq 'length' "$pagef" 2>/dev/null) || n=0
    if [ "${n:-0}" -eq 0 ]; then
      break
    fi
    if ! jq -s '.[0] + .[1]' "$accf" "$pagef" >"${accf}.m"; then
      sc_search_rm
      return 1
    fi
    mv "${accf}.m" "$accf"
    total_in_acc=$(jq 'length' "$accf")
    if [ "$n" -lt 100 ] || [ "$total_in_acc" -ge "$cap" ]; then
      break
    fi
    page=$((page + 1))
  done

  if ! jq '
    group_by(.number) | map(.[0])
    | sort_by(.number)
    | map({
        number: .number,
        title: .title,
        author: .user.login,
        url: .html_url,
        body: ((.body // "") | if length > 2000 then .[0:2000] + "..." else . end)
      })
  ' "$accf"; then
    sc_search_rm
    return 1
  fi
  sc_search_rm
}

# pr_data_path: file containing a JSON array of PR objects (avoids argv size limits for large lists).
openrouter_changelog() {
  local pr_data_path="$1"
  local version="$2"
  local prev_version="$3"
  local system
  system="You are a release notes writer. Given merged pull requests for a software project, write a clear, user-focused changelog in Markdown for this version. Use sections only if they help (e.g. Added, Fixed, Changed). Be concise. Link PR numbers in parentheses with URLs when present. Do not invent features not implied by the PRs. If the list is empty, write a short note that this release has no merged PRs in the GitHub search range. Output Markdown only, no surrounding quotes."

  local referer req_tmp
  referer="${OPENROUTER_REFERER:-https://github.com/${REPO_SLUG}}"
  req_tmp=$(mktemp)
  or_rm_req() { rm -f "$req_tmp" 2>/dev/null; }

  if ! jq -n \
    --arg model "$OPENROUTER_MODEL" \
    --arg sys "$system" \
    --arg ver "$version" \
    --arg prev "${prev_version:-<none: first v* release>}" \
    --rawfile prs "$pr_data_path" \
    '
    ($prs | fromjson) as $prlist
    | {
        model: $model,
        messages: [
          { role: "system", content: $sys },
          { role: "user", content: (
              {
                instruction: "Write release notes for this version.",
                new_version: $ver,
                previous_version_tag: $prev,
                merged_pull_requests: $prlist
              } | tojson
            ) }
        ]
      }
    ' >"$req_tmp"; then
    or_rm_req
    return 1
  fi

  local resp text
  if ! resp=$(
    curl -fsS "$OPENROUTER_API" \
      -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
      -H "Content-Type: application/json" \
      -H "HTTP-Referer: ${referer}" \
      -H "X-Title: ysc release notes" \
      -d @"$req_tmp"
  ); then
    or_rm_req
    return 1
  fi
  or_rm_req
  text=$(echo "$resp" | jq -r '.choices[0].message.content // empty')
  if [ -z "$text" ] || [ "$text" = "null" ]; then
    echo "${RED}Error: OpenRouter returned no text. Response:${RESET}" >&2
    echo "$resp" | jq . >&2 || echo "$resp" >&2
    exit 1
  fi
  printf '%s\n' "$text"
}

# Create GitHub release or set body on an existing one for this tag.
create_or_update_release() {
  local tag="$1"
  local bodyfile="$2"
  local token
  token=$(github_token)
  local status
  status=$(
    curl -sS -o /dev/null -w "%{http_code}" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${token}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${GITHUB_API}/repos/${REPO_SLUG}/releases/tags/${tag}"
  )
  if [ "$status" = "200" ]; then
    local release_id data
    release_id=$(
      curl -fsS \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${token}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API}/repos/${REPO_SLUG}/releases/tags/${tag}" | jq -r '.id'
    )
    data=$(jq -n --rawfile b "$bodyfile" '{ body: $b }')
    curl -fsS -X PATCH \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${token}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -d "$data" \
      "${GITHUB_API}/repos/${REPO_SLUG}/releases/${release_id}" >/dev/null
  else
    local data
    data=$(
      jq -n \
        --arg tag "$tag" \
        --arg name "Release $tag" \
        --rawfile b "$bodyfile" \
        '{ tag_name: $tag, name: $name, body: $b, draft: false, prerelease: false, generate_release_notes: false }'
    )
    curl -fsS -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${token}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -d "$data" \
      "${GITHUB_API}/repos/${REPO_SLUG}/releases" >/dev/null
  fi
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
fi

require_cmd jq
require_cmd curl

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "${RED}Error: OPENROUTER_API_KEY is not set.${RESET}" >&2
  exit 1
fi
github_token >/dev/null

REPO_SLUG=$(resolve_repo)
export REPO_SLUG

TAG=${1:-${GITHUB_REF_NAME:-}}
if [ -z "$TAG" ]; then
  TAG=$(git -C "$PROJECT_ROOT" describe --tags --exact-match 2>/dev/null || true)
fi
if [ -z "$TAG" ]; then
  echo "${RED}Error: pass TAG, set GITHUB_REF_NAME, or check out a tag.${RESET}" >&2
  exit 1
fi

# Normalize: ensure v* prefix is consistent with git
if ! git -C "$PROJECT_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
  echo "${RED}Error: not a valid git ref: $TAG${RESET}" >&2
  exit 1
fi

cd "$PROJECT_ROOT"

echo "${TEAL}Repository: $REPO_SLUG  Tag: $TAG${RESET}"

PREV_TAG=$(find_previous_v_tag "$TAG")
t_end=$(ref_timestamp "$TAG")
pr_file=$(mktemp)
notes_tmp=$(mktemp)
# shellcheck disable=SC2064
trap 'rm -f "$pr_file" "$notes_tmp"' EXIT

if [ -n "$PREV_TAG" ]; then
  t_start=$(ref_timestamp "$PREV_TAG")
  echo "${TEAL}Previous tag: $PREV_TAG${RESET}"
  search_merged_prs "$REPO_SLUG" "$t_start" "$t_end" >"$pr_file"
else
  echo "${TEAL}No previous v* tag; bounding PRs from repository root to this tag.${RESET}"
  search_merged_prs "$REPO_SLUG" "" "$t_end" >"$pr_file"
fi

PR_COUNT=$(jq 'length' "$pr_file")
echo "${TEAL}Merged PRs in range (GitHub search): $PR_COUNT${RESET}"

openrouter_changelog "$pr_file" "$TAG" "${PREV_TAG:-}" | tee "$notes_tmp"

if [ "$DRY_RUN" = "1" ]; then
  echo "${TEAL}DRY_RUN=1 — not updating GitHub release.${RESET}"
  exit 0
fi

echo "${TEAL}Updating GitHub release for $TAG...${RESET}"
create_or_update_release "$TAG" "$notes_tmp"
echo "${GREEN}Done. Release $TAG body updated.${RESET}"

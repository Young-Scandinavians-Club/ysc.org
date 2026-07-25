#!/usr/bin/env bash
# update_github_release_notes.sh — Build a tag's GitHub release body from merged PRs since the
# previous v* tag, via OpenRouter (OpenAI-compatible chat), then create or update the release.
#
# Environment:
#   OPENROUTER_API_KEY  (required)  API key for https://openrouter.ai/
#   GITHUB_TOKEN or GH_TOKEN        (required)  token with repo / contents:write
#   GITHUB_REPOSITORY               (optional)  "owner/name"; inferred from `git remote` if unset
#   OPENROUTER_MODEL                (optional)  default: deepseek/deepseek-v4-flash
#   OPENROUTER_REFERER              (optional)  HTTP-Referer for OpenRouter (default: this repo on GitHub)
#   OPENROUTER_MAX_FULL_PR_BODIES   (optional)  if PR count exceeds this, drop body text and send title/link only (default: 100)
#   OPENROUTER_MAX_PRS              (optional)  max PRs to send after sorting by number, tail (default: 200; use after git scope)
#   OPENROUTER_PR_BODY_MAX          (optional)  max characters per PR body fetched from GitHub (default: 8000)
#   OPENROUTER_MAX_TOKENS           (optional)  max completion tokens for the LLM response (default: 8192)
#   OPENROUTER_SMALL_RELEASE_MAX_COMMITS (opt.)  if previous tag exists and rev-list --count PREV..TAG is at most this, do not
#                                   cap LLM input (no OPENROUTER_MAX_* trim; per-PR body fetch up to 1M chars) (default: 50; 0 disables)
#   When a previous v* tag exists, PRs are scoped by git (PREV..TAG), not only by merge timestamps on GitHub
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
OPENROUTER_MODEL="${OPENROUTER_MODEL:-deepseek/deepseek-v4-flash}"
OPENROUTER_PR_BODY_MAX="${OPENROUTER_PR_BODY_MAX:-8000}"
OPENROUTER_MAX_TOKENS="${OPENROUTER_MAX_TOKENS:-8192}"
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

# Previous v* tag (immediately older in semver) before TAG. Empty if TAG is the oldest v* tag.
# Tags must be listed oldest→newest so that when we find TAG, the previous line is the prior release.
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
  done < <(git -C "$PROJECT_ROOT" tag -l 'v*' | LC_ALL=C sort -V)
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

# PR numbers that appear in commit subjects/bodies for commits between two refs (GitHub merge + squash).
# This matches what actually landed on `main` between tags; a GitHub "merged" timestamp search is often wider.
pr_numbers_from_rev_range() {
  local a="${1:-}" b="${2:-}"
  if [ -z "$a" ] || [ -z "$b" ]; then
    return 0
  fi
  if ! git -C "$PROJECT_ROOT" rev-parse --verify "$a^{commit}" >/dev/null 2>&1; then
    return 0
  fi
  if ! git -C "$PROJECT_ROOT" rev-parse --verify "$b^{commit}" >/dev/null 2>&1; then
    return 0
  fi
  local _lf
  _lf=$(mktemp)
  if ! git -C "$PROJECT_ROOT" log --format="%s%n%b" "${a}..${b}" 2>/dev/null >"$_lf"; then
    rm -f "$_lf"
    return 0
  fi
  {
    # grep can return 1; with set -e and pipefail the pipeline would abort without || true
    grep -oE 'Merge pull request #[0-9][0-9]*' "$_lf" 2>/dev/null | sed 's/Merge pull request #//' || true
    # Squash: (#NNN) in subject/body; tr leaves digits
    grep -oE '\(#[0-9][0-9]*\)' "$_lf" 2>/dev/null | tr -d '()#' || true
  } | sort -n -u
  rm -f "$_lf"
}

# PR numbers from GitHub's "pull requests associated with a commit" API for each commit in a..b.
# Catches squashes/rebases where the subject has no "(#NN)"; avoids relying on a broad merged-date search.
# Exits 0; prints one number per line, sorted -u. Caps API calls to avoid rate limits.
pr_numbers_from_commits_api() {
  local a="${1:-}" b="${2:-}"
  if [ -z "$a" ] || [ -z "$b" ]; then
    return 0
  fi
  if ! git -C "$PROJECT_ROOT" rev-parse --verify "$a^{commit}" >/dev/null 2>&1; then
    return 0
  fi
  if ! git -C "$PROJECT_ROOT" rev-parse --verify "$b^{commit}" >/dev/null 2>&1; then
    return 0
  fi
  local token n_shas resp
  token=$(github_token)
  n_shas=0
  while IFS= read -r _sha; do
    [ -z "$_sha" ] && continue
    n_shas=$((n_shas + 1))
    if [ "$n_shas" -gt 100 ]; then
      break
    fi
    if ! resp=$(
      curl -fsS \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${token}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API}/repos/${REPO_SLUG}/commits/${_sha}/pulls" 2>/dev/null
    ); then
      continue
    fi
    echo "$resp" | jq -r '.[] | .number' 2>/dev/null
  done < <(git -C "$PROJECT_ROOT" log --format=%H "${a}..${b}" 2>/dev/null) | sort -n -u
}

# JSON array of { "subject": "..." } for each commit in a..b (for LLM when no PRs are in scope).
commits_in_range_json() {
  local a="${1:-}" b="${2:-}"
  if [ -z "$a" ] || [ -z "$b" ]; then
    echo '[]'
    return 0
  fi
  git -C "$PROJECT_ROOT" log --format=%s "${a}..${b}" 2>/dev/null | jq -R -s 'split("\n") | map(select(length>0) | {subject: .})'
}

# Write OpenRouter user payload: merged_pull_requests (array). When the PR list is empty and
# range is set, include commits_in_range from git; otherwise commits_in_range is [].
write_openrouter_input_file() {
  local out="$1" prs_jsonf="$2" range_from="${3:-}" range_to="${4:-}"
  local npr cj
  npr=$(jq 'length' "$prs_jsonf" 2>/dev/null) || npr=0
  if [ "$npr" -eq 0 ] && [ -n "$range_from" ] && [ -n "$range_to" ]; then
    cj=$(commits_in_range_json "$range_from" "$range_to")
  else
    cj='[]'
  fi
  if ! jq -n --argjson prs "$(cat "$prs_jsonf")" --argjson c "$cj" \
    '{
       merged_pull_requests: $prs,
       commits_in_range: $c
     }' >"$out"; then
    return 1
  fi
  return 0
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
        body: ((.body // "") | if length > $lim then .[0:$lim] + "..." else . end)
      })
  ' --argjson lim "$OPENROUTER_PR_BODY_MAX" "$accf"; then
    sc_search_rm
    return 1
  fi
  sc_search_rm
}

# Fetches merged PRs by number into a JSON array file (for when id-list ⊄ timestamp search result).
# Optional 3rd arg: max body length before truncation in JSON (default OPENROUTER_PR_BODY_MAX). Use a large value when not capping LLM input.
rebuild_pr_file_from_fetched() {
  local outf="$1" numsf="$2"
  local body_max="${3:-$OPENROUTER_PR_BODY_MAX}"
  local token n resp line
  token=$(github_token)
  local _nd
  _nd=$(mktemp)
  : >"$_nd"
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
      continue
    fi
    resp=$(
      curl -fsS \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${token}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API}/repos/${REPO_SLUG}/pulls/${n}" 2>/dev/null
    ) || continue
    if ! echo "$resp" | jq -e '(.merged_at // empty | length) > 0' >/dev/null 2>&1; then
      continue
    fi
    line=$(
      echo "$resp" | jq -c --argjson lim "$body_max" '{
        number, title, author: .user.login, url: .html_url,
        body: ((.body // "") | if length > $lim then .[0:$lim] + "..." else . end)
      }'
    )
    echo "$line" >>"$_nd"
  done <"$numsf"
  if [ ! -s "$_nd" ]; then
    rm -f "$_nd"
    return 1
  fi
  jq -s 'sort_by(.number)' "$_nd" >"$outf"
  rm -f "$_nd"
  return 0
}

# Rewrites the PR JSON file in place so the OpenRouter request stays within model limits (and avoids
# HTTP 402 from oversized prompts or from hitting free-tier / credit limits for huge chats).
# Optional 2nd arg: if 1, do not apply caps (for very small tag ranges with few commits).
pr_json_shrink_for_openrouter() {
  local f="$1"
  local no_cap="${2:-0}"
  local max_bodies max_prs n
  max_bodies=${OPENROUTER_MAX_FULL_PR_BODIES:-100}
  max_prs=${OPENROUTER_MAX_PRS:-200}
  if [ "$no_cap" = "1" ]; then
    max_bodies=999999
    max_prs=999999
    echo "${TEAL}Small release: not applying OPENROUTER_MAX_PRS / OPENROUTER_MAX_FULL_PR_BODIES trim.${RESET}" >&2
  fi
  n=$(jq 'length' "$f")

  if [ "$n" -gt "$max_bodies" ]; then
    echo "${TEAL}PR list has $n items; using title and link only (no PR bodies). Threshold OPENROUTER_MAX_FULL_PR_BODIES is $max_bodies; raise it if you need descriptions.${RESET}" >&2
    jq 'map({ number: .number, title: .title, url: .url, author: .author })' "$f" >"${f}.t" && mv "${f}.t" "$f"
    n=$(jq 'length' "$f")
  fi
  if [ "$n" -gt "$max_prs" ]; then
    echo "${TEAL}Capping to the last $max_prs PRs by number (oldest in range dropped). Set OPENROUTER_MAX_PRS to change.${RESET}" >&2
    jq --argjson m "$max_prs" \
      'sort_by(.number) | (length as $L | if $L > $m then .[$L - $m : $L] else . end )' \
      "$f" >"${f}.t" && mv "${f}.t" "$f"
  fi
}

# pr_data_path: JSON object { merged_pull_requests, commits_in_range } (see write_openrouter_input_file).
openrouter_changelog() {
  local pr_data_path="$1"
  local version="$2"
  local prev_version="$3"
  local system
  system="You write comprehensive GitHub release notes in Markdown for one production release.

The user JSON has merged_pull_requests and commits_in_range (git commit subjects in this tag range, newest first). These are the ONLY sources: do not mention features, tickets, or areas not supported by the PR titles/bodies or commit subjects you were given. Never invent product areas, past releases, or themes that do not appear in the data.

Scoping rules (strict):
- If merged_pull_requests is non-empty: use PR titles and bodies (when present) as the primary source. Document every PR in the input at least once. You may use commits_in_range to clarify wording, but it must not add themes beyond the PRs.
- If merged_pull_requests is empty and commits_in_range is non-empty: summarize from those commit subjects. Bullet each meaningful change; skip pure version-bump or empty chore lines unless they are the only content. Do not invent work not in those subjects.
- If both are empty: one sentence, e.g. no merged PRs or commits in range.

Structure:
- Optional 1–2 sentence release summary at the top when the data supports a clear theme.
- Use H2 sections as appropriate: ## Highlights, ## Added, ## Changed, ## Fixed, ## Security, ## Internal / Technical. Omit empty sections.
- Under each section, use bullets; nest one level when grouping closely related PRs.
- Link PRs as [#NNN](url) when url is in the data, or #NNN otherwise.

Length and detail:
- Be thorough and specific: prefer concrete user-visible outcomes over vague \"improvements\".
- Aim for roughly one substantive bullet per PR on small releases; on large releases, group related PRs but ensure every PR number still appears.
- Target roughly 500–3000 words depending on PR count — longer when there are many PRs. Do not artificially truncate coverage of the input.
- Output Markdown only, no preamble or code fences around the whole text."

  local referer req_tmp
  referer="${OPENROUTER_REFERER:-https://github.com/${REPO_SLUG}}"
  req_tmp=$(mktemp)
  or_rm_req() { rm -f "$req_tmp" 2>/dev/null; }

  if ! jq -n \
    --arg model "$OPENROUTER_MODEL" \
    --arg sys "$system" \
    --arg ver "$version" \
    --arg prev "${prev_version:-<none: first v* release>}" \
    --argjson max_tokens "$OPENROUTER_MAX_TOKENS" \
    --rawfile payload "$pr_data_path" \
    '
    ($payload | fromjson) as $p
    | {
        model: $model,
        max_tokens: $max_tokens,
        messages: [
          { role: "system", content: $sys },
          { role: "user", content: (
              {
                instruction: "Write comprehensive user-facing release notes (see system rules). Cover every PR in the input.",
                new_version: $ver,
                previous_version_tag: $prev,
                merged_pull_requests: ($p.merged_pull_requests // []),
                commits_in_range: ($p.commits_in_range // [])
              } | tojson
            ) }
        ]
      }
    ' >"$req_tmp"; then
    or_rm_req
    return 1
  fi

  local resp_tmp code text
  resp_tmp=$(mktemp)
  code=$(
    curl -sS -o "$resp_tmp" -w "%{http_code}" \
      -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
      -H "Content-Type: application/json" \
      -H "HTTP-Referer: ${referer}" \
      -H "X-Title: ysc release notes" \
      -d @"$req_tmp" \
      "$OPENROUTER_API"
  )
  or_rm_req
  if [ "$code" != "200" ]; then
    echo "${RED}OpenRouter request failed: HTTP $code${RESET}" >&2
    case "$code" in
      401) echo "Invalid or missing API key (check OPENROUTER_API_KEY)." >&2 ;;
      402)
        echo "HTTP 402 from OpenRouter: add credits (https://openrouter.ai/credits), confirm billing," >&2
        echo "  or use a different OPENROUTER_MODEL. Large first releases are trimmed by OPENROUTER_MAX_*; see script header." >&2
        ;;
      403) echo "Request forbidden: model or key may not be allowed for this call." >&2 ;;
      429) echo "Rate limit — retry later." >&2 ;;
    esac
    echo "${TEAL}Response body:${RESET}" >&2
    cat "$resp_tmp" >&2
    echo >&2
    rm -f "$resp_tmp"
    return 1
  fi
  text=$(jq -r '.choices[0].message.content // empty' "$resp_tmp")
  if [ -z "$text" ] || [ "$text" = "null" ]; then
    echo "${RED}Error: OpenRouter returned no text. Response:${RESET}" >&2
    jq . "$resp_tmp" 2>/dev/null || cat "$resp_tmp" >&2
    rm -f "$resp_tmp"
    return 1
  fi
  rm -f "$resp_tmp"
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

# How many commits land between tags? Very small ranges skip OPENROUTER_MAX_* caps and widen PR body fetch.
COMMIT_IN_RELEASE=0
NO_CAP=0
PR_BODY_MAX=$OPENROUTER_PR_BODY_MAX
if [ -n "$PREV_TAG" ]; then
  COMMIT_IN_RELEASE=$(git -C "$PROJECT_ROOT" rev-list --count "$PREV_TAG".."$TAG" 2>/dev/null || echo 0)
  # OPENROUTER_SMALL_RELEASE_MAX_COMMITS=0 means never auto-relax (always use caps and OPENROUTER_PR_BODY_MAX bodies)
  _sr_max="${OPENROUTER_SMALL_RELEASE_MAX_COMMITS:-50}"
  if [ "$_sr_max" != "0" ] && [ "$COMMIT_IN_RELEASE" -le "$_sr_max" ]; then
    NO_CAP=1
    PR_BODY_MAX=1000000
  fi
  echo "${TEAL}Commits in ${PREV_TAG}..${TAG}: ${COMMIT_IN_RELEASE} (auto skip LLM input caps when ≤${_sr_max} commits, enabled: $([ "$NO_CAP" = "1" ] && echo yes || echo no))${RESET}" >&2
else
  echo "${TEAL}No previous v* tag; standard LLM input caps and ${OPENROUTER_PR_BODY_MAX}-char PR body fetch apply.${RESET}" >&2
fi

pr_file=$(mktemp)
or_payload=$(mktemp)
notes_tmp=$(mktemp)
NUMS_F=""
# shellcheck disable=SC2064
trap 'rm -f "$pr_file" "$or_payload" "$notes_tmp" "${pr_file}.bak" "${NUMS_F:-}" 2>/dev/null' EXIT

if [ -n "$PREV_TAG" ]; then
  echo "${TEAL}Previous tag: $PREV_TAG${RESET}"
  NUMS_F=$(mktemp)
  {
    pr_numbers_from_rev_range "$PREV_TAG" "$TAG"
    pr_numbers_from_commits_api "$PREV_TAG" "$TAG"
  } | sort -n -u | sed '/^$/d' >"$NUMS_F"
  n_nums=$(wc -l <"$NUMS_F" 2>/dev/null | tr -d ' ' || true)
  n_nums=${n_nums:-0}
  if [ "$n_nums" -gt 0 ]; then
    if rebuild_pr_file_from_fetched "$pr_file" "$NUMS_F" "$PR_BODY_MAX"; then
      echo "${TEAL}Scope ${PREV_TAG}..${TAG}: ${n_nums} PR id(s) (git + commit→PR API) -> $(jq 'length' "$pr_file") merged PR(s) fetched from API.${RESET}" >&2
    else
      echo "${YELLOW}Could not build PR list from ids; using commit-only release notes (no wide merged-date search).${RESET}" >&2
      echo '[]' >"$pr_file"
    fi
  else
    echo "${TEAL}No PR numbers in ${PREV_TAG}..${TAG} (log + commit-PR API) — release notes from git commits only (not merged-PR time window).${RESET}" >&2
    echo '[]' >"$pr_file"
  fi
  rm -f "$NUMS_F"
  NUMS_F=""
else
  echo "${TEAL}No previous v* tag; bounding PRs from repository root to this tag.${RESET}"
  search_merged_prs "$REPO_SLUG" "" "$t_end" >"$pr_file"
fi

PR_COUNT=$(jq 'length' "$pr_file")
echo "${TEAL}PR rows for the LLM: $PR_COUNT${RESET}" >&2

pr_json_shrink_for_openrouter "$pr_file" "$NO_CAP"

if [ -n "$PREV_TAG" ]; then
  write_openrouter_input_file "$or_payload" "$pr_file" "$PREV_TAG" "$TAG"
else
  write_openrouter_input_file "$or_payload" "$pr_file" "" ""
fi
echo "${TEAL}Sending OpenRouter request (model: ${OPENROUTER_MODEL}, PRs: $(jq '.merged_pull_requests | length' "$or_payload"), commits_in_range: $(jq '.commits_in_range | length' "$or_payload")).${RESET}" >&2

openrouter_changelog "$or_payload" "$TAG" "${PREV_TAG:-}" | tee "$notes_tmp"

if [ "$DRY_RUN" = "1" ]; then
  echo "${TEAL}DRY_RUN=1 — not updating GitHub release.${RESET}"
  exit 0
fi

echo "${TEAL}Updating GitHub release for $TAG...${RESET}"
create_or_update_release "$TAG" "$notes_tmp"
echo "${GREEN}Done. Release $TAG body updated.${RESET}"

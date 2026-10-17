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
#   OPENROUTER_MAX_TOKENS           (optional)  max completion tokens per LLM response, reasoning included (default: 16384)
#   OPENROUTER_CHUNK_PRS            (optional)  if more PRs than this, summarize them in chunks of this size, merge the sections
#                                   locally, then make one short request for the intro/Highlights (default: 25; 0 disables)
#   OPENROUTER_SMALL_RELEASE_MAX_COMMITS (opt.)  if previous tag exists and rev-list --count PREV..TAG is at most this, do not
#                                   cap LLM input (no OPENROUTER_MAX_* trim; per-PR body fetch up to 1M chars) (default: 50; 0 disables)
#   When a previous v* tag exists, PRs are scoped by git (PREV..TAG), not only by merge timestamps on GitHub
#   DRY_RUN                         (optional)  if 1, print notes to stdout; skip GitHub release API
#
# Usage:
#   etc/scripts/update_github_release_notes.sh [TAG]
#   etc/scripts/update_github_release_notes.sh --self-test
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
OPENROUTER_MAX_TOKENS="${OPENROUTER_MAX_TOKENS:-16384}"
OPENROUTER_CHUNK_PRS="${OPENROUTER_CHUNK_PRS:-25}"
GITHUB_API="${GITHUB_API:-https://api.github.com}"
OPENROUTER_API="${OPENROUTER_API:-https://openrouter.ai/api/v1/chat/completions}"

usage() {
  echo "Usage: $0 [TAG|--self-test]"
  echo "Requires OPENROUTER_API_KEY and GITHUB_TOKEN (or GH_TOKEN) except for --self-test."
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
# Reads JSON from files via --slurpfile. --argjson "$(cat file)" exceeds Linux MAX_ARG_STRLEN
# (~128KiB per argument) when a tag has many PR bodies (v2.41.0: 91 PRs, job 107277364820).
write_openrouter_input_file() {
  local out="$1" prs_jsonf="$2" range_from="${3:-}" range_to="${4:-}"
  local npr commits_jsonf
  npr=$(jq 'length' "$prs_jsonf" 2>/dev/null) || npr=0
  commits_jsonf=$(mktemp)
  if [ "$npr" -eq 0 ] && [ -n "$range_from" ] && [ -n "$range_to" ]; then
    if ! commits_in_range_json "$range_from" "$range_to" >"$commits_jsonf"; then
      rm -f "$commits_jsonf"
      return 1
    fi
  else
    echo '[]' >"$commits_jsonf"
  fi
  if ! jq -n --slurpfile prs "$prs_jsonf" --slurpfile c "$commits_jsonf" \
    '{
       merged_pull_requests: $prs[0],
       commits_in_range: $c[0]
     }' >"$out"; then
    rm -f "$commits_jsonf"
    return 1
  fi
  rm -f "$commits_jsonf"
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

# openrouter_complete SYSTEM USER_FILE — one chat completion with retries; prints the assistant text.
# USER_FILE holds the raw user message. Fails (non-zero) on HTTP errors or an empty answer, with a
# specific hint when the model spent its whole max_tokens budget (reasoning models) before answering.
openrouter_complete() {
  local system="$1" user_file="$2"
  local referer req_tmp resp_tmp code text finish attempt
  referer="${OPENROUTER_REFERER:-https://github.com/${REPO_SLUG}}"
  req_tmp=$(mktemp)
  resp_tmp=$(mktemp)

  if ! jq -n \
    --arg model "$OPENROUTER_MODEL" \
    --arg sys "$system" \
    --argjson max_tokens "$OPENROUTER_MAX_TOKENS" \
    --rawfile user "$user_file" \
    '{
       model: $model,
       max_tokens: $max_tokens,
       messages: [
         { role: "system", content: $sys },
         { role: "user", content: $user }
       ]
     }' >"$req_tmp"; then
    rm -f "$req_tmp" "$resp_tmp"
    return 1
  fi

  for attempt in 1 2 3; do
    code=$(
      curl -sS -o "$resp_tmp" -w "%{http_code}" \
        -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
        -H "Content-Type: application/json" \
        -H "HTTP-Referer: ${referer}" \
        -H "X-Title: ysc release notes" \
        -d @"$req_tmp" \
        "$OPENROUTER_API"
    ) || code=000

    if [ "$code" = "200" ]; then
      text=$(jq -r '.choices[0].message.content // empty' "$resp_tmp")
      if [ -n "$text" ] && [ "$text" != "null" ]; then
        rm -f "$req_tmp" "$resp_tmp"
        printf '%s\n' "$text"
        return 0
      fi
      finish=$(jq -r '.choices[0].finish_reason // "unknown"' "$resp_tmp" 2>/dev/null || echo unknown)
      echo "${RED}Error: OpenRouter returned no text (finish_reason: ${finish}). Response:${RESET}" >&2
      jq . "$resp_tmp" 2>/dev/null || cat "$resp_tmp" >&2
      if [ "$finish" = "length" ]; then
        echo "The model used all ${OPENROUTER_MAX_TOKENS} completion tokens (reasoning counts) before answering." >&2
        echo "  Raise OPENROUTER_MAX_TOKENS or lower OPENROUTER_CHUNK_PRS so each request is smaller." >&2
        break
      fi
    else
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
      # Client errors other than rate limiting will not succeed on retry.
      case "$code" in 401 | 402 | 403) break ;; esac
    fi
    if [ "$attempt" -lt 3 ]; then
      echo "${YELLOW}Retrying OpenRouter request (attempt $((attempt + 1)) of 3)...${RESET}" >&2
      sleep $((attempt * 5))
    fi
  done
  rm -f "$req_tmp" "$resp_tmp"
  return 1
}

# or_user_message PAYLOAD_JSON INSTRUCTION VERSION PREV_VERSION — prints the user message JSON text.
or_user_message() {
  local pr_data_path="$1" instruction="$2" version="$3" prev_version="$4"
  jq -n \
    --arg instruction "$instruction" \
    --arg ver "$version" \
    --arg prev "${prev_version:-<none: first v* release>}" \
    --slurpfile p "$pr_data_path" \
    '{
       instruction: $instruction,
       new_version: $ver,
       previous_version_tag: $prev,
       merged_pull_requests: ($p[0].merged_pull_requests // []),
       commits_in_range: ($p[0].commits_in_range // [])
     } | tojson' -r
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

  local user_tmp
  user_tmp=$(mktemp)
  or_user_message "$pr_data_path" \
    "Write comprehensive user-facing release notes (see system rules). Cover every PR in the input." \
    "$version" "$prev_version" >"$user_tmp" || {
    rm -f "$user_tmp"
    return 1
  }
  openrouter_complete "$system" "$user_tmp" || {
    rm -f "$user_tmp"
    return 1
  }
  rm -f "$user_tmp"
}

# merge_release_sections FILE... — concatenates the bullets of each chunk's H2 sections under one
# heading per section, in a fixed order. Unknown headings fold into Changed; Highlights/Summary and
# text before the first heading are dropped (the final pass rewrites those).
merge_release_sections() {
  awk '
    BEGIN {
      n = split("Added|Changed|Fixed|Security|Internal / Technical", order, "|")
      for (i = 1; i <= n; i++) canon[tolower(order[i])] = order[i]
    }
    FNR == 1 { cur = "" }
    /^##[[:space:]]+/ {
      h = $0
      sub(/^##[[:space:]]+/, "", h)
      sub(/[[:space:]]+$/, "", h)
      key = tolower(h)
      if (key in canon) cur = canon[key]
      else if (key == "highlights" || key == "summary") cur = ""
      else cur = "Changed"
      next
    }
    cur == "" { next }
    /^[[:space:]]*$/ { next }
    { buf[cur] = buf[cur] $0 "\n" }
    END {
      for (i = 1; i <= n; i++) {
        o = order[i]
        if (buf[o] != "") printf "## %s\n\n%s\n", o, buf[o]
      }
    }
  ' "$@"
}

# missing_pr_bullets MERGED_MD PRS_JSON — one bullet per PR whose number never appears in the notes,
# so a chunk that skipped a PR still gets it listed.
missing_pr_bullets() {
  local merged="$1" prs="$2" n title url
  while IFS=$'\t' read -r n title url; do
    [ -z "$n" ] && continue
    if ! grep -Eq "#${n}([^0-9]|$)" "$merged"; then
      if [ -n "$url" ] && [ "$url" != "null" ]; then
        printf -- '- %s ([#%s](%s))\n' "$title" "$n" "$url"
      else
        printf -- '- %s (#%s)\n' "$title" "$n"
      fi
    fi
  done < <(jq -r '.[] | [.number, .title, .url] | @tsv' "$prs")
}

# openrouter_changelog_chunked PR_FILE VERSION PREV_VERSION CHUNK_SIZE
# Map-reduce for big releases: each chunk of PRs is summarized into H2 sections separately (small
# prompts, small answers), the sections are merged locally, and one short final request writes the
# intro and Highlights from the merged notes. Every PR is guaranteed to appear in the result.
openrouter_changelog_chunked() {
  local pr_file="$1" version="$2" prev_version="$3" chunk_size="$4"
  local total n_chunks i work part_system final_system
  total=$(jq 'length' "$pr_file")
  n_chunks=$(((total + chunk_size - 1) / chunk_size))
  work=$(mktemp -d)

  part_system="You write one PART of the GitHub release notes in Markdown for a production release. Other parts covering other PRs are written separately and merged afterwards.

The user JSON has merged_pull_requests: the ONLY source. Do not mention features, tickets, or areas not supported by the PR titles/bodies. Never invent anything.

Rules:
- Document every PR in the input at least once. Prefer concrete user-visible outcomes over vague \"improvements\"; group closely related PRs into one bullet but keep every PR number.
- Output ONLY these H2 sections, omitting empty ones: ## Added, ## Changed, ## Fixed, ## Security, ## Internal / Technical.
- Do NOT write a summary, a title, a Highlights section, or any text outside those sections.
- Under each section use bullets. Link PRs as [#NNN](url) when url is in the data, or #NNN otherwise.
- Output Markdown only, no preamble or code fences."

  final_system="You write the opening of GitHub release notes in Markdown. The user message contains the already-written sections of the notes for one release. Use ONLY that text; do not invent anything.

Output exactly:
1. A 1–2 sentence summary of the release's main themes (no heading).
2. A blank line, then \"## Highlights\" followed by 3–5 bullets naming the most user-visible changes, keeping the [#NNN](url) links copied from the notes.

Do not repeat the full sections. Output Markdown only, no code fences."

  for ((i = 0; i < n_chunks; i++)); do
    jq --argjson s "$chunk_size" --argjson i "$i" '.[($i * $s):(($i + 1) * $s)]' "$pr_file" >"$work/chunk.json"
    write_openrouter_input_file "$work/payload.json" "$work/chunk.json" "" "" || {
      rm -rf "$work"
      return 1
    }
    echo "${TEAL}Release notes part $((i + 1))/${n_chunks}: $(jq 'length' "$work/chunk.json") PRs.${RESET}" >&2
    or_user_message "$work/payload.json" \
      "Write this part of the release notes (see system rules). Cover every PR in the input." \
      "$version" "$prev_version" >"$work/user.txt" || {
      rm -rf "$work"
      return 1
    }
    openrouter_complete "$part_system" "$work/user.txt" >"$work/part_${i}.md" || {
      rm -rf "$work"
      return 1
    }
  done

  merge_release_sections "$work"/part_*.md >"$work/merged.md"
  local extra
  extra=$(missing_pr_bullets "$work/merged.md" "$pr_file")
  if [ -n "$extra" ]; then
    echo "${YELLOW}Some PRs were skipped by the model; listing them under Other changes.${RESET}" >&2
    printf '## Other changes\n\n%s\n' "$extra" >>"$work/merged.md"
  fi

  if openrouter_complete "$final_system" "$work/merged.md" >"$work/intro.md"; then
    cat "$work/intro.md"
    echo
  else
    echo "${YELLOW}Could not generate the release summary; publishing sections only.${RESET}" >&2
  fi
  cat "$work/merged.md"
  rm -rf "$work"
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

self_test() {
  local dir i nd body bytes n
  dir=$(mktemp -d)
  self_test_cleanup() { rm -rf "$dir"; }

  echo '[]' >"$dir/empty.json"
  if ! write_openrouter_input_file "$dir/out.json" "$dir/empty.json" "" ""; then
    echo "update_github_release_notes.sh: empty payload write failed" >&2
    self_test_cleanup
    return 1
  fi
  if [ "$(jq -c '{n:(.merged_pull_requests|length),c:(.commits_in_range|length)}' "$dir/out.json")" != '{"n":0,"c":0}' ]; then
    echo "update_github_release_notes.sh: empty input payload mismatch" >&2
    self_test_cleanup
    return 1
  fi

  # Larger than Linux MAX_ARG_STRLEN (32 pages = 131072) so --argjson "$(cat file)" fails.
  body=$(head -c 2500 /dev/zero | tr '\0' 'x')
  nd="$dir/nd.json"
  : >"$nd"
  for i in $(seq 1 80); do
    jq -n --argjson n "$i" --arg body "$body" \
      '{number:$n, title:("PR "+($n|tostring)), author:"bot", url:"https://example.invalid/p", body:$body}' >>"$nd"
  done
  jq -s '.' "$nd" >"$dir/prs.json"
  bytes=$(wc -c <"$dir/prs.json" | tr -d ' ')
  if [ "$bytes" -lt 131072 ]; then
    echo "update_github_release_notes.sh: test payload too small ($bytes bytes)" >&2
    self_test_cleanup
    return 1
  fi

  if jq -n --argjson prs "$(cat "$dir/prs.json")" '{merged_pull_requests:$prs}' >/dev/null 2>"$dir/argjson.err"; then
    echo "update_github_release_notes.sh: warning: --argjson succeeded on ${bytes}-byte payload (ARG_MAX may be larger than Linux MAX_ARG_STRLEN)" >&2
  elif ! grep -qi 'Argument list too long' "$dir/argjson.err"; then
    echo "update_github_release_notes.sh: --argjson failed for unexpected reason:" >&2
    cat "$dir/argjson.err" >&2
    self_test_cleanup
    return 1
  else
    echo "update_github_release_notes.sh: --argjson rejected ${bytes}-byte payload (Argument list too long)"
  fi

  if ! write_openrouter_input_file "$dir/out.json" "$dir/prs.json" "" ""; then
    echo "update_github_release_notes.sh: large payload write failed" >&2
    self_test_cleanup
    return 1
  fi
  n=$(jq '.merged_pull_requests | length' "$dir/out.json")
  if [ "$n" != "80" ]; then
    echo "update_github_release_notes.sh: large payload PR count mismatch (got $n)" >&2
    self_test_cleanup
    return 1
  fi
  if [ "$(jq '.merged_pull_requests[0].number' "$dir/out.json")" != "1" ]; then
    echo "update_github_release_notes.sh: large payload first PR mismatch" >&2
    self_test_cleanup
    return 1
  fi
  if [ "$(jq -r '.merged_pull_requests[-1].title' "$dir/out.json")" != "PR 80" ]; then
    echo "update_github_release_notes.sh: large payload last PR mismatch" >&2
    self_test_cleanup
    return 1
  fi
  if [ "$(jq '.commits_in_range | length' "$dir/out.json")" != "0" ]; then
    echo "update_github_release_notes.sh: large payload commits should be empty" >&2
    self_test_cleanup
    return 1
  fi

  printf '## Added\n- A ([#1](u))\n\n## Weird\n- B ([#2](u))\n' >"$dir/p1.md"
  printf 'intro\n## Highlights\n- skip\n## Fixed\n- C (#3)\n## Added\n- D ([#4](u))\n' >"$dir/p2.md"
  merge_release_sections "$dir/p1.md" "$dir/p2.md" >"$dir/merged.md"
  if [ "$(grep -c '^## ' "$dir/merged.md")" != "3" ] ||
    [ "$(grep '^## ' "$dir/merged.md" | tr '\n' '|')" != "## Added|## Changed|## Fixed|" ] ||
    grep -q 'skip\|intro' "$dir/merged.md" ||
    [ "$(awk '/^## Added/{f=1;next} /^## /{f=0} f&&/^- /' "$dir/merged.md" | wc -l | tr -d ' ')" != "2" ]; then
    echo "update_github_release_notes.sh: merge_release_sections mismatch" >&2
    cat "$dir/merged.md" >&2
    self_test_cleanup
    return 1
  fi
  echo '[{"number":2,"title":"B","url":"u"},{"number":5,"title":"E","url":"https://x/5"},{"number":30,"title":"F","url":null}]' >"$dir/mp.json"
  printf '[#3](u) and #30\n' >"$dir/notes.md"
  if [ "$(missing_pr_bullets "$dir/notes.md" "$dir/mp.json" | tr '\n' '|')" != "- B ([#2](u))|- E ([#5](https://x/5))|" ]; then
    echo "update_github_release_notes.sh: missing_pr_bullets mismatch" >&2
    self_test_cleanup
    return 1
  fi

  self_test_cleanup
  echo "update_github_release_notes.sh: self-test passed"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
fi

if [ "${1:-}" = "--self-test" ]; then
  require_cmd jq
  self_test
  exit 0
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

if [ "$OPENROUTER_CHUNK_PRS" -gt 0 ] && [ "$(jq 'length' "$pr_file")" -gt "$OPENROUTER_CHUNK_PRS" ]; then
  echo "${TEAL}Large release: summarizing in chunks of ${OPENROUTER_CHUNK_PRS} PRs, then merging.${RESET}" >&2
  openrouter_changelog_chunked "$pr_file" "$TAG" "${PREV_TAG:-}" "$OPENROUTER_CHUNK_PRS" | tee "$notes_tmp"
else
  openrouter_changelog "$or_payload" "$TAG" "${PREV_TAG:-}" | tee "$notes_tmp"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "${TEAL}DRY_RUN=1 — not updating GitHub release.${RESET}"
  exit 0
fi

echo "${TEAL}Updating GitHub release for $TAG...${RESET}"
create_or_update_release "$TAG" "$notes_tmp"
echo "${GREEN}Done. Release $TAG body updated.${RESET}"

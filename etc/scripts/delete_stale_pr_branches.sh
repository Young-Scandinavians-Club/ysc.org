#!/usr/bin/env bash
# delete_stale_pr_branches.sh — Delete remote branches for closed or merged pull requests.
#
# Environment:
#   GITHUB_TOKEN or GH_TOKEN  (required)  token with contents: write
#   GITHUB_REPOSITORY         (optional)  "owner/name"; inferred from `git remote` if unset
#   STALE_DAYS                (optional)  only delete when PR closed at least this many days ago (default: 7; 0 = no wait)
#   PROTECTED_BRANCHES        (optional)  extra space-separated branch names to never delete
#                                           (`main` and release tag names `v*` are always protected)
#   DRY_RUN                   (optional)  if 1, print actions without deleting
#   PR_NUMBER                 (optional)  if set, only consider this pull request (for pull_request closed events)
#
# Usage:
#   etc/scripts/delete_stale_pr_branches.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STALE_DAYS="${STALE_DAYS:-7}"
PROTECTED_BRANCHES="${PROTECTED_BRANCHES:-}"
DRY_RUN="${DRY_RUN:-0}"
PR_NUMBER="${PR_NUMBER:-}"

resolve_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    echo "$GITHUB_REPOSITORY"
    return
  fi

  local remote_url
  remote_url="$(git -C "$SCRIPT_DIR/../.." remote get-url origin 2>/dev/null || true)"

  case "$remote_url" in
    git@github.com:*)
      echo "${remote_url#git@github.com:}" | sed 's/\.git$//'
      ;;
    https://github.com/*)
      echo "${remote_url#https://github.com/}" | sed 's/\.git$//'
      ;;
    *)
      echo "Could not resolve GITHUB_REPOSITORY from git remote." >&2
      exit 1
      ;;
  esac
}

ensure_gh_auth() {
  if [ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
    echo "GITHUB_TOKEN or GH_TOKEN is required." >&2
    exit 1
  fi

  export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"
}

is_always_protected_branch() {
  local branch="$1"

  # Default branch and release tags (v1.2.3, etc.) must never be deleted.
  [ "$branch" = "main" ] && return 0
  [[ "$branch" =~ ^v[0-9] ]] && return 0

  return 1
}

is_protected_branch() {
  local branch="$1"
  local protected

  if is_always_protected_branch "$branch"; then
    return 0
  fi

  for protected in $PROTECTED_BRANCHES; do
    if [ "$branch" = "$protected" ]; then
      return 0
    fi
  done

  return 1
}

tag_exists() {
  local repo="$1"
  local name="$2"

  gh api "repos/${repo}/git/refs/tags/${name}" >/dev/null 2>&1
}

branch_exists() {
  local repo="$1"
  local branch="$2"

  gh api "repos/${repo}/git/refs/heads/${branch}" >/dev/null 2>&1
}

open_pr_on_branch() {
  local repo="$1"
  local branch="$2"

  [ "$(gh pr list --repo "$repo" --state open --head "$branch" --json number --jq 'length')" -gt 0 ]
}

closed_long_enough() {
  local closed_at="$1"
  local cutoff_epoch now closed_epoch

  if [ "$STALE_DAYS" -eq 0 ]; then
    return 0
  fi

  now="$(date -u +%s)"
  closed_epoch="$(date -u -d "$closed_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$closed_at" +%s)"
  cutoff_epoch=$((now - STALE_DAYS * 86400))

  [ "$closed_epoch" -le "$cutoff_epoch" ]
}

delete_branch() {
  local repo="$1"
  local branch="$2"

  if is_always_protected_branch "$branch"; then
    echo "Refusing to delete protected branch ${branch}." >&2
    exit 1
  fi

  if tag_exists "$repo" "$branch"; then
    echo "Refusing to delete branch ${branch}: a release tag with this name exists." >&2
    exit 1
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "DRY_RUN: would delete branch ${branch}"
    return 0
  fi

  # Only delete branch refs (refs/heads/*). Release tags live under refs/tags/* and are never touched.
  gh api -X DELETE "repos/${repo}/git/refs/heads/${branch}" >/dev/null
  echo "Deleted branch ${branch}"
}

process_pr() {
  local repo="$1"
  local number="$2"
  local branch closed_at

  read -r branch closed_at < <(
    gh pr view "$number" --repo "$repo" --json headRefName,closedAt --jq '[.headRefName, .closedAt] | @tsv'
  )

  if [ -z "$closed_at" ] || [ "$closed_at" = "null" ]; then
    echo "Skipping PR #${number}: not closed."
    return 0
  fi

  if is_protected_branch "$branch"; then
    echo "Skipping PR #${number}: protected branch or release ref ${branch}."
    return 0
  fi

  if tag_exists "$repo" "$branch"; then
    echo "Skipping PR #${number}: release tag ${branch} exists."
    return 0
  fi

  if ! closed_long_enough "$closed_at"; then
    echo "Skipping PR #${number}: closed within the last ${STALE_DAYS} day(s)."
    return 0
  fi

  if open_pr_on_branch "$repo" "$branch"; then
    echo "Skipping PR #${number}: open PR still uses ${branch}."
    return 0
  fi

  if ! branch_exists "$repo" "$branch"; then
    echo "Skipping PR #${number}: branch ${branch} already deleted."
    return 0
  fi

  echo "PR #${number} (${branch}) closed at ${closed_at}"
  delete_branch "$repo" "$branch"
}

list_closed_prs() {
  local repo="$1"

  gh pr list \
    --repo "$repo" \
    --state closed \
    --limit 500 \
    --json number \
    --jq '.[].number'
}

main() {
  local repo number

  ensure_gh_auth
  repo="$(resolve_repo)"

  echo "Repository: ${repo}"
  echo "Stale threshold: ${STALE_DAYS} day(s)"
  echo "Always protected: main, release refs matching v*"
  if [ -n "$PROTECTED_BRANCHES" ]; then
    echo "Also protected: ${PROTECTED_BRANCHES}"
  fi

  if [ -n "$PR_NUMBER" ]; then
    process_pr "$repo" "$PR_NUMBER"
    exit 0
  fi

  while IFS= read -r number; do
    [ -n "$number" ] || continue
    process_pr "$repo" "$number" || true
  done < <(list_closed_prs "$repo")
}

main "$@"

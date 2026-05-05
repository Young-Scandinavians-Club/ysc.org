#!/usr/bin/env bash
# PR CI: detect query-shaped diffs, run mix ci.query_explain, optional OpenRouter, set GITHUB_OUTPUT.
#
# Env (required in CI): BASE_SHA, HEAD_SHA, GITHUB_REPOSITORY
# Optional: GITHUB_OUTPUT (GitHub Actions), OPENROUTER_API_KEY, OPENROUTER_MODEL, COMMENT_DIR
#
# Writes GITHUB_OUTPUT keys:
#   skip=true|false   — true when no query-shaped additions in lib/**/*.ex (excluding *_test.exs)
#   comment_path=...  — markdown for the PR comment when skip=false

set -euo pipefail

: "${BASE_SHA:?BASE_SHA is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMMENT_DIR="${COMMENT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/ysc-query-explain.XXXXXX")}"
mkdir -p "$COMMENT_DIR"

write_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s\n' "$1" >>"$GITHUB_OUTPUT"
  fi
}

heuristic_match=false
if git diff "${BASE_SHA}" "${HEAD_SHA}" -- 'lib/**/*.ex' ':(exclude)lib/**/*_test.exs' 2>/dev/null |
  grep '^+' | grep -v '^+++' |
  grep -qE '\bfrom\s*\(|\bjoin\s*\(|dynamic\s*\(|fragment\s*\(|subquery\s*\(|union_all\s*\(|\bexcept\s*\(|\bintersect\s*\('; then
  heuristic_match=true
fi

if [ "$heuristic_match" != true ]; then
  write_output "skip=true"
  write_output "comment_path="
  exit 0
fi

write_output "skip=false"

changed_files="${COMMENT_DIR}/changed_files.txt"
git diff --name-only "${BASE_SHA}" "${HEAD_SHA}" -- 'lib/' |
  grep '\.ex$' |
  grep -v '_test\.exs$' |
  sort -u >"$changed_files"

export GITHUB_SHA="${GITHUB_SHA:-${HEAD_SHA}}"
export GITHUB_BASE_REF="${GITHUB_BASE_REF:-}"

mix ci.query_explain \
  --changed-files "$changed_files" \
  --heuristic-matched \
  --output-json "${COMMENT_DIR}/result.json" \
  --output-markdown "${COMMENT_DIR}/comment.md"

if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  if out=$(bash "${SCRIPT_DIR}/query_explain_openrouter.sh" "${COMMENT_DIR}/result.json" 2>/dev/null); then
    if [ -n "$out" ]; then
      printf '\n%s\n' "$out" >>"${COMMENT_DIR}/comment.md"
    fi
  fi
fi

write_output "comment_path=${COMMENT_DIR}/comment.md"

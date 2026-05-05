#!/usr/bin/env bash
# Local: run mix ci.query_explain for lib/*.ex changes in a given scope (staged vs HEAD, or branch vs main).
#
# Usage: query_explain_local.sh staged|main
#
# Env:
#   MIX_ENV          should be test (Makefile sets it)
#   QUERY_EXPLAIN_OUT  optional output directory (default: repo/.query-explain)
#   QUERY_EXPLAIN_BASE optional ref for main mode (default: origin/main, else main)
#   OPENROUTER_API_KEY optional — same appendix as CI

set -euo pipefail

MODE="${1:?usage: query_explain_local.sh staged|main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

OUT="${QUERY_EXPLAIN_OUT:-$REPO_ROOT/.query-explain}"
mkdir -p "$OUT"

changed="$OUT/changed_files.txt"
: >"$changed"

base_ref=""

if [ "$MODE" = "staged" ]; then
  git diff --cached --name-only -- lib/ |
    grep '\.ex$' |
    grep -v '_test\.exs$' |
    sort -u >"$changed" || true
elif [ "$MODE" = "main" ]; then
  base_ref="${QUERY_EXPLAIN_BASE:-}"
  if [ -z "$base_ref" ]; then
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
      base_ref="origin/main"
    elif git rev-parse --verify main >/dev/null 2>&1; then
      base_ref="main"
    else
      echo "Neither origin/main nor main exists. Try: git fetch origin main" >&2
      exit 1
    fi
  fi
  merge_base=$(git merge-base HEAD "$base_ref")
  git diff "$merge_base...HEAD" --name-only -- lib/ |
    grep '\.ex$' |
    grep -v '_test\.exs$' |
    sort -u >"$changed" || true
else
  echo "Unknown mode: $MODE (use staged or main)" >&2
  exit 1
fi

if [ ! -s "$changed" ]; then
  echo "No lib/*.ex changes (excluding *_test.exs) in this scope."
  exit 0
fi

GITHUB_SHA="$(git rev-parse HEAD)"
export GITHUB_SHA
GITHUB_BASE_REF="${base_ref}"
export GITHUB_BASE_REF

mix ci.query_explain \
  --changed-files "$changed" \
  --output-json "$OUT/result.json" \
  --output-markdown "$OUT/comment.md"

if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  if out=$(bash "${SCRIPT_DIR}/query_explain_openrouter.sh" "$OUT/result.json" 2>/dev/null); then
    if [ -n "$out" ]; then
      printf '\n%s\n' "$out" >>"$OUT/comment.md"
    fi
  fi
fi

echo ""
echo "Wrote:"
echo "  $OUT/result.json"
echo "  $OUT/comment.md"

#!/usr/bin/env bash
# Append an LLM-written summary (Markdown) to stdout from a ci.query_explain JSON file.
# Requires: curl, jq, OPENROUTER_API_KEY. Non-fatal on failure (caller may ignore stderr).

set -u

json_path="${1:?usage: query_explain_openrouter.sh RESULT.json}"

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo "query_explain_openrouter: jq or curl missing; skipping LLM." >&2
  exit 0
fi

OPENROUTER_API="${OPENROUTER_API:-https://openrouter.ai/api/v1/chat/completions}"
OPENROUTER_MODEL="${OPENROUTER_MODEL:-deepseek/deepseek-v4-flash}"
REPO_SLUG="${GITHUB_REPOSITORY:-unknown/repo}"
referer="${OPENROUTER_REFERER:-https://github.com/${REPO_SLUG}}"

req_tmp=$(mktemp)
resp_tmp=$(mktemp)
cleanup() {
  rm -f "$req_tmp" "$resp_tmp"
}
trap cleanup EXIT

# shellcheck disable=SC2016
system='You are a PostgreSQL performance reviewer. You ONLY use the JSON payload (SQL + EXPLAIN text per target). The database in CI is nearly empty: plans are shape-only; do not claim production row counts.

Output Markdown only:
- Start with "## LLM summary" (exact heading).
- Then one short subsection per target id (### `id`).
- 3–6 bullets each: plan shape, index vs seq scan (if visible), obvious risks, one "verify with real data" caveat.
- No preamble, no wrapping the whole response in a code fence.'

if ! jq -n \
  --arg model "$OPENROUTER_MODEL" \
  --arg sys "$system" \
  --rawfile payload "$json_path" \
  '{
    model: $model,
    messages: [
      { role: "system", content: $sys },
      { role: "user", content: ($payload | fromjson | tojson) }
    ]
  }' >"$req_tmp"; then
  echo "query_explain_openrouter: jq build failed" >&2
  exit 0
fi

code=$(
  curl -sS --max-time 30 -o "$resp_tmp" -w "%{http_code}" \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "HTTP-Referer: ${referer}" \
    -H "X-Title: ysc query explain" \
    -d @"$req_tmp" \
    "$OPENROUTER_API" || echo "000"
)

if [ "$code" != "200" ]; then
  echo "query_explain_openrouter: OpenRouter HTTP $code" >&2
  exit 0
fi

text=$(jq -r '.choices[0].message.content // empty' "$resp_tmp")
if [ -z "$text" ] || [ "$text" = "null" ]; then
  echo "query_explain_openrouter: empty model response" >&2
  exit 0
fi

printf '%s\n\n' "$text"

#!/usr/bin/env bash
# preflight_parallel.sh - Run all CI checks in parallel where possible (faster)
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_colors.sh
. "$SCRIPT_DIR/_colors.sh"

echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo "${BOLD}                      🚀 PREFLIGHT CHECKS (PARALLEL)                        ${RESET}"
echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "${TEAL}Running CI checks in parallel for faster execution...${RESET}"
echo ""

echo "${BOLD}Ensuring PostgreSQL is running...${RESET}"
docker compose -f "${DOCKER_COMPOSE_FILE:-etc/docker/docker-compose.yml}" up -d postgres || true
DBNAME=postgres "$SCRIPT_DIR/_wait_db_connection.sh"
echo "${GREEN}✓ PostgreSQL is ready${RESET}"
echo ""

# ── Phase 1: Sequential prerequisites ────────────────────────────────────────
echo "${BOLD}[Phase 1] Installing dependencies...${RESET}"
if ! mix deps.get; then
  echo "${RED}✗ Dependencies installation failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Dependencies installed${RESET}"
echo ""

# ── Phase 2: Compile (sequential — gates credo, sobelow, and tests) ───────────
# Running compile alone avoids races with other mix tasks that also write to _build/dev.
echo "${BOLD}[Phase 2] Compiling with warnings as errors...${RESET}"
if ! mix compile --warnings-as-errors; then
  echo "${RED}✗ Compilation failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Compilation successful${RESET}"
echo ""

# ── Phase 3: Parallel checks that do not touch _build ────────────────────────
echo "${BOLD}[Phase 3] Running parallel checks (format, deps audit, shell scripts)...${RESET}"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

(
  mix format --check-formatted >"$tmpdir/format.log" 2>&1 &&
    echo "✓ format" >"$tmpdir/format.status" ||
    echo "✗ format" >"$tmpdir/format.status"
) &
pid_format=$!

(
  mix deps.audit --ignore-file config/mix_audit.ignore >"$tmpdir/audit.log" 2>&1 &&
    echo "✓ deps.audit" >"$tmpdir/audit.status" ||
    echo "✗ deps.audit" >"$tmpdir/audit.status"
) &
pid_audit=$!

(
  make shell-lint shell-format-check >"$tmpdir/shell.log" 2>&1 &&
    echo "✓ shell" >"$tmpdir/shell.status" ||
    echo "✗ shell" >"$tmpdir/shell.status"
) &
pid_shell=$!

wait $pid_format $pid_audit $pid_shell

format_status=$(cat "$tmpdir/format.status")
audit_status=$(cat "$tmpdir/audit.status")
shell_status=$(cat "$tmpdir/shell.status")

if [[ "$format_status" == "✗ format" ]]; then
  echo "${RED}✗ Code format check failed. Run make format to fix.${RESET}"
  cat "$tmpdir/format.log"
  exit 1
fi

if [[ "$audit_status" == "✗ deps.audit" ]]; then
  echo "${RED}✗ Dependency audit failed${RESET}"
  cat "$tmpdir/audit.log"
  exit 1
fi

if [[ "$shell_status" == "✗ shell" ]]; then
  echo "${RED}✗ Shell script checks failed${RESET}"
  cat "$tmpdir/shell.log"
  exit 1
fi

echo "${GREEN}✓ Code formatting is correct${RESET}"
echo "${GREEN}✓ Dependency audit passed${RESET}"
echo "${GREEN}✓ Shell scripts OK${RESET}"
echo ""

# ── Phase 4: Parallel checks that read compiled _build/dev artifacts ──────────
# credo and sobelow read from _build/dev (compiled above); test uses _build/test.
# All three are safe to run in parallel since no concurrent writes to the same env.
echo "${BOLD}[Phase 4] Running parallel checks (credo, sobelow, tests)...${RESET}"

(
  mix credo --strict >"$tmpdir/credo.log" 2>&1 &&
    echo "✓ credo" >"$tmpdir/credo.status" ||
    echo "✗ credo" >"$tmpdir/credo.status"
) &
pid_credo=$!

(
  mix sobelow --skip --exit >"$tmpdir/sobelow.log" 2>&1 &&
    echo "✓ sobelow" >"$tmpdir/sobelow.status" ||
    echo "✗ sobelow" >"$tmpdir/sobelow.status"
) &
pid_sobelow=$!

(
  MIX_ENV="test" mix test --cover >"$tmpdir/test.log" 2>&1 &&
    echo "✓ test" >"$tmpdir/test.status" ||
    echo "✗ test" >"$tmpdir/test.status"
) &
pid_test=$!

wait $pid_credo $pid_sobelow $pid_test

credo_status=$(cat "$tmpdir/credo.status")
sobelow_status=$(cat "$tmpdir/sobelow.status")
test_status=$(cat "$tmpdir/test.status")

failed=0

if [[ "$credo_status" == "✗ credo" ]]; then
  echo "${RED}✗ Credo checks failed${RESET}"
  cat "$tmpdir/credo.log"
  failed=1
else
  echo "${GREEN}✓ Credo checks passed${RESET}"
fi

if [[ "$sobelow_status" == "✗ sobelow" ]]; then
  echo "${RED}✗ Sobelow security audit failed${RESET}"
  cat "$tmpdir/sobelow.log"
  failed=1
else
  echo "${GREEN}✓ Sobelow security audit passed${RESET}"
fi

if [[ "$test_status" == "✗ test" ]]; then
  echo "${RED}✗ Tests failed${RESET}"
  cat "$tmpdir/test.log"
  failed=1
else
  echo "${GREEN}✓ All tests passed${RESET}"
fi

if [ $failed -eq 1 ]; then
  exit 1
fi

echo ""
echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}                      ✓ ALL PREFLIGHT CHECKS PASSED!                       ${RESET}"
echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "${TEAL}Your code is ready to be pushed to CI. All checks that run in GitHub Actions${RESET}"
echo "${TEAL}have passed locally.${RESET}"
echo ""

#!/usr/bin/env bash
# preflight.sh - Run all CI checks locally (compile, format, credo, sobelow, audit, tests)
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_colors.sh
. "$SCRIPT_DIR/_colors.sh"

echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo "${BOLD}                           🚀 PREFLIGHT CHECKS                              ${RESET}"
echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "${TEAL}Running all CI checks that would run in GitHub Actions...${RESET}"
echo ""

echo "${BOLD}Ensuring PostgreSQL is running...${RESET}"
docker compose -f "${DOCKER_COMPOSE_FILE:-etc/docker/docker-compose.yml}" up -d postgres || true
DBNAME=postgres "$SCRIPT_DIR/_wait_db_connection.sh"
echo "${GREEN}✓ PostgreSQL is ready${RESET}"
echo ""

step=0
total=8
next_step() {
  step=$((step + 1))
  echo "${BOLD}[$step/$total] $1${RESET}"
}

next_step "Installing dependencies..."
if ! mix deps.get; then
  echo "${RED}✗ Dependencies installation failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Dependencies installed${RESET}"
echo ""

next_step "Compiling with warnings as errors..."
if ! mix compile --warnings-as-errors; then
  echo "${RED}✗ Compilation failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Compilation successful${RESET}"
echo ""

next_step "Checking code format..."
if ! mix format --check-formatted; then
  echo "${RED}✗ Code format check failed. Run 'make format' to fix.${RESET}"
  exit 1
fi
echo "${GREEN}✓ Code formatting is correct${RESET}"
echo ""

next_step "Checking shell scripts (ShellCheck + shfmt)..."
if ! make shell-lint shell-format-check; then
  echo "${RED}✗ Shell script checks failed. Run 'make format' for shfmt, fix ShellCheck issues manually.${RESET}"
  exit 1
fi
echo "${GREEN}✓ Shell scripts OK${RESET}"
echo ""

next_step "Running Credo (strict mode)..."
if ! mix credo --strict; then
  echo "${RED}✗ Credo checks failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Credo checks passed${RESET}"
echo ""

next_step "Running Sobelow (security audit)..."
if ! mix sobelow --skip --exit; then
  echo "${RED}✗ Sobelow security audit failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Sobelow security audit passed${RESET}"
echo ""

next_step "Running dependency audit..."
if ! mix deps.audit; then
  echo "${RED}✗ Dependency audit failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Dependency audit passed${RESET}"
echo ""

next_step "Running test suite with coverage..."
if ! MIX_ENV="test" mix test --cover; then
  echo "${RED}✗ Tests failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ All tests passed${RESET}"
echo ""

echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}                      ✓ ALL PREFLIGHT CHECKS PASSED!                       ${RESET}"
echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "${TEAL}Your code is ready to be pushed to CI. All checks that run in GitHub Actions${RESET}"
echo "${TEAL}have passed locally.${RESET}"
echo ""

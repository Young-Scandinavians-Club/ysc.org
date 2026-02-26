#!/usr/bin/env bash
# preflight.sh - Run all CI checks locally (compile, format, credo, sobelow, audit, tests)

set -e

# Check if formatting variables are passed as environment variables
if [ -z "$BOLD" ] || [ -z "$RESET" ] || [ -z "$RED" ] || [ -z "$GREEN" ] || [ -z "$TEAL" ]; then
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  TEAL=$(tput setaf 6)
fi

echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo "${BOLD}                           🚀 PREFLIGHT CHECKS                              ${RESET}"
echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "${TEAL}Running all CI checks that would run in GitHub Actions...${RESET}"
echo ""

echo "${BOLD}Ensuring PostgreSQL is running...${RESET}"
docker-compose -f "${DOCKER_COMPOSE_FILE:-etc/docker/docker-compose.yml}" up -d postgres || true
DBNAME=postgres ./etc/scripts/_wait_db_connection.sh true
echo "${GREEN}✓ PostgreSQL is ready${RESET}"
echo ""

echo "${BOLD}[1/8] Installing dependencies...${RESET}"
if ! mix deps.get; then
  echo "${RED}✗ Dependencies installation failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Dependencies installed${RESET}"
echo ""

echo "${BOLD}[2/8] Compiling with warnings as errors...${RESET}"
if ! mix compile --warnings-as-errors; then
  echo "${RED}✗ Compilation failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Compilation successful${RESET}"
echo ""

echo "${BOLD}[3/8] Checking code format...${RESET}"
if ! mix format --check-formatted; then
  echo "${RED}✗ Code format check failed. Run 'make format' to fix.${RESET}"
  exit 1
fi
echo "${GREEN}✓ Code formatting is correct${RESET}"
echo ""

echo "${BOLD}[4/8] Checking shell scripts (ShellCheck + shfmt)...${RESET}"
if ! make shell-lint shell-format-check; then
  echo "${RED}✗ Shell script checks failed. Run 'make format' for shfmt, fix ShellCheck issues manually.${RESET}"
  exit 1
fi
echo "${GREEN}✓ Shell scripts OK${RESET}"
echo ""

echo "${BOLD}[5/8] Running Credo (strict mode)...${RESET}"
if ! mix credo --strict; then
  echo "${RED}✗ Credo checks failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Credo checks passed${RESET}"
echo ""

echo "${BOLD}[6/8] Running Sobelow (security audit)...${RESET}"
if ! mix sobelow --skip --exit; then
  echo "${RED}✗ Sobelow security audit failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Sobelow security audit passed${RESET}"
echo ""

echo "${BOLD}[7/8] Running dependency audit...${RESET}"
if ! mix deps.audit; then
  echo "${RED}✗ Dependency audit failed${RESET}"
  exit 1
fi
echo "${GREEN}✓ Dependency audit passed${RESET}"
echo ""

echo "${BOLD}[8/8] Running test suite with coverage...${RESET}"
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

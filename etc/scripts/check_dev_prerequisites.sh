#!/usr/bin/env bash
# check_dev_prerequisites.sh - Verify all prerequisites are met before starting dev server

set -e

# Check if formatting variables are passed as environment variables
if [ -z "$BOLD" ] || [ -z "$RESET" ] || [ -z "$RED" ] || [ -z "$GREEN" ] || [ -z "$TEAL" ]; then
  # If not passed, set them here
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  TEAL=$(tput setaf 6)
fi

# Load environment variables from .env if it exists
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . .env
  set +a
fi

echo "${BOLD}🔍 Checking prerequisites...${RESET}"
echo ""

# Check environment variables
echo "${BOLD}→ Checking environment variables...${RESET}"
if [ -z "$STRIPE_SECRET" ]; then
  echo "${RED}✗ Required environment variable ${BOLD}STRIPE_SECRET${RESET}${RED} not set.${RESET}"
  echo "${TEAL}  Hint: Add it to your .env file (see .env.example)${RESET}"
  exit 1
fi
if [ -z "$STRIPE_PUBLIC_KEY" ]; then
  echo "${RED}✗ Required environment variable ${BOLD}STRIPE_PUBLIC_KEY${RESET}${RED} not set.${RESET}"
  echo "${TEAL}  Hint: Add it to your .env file (see .env.example)${RESET}"
  exit 1
fi
if [ -z "$STRIPE_WEBHOOK_SECRET" ]; then
  echo "${RED}✗ Required environment variable ${BOLD}STRIPE_WEBHOOK_SECRET${RESET}${RED} not set.${RESET}"
  echo "${TEAL}  Hint: Run stripe listen --forward-to localhost:4000/webhooks/stripe${RESET}"
  exit 1
fi
echo "${GREEN}✓ Environment variables configured${RESET}"
echo ""

# Check Docker
echo "${BOLD}→ Checking Docker containers...${RESET}"
if ! docker ps >/dev/null 2>&1; then
  echo "${RED}✗ Docker is not running${RESET}"
  echo "${TEAL}  Hint: Start Docker Desktop (macOS) or docker service (Linux)${RESET}"
  exit 1
fi

# Check PostgreSQL container
POSTGRES_RUNNING=$(docker ps --filter "name=postgres" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -c "postgres" || echo "0")
if [ "$POSTGRES_RUNNING" -eq "0" ]; then
  echo "${RED}✗ PostgreSQL container is not running${RESET}"
  echo "${TEAL}  Hint: Start containers with: docker-compose -f ${DOCKER_COMPOSE_FILE:-etc/docker/docker-compose.yml} up -d${RESET}"
  echo "${TEAL}  Or run: make dev-setup${RESET}"
  exit 1
fi
echo "${GREEN}✓ PostgreSQL container is running${RESET}"

# Check LocalStack container
LOCALSTACK_RUNNING=$(docker ps --filter "name=localstack" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -c "localstack" || echo "0")
if [ "$LOCALSTACK_RUNNING" -eq "0" ]; then
  echo "${RED}✗ LocalStack container is not running${RESET}"
  echo "${TEAL}  Hint: Start containers with: docker-compose -f ${DOCKER_COMPOSE_FILE:-etc/docker/docker-compose.yml} up -d${RESET}"
  echo "${TEAL}  Or run: make dev-setup${RESET}"
  exit 1
fi
echo "${GREEN}✓ LocalStack container is running${RESET}"
echo ""

# Check database connection
echo "${BOLD}→ Checking database connection...${RESET}"
if ! PGPASSWORD=${PGPASSWORD:-postgres} psql -h localhost -U postgres -d "${DBNAME:-ysc_dev}" -c "SELECT 1" >/dev/null 2>&1; then
  echo "${RED}✗ Cannot connect to database${RESET}"
  echo "${TEAL}  Hint: Wait for PostgreSQL to be ready or run: make dev-setup${RESET}"
  exit 1
fi
echo "${GREEN}✓ Database connection successful${RESET}"
echo ""

# Check database migrations
echo "${BOLD}→ Checking database migrations...${RESET}"
PENDING_MIGRATIONS=$(mix ecto.migrations 2>/dev/null | grep -c "down" || true)
if [ "$PENDING_MIGRATIONS" -gt "0" ]; then
  echo "${RED}✗ Database has pending migrations ($PENDING_MIGRATIONS migration(s) not applied)${RESET}"
  echo "${TEAL}  Hint: Run: mix ecto.migrate${RESET}"
  echo "${TEAL}  Or run: make setup-dev-db${RESET}"
  exit 1
fi
echo "${GREEN}✓ All migrations applied${RESET}"
echo ""

echo "${GREEN}${BOLD}✓ All checks passed!${RESET}"
echo ""
echo "${BOLD}🚀 Starting Phoenix server...${RESET}"
echo "${TEAL}Visit http://localhost:4000${RESET}"
echo ""

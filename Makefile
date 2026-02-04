# Basics
PROJECT_NAME 		:= ysc
SHELL 			:= /bin/bash

# Directory structure
DOCKER_DIR 		?= etc/docker
DOCKER_COMPOSE_FILE	?= $(DOCKER_DIR)/docker-compose.yml
RELEASE_DOCKERFILE 	?= $(DOCKER_DIR)/Dockerfile

# Versioning
VERSION_LONG 		:= $(shell git describe --first-parent --abbrev=10 --long --tags --dirty)
VERSION_SHORT 		:= $(shell echo $(VERSION_LONG) | cut -f 1 -d "-")
DATE_STRING 		:= $(shell date +'%m-%d-%Y')
GIT_HASH  		:= $(shell git rev-parse --verify HEAD)

# Formatting variables
BOLD 			:= $(shell tput bold)
RESET 			:= $(shell tput sgr0)
RED 			:= $(shell tput setaf 1)
GREEN 			:= $(shell tput setaf 2)
TEAL 			:= $(shell tput setaf 6)

# AWS configuration for local development
export AWS_ACCESS_KEY_ID 	?= fake
export AWS_SECRET_ACCESS_KEY 	?= secret
export PGPASSWORD 		?= postgres
export DBNAME 			?= ysc_dev

.DEFAULT_GOAL := help

##
# ~~~ Dev Targets ~~~
##

.PHONY: dev
dev: ## Start the local dev server
	@bash -c ' \
		echo "$(BOLD)🔍 Checking prerequisites...$(RESET)"; \
		echo ""; \
		\
		if [ -f .env ]; then \
			set -a; \
			. .env; \
			set +a; \
		fi; \
		\
		echo "$(BOLD)→ Checking environment variables...$(RESET)"; \
		if [ -z "$$STRIPE_SECRET" ]; then \
			echo "$(RED)✗ Required environment variable $(BOLD)STRIPE_SECRET$(RESET)$(RED) not set.$(RESET)"; \
			echo "$(TEAL)  Hint: Add it to your .env file (see .env.example)$(RESET)"; \
			exit 1; \
		fi; \
		if [ -z "$$STRIPE_PUBLIC_KEY" ]; then \
			echo "$(RED)✗ Required environment variable $(BOLD)STRIPE_PUBLIC_KEY$(RESET)$(RED) not set.$(RESET)"; \
			echo "$(TEAL)  Hint: Add it to your .env file (see .env.example)$(RESET)"; \
			exit 1; \
		fi; \
		if [ -z "$$STRIPE_WEBHOOK_SECRET" ]; then \
			echo "$(RED)✗ Required environment variable $(BOLD)STRIPE_WEBHOOK_SECRET$(RESET)$(RED) not set.$(RESET)"; \
			echo "$(TEAL)  Hint: Run stripe listen --forward-to localhost:4000/webhooks/stripe$(RESET)"; \
			exit 1; \
		fi; \
		echo "$(GREEN)✓ Environment variables configured$(RESET)"; \
		echo ""; \
		\
		echo "$(BOLD)→ Checking Docker containers...$(RESET)"; \
		if ! docker ps > /dev/null 2>&1; then \
			echo "$(RED)✗ Docker is not running$(RESET)"; \
			echo "$(TEAL)  Hint: Start Docker Desktop (macOS) or docker service (Linux)$(RESET)"; \
			exit 1; \
		fi; \
		\
		POSTGRES_RUNNING=$$(docker ps --filter "name=postgres" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -c "postgres" || echo "0"); \
		if [ "$$POSTGRES_RUNNING" -eq "0" ]; then \
			echo "$(RED)✗ PostgreSQL container is not running$(RESET)"; \
			echo "$(TEAL)  Hint: Start containers with: docker-compose -f $(DOCKER_COMPOSE_FILE) up -d$(RESET)"; \
			echo "$(TEAL)  Or run: make dev-setup$(RESET)"; \
			exit 1; \
		fi; \
		echo "$(GREEN)✓ PostgreSQL container is running$(RESET)"; \
		\
		LOCALSTACK_RUNNING=$$(docker ps --filter "name=localstack" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -c "localstack" || echo "0"); \
		if [ "$$LOCALSTACK_RUNNING" -eq "0" ]; then \
			echo "$(RED)✗ LocalStack container is not running$(RESET)"; \
			echo "$(TEAL)  Hint: Start containers with: docker-compose -f $(DOCKER_COMPOSE_FILE) up -d$(RESET)"; \
			echo "$(TEAL)  Or run: make dev-setup$(RESET)"; \
			exit 1; \
		fi; \
		echo "$(GREEN)✓ LocalStack container is running$(RESET)"; \
		echo ""; \
		\
		echo "$(BOLD)→ Checking database connection...$(RESET)"; \
		if ! PGPASSWORD=$$PGPASSWORD psql -h localhost -U postgres -d $$DBNAME -c "SELECT 1" > /dev/null 2>&1; then \
			echo "$(RED)✗ Cannot connect to database$(RESET)"; \
			echo "$(TEAL)  Hint: Wait for PostgreSQL to be ready or run: make dev-setup$(RESET)"; \
			exit 1; \
		fi; \
		echo "$(GREEN)✓ Database connection successful$(RESET)"; \
		echo ""; \
		\
		echo "$(BOLD)→ Checking database migrations...$(RESET)"; \
		PENDING_MIGRATIONS=$$(mix ecto.migrations 2>/dev/null | grep -c "down" || echo "0"); \
		if [ "$$PENDING_MIGRATIONS" -gt "0" ]; then \
			echo "$(RED)✗ Database has pending migrations ($$PENDING_MIGRATIONS migration(s) not applied)$(RESET)"; \
			echo "$(TEAL)  Hint: Run: mix ecto.migrate$(RESET)"; \
			echo "$(TEAL)  Or run: make setup-dev-db$(RESET)"; \
			exit 1; \
		fi; \
		echo "$(GREEN)✓ All migrations applied$(RESET)"; \
		echo ""; \
		\
		echo "$(GREEN)$(BOLD)✓ All checks passed!$(RESET)"; \
		echo ""; \
		echo "$(BOLD)🚀 Starting Phoenix server...$(RESET)"; \
		echo "$(TEAL)Visit http://localhost:4000$(RESET)"; \
		echo ""; \
		mix phx.server'

.PHONY: dev-setup
dev-setup:  ## Set up local dev environment
	@echo "$(BOLD)Setting up development environment...$(RESET)"
	@mix deps.get
	@docker-compose -f $(DOCKER_COMPOSE_FILE) up -d
	@./etc/scripts/_wait_db_connection.sh
	@if [ "$($(reset-db))" = "true" ]; then $(MAKE) reset-db; fi
	@$(MAKE) setup-s3
	@$(MAKE) setup-dev-db
	@echo "$(GREEN)Your local dev env is ready!$(RESET)"
	@echo "Run $(BOLD)make dev$(RESET) to start the server and then visit $(BOLD)http://localhost:4000/$(RESET)"

.PHONY: dev-services
dev-services:  ## Start Docker services (postgres, localstack, etc.)
	@echo "$(BOLD)Starting Docker services...$(RESET)"
	@docker-compose -f $(DOCKER_COMPOSE_FILE) up -d
	@./etc/scripts/_wait_db_connection.sh
	@echo "$(GREEN)Docker services are running!$(RESET)"

.PHONY: setup
setup: dev-setup

.PHONY: setup-s3
setup-s3:  ## Set up local S3 buckets
	@awslocal s3api create-bucket --bucket media || true
	@awslocal s3api put-bucket-cors --bucket media --cors-configuration file://etc/config/s3_bucket_cors_rules.json || true
	@awslocal s3api create-bucket --bucket expense-reports || true
	@echo "$(GREEN)Note: expense-reports bucket is backend-only (no CORS configured)$(RESET)"

.PHONY: shell
shell:  ## Open a shell in the dev container
	@iex -S mix

.PHONY: reset-db
reset-db:  ## Drop the local dev db
	@mix ecto.drop

.PHONY: setup-dev-db
setup-dev-db:  ## Create, migrate and seed the local dev database
	@mix ecto.create
	@mix ecto.migrate
	@mix run priv/repo/seeds.exs || true
	@mix run priv/repo/seeds_bookings.exs || true

.PHONY: tests
tests:  ## Run the test suite (starts postgres if needed)
	@echo "$(BOLD)Ensuring PostgreSQL is running...$(RESET)"
	@docker-compose -f $(DOCKER_COMPOSE_FILE) up -d postgres || true
	@DBNAME=postgres ./etc/scripts/_wait_db_connection.sh true
	@echo "$(BOLD)Running test suite...$(RESET)"
	@MIX_ENV=test mix test --cover

.PHONY: test
test: tests

.PHONY: tests-failed
tests-failed: test-failed

.PHONY: test-failed
test-failed:  ## Run the test suite for failed tests from previous run
	@MIX_ENV=test mix test --trace --failed

.PHONY: format
format:  ## Format the code
	@mix format

.PHONY: lint
lint:  ## Run the lint suite
	@mix credo --all
	@mix format --check-formatted

.PHONY: preflight
preflight:  ## Run all CI checks locally (compile, format, credo, sobelow, audit, tests)
	@echo "$(BOLD)════════════════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)                           🚀 PREFLIGHT CHECKS                              $(RESET)"
	@echo "$(BOLD)════════════════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "$(TEAL)Running all CI checks that would run in GitHub Actions...$(RESET)"
	@echo ""
	@echo "$(BOLD)Ensuring PostgreSQL is running...$(RESET)"
	@docker-compose -f $(DOCKER_COMPOSE_FILE) up -d postgres || true
	@DBNAME=postgres ./etc/scripts/_wait_db_connection.sh true
	@echo "$(GREEN)✓ PostgreSQL is ready$(RESET)"
	@echo ""
	@echo "$(BOLD)[1/7] Installing dependencies...$(RESET)"
	@mix deps.get || (echo "$(RED)✗ Dependencies installation failed$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Dependencies installed$(RESET)"
	@echo ""
	@echo "$(BOLD)[2/7] Compiling with warnings as errors...$(RESET)"
	@mix compile --warnings-as-errors || (echo "$(RED)✗ Compilation failed$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Compilation successful$(RESET)"
	@echo ""
	@echo "$(BOLD)[3/7] Checking code format...$(RESET)"
	@mix format --check-formatted || (echo "$(RED)✗ Code format check failed. Run 'make format' to fix.$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Code formatting is correct$(RESET)"
	@echo ""
	@echo "$(BOLD)[4/7] Running Credo (strict mode)...$(RESET)"
	@mix credo --strict || (echo "$(RED)✗ Credo checks failed$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Credo checks passed$(RESET)"
	@echo ""
	@echo "$(BOLD)[5/7] Running Sobelow (security audit)...$(RESET)"
	@mix sobelow --skip --exit || (echo "$(RED)✗ Sobelow security audit failed$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Sobelow security audit passed$(RESET)"
	@echo ""
	@echo "$(BOLD)[6/7] Running dependency audit...$(RESET)"
	@mix deps.audit || (echo "$(RED)✗ Dependency audit failed$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Dependency audit passed$(RESET)"
	@echo ""
	@echo "$(BOLD)[7/7] Running test suite with coverage...$(RESET)"
	@MIX_ENV=test mix test --cover || (echo "$(RED)✗ Tests failed$(RESET)" && exit 1)
	@echo "$(GREEN)✓ All tests passed$(RESET)"
	@echo ""
	@echo "$(BOLD)════════════════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(GREEN)$(BOLD)                      ✓ ALL PREFLIGHT CHECKS PASSED!                       $(RESET)"
	@echo "$(BOLD)════════════════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "$(TEAL)Your code is ready to be pushed to CI. All checks that run in GitHub Actions$(RESET)"
	@echo "$(TEAL)have passed locally.$(RESET)"
	@echo ""

.PHONY: preflight-parallel
preflight-parallel:  ## Run all CI checks in parallel where possible (faster)
	@echo "$(BOLD)════════════════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)                      🚀 PREFLIGHT CHECKS (PARALLEL)                        $(RESET)"
	@echo "$(BOLD)════════════════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "$(TEAL)Running CI checks in parallel for faster execution...$(RESET)"
	@echo ""
	@echo "$(BOLD)Ensuring PostgreSQL is running...$(RESET)"
	@docker-compose -f $(DOCKER_COMPOSE_FILE) up -d postgres || true
	@DBNAME=postgres ./etc/scripts/_wait_db_connection.sh true
	@echo "$(GREEN)✓ PostgreSQL is ready$(RESET)"
	@echo ""
	@echo "$(BOLD)[Phase 1] Installing dependencies...$(RESET)"
	@mix deps.get || (echo "$(RED)✗ Dependencies installation failed$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Dependencies installed$(RESET)"
	@echo ""
	@echo "$(BOLD)[Phase 2] Running parallel checks (format, deps audit, compile)...$(RESET)"
	@bash -c ' \
		set -e; \
		tmpdir=$$(mktemp -d); \
		trap "rm -rf $$tmpdir" EXIT; \
		( \
			mix format --check-formatted > $$tmpdir/format.log 2>&1 && \
			echo "✓ format" > $$tmpdir/format.status || \
			echo "✗ format" > $$tmpdir/format.status \
		) & \
		pid_format=$$!; \
		( \
			mix deps.audit > $$tmpdir/audit.log 2>&1 && \
			echo "✓ deps.audit" > $$tmpdir/audit.status || \
			echo "✗ deps.audit" > $$tmpdir/audit.status \
		) & \
		pid_audit=$$!; \
		( \
			mix compile --warnings-as-errors > $$tmpdir/compile.log 2>&1 && \
			echo "✓ compile" > $$tmpdir/compile.status || \
			echo "✗ compile" > $$tmpdir/compile.status \
		) & \
		pid_compile=$$!; \
		wait $$pid_format $$pid_audit $$pid_compile; \
		format_status=$$(cat $$tmpdir/format.status); \
		audit_status=$$(cat $$tmpdir/audit.status); \
		compile_status=$$(cat $$tmpdir/compile.status); \
		if [[ "$$format_status" == "✗ format" ]]; then \
			echo "$(RED)✗ Code format check failed. Run make format to fix.$(RESET)"; \
			cat $$tmpdir/format.log; \
			exit 1; \
		fi; \
		if [[ "$$audit_status" == "✗ deps.audit" ]]; then \
			echo "$(RED)✗ Dependency audit failed$(RESET)"; \
			cat $$tmpdir/audit.log; \
			exit 1; \
		fi; \
		if [[ "$$compile_status" == "✗ compile" ]]; then \
			echo "$(RED)✗ Compilation failed$(RESET)"; \
			cat $$tmpdir/compile.log; \
			exit 1; \
		fi; \
		echo "$(GREEN)✓ Code formatting is correct$(RESET)"; \
		echo "$(GREEN)✓ Dependency audit passed$(RESET)"; \
		echo "$(GREEN)✓ Compilation successful$(RESET)"; \
	'
	@echo ""
	@echo "$(BOLD)[Phase 3] Running parallel checks (credo, sobelow, tests)...$(RESET)"
	@bash -c ' \
		set -e; \
		tmpdir=$$(mktemp -d); \
		trap "rm -rf $$tmpdir" EXIT; \
		( \
			mix credo --strict > $$tmpdir/credo.log 2>&1 && \
			echo "✓ credo" > $$tmpdir/credo.status || \
			echo "✗ credo" > $$tmpdir/credo.status \
		) & \
		pid_credo=$$!; \
		( \
			mix sobelow --skip --exit > $$tmpdir/sobelow.log 2>&1 && \
			echo "✓ sobelow" > $$tmpdir/sobelow.status || \
			echo "✗ sobelow" > $$tmpdir/sobelow.status \
		) & \
		pid_sobelow=$$!; \
		( \
			MIX_ENV=test mix test --cover > $$tmpdir/test.log 2>&1 && \
			echo "✓ test" > $$tmpdir/test.status || \
			echo "✗ test" > $$tmpdir/test.status \
		) & \
		pid_test=$$!; \
		wait $$pid_credo $$pid_sobelow $$pid_test; \
		credo_status=$$(cat $$tmpdir/credo.status); \
		sobelow_status=$$(cat $$tmpdir/sobelow.status); \
		test_status=$$(cat $$tmpdir/test.status); \
		failed=0; \
		if [[ "$$credo_status" == "✗ credo" ]]; then \
			echo "$(RED)✗ Credo checks failed$(RESET)"; \
			cat $$tmpdir/credo.log; \
			failed=1; \
		else \
			echo "$(GREEN)✓ Credo checks passed$(RESET)"; \
		fi; \
		if [[ "$$sobelow_status" == "✗ sobelow" ]]; then \
			echo "$(RED)✗ Sobelow security audit failed$(RESET)"; \
			cat $$tmpdir/sobelow.log; \
			failed=1; \
		else \
			echo "$(GREEN)✓ Sobelow security audit passed$(RESET)"; \
		fi; \
		if [[ "$$test_status" == "✗ test" ]]; then \
			echo "$(RED)✗ Tests failed$(RESET)"; \
			cat $$tmpdir/test.log; \
			failed=1; \
		else \
			echo "$(GREEN)✓ All tests passed$(RESET)"; \
		fi; \
		exit $$failed; \
	'
	@echo ""
	@echo "$(BOLD)════════════════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(GREEN)$(BOLD)                      ✓ ALL PREFLIGHT CHECKS PASSED!                       $(RESET)"
	@echo "$(BOLD)════════════════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "$(TEAL)Your code is ready to be pushed to CI. All checks that run in GitHub Actions$(RESET)"
	@echo "$(TEAL)have passed locally.$(RESET)"
	@echo ""

.PHONY: clean-compose
clean-compose:  ## Remove docker containers and volumes
	@docker-compose -f $(DOCKER_COMPOSE_FILE) down -v --remove-orphans

.PHONY: clean-docker
clean-docker: clean-compose  ## Delete docker images, volumes and networks
	@echo "$(BOLD)** Cleaning up Docker resources...$(RESET)"
	@docker-compose -f $(DOCKER_COMPOSE_FILE) rm -f -s -v

.PHONY: clean-elixir
clean-elixir:  ## Clean up Elixir and Phoenix files
	@echo "$(BOLD)** Cleaning up Elixir files...$(RESET)"
	@mix clean
	@rm -rf _build/ deps/

.PHONY: clean
clean: clean-elixir clean-docker  ## Clean docker and elixir

##
# ~~~ iOS Build Targets ~~~
##

.PHONY: build-ios-ipad
build-ios-ipad:  ## Build the iOS app for iPad target
	@echo "$(BOLD)Building iOS app for iPad...$(RESET)"
	@xcodebuild -project native/swiftui/Ysc.xcodeproj \
		-scheme Ysc \
		-destination 'generic/platform=iOS' \
		-configuration Debug \
		build
	@echo "$(GREEN)Build complete!$(RESET)"

.PHONY: run-ios-ipad-simulator
run-ios-ipad-simulator:  ## Build and launch the iOS app in iPad simulator
	@echo "$(BOLD)Building and launching iOS app in iPad simulator...$(RESET)"
	@xcodebuild -project native/swiftui/Ysc.xcodeproj \
		-scheme Ysc \
		-destination 'platform=iOS Simulator,name=iPad' \
		-configuration Debug \
		-derivedDataPath build/ios \
		build
	@echo "$(BOLD)Finding iPad simulator...$(RESET)"
	@SIMULATOR_UDID=$$(xcrun simctl list devices | grep -i "iPad" | grep -E '\([0-9A-F-]{36}\)' | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'); \
	if [ -z "$$SIMULATOR_UDID" ]; then \
		echo "$(RED)No iPad simulator found. Please create one in Xcode.$(RESET)"; \
		exit 1; \
	fi; \
	echo "$(BOLD)Using simulator: $$SIMULATOR_UDID$(RESET)"; \
	echo "$(BOLD)Booting simulator...$(RESET)"; \
	xcrun simctl boot $$SIMULATOR_UDID 2>/dev/null || true; \
	open -a Simulator; \
	sleep 3; \
	APP_PATH=$$(find build/ios/Build/Products/Debug-iphonesimulator -name "Ysc.app" -type d | head -1); \
	if [ -z "$$APP_PATH" ]; then \
		echo "$(RED)Could not find built app at build/ios/Build/Products/Debug-iphonesimulator/Ysc.app$(RESET)"; \
		exit 1; \
	fi; \
	echo "$(BOLD)Installing app...$(RESET)"; \
	xcrun simctl install $$SIMULATOR_UDID "$$APP_PATH" || (echo "$(RED)Installation failed$(RESET)" && exit 1); \
	echo "$(BOLD)Launching app...$(RESET)"; \
	xcrun simctl launch $$SIMULATOR_UDID com.example.Ysc || (echo "$(RED)Launch failed$(RESET)" && exit 1); \
	echo "$(GREEN)App launched in iPad simulator!$(RESET)"

##
# ~~~ Release Targets ~~~
##

.PHONY: version
version:  ## Print the current version
	@echo $(VERSION_LONG)

.PHONY: release
release:  ## Build and tag a docker image for release
	@DOCKER_BUILDKIT=1 docker build -f $(RELEASE_DOCKERFILE) -t $(PROJECT_NAME):$(VERSION_LONG) .
	@docker tag $(PROJECT_NAME):$(VERSION_LONG) $(PROJECT_NAME):$(VERSION_SHORT)
	@docker tag $(PROJECT_NAME):$(VERSION_LONG) $(PROJECT_NAME):latest

.PHONY: deploy-sandbox
deploy-sandbox:  ## Deploy the sandbox application to Fly.io
	@echo "$(BOLD)Deploying sandbox application to Fly.io...$(RESET)"
	@echo "$(BOLD)Version: $(VERSION_LONG)$(RESET)"
	@fly deploy --dockerfile $(DOCKER_DIR)/Dockerfile -a ysc-sandbox -c etc/fly/fly-sandbox.toml --image-label $(VERSION_LONG) --build-arg BUILD_VERSION=$(VERSION_LONG)

.PHONY: shell-sandbox
shell-sandbox:  ## Open an IEx shell in the sandbox environment on Fly.io
	@echo "$(BOLD)Opening IEx console in sandbox environment...$(RESET)"
	@fly ssh console -a ysc-sandbox -C "/app/bin/ysc remote"

##
# ~~~ Make Helpers ~~~
##

.PHONY: help
help:  ## Print this make target help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make $(TEAL)<target>$(RESET)\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n$(TEAL)%s$(RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@printf "\n"

.PHONY: arg-%
arg-%: ARG  # Checks if param is present: make key=value
	@if [ "$($(*))" = "" ]; then \
		echo "$(RED)Missing param: $(BOLD)$(*)$(RESET)$(RED). Use '$(BOLD)make $(MAKECMDGOALS) $(*)=value$(RESET)$(RED)'$(RESET)" && exit 1; \
	fi

.PHONY: guard-%
guard-%: GUARD  ## Check if required environment variables are set
	@if [ -z "${${*}}" ]; then \
		echo "$(RED)Required environment variable $(BOLD)$*$(RESET)$(RED) not set.$(RESET)" && exit 1; \
	fi

.PHONY: GUARD ARG
GUARD:
ARG:

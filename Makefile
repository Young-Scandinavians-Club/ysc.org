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

# S3 (MinIO) credentials for local development
export AWS_ACCESS_KEY_ID 	?= minioadmin
export AWS_SECRET_ACCESS_KEY 	?= minioadmin
export PGPASSWORD 		?= postgres
export DBNAME 			?= ysc_dev

# LAN IP for exposing avatar/media image URLs when testing the mobile app
# (ysc-admin-mobile) on a physical device — `localhost:9000` only resolves to
# this machine, not the phone. Leave unset for normal web development.
# e.g. `make dev HOST=192.168.0.126`.
HOST ?=

.DEFAULT_GOAL := help

##
# ~~~ Dev Targets ~~~
##

.PHONY: dev
dev: ## Start the local dev server. HOST=<lan-ip> to expose avatar/media image URLs for mobile device testing
	@BOLD="$(BOLD)" RESET="$(RESET)" RED="$(RED)" GREEN="$(GREEN)" TEAL="$(TEAL)" \
		DOCKER_COMPOSE_FILE="$(DOCKER_COMPOSE_FILE)" \
		PGPASSWORD="$(PGPASSWORD)" DBNAME="$(DBNAME)" \
		./etc/scripts/check_dev_prerequisites.sh
	@set -a; [ -f .env ] && . .env; set +a; \
		if [ -n "$(HOST)" ]; then \
			export S3_AVATARS_PUBLIC_BASE_URL="http://$(HOST):9000/avatars"; \
			export S3_MEDIA_PUBLIC_BASE_URL="http://$(HOST):9000/media"; \
			echo "==> Exposing avatar/media image URLs on the LAN: http://$(HOST):9000"; \
		fi; \
		mix phx.server

.PHONY: dev-setup
dev-setup:  ## Set up local dev environment
	@echo "$(BOLD)Setting up development environment...$(RESET)"
	@./etc/scripts/install_hex.sh
	@mix deps.get
	@docker compose -f $(DOCKER_COMPOSE_FILE) up -d
	@./etc/scripts/_wait_db_connection.sh
	@if [ "$($(reset-db))" = "true" ]; then $(MAKE) reset-db; fi
	@$(MAKE) setup-dev-db
	@echo "$(GREEN)Your local dev env is ready!$(RESET)"
	@echo "Run $(BOLD)make dev$(RESET) to start the server and then visit $(BOLD)http://localhost:4000/$(RESET)"

# I always write this wrong. I'm too lazy to fix it so lets alias it to dev-setup.
.PHONY: setup-dev
setup-dev: dev-setup

.PHONY: dev-services
dev-services:  ## Start Docker services (postgres, minio, etc.)
	@echo "$(BOLD)Starting Docker services...$(RESET)"
	@docker compose -f $(DOCKER_COMPOSE_FILE) up -d
	@./etc/scripts/_wait_db_connection.sh
	@echo "$(GREEN)Docker services are running!$(RESET)"

.PHONY: setup
setup: dev-setup

.PHONY: setup-s3
setup-s3:  ## No-op: S3 buckets are created automatically by MinIO init when you run make dev-services
	@echo "$(GREEN)S3 buckets (media, expense-reports, avatars) are created automatically when MinIO starts.$(RESET)"

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
	@docker compose -f $(DOCKER_COMPOSE_FILE) up -d postgres || true
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

##@ Query EXPLAIN

.PHONY: query-explain-staged
query-explain-staged:  ## EXPLAIN + SQL for CI targets matching staged lib/*.ex (MIX_ENV=test → .query-explain/)
	@echo "$(BOLD)Query EXPLAIN (staged vs HEAD)$(RESET)"
	@docker compose -f $(DOCKER_COMPOSE_FILE) up -d postgres || true
	@DBNAME=postgres ./etc/scripts/_wait_db_connection.sh true
	@MIX_ENV=test bash "$(CURDIR)/etc/scripts/ci/query_explain_local.sh" staged

.PHONY: query-explain-main
query-explain-main:  ## EXPLAIN + SQL for CI targets vs main since merge-base (fetches origin/main; .query-explain/)
	@echo "$(BOLD)Query EXPLAIN (vs origin/main)$(RESET)"
	@docker compose -f $(DOCKER_COMPOSE_FILE) up -d postgres || true
	@DBNAME=postgres ./etc/scripts/_wait_db_connection.sh true
	@git fetch origin main --quiet 2>/dev/null || true
	@MIX_ENV=test bash "$(CURDIR)/etc/scripts/ci/query_explain_local.sh" main

# Shell scripts to lint/format (respects all .gitignore files)
SHELL_SCRIPTS := $(shell ./etc/scripts/list_lintable_shell_scripts.sh)

.PHONY: format
format:  ## Format the code (Elixir, shell scripts, and JSON/YAML/TOML)
	@mix format
	@if command -v shfmt >/dev/null 2>&1 && [ -n "$(SHELL_SCRIPTS)" ]; then \
		shfmt -w -i 2 -ci $(SHELL_SCRIPTS); \
	fi
	@if command -v dprint >/dev/null 2>&1; then \
		dprint fmt; \
	fi

.PHONY: config-format-check
config-format-check:  ## Check JSON/YAML/TOML formatting with dprint
	@command -v dprint >/dev/null 2>&1 || { echo "Install dprint: brew install dprint"; exit 1; }
	@dprint check

.PHONY: shell-lint
shell-lint:  ## Lint shell scripts with ShellCheck
	@command -v shellcheck >/dev/null 2>&1 || { echo "Install ShellCheck: brew install shellcheck"; exit 1; }
	@if [ -n "$(SHELL_SCRIPTS)" ]; then shellcheck $(SHELL_SCRIPTS); fi

.PHONY: shell-format-check
shell-format-check:  ## Check shell script formatting with shfmt
	@command -v shfmt >/dev/null 2>&1 || { echo "Install shfmt: brew install shfmt"; exit 1; }
	@if [ -n "$(SHELL_SCRIPTS)" ]; then shfmt -d -i 2 -ci $(SHELL_SCRIPTS); fi

.PHONY: dialyzer
dialyzer:  ## Run Dialyzer type checker (builds PLT on first run, cached after)
	@mix dialyzer

.PHONY: lint
lint:  ## Run the lint suite
	@mix credo --all
	@mix format --check-formatted
	@mix lint_notification_samples
	@$(MAKE) shell-lint shell-format-check config-format-check

.PHONY: preflight
preflight:  ## Run all CI checks locally (compile, format, credo, dialyzer, notification samples, sobelow, audit, tests)
	@BOLD="$(BOLD)" RESET="$(RESET)" RED="$(RED)" GREEN="$(GREEN)" TEAL="$(TEAL)" \
		DOCKER_COMPOSE_FILE="$(DOCKER_COMPOSE_FILE)" \
		./etc/scripts/preflight.sh

.PHONY: preflight-parallel
preflight-parallel:  ## Run all CI checks in parallel where possible (faster)
	@BOLD="$(BOLD)" RESET="$(RESET)" RED="$(RED)" GREEN="$(GREEN)" TEAL="$(TEAL)" \
		DOCKER_COMPOSE_FILE="$(DOCKER_COMPOSE_FILE)" \
		./etc/scripts/preflight_parallel.sh

.PHONY: clean-compose
clean-compose:  ## Remove docker containers and volumes
	@docker compose -f $(DOCKER_COMPOSE_FILE) down -v --remove-orphans

.PHONY: clean-docker
clean-docker: clean-compose  ## Delete docker images, volumes and networks
	@echo "$(BOLD)** Cleaning up Docker resources...$(RESET)"
	@docker compose -f $(DOCKER_COMPOSE_FILE) rm -f -s -v

.PHONY: clean-elixir
clean-elixir:  ## Clean up Elixir and Phoenix files
	@echo "$(BOLD)** Cleaning up Elixir files...$(RESET)"
	@mix clean
	@rm -rf _build/ deps/
	@rm -f priv/static/assets/*.gz priv/static/assets/*.br priv/static/assets/*.zst

.PHONY: clean
clean: clean-elixir clean-docker  ## Clean docker and elixir

##
# ~~~ Release Targets ~~~
##

.PHONY: version
version:  ## Print the current version
	@echo $(VERSION_LONG)

.PHONY: release-tag
release-tag:  ## Create a new release (update version in mix.exs, create git tag, commit and push). Use TAG=v1.0.0 to pass version
	@./etc/scripts/release.sh $(TAG)

.PHONY: release-github-notes
release-github-notes:  ## Create/update GitHub release body for TAG from PRs (OpenRouter). Needs OPENROUTER_API_KEY, GITHUB_TOKEN, TAG. DRY_RUN=1 only prints
	@test -n "$(TAG)" || (echo "Set TAG, e.g. make release-github-notes TAG=v1.2.0" >&2; exit 1)
	@./etc/scripts/update_github_release_notes.sh $(TAG)

.PHONY: release
release:  ## Build and tag a docker image for release
	@DOCKER_BUILDKIT=1 docker build -f $(RELEASE_DOCKERFILE) -t $(PROJECT_NAME):$(VERSION_LONG) .
	@docker tag $(PROJECT_NAME):$(VERSION_LONG) $(PROJECT_NAME):$(VERSION_SHORT)
	@docker tag $(PROJECT_NAME):$(VERSION_LONG) $(PROJECT_NAME):latest

##
# Fly.io — sandbox and production use different accounts.
#
# Local CLI: set tokens from each org (Fly dashboard → Access Tokens), then:
#   export FLY_SANDBOX_ACCESS_TOKEN=...   # optional if `fly auth login` is the sandbox user
#   export FLY_PROD_ACCESS_TOKEN=...      # optional if `fly auth login` is the production org user (do not reuse sandbox token)
# If FLY_API_TOKEN is exported in your shell (e.g. for CI), flyctl ignores `fly auth login`.
# Sandbox targets unset it when FLY_SANDBOX_ACCESS_TOKEN is unset so login works; or run: unset FLY_API_TOKEN
# Optional org slug checks (from `fly orgs list`) to catch wrong token:
#   export FLY_ORG_SANDBOX=your-sandbox-org
#   export FLY_ORG_PROD=your-prod-org
#
# GitHub: sandbox workflow uses secret FLY_SANDBOX_API_TOKEN (falls back to FLY_API_TOKEN);
#         production uses FLY_PROD_API_TOKEN only.
##

.PHONY: fly-verify-sandbox
fly-verify-sandbox:  ## Confirm credentials can access ysc-sandbox (uses FLY_SANDBOX_ACCESS_TOKEN if set)
	@set -e; \
	if [ -n "$${FLY_SANDBOX_ACCESS_TOKEN:-}" ]; then \
	  export FLY_API_TOKEN="$${FLY_SANDBOX_ACCESS_TOKEN}"; \
	else \
	  unset FLY_API_TOKEN; \
	fi; \
	"$(CURDIR)/etc/scripts/fly_verify_app_access.sh" ysc-sandbox "$${FLY_ORG_SANDBOX:-}"

.PHONY: fly-verify-prod
fly-verify-prod:  ## Confirm credentials can access ysc-prod (uses FLY_PROD_ACCESS_TOKEN if set)
	@set -e; \
	if [ -n "$${FLY_PROD_ACCESS_TOKEN:-}" ]; then \
	  export FLY_API_TOKEN="$${FLY_PROD_ACCESS_TOKEN}"; \
	else \
	  unset FLY_API_TOKEN; \
	fi; \
	"$(CURDIR)/etc/scripts/fly_verify_app_access.sh" ysc-prod "$${FLY_ORG_PROD:-}"

.PHONY: deploy-sandbox
deploy-sandbox: fly-verify-sandbox  ## Deploy the sandbox application to Fly.io
	@echo "$(BOLD)Deploying sandbox application to Fly.io...$(RESET)"
	@echo "$(BOLD)Version: $(VERSION_LONG)$(RESET)"
	@set -e; \
	if [ -n "$${FLY_SANDBOX_ACCESS_TOKEN:-}" ]; then \
	  export FLY_API_TOKEN="$${FLY_SANDBOX_ACCESS_TOKEN}"; \
	else \
	  unset FLY_API_TOKEN; \
	fi; \
	fly deploy --dockerfile $(DOCKER_DIR)/Dockerfile -a ysc-sandbox -c etc/fly/fly-sandbox.toml --image-label $(VERSION_LONG) --build-arg BUILD_VERSION=$(VERSION_LONG)

.PHONY: deploy-prod
deploy-prod: fly-verify-prod  ## Deploy production to Fly (ensures 2+ started machines first; same prep as CI)
	@echo "$(BOLD)Ensuring at least 2 started machines on ysc-prod...$(RESET)"
	@set -e; \
	if [ -n "$${FLY_PROD_ACCESS_TOKEN:-}" ]; then \
	  export FLY_API_TOKEN="$${FLY_PROD_ACCESS_TOKEN}"; \
	else \
	  unset FLY_API_TOKEN; \
	fi; \
	"$(CURDIR)/etc/scripts/fly_ensure_min_started_machines.sh" ysc-prod 2
	@echo "$(BOLD)Deploying production application to Fly.io...$(RESET)"
	@echo "$(BOLD)Version: $(VERSION_LONG)$(RESET)"
	@set -e; \
	if [ -n "$${FLY_PROD_ACCESS_TOKEN:-}" ]; then \
	  export FLY_API_TOKEN="$${FLY_PROD_ACCESS_TOKEN}"; \
	else \
	  unset FLY_API_TOKEN; \
	fi; \
	fly deploy \
	  --dockerfile $(DOCKER_DIR)/Dockerfile \
	  -a ysc-prod \
	  -c etc/fly/fly-prod.toml \
	  --local-only \
	  --build-arg BUILD_VERSION=$(VERSION_LONG) \
	  --image-label $(VERSION_LONG)

.PHONY: shell-sandbox
shell-sandbox: fly-verify-sandbox  ## Open an IEx shell in the sandbox environment on Fly.io
	@echo "$(BOLD)Opening IEx console in sandbox environment...$(RESET)"
	@set -e; \
	if [ -n "$${FLY_SANDBOX_ACCESS_TOKEN:-}" ]; then \
	  export FLY_API_TOKEN="$${FLY_SANDBOX_ACCESS_TOKEN}"; \
	else \
	  unset FLY_API_TOKEN; \
	fi; \
	fly ssh console -a ysc-sandbox -C "/app/bin/ysc remote"

.PHONY: shell-prod
shell-prod: fly-verify-prod  ## Open an IEx shell in production on Fly.io
	@echo "$(BOLD)Opening IEx console in production...$(RESET)"
	@set -e; \
	if [ -n "$${FLY_PROD_ACCESS_TOKEN:-}" ]; then \
	  export FLY_API_TOKEN="$${FLY_PROD_ACCESS_TOKEN}"; \
	else \
	  unset FLY_API_TOKEN; \
	fi; \
	fly ssh console -a ysc-prod -C "/app/bin/ysc remote"

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

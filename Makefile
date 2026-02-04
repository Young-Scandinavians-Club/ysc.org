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
		if [ -f .env ]; then \
			set -a; \
			. .env; \
			set +a; \
		fi; \
		if [ -z "$$STRIPE_SECRET" ]; then \
			echo "$(RED)Required environment variable $(BOLD)STRIPE_SECRET$(RESET)$(RED) not set.$(RESET)"; \
			exit 1; \
		fi; \
		if [ -z "$$STRIPE_PUBLIC_KEY" ]; then \
			echo "$(RED)Required environment variable $(BOLD)STRIPE_PUBLIC_KEY$(RESET)$(RED) not set.$(RESET)"; \
			exit 1; \
		fi; \
		if [ -z "$$STRIPE_WEBHOOK_SECRET" ]; then \
			echo "$(RED)Required environment variable $(BOLD)STRIPE_WEBHOOK_SECRET$(RESET)$(RED) not set.$(RESET)"; \
			exit 1; \
		fi; \
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

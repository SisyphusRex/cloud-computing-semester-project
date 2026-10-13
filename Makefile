UV ?= uv
COMPOSE ?= docker compose
# Postgres from docker-compose; tests create and drop their own schemas in it.
TEST_DATABASE_URL ?= postgresql://li:li@localhost:55432/li

.PHONY: help install lint format test test-db dev-up dev-down dev-reset dev-logs

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

install: ## Create services/.venv with all workspace packages
	cd services && $(UV) sync --all-packages

lint: ## Ruff lint + format check
	cd services && $(UV) run ruff check . && $(UV) run ruff format --check .

format: ## Apply ruff fixes and formatting
	cd services && $(UV) run ruff check --fix . && $(UV) run ruff format .

test: ## Unit tests (database tests skip)
	cd services && $(UV) run pytest

test-db: ## All tests, against the compose Postgres
	$(COMPOSE) up -d --wait db
	cd services && DATABASE_URL=$(TEST_DATABASE_URL) $(UV) run pytest

dev-up: ## Build and start Postgres, migrations, ingest (:8081), search (:8082)
	$(COMPOSE) up --build -d

dev-down: ## Stop the stack (keeps data)
	$(COMPOSE) down

dev-reset: ## Stop the stack and delete the database volume
	$(COMPOSE) down -v

dev-logs: ## Follow API logs
	$(COMPOSE) logs -f ingest search

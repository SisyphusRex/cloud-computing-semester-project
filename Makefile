UV ?= uv
COMPOSE ?= docker compose
KUSTOMIZE ?= kustomize
KUBECONFORM ?= kubeconform
# Postgres from docker-compose; tests create and drop their own schemas in it.
TEST_DATABASE_URL ?= postgresql://li:li@localhost:55432/li

.PHONY: help doctor install lint format test test-db dev-up dev-down dev-reset dev-logs smoke \
	frontend-install frontend-dev frontend-test k8s-check

help: ## List targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

doctor: ## Check that the tools needed to run the app are installed
	@scripts/check-prereqs.sh

install: ## Create services/.venv with all workspace packages
	cd services && $(UV) sync --all-packages

lint: ## Ruff lint + format check
	cd services && $(UV) run ruff check . && $(UV) run ruff format --check .

format: ## Apply ruff fixes and formatting
	cd services && $(UV) run ruff check --fix . && $(UV) run ruff format .

test: ## Tests; database tests run only if DATABASE_URL is set
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

smoke: ## Smoke-test the running dev stack
	scripts/smoke-test.sh

frontend-install: ## Install frontend dependencies
	cd frontend && npm ci

frontend-dev: ## Frontend dev server on :5173 (proxies the APIs on :8081/:8082)
	cd frontend && npm run dev

frontend-test: ## Frontend lint, tests, build
	cd frontend && npm run lint && npm test && npm run build

# GKE CRDs (ManagedCertificate, BackendConfig, FrontendConfig) have no bundled
# schema, so kubeconform skips them; everything else is checked strictly.
k8s-check: ## Render the Kustomize overlays and validate them against Kubernetes schemas
	@out=$$(mktemp); trap 'rm -f $$out' EXIT; \
	for k in deploy/k8s/overlays/prod deploy/k8s/overlays/prod/migrate; do \
		echo "== $$k"; \
		$(KUSTOMIZE) build $$k > $$out || exit 1; \
		$(KUBECONFORM) -strict -summary -ignore-missing-schemas < $$out || exit 1; \
	done

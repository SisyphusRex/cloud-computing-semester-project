UV ?= uv
COMPOSE ?= docker compose
KUSTOMIZE ?= kustomize
KUBECONFORM ?= kubeconform
# Postgres from docker-compose; tests create and drop their own schemas in it.
TEST_DATABASE_URL ?= postgresql://li:li@localhost:55432/li

.PHONY: help doctor install lint format test test-db dev-up dev-down dev-reset dev-logs smoke \
	frontend-install frontend-dev frontend-test frontend-image k8s-check docs-check release-diff cloud-status cloud-pause cloud-resume \
	cloud-backup cloud-backup-sas cloud-restore cloud-create-admin cloud-admin report

help: ## List targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-24s %s\n", $$1, $$2}'

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

frontend-image: ## Build the nginx frontend image and check what it serves (DOCKER="sudo docker" if needed)
	scripts/test-frontend-image.sh

# GKE CRDs (ManagedCertificate, BackendConfig, FrontendConfig) have no bundled
# schema, so kubeconform skips them; everything else is checked strictly.
k8s-check: ## Render the Kustomize overlays and validate them against Kubernetes schemas
	@out=$$(mktemp); trap 'rm -f $$out' EXIT; \
	for k in deploy/k8s/overlays/prod deploy/k8s/overlays/prod/migrate; do \
		echo "== $$k"; \
		$(KUSTOMIZE) build $$k > $$out || exit 1; \
		$(KUBECONFORM) -strict -summary -ignore-missing-schemas < $$out || exit 1; \
		python3 scripts/check-k8s-namespaces.py < $$out || exit 1; \
	done

docs-check: ## Check that document links and repository paths resolve
	python3 scripts/check-docs.py

release-diff: ## What the next release would deploy (since the last prod-* tag), for review before merging to main
	@git fetch --tags --quiet 2>/dev/null || true
	@scripts/ci/release-summary.sh

cloud-status: ## Show whether the deployed environment is running (Cloud SQL, pods, load balancer)
	scripts/cloud-power.sh status

cloud-pause: ## Back up the database, then stop billable resources (keeps data and the API hostname; SKIP_BACKUP=1 skips the backup)
	scripts/cloud-power.sh pause

cloud-resume: ## Start the deployed environment again
	scripts/cloud-power.sh resume

cloud-backup: ## Back up the production database to Azure now
	scripts/cloud-power.sh backup

cloud-backup-sas: ## Create or renew the SAS that backups upload with; see ADR 0004
	scripts/cloud-backup-sas.sh

cloud-restore: ## List or restore backups (ARGS="list", ARGS="restore BLOB KEYFILE [--overwrite]")
	@test -n "$(ARGS)" || { echo 'usage: make cloud-restore ARGS="list"'; exit 2; }
	scripts/cloud-restore.sh $(ARGS)

cloud-create-admin: ## Make EMAIL an admin in prod (EMAIL=you@example.com); see ADR 0003
	@test -n "$(EMAIL)" || { echo 'usage: make cloud-create-admin EMAIL=you@example.com'; exit 2; }
	scripts/cloud-admin.sh create-admin "$(EMAIL)"

cloud-admin: ## Run li-admin in prod (ARGS="list", ARGS="add-user EMAIL --role professor")
	@test -n "$(ARGS)" || { echo 'usage: make cloud-admin ARGS="list"'; exit 2; }
	scripts/cloud-admin.sh $(ARGS)

report: ## Build the Milestone 2 report PDF (needs pdflatex, latexmk, IEEEtran)
	cd docs/milestones/m2_prototype_review/report && latexmk -pdf -interaction=nonstopmode -halt-on-error m2-report.tex
	cp docs/milestones/m2_prototype_review/report/m2-report.pdf docs/milestones/m2_prototype_review/CS6030_F26_PrototypeReview_LectureIndexer.pdf

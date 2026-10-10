.DEFAULT_GOAL := help
.PHONY: help env up down ps logs init clean engine-up engine-down trino-cli ingest-build download ingest storage-report

ENGINE ?= trino
PROFILE ?= m

help: ## List the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-15s %s\n", $$1, $$2}'

env: ## Create .env from .env.example if .env does not exist yet
	@test -f .env || cp .env.example .env

up: ## Start storage (RustFS, Postgres, Lakekeeper) and the Traefik proxy
	docker compose up -d --wait

down: ## Stop and remove the containers (volumes are kept)
	docker compose down

ps: ## Show the status of the containers
	docker compose ps -a

logs: ## Follow the logs of all services
	docker compose logs -f

init: ## Create the bucket and bootstrap Lakekeeper with the lakehouse warehouse (idempotent)
	docker compose run --rm rustfs-create-bucket
	docker compose run --rm lakekeeper-bootstrap

engine-up: ## Start one engine with a resource profile (ENGINE=trino PROFILE=s|m|l, default m)
	docker compose --env-file .env --env-file env/$(PROFILE).env --profile $(ENGINE) up -d --wait $(ENGINE)

engine-down: ## Stop and remove one engine container (ENGINE=trino)
	docker compose --profile $(ENGINE) rm --stop --force $(ENGINE)

trino-cli: ## Open the Trino CLI inside the trino container, on the lakehouse catalog
	docker compose exec trino trino --catalog lakehouse

ingest-build: ## Build the ingest image (sleipnir-ingest:INGEST_VERSION)
	docker compose --profile ingest build ingest

download: ## Download GHCN_YEARS (default 2025) + stations + countries into LANDING_DIR (idempotent)
	docker compose --profile ingest run --rm --no-deps ingest download.py

ingest: ## Load all batches of GHCN_YEARS into duckdb_bronze, skipping loaded ones (BATCH=YYYYMM for one)
	docker compose --env-file .env --env-file env/$(PROFILE).env --profile ingest run --rm ingest load.py

storage-report: ## Object-store bytes of duckdb_bronze + ENGINE_* namespaces; fails over STORAGE_BUDGET_GB
	docker compose --profile ingest run --rm -e ENGINE=$(ENGINE) storage-report

clean: ## DESTRUCTIVE: stop the stack and delete its volumes (all lake data and catalog metadata)
	docker compose --profile init down --volumes --remove-orphans

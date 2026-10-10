.DEFAULT_GOAL := help
.PHONY: help env up down ps logs init clean engine-up engine-down trino-cli ingest-build download ingest storage-report \
	dbt-image dbt-debug dbt-build dbt-run dbt-test dbt-full-refresh dbt-shell drop-run \
	cube-up cube-down cube-query cube-sql

ENGINE ?= trino
PROFILE ?= m
DBT_TARGET ?= trino
# Optional dbt passthrough: VARS='{maintenance: false}', ARGS='--select ghcn_daily', RUN_ID=<id>.
VARS ?=
ARGS ?=
RUN_ID ?=
# cube-query: Q=<n> picks bench/queries/cube/q<n>.json; ENDPOINT=load (rows) or sql (generated SQL).
Q ?=
ENDPOINT ?= load

dbt_vars = $(if $(VARS),--vars '$(VARS)')
dbt = docker compose --env-file .env --env-file env/$(PROFILE).env --profile dbt run --rm \
	-e DBT_TARGET=$(DBT_TARGET) -e RUN_ID=$(RUN_ID) dbt

help: ## List the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-17s %s\n", $$1, $$2}'

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

dbt-image: ## Build the dbt image (sleipnir-dbt:DBT_VERSION) with its packages baked in
	docker compose --profile dbt build dbt

dbt-debug: ## Check the dbt connection to DBT_TARGET (default trino)
	$(dbt) debug

dbt-build: ## dbt build (models + tests) on DBT_TARGET; VARS='{maintenance: false}' ARGS=... RUN_ID=...
	$(dbt) build $(dbt_vars) $(ARGS)

dbt-run: ## dbt run (models only); same VARS/ARGS/RUN_ID passthrough as dbt-build
	$(dbt) run $(dbt_vars) $(ARGS)

dbt-test: ## dbt test (data + unit tests); same VARS/ARGS/RUN_ID passthrough
	$(dbt) test $(dbt_vars) $(ARGS)

dbt-full-refresh: ## dbt build --full-refresh: rebuild the incremental models from bronze
	$(dbt) build --full-refresh $(dbt_vars) $(ARGS)

dbt-shell: ## Open a shell in the dbt container (project mounted at /app)
	docker compose --env-file .env --env-file env/$(PROFILE).env --profile dbt run --rm \
		-e DBT_TARGET=$(DBT_TARGET) -e RUN_ID=$(RUN_ID) --entrypoint bash dbt

drop-run: ## Drop the bench_RUN_ID_* namespaces via Trino and wait until their files are purged
	scripts/drop-run-namespaces.sh $(RUN_ID)

cube-up: ## Start Cube (API, refresh worker) and Cube Store; the engines are started on their own
	docker compose --profile cube up -d --wait cube-api cube-refresh-worker cubestore-router cubestore-worker

cube-down: ## Stop and remove the Cube and Cube Store containers (the Cube Store volume is kept)
	docker compose --profile cube rm --stop --force cube-api cube-refresh-worker cubestore-router cubestore-worker

cube-query: ## Run bench/queries/cube/qQ.json on the Cube REST API and print the result (Q=1..10; ENDPOINT=sql for the SQL)
	scripts/cube-query.sh $(Q) $(ENDPOINT)

cube-sql: ## Open psql on Cube's SQL API (Postgres protocol), from inside the postgres container
	docker compose exec -e PGPASSWORD=$$(docker compose exec -T cube-api printenv CUBEJS_SQL_PASSWORD) \
		postgres psql -h cube-api -p 15432 -U cube cube

clean: ## DESTRUCTIVE: stop the stack and delete its volumes (all lake data and catalog metadata)
	docker compose --profile init down --volumes --remove-orphans

.DEFAULT_GOAL := help
.PHONY: help env up down ps logs init clean engine-up engine-down trino-cli ingest-build download ingest storage-report \
	dbt-image dbt-debug dbt-build dbt-backfill dbt-check-unique dbt-run dbt-test dbt-full-refresh dbt-shell drop-run \
	cube-up cube-down cube-query cube-sql bench report

ENGINE ?= trino
PROFILE ?= m
DBT_TARGET ?= trino
# Optional dbt passthrough: VARS='{maintenance: false}', ARGS='--select ghcn_daily', RUN_ID=<id>.
VARS ?=
ARGS ?=
RUN_ID ?=
# dbt-backfill: months to build from scratch (default: the r2 scale, GHCN 2010-2025).
BACKFILL_START ?= 2010-01-01
BACKFILL_END ?= 2026-01-01
# cube-query: Q=<n> picks bench/queries/cube/q<n>.json; ENGINE=trino|duckdb picks the view; ENDPOINT=load (rows) or sql (generated SQL).
Q ?=
ENDPOINT ?= load
# bench: SUITE=b1|b2; B1 always measures DuckDB. ARGS is passed to dbt (B2).
SUITE ?=
bench_engine = $(if $(filter b1,$(SUITE)),duckdb,$(ENGINE))
harness = uv run --directory bench/harness

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

dbt-backfill: ## Build silver/gold from scratch one month at a time (BACKFILL_START/BACKFILL_END); needed from scale r2 up
	$(dbt) run --vars '{incremental_strategy: microbatch, microbatch_begin: "$(BACKFILL_START)", maintenance: false}' \
		--event-time-start $(BACKFILL_START) --event-time-end $(BACKFILL_END) $(ARGS)
	# In a microbatch run the maintenance post-hook would run once per batch, so it runs once per table here.
	$(dbt) run-operation maintain_table --args '{relation: $(DBT_TARGET)_silver.ghcn_daily}'
	$(dbt) run-operation maintain_table --args '{relation: $(DBT_TARGET)_gold.fct_weather_daily}'
	$(dbt) run-operation maintain_table --args '{relation: $(DBT_TARGET)_gold.agg_weather_monthly_country}'

dbt-check-unique: ## Check the silver natural key over the whole table, one year per query (after a backfill; not measured)
	$(dbt) run-operation assert_unique_by_year --args '{relation: $(DBT_TARGET)_silver.ghcn_daily, key_columns: [station_id, date, element]}'

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

cube-query: ## Run bench/queries/cube/qQ.json on the Cube REST API and print the result (Q=1..10; ENGINE=duckdb; ENDPOINT=sql for the SQL)
	ENGINE=$(ENGINE) scripts/cube-query.sh $(Q) $(ENDPOINT)

cube-sql: ## Open psql on Cube's SQL API (Postgres protocol), from inside the postgres container
	docker compose exec -e PGPASSWORD=$$(docker compose exec -T cube-api printenv CUBEJS_SQL_PASSWORD) \
		postgres psql -h cube-api -p 15432 -U cube cube

bench: ## Run one measured suite and append results/SUITE.parquet (SUITE=b1|b2 ENGINE=trino PROFILE=m ARGS=...)
	$(harness) python run.py $(SUITE) --engine $(bench_engine) --profile $(PROFILE) --args '$(ARGS)'

report: ## Print p50/p95 per engine x profile x scenario and time per step from results/*.parquet
	$(harness) python report.py

clean: ## DESTRUCTIVE: stop the stack and delete its volumes (all lake data and catalog metadata)
	docker compose --profile init down --volumes --remove-orphans

.DEFAULT_GOAL := help
.PHONY: help env up down ps logs init clean engine-up engine-down postgres-load trino-cli starrocks-init starrocks-mv-create starrocks-mv-refresh starrocks-mv-drop starrocks-cli ingest-build download ingest tpch tpch-check storage-report \
	dbt-image dbt-debug dbt-build dbt-backfill dbt-maintain dbt-check-unique dbt-run dbt-test dbt-full-refresh dbt-shell drop-run \
	cube-up cube-down b5-refresh cube-query cube-sql b2-campaign b6 b6-all bench bench-image bench-check report

ENGINE ?= trino
# tpch: integer TPC-H scale factor for D2 (SPEC §6).
SF ?= 1
PROFILE ?= m
DBT_TARGET ?= trino
# Optional dbt passthrough: VARS='{maintenance: false}', ARGS='--select ghcn_daily', RUN_ID=<id>.
VARS ?=
ARGS ?=
RUN_ID ?=
# SCHEMA_SUFFIX=_small writes <engine>_silver_small / <engine>_gold_small (the small scale, SPEC D-23); Postgres ignores it.
SCHEMA_SUFFIX ?=
# b2-campaign: r2 (full GHCN 2010-2025) or small (2025).
DATA_SCALE ?= r2
# dbt-backfill: months to build from scratch (default: the r2 scale, GHCN 1998-2025).
BACKFILL_START ?= 1998-01-01
BACKFILL_END ?= 2026-01-01
# cube-query: Q=<n> picks bench/queries/cube/q<n>.json; ENGINE=trino|duckdb|starrocks picks the view (trinomv: B5b table, trinopa|starrockspa: B5c rollups); ENDPOINT=load (rows) or sql (generated SQL).
Q ?=
ENDPOINT ?= load
# bench: SUITE=b1..b5; B1 always measures DuckDB. ARGS is passed to dbt (B2).
# B3-B5 read suites: DATASET=ghcn|tpch (tpch: B3 only, set SF to the loaded scale factor), SCENARIO=b5a|b5b|b5c (B5),
# QUERIES=q1,q2 to run a subset, DATA_SCALE to label the run (default r2, small for postgres, sf<SF> for tpch).
SUITE ?=
DATASET ?= ghcn
SCENARIO ?=
QUERIES ?=
# b6: VARIANT (see `make help`), MAINTAIN=trino|spark.
VARIANT ?=
RELATION ?=
MAINTAIN ?=
bench_engine = $(if $(filter b1,$(SUITE)),duckdb,$(ENGINE))
harness = uv run --directory bench/harness

# The service name `postgres` is the catalog Postgres; the benchmark one is postgres-bench.
engine_service = $(if $(filter postgres,$(ENGINE)),postgres-bench,$(ENGINE))

dbt_vars = $(if $(VARS),--vars '$(VARS)')
dbt = docker compose --env-file .env --env-file env/$(PROFILE).env --profile dbt run --rm \
	-e DBT_TARGET=$(DBT_TARGET) -e RUN_ID=$(RUN_ID) -e SCHEMA_SUFFIX=$(SCHEMA_SUFFIX) dbt

help: ## List the available targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-17s %s\n", $$1, $$2}'

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
	docker compose --env-file .env --env-file env/$(PROFILE).env --profile $(ENGINE) up -d --wait $(engine_service)

engine-down: ## Stop and remove one engine container (ENGINE=trino)
	docker compose --profile $(ENGINE) rm --stop --force $(engine_service)

postgres-load: ## Copy the small scale (2025 batches) of duckdb_bronze into postgres_bronze; replaces the tables (needs ENGINE=postgres up)
	docker compose --env-file .env --env-file env/$(PROFILE).env --profile postgres-load run --rm postgres-load

trino-cli: ## Open the Trino CLI inside the trino container, on the lakehouse catalog
	docker compose exec trino trino --catalog lakehouse

starrocks-init: ## Create the lakehouse external catalog and the MV database in the running StarRocks (idempotent)
	scripts/starrocks-init.sh

starrocks-mv-create: ## Create the B5a materialized views (one per gold table, empty until refreshed; idempotent)
	scripts/starrocks-mv.sh create

starrocks-mv-refresh: ## Refresh the B5a materialized views, one JSON line per MV with the seconds
	scripts/starrocks-mv.sh refresh

starrocks-mv-drop: ## Drop the B5a materialized views (the BE keeps the files for 1 h)
	scripts/starrocks-mv.sh drop

starrocks-cli: ## Open the mysql client inside the starrocks container
	docker compose exec starrocks mysql -h 127.0.0.1 -P 9030 -u root

ingest-build: ## Build the ingest image (sleipnir-ingest:INGEST_VERSION)
	docker compose --profile ingest build ingest

download: ## Download GHCN_YEARS (default 2025) + stations + countries into LANDING_DIR (idempotent)
	docker compose --profile ingest run --rm --no-deps ingest download.py

ingest: ## Load all batches of GHCN_YEARS into duckdb_bronze, skipping loaded ones (BATCH=YYYYMM for one)
	docker compose --env-file .env --env-file env/$(PROFILE).env --profile ingest run --rm ingest load.py

tpch: ## Generate D2 (derived from TPC-H) into duckdb_tpch at SF=<n>; replaces the tables
	docker compose --env-file .env --env-file env/$(PROFILE).env --profile ingest run --rm -e TPCH_SF=$(SF) ingest tpch.py

tpch-check: ## Run the 22 TPC-H queries on ENGINE=duckdb|trino|starrocks and compare row count + checksum with DuckDB (engine up for trino/starrocks)
	python3 bench/queries/tpch/check.py $(ENGINE)

storage-report: ## Object-store bytes of duckdb_bronze + ENGINE_* namespaces; fails over STORAGE_BUDGET_GB
	docker compose --profile ingest run --rm -e ENGINE=$(ENGINE) storage-report

dbt-image: ## Build the dbt image (sleipnir-dbt:DBT_VERSION) with its packages baked in
	docker compose --profile dbt build dbt

dbt-debug: ## Check the dbt connection to DBT_TARGET (default trino)
	$(dbt) debug

dbt-build: ## dbt build (models + tests) on DBT_TARGET; VARS='{maintenance: false}' ARGS=... RUN_ID=...
	$(dbt) build $(dbt_vars) $(ARGS)

dbt-backfill: ## Build silver/gold from scratch one month at a time (BACKFILL_START/BACKFILL_END); needed from scale r2 up
# An existing incremental table is only appended to: pass ARGS='--full-refresh --select ...' to rebuild its layout.
	$(dbt) run --vars '{incremental_strategy: microbatch, microbatch_begin: "$(BACKFILL_START)", maintenance: false}' \
		--event-time-start $(BACKFILL_START) --event-time-end $(BACKFILL_END) $(ARGS)
	# In a microbatch run the maintenance post-hook would run once per batch, so it runs once per table here.
	$(dbt) run-operation maintain_table --args '{relation: $(DBT_TARGET)_silver.ghcn_daily}'
	$(dbt) run-operation maintain_table --args '{relation: $(DBT_TARGET)_gold.fct_weather_daily}'
	$(dbt) run-operation maintain_table --args '{relation: $(DBT_TARGET)_gold.agg_weather_monthly_country}'

dbt-maintain: ## Run maintain_table once on RELATION=<schema.table> (B2 measures it through the harness)
	$(dbt) run-operation maintain_table --args '{relation: $(RELATION)}'

dbt-check-unique: ## Check the silver and fact natural keys over the whole tables, one year per query (after a backfill; not measured)
	$(dbt) run-operation assert_unique_by_year --args '{relation: $(DBT_TARGET)_silver.ghcn_daily, key_columns: [station_id, date, element]}'
	$(dbt) run-operation assert_unique_by_year --args '{relation: $(DBT_TARGET)_gold.fct_weather_daily, key_columns: [station_id, date]}'

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

cube-up: ## Start the Cube API and Cube Store (no refresh worker: it would build rollups in the middle of a measured run); the engines are started on their own
	docker compose --profile cube up -d --wait cube-api cubestore-router cubestore-worker

b5-refresh: ## Measured B5 refresh as its own row in results/b5.parquet (SCENARIO=b5b: dbt run of mv_weather_wide; b5c: Cube Store rollup build of ENGINE=trino|starrocks)
	ENGINE=$(ENGINE) PROFILE=$(PROFILE) scripts/cube-b5-refresh.sh $(SCENARIO)

cube-down: ## Stop and remove the Cube and Cube Store containers (the Cube Store volume is kept)
	docker compose --profile cube rm --stop --force cube-api cube-refresh-worker cubestore-router cubestore-worker

cube-query: ## Run bench/queries/cube/qQ.json on the Cube REST API and print the result (Q=1..10; ENGINE=duckdb; ENDPOINT=sql for the SQL)
	ENGINE=$(ENGINE) scripts/cube-query.sh $(Q) $(ENDPOINT)

cube-sql: ## Open psql on Cube's SQL API (Postgres protocol), from inside the postgres container
	docker compose exec -e PGPASSWORD=$$(docker compose exec -T cube-api printenv CUBEJS_SQL_PASSWORD) \
		postgres psql -h cube-api -p 15432 -U cube cube

bench-image: ## Build the bench image (sleipnir-bench:BENCH_VERSION) used by the read suites
	docker compose --profile bench build bench

bench: ## Run one measured suite and append results/SUITE.parquet (SUITE=b1..b5 ENGINE=trino PROFILE=m DATASET=ghcn|tpch SCENARIO=b5a|b5b|b5c QUERIES=q1,q2 ARGS=...)
	$(harness) python run.py $(SUITE) --engine $(bench_engine) --profile $(PROFILE) --args '$(ARGS)' \
		--dataset $(DATASET) --scenario '$(SCENARIO)' --queries '$(QUERIES)'

b2-campaign: ## B2 end to end on ENGINE=trino|spark|postgres PROFILE=m DATA_SCALE=r2|small: full build, maintenance, then each incremental strategy x3; resumable (finished steps are skipped)
	$(harness) python b2.py --engine $(ENGINE) --profile $(PROFILE) --scale $(DATA_SCALE)

b6: ## B6 layout variant on bench_* (VARIANT=baseline|file128|file256|file512|snappy|gzip|year|sorted|zorder; MAINTAIN=trino|spark adds the maintenance step)
	$(harness) python b6.py $(VARIANT) --engine $(ENGINE) --profile $(PROFILE) --maintain '$(MAINTAIN)'

b6-all: ## B6 over every variant, one after the other (one namespace alive at a time)
	$(harness) python b6.py all --engine $(ENGINE) --profile $(PROFILE) --maintain '$(MAINTAIN)'

bench-check: ## Self-check of the harness: parsers, result comparison and the run protocol
	$(harness) python parsers.py
	$(harness) python checks.py

report: ## Print p50/p95 per engine x profile x scenario and time per step from results/*.parquet
	$(harness) python report.py

clean: ## DESTRUCTIVE: stop the stack and delete its volumes (all lake data and catalog metadata)
	docker compose --profile init down --volumes --remove-orphans

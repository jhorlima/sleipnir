# Sleipnir

> Sleipnir is Odin's eight-legged horse, the fastest steed in the nine worlds.
> Here, many engines carry the same data, and the project measures how fast each one runs.

Sleipnir is a local, reproducible **lakehouse benchmark**. It ingests public CSV data into Apache Iceberg, models it in a medallion layout with dbt, serves it through a Cube semantic layer, and measures every step on several query engines under identical resource limits.

**Status:** work in progress (phase 1, MVP lakehouse). Results are not published yet.

## What it measures

| Suite | Question |
|---|---|
| B1 Ingestion | How fast does DuckDB load raw CSV into Iceberg? |
| B2 Transformation | How long does each dbt model take on Trino, Spark and Postgres, per incremental strategy? |
| B3 Direct reads | How fast do StarRocks, Trino, DuckDB and Postgres answer the same queries? |
| B4 Reads via Cube | How much does the semantic layer add? |
| B5 Acceleration | StarRocks materialized views vs Trino materialized views vs Cube Store pre-aggregations. |
| B6 Maintenance and layout | What do compaction, file size, codec and partitioning cost, and what do they buy? |

## Architecture

```
public CSV ─► DuckDB ─► Iceberg (RustFS + Lakekeeper REST catalog)
                              │
        dbt: Trino / Spark ─► silver / gold      (Postgres as a baseline)
                              │
     StarRocks · Trino · DuckDB · Postgres ─► Cube (+ Cube Store) ─► benchmark harness
```

| Layer | Choice |
|---|---|
| Object storage | RustFS (S3-compatible) |
| Table format / catalog | Apache Iceberg v2 · Lakekeeper (Iceberg REST) |
| Ingestion | DuckDB |
| Transformation | dbt Core 1.x on Trino, Spark 4.1, Postgres |
| Readers | StarRocks, Trino, DuckDB, Postgres |
| Semantic layer | Cube + Cube Store |
| Runtime | Docker Compose with profiles and per-service resource limits |

The full design, the decisions behind each choice and the benchmark protocol are in [`docs/SPEC.md`](docs/SPEC.md) (Portuguese; an English version follows once it stabilizes).

## Quick start

Requirements: Docker with Compose v2, `make`.

```sh
make env    # create .env from .env.example (local-only credentials)
make up     # start storage, catalog and proxy
make init   # create the bucket and the Iceberg warehouse (idempotent)
make help   # list every target
```

Web UIs are served through Traefik on `http://<service>.localhost` (for example `http://lakekeeper.localhost`). No other port is published by default.

## Methodology in one paragraph

Only one engine runs at a time. Every engine gets the same CPU and memory limits (profiles S, M, L). dbt runs with the same thread count everywhere. Every query result is checked against a DuckDB reference before its timing counts. Each step is recorded with versions and engine settings in `results/*.parquet`. A single run, meaning bronze plus one engine's silver and gold plus TPC-H data, fits in 10 GB, so it can be repeated on a free-tier object store.

## Data

- **NOAA GHCN-Daily**: public-domain daily weather observations from NOAA's National Centers for Environmental Information (NCEI).
- **TPC-H**: generated locally with DuckDB's `tpch` extension. Results derived from TPC-H are not comparable to published TPC-H results.

## License

[Apache License 2.0](LICENSE).

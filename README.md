# Sleipnir

> Sleipnir is Odin's eight-legged horse, the fastest steed in the nine worlds.
> Here, many engines carry the same data, and the project measures how fast each one runs.

Sleipnir is a local, reproducible **lakehouse benchmark**. It ingests public CSV data into Apache Iceberg, models it in a medallion layout with dbt, serves it through a Cube semantic layer, and measures every step on several query engines under identical resource limits.

**Status:** phase 2 (the benchmark) is done on a single laptop; the next round runs in the cloud with more workers. The full story is in the article ([`docs/blog/01-medium-local-benchmark.md`](docs/blog/01-medium-local-benchmark.md)), and every decision, failure and invalidated run is in the [lab notebook](docs/lab-notebook.md).

## The films

Three ~30 s films, rendered deterministically from HTML with [HyperFrames](https://github.com/heygen-com/hyperframes) (sources in [`media/`](media/); the files are also in [`docs/assets/films/`](docs/assets/films/), with silent copies).

### The race

Four engines on the same chart paper, and the result more CPU didn't buy.

https://github.com/user-attachments/assets/2b197800-630f-4a67-a09e-dc6fdab675d8

### One row, four engines

One real weather row, from Milan in 1763 to an answer in 16-34 ms.

https://github.com/user-attachments/assets/0dc92685-9947-4a48-9669-3a1c6755d272

### The night shift

What benchmarking on a laptop overnight actually looks like.

https://github.com/user-attachments/assets/7d0cc641-3cb4-4b57-a3ac-c7cef7042200

## Results at a glance

Single node, Docker VM on a Mac, NOAA GHCN-Daily (up to 3.97 B rows). Read them as "this setup", not as a ranking.

| | |
|---|---|
| Load 742 M rows (DuckDB) | 146 s |
| Build from scratch at 3.97 B rows (Trino, profile L) | 9,351 s |
| Whole-table query through Cube (Trino: M → L → L with object store at 2 CPU) | 32.4 → 65.3 → 24.6 s |
| Cube Store pre-aggregations | 16-34 ms at every scale |
| Sorting the fact table | half the size (0.73 → 0.38 GB) |
| Postgres vs Parquet, same 44 M rows | 35× the disk |

All numbers come from `results/*.parquet` (`make report`).

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

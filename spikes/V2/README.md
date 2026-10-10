# V2 - Trino materialized views on the Iceberg REST catalog

## Question
Does Trino 483's Iceberg connector support materialized views (MV) with an Iceberg REST catalog (Lakekeeper 0.14.0)? How are they refreshed?

## Answer: NOT SUPPORTED
`CREATE MATERIALIZED VIEW` fails on the REST catalog.

- **Verified locally** (Trino 483, Lakekeeper 0.14.0, `spikes/V2/proof.sh`):
  `Query failed: createMaterializedView is not supported for Iceberg REST catalog`.
  Logical views (`CREATE VIEW`) work on the same catalog (control in the script). The script created and dropped only `lakehouse.bench_v2`.
- **Source code** (tag 483, `TrinoRestCatalog.java`): `createMaterializedView`, `dropMaterializedView`, `renameMaterializedView`,
  `updateMaterializedViewColumnComment` throw `NOT_SUPPORTED`; `getMaterializedViewProperties` and `getMaterializedViewStorageTable`
  throw "The Iceberg REST catalog does not support materialized views". Same on `master` (checked 2026-10-10).
- The cause is in Trino, not Lakekeeper: Trino stores MV definitions in catalog-specific metadata (Hive Metastore/Glue style); the Iceberg REST spec has no MV endpoint (only tables and views).
  Documented: the Iceberg MV metadata format is still a community proposal (inferred: no catalog, Lakekeeper included, can host Trino MVs). No Lakekeeper MV support found in docs/issues (negative search result, not proof).

## What Trino MVs do elsewhere (documented, for the article; not usable here)
Source: https://trino.io/docs/current/connector/iceberg.html (483)
- An MV = view definition + a normal Iceberg storage table (`storage_schema` property picks the schema; Iceberg table properties such as `partitioning` apply). Readable by other engines in principle.
- `CREATE` does not populate it; `REFRESH MATERIALIZED VIEW` does. Full refresh = delete + insert; incremental = append only new source records (`iceberg.incremental-refresh-enabled`, default `true`); both atomic.
- Freshness: snapshot ids of source Iceberg tables are stored at refresh; with only Iceberg sources the connector knows when data is unchanged. `WHEN STALE` clause and grace period apply for non-Iceberg sources.
- Trino does not rewrite queries to MVs; a query must name the MV (it transparently reads the storage table or falls back to the view query if stale).
- Not covered by the docs for 483: `hide-storage-table` (not found in the 483 doc page; do not rely on it).

## Fallback for B5b (SPEC V2 fallback applies)
Build the "equivalent table" with dbt-trino as a regular Iceberg table, e.g. `trino_gold.mv_weather_wide` (same SQL as the StarRocks `mv_weather_wide`: `fct_weather_daily` x `dim_station` x `dim_date`).

- Materialization `table` (full rebuild = the equivalent of a full `REFRESH`, measured as its own step "refresh", run after the transformation and before reads, with `--vars '{maintenance: false}'`).
- Cube points to it via `sql_table` (per engine, as SPEC B5b already says); no rewrite involved.
- Extra storage = size of that table (`make storage-report`).
- Incremental refresh would be `incremental` materialization; keep it out of the first run so the comparison with StarRocks full refresh is like for like.
- Label it in the results/article as "MV-equivalent table (Trino Iceberg MVs unsupported on REST catalogs)".

## SPEC changes
- §15 V2: resolved, NOT SUPPORTED on REST catalog (error text above); fallback adopted.
- §10.3 B5b: replace "Trino materialized view" by a dbt `table` model; refresh step = `dbt run --select mv_weather_wide`; drop the `REFRESH MATERIALIZED VIEW` mention for Trino at §9 step 6 (StarRocks keeps it).
- Re-check on Trino upgrades (the `TrinoRestCatalog` code above).

## Sources
- https://trino.io/docs/current/connector/iceberg.html
- https://github.com/trinodb/trino/blob/483/plugin/trino-iceberg/src/main/java/io/trino/plugin/iceberg/catalog/rest/TrinoRestCatalog.java (lines ~828-872)

## Files
- `proof.sh`: reproducible proof (run from repo root, Trino and Lakekeeper up).

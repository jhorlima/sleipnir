# V3: does StarRocks rewrite queries to an async MV defined as a join over Iceberg (REST catalog)?

**Result: PARTIAL (documented as supported; not run locally).** Research only, nothing was started. Research date: 2026-10-10.

Labels: **[doc]** official docs/release notes, **[issue]** GitHub issue, **[inf]** inferred, **[verify]** the proof in this folder must check it.

## 1. Version to pin

**`starrocks/allin1-ubuntu:4.1.6`** (Docker Hub, 2026-10-01, amd64 + arm64; `fe-ubuntu`/`be-ubuntu` have the same tags). 4.1.6 notes are dated 2026-09-30. **[doc]**
- Do not use 4.1.0: unstable BE start in the container image, fixed in 4.1.1. **[doc: release notes 4.1]**
- 4.1.4-4.1.6 carry MV-rewrite and Iceberg fixes: no stale results after `rollback_to_snapshot` (4.1.4), staleness baseline and time-travel skip (4.1.5), incremental MV no longer deactivated by `rewrite_data_files` (4.1.6). **[doc]**
- Whether 4.1 is formally "stable" is unclear (docs selector listed 3.5 as stable, 4.0 latest, 4.1 candidate in some snapshots). 4.1.6 is the latest GA-tagged build; no `4.1.5` image tag exists on Docker Hub, which is harmless.

## 2. Answer

| Question | Finding |
|---|---|
| Async MV on external Iceberg tables | Supported (non-partitioned 3.0+, partitioned 3.1.4+, partition transforms 3.2.3, partition-level refresh 3.1.7/3.2.3). **[doc]** |
| Automatic rewrite on external-catalog MVs | Supported for Hive, Hudi, Iceberg, Paimon (not JDBC). `force_external_table_query_rewrite` is `true` by default since 3.3 per the CREATE MV reference; the data-lake page still says it is off for Hudi/JDBC, so set it explicitly. **[doc]** |
| Join MVs | SPJG rewrite supports inner/cross/left/right/full/semi/anti joins, Query Delta Join (query joins a superset), View Delta Join (query joins a subset, needs constraints), Join Derivability. **[doc]** |
| Aggregate over an SPJ MV | Supported (the query's `GROUP BY` runs on the MV scan). Aggregate rollup, `avg` -> `sum/count`, `count(distinct)` -> bitmap. **[doc]** |
| Union rewrite | `enable_materialized_view_union_rewrite` default `true`; partition union and predicate union. **[doc]** |
| Staleness | If base data changed since the last refresh, the query is **not** rewritten (partition level for Iceberg). Tolerance via MV property `mv_rewrite_staleness_second`. External catalogs have no strong consistency guarantee. **[doc]** |
| Confirm with EXPLAIN | `EXPLAIN`: the scan node `TABLE:` shows the MV name. `EXPLAIN LOGICAL`: `SCAN [mv_name]` with `MaterializedView: true`. **[doc]** |

Verdict: the SPEC §10.3 design is feasible on paper. Three conditions can break it and decide VALID/INVALID per query; the proof is built to expose each one:

1. **View Delta Join (Q1, Q3).** A query that joins fewer tables than the MV (fact + `dim_date`, or fact only) is only rewritten through View Delta Join, which needs `unique_constraints` (dimension) and `foreign_key_constraints` (fact) as table properties. **[doc]** The docs do not say whether those can be declared on Iceberg external tables (they are documented for OLAP tables/MVs). **[verify]** Mitigations if not: (a) have the Cube cubes for StarRocks always request the dimension joins (not controllable), (b) create one MV per join shape (fact+date, fact+station, fact+station+date) instead of one wide MV, (c) accept those queries as "not rewritten", and mark them invalid per §10.3. Q2 (all three tables) matches the MV exactly and should rewrite.
2. **Iceberg v2 partition change detection.** One doc sentence says partition-level change detection for Iceberg applies "only to Iceberg V1 tables" (data lake MV page). Our tables are v2 (Trino writes with row-level delete support). If detection falls back to table level, a rewrite may still work right after a full refresh, but partial/incremental freshness is lost. **[doc, ambiguous] [verify]** Because the SPEC refreshes after every transformation and the MV is a full-table `REFRESH`, this is acceptable as long as the post-refresh EXPLAIN shows the MV.
3. **Metadata cache.** The Iceberg metadata cache (60 s fresh window, background refresh ~10 min) "may affect MV rewrite, causing queries to miss the MV": when the snapshot id changes, partition metadata is dropped. **[doc]** After `REFRESH ... WITH SYNC MODE`, a first EXPLAIN may miss the MV. The harness should run one warm-up `EXPLAIN` and check; or lower the catalog cache TTL (`iceberg_meta_cache_ttl_sec`, listed by the docs, catalog-property syntax **[verify]**).

Other limits that apply to us: **[doc]**
- MV definition with `ORDER BY`, `LIMIT`, `UNION`, `GROUPING SETS`/`CUBE`/`ROLLUP` cannot be used for rewrite (the MV *key* clause `ORDER BY (cols)` in the DDL header is a sort key, not the query ORDER BY, and is fine).
- Window functions are not supported in rewrite: Q5 (rolling 7 day) and Cube's multi-stage queries (Q9, Q10) will not use the MV. Q5/Q6 are controls anyway (§10.3).
- `PERCENTILE_CONT(x, p)` (Q7) is not in the documented rollup mappings (`percentile_approx` -> `percentile_union` only). A query with it over an SPJ MV is a plain aggregate over the MV scan, so it may still rewrite through SPJG with the aggregate evaluated on MV rows; this is **[inf]** and Q7 is outside Q1-Q3, so just record it.
- Non-deterministic functions (`rand`, `uuid`, `sleep`) block rewrite.
- Bug: **[issue]** [#79345](https://github.com/StarRocks/starrocks/issues/79345) (open at research date, seen on 4.1.4): union compensation on Iceberg tables partitioned by time transforms uses an equality predicate on the partition start and silently drops rows. It only triggers when the MV is stale for some partitions and union rewrite is used. Our flow refreshes fully before reading, so avoid it by (a) never reading with a stale MV and (b) setting `enable_materialized_view_union_rewrite=false` in the benchmark session. Re-check the issue/PR #79346 before pinning.

## 3. External catalog (Iceberg REST + RustFS, static keys)

Source: the StarRocks Iceberg quick start (REST + MinIO) and the REST pages. **[doc]**

```sql
CREATE EXTERNAL CATALOG lakehouse
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "rest",
    "iceberg.catalog.uri" = "http://lakekeeper:8181/catalog",
    "iceberg.catalog.warehouse" = "lakehouse",
    "iceberg.catalog.vended-credentials-enabled" = "false",
    "aws.s3.endpoint" = "http://rustfs:9000",
    "aws.s3.enable_path_style_access" = "true",
    "aws.s3.region" = "local-01",
    "aws.s3.access_key" = "...",
    "aws.s3.secret_key" = "..."
);
```

- Same URI and warehouse as Trino (`config/trino/catalog`). `warehouse = lakehouse` (the Lakekeeper warehouse name). **[inf]**
- Vended credentials are opt-in via `iceberg.catalog.vended-credentials-enabled` (4.0+); the default is not stated in the docs, so set `false` explicitly, which also keeps StarRocks on the static keys like every other engine (SPEC §3.1). **[doc] [verify]**
- `aws.s3.region`: documented on the Glue REST page; quick start sets the region through env. **[doc]**
- Three-part names `lakehouse.trino_gold.fct_weather_daily` work as in cube-models.md. MVs live in an internal database (`sleipnir_mv`), not in the Iceberg catalog.

## 4. MV DDL (SPEC §10.3), see `02_mv.sql`

- `PARTITION BY date_trunc('month', date)` is the supported form for Iceberg `month(date)` partitioning: hour/day/month/year transforms map to `date_trunc('<unit>', col)`; bucket/truncate are not supported. **[doc: CREATE MATERIALIZED VIEW]** `fct_weather_daily` is `month(date)` partitioned (`partitioned_by_month`), so MV partitions align 1:1 with base partitions. The partition column must come from the partitioned base table (`f.date`); the unpartitioned dims (`dim_station`, `dim_date`) join in unpartitioned, so a change in a dim marks all partitions stale. **[doc] [inf]**
- `DISTRIBUTED BY HASH(station_id) BUCKETS n`, sort key `ORDER BY (country_code, date, station_id)`, `REFRESH MANUAL` (default). External-table MVs cannot refresh on base-table change anyway; only manual or fixed-interval. **[doc]**
- `PROPERTIES`: `force_external_table_query_rewrite=true`, `query_rewrite_consistency=checked` (default; values `disable|checked|loose|force_mv`), optional `mv_rewrite_staleness_second`. **[doc]**
- Refresh: `REFRESH MATERIALIZED VIEW sleipnir_mv.mv_weather_wide WITH SYNC MODE;` (blocks; time it). Partitions per refresh default `partition_refresh_number=1` since 3.3, so a first full build is N sequential month tasks; consider `"partition_refresh_number" = "-1"`? **[verify]** (the value semantics for "all" are not in the pages read).
- No `CREATE OR REPLACE`: `DROP MATERIALIZED VIEW IF EXISTS` then `CREATE`. **[doc]**
- Session: `enable_materialized_view_rewrite=true` (default for default-catalog MVs). Cube's MySQL connection must keep the default or the harness must `SET` it per connection.
- LEFT JOINs match Cube's SQL (many_to_one joins from the fact cube). Inner-join queries against a left-join MV are covered by Join Derivability with added `IS NOT NULL` predicates. **[doc]**

## 5. Compose and sizing

Recommendation: **`starrocks/allin1-ubuntu`, one service** (`compose.starrocks.yaml`). One cgroup limit is exactly "FE+BE sum" from SPEC §10.1 with no extra split knob, and a single `memswap_limit`. Separate `fe-ubuntu` + `be-ubuntu` (as in the quick start compose, with `depends_on` the FE healthcheck) is the alternative if allin1's config paths cannot be overridden; then the profile limit must be split FE/BE and recorded. Single-node: the allin1 image runs one FE and one BE; no replication issue (replication_num=1). **[doc: quick start uses allin1 and requires >= 4 GB Docker RAM]**

- Ports: 9030 (MySQL, Cube), 8030 (FE HTTP), 8040 (BE HTTP). Publish none (Cube reaches `starrocks:9030` on the compose network); optionally `127.0.0.1:9030`.
- Healthcheck: `mysql -h 127.0.0.1 -P 9030 -u root -N -e 'SHOW BACKENDS' | grep -q true` (the quick start's own healthchecks run `SHOW FRONTENDS`/`SHOW BACKENDS` and check alive). **[doc]** The `mysql` client exists in the allin1 image (the quick start runs it via `docker exec`). **[doc]**
- Memory (**[inf]**, must be verified by `SHOW BACKENDS` `MemLimit` and `docker stats`): BE `mem_limit` defaults to 90% of the server memory, soft limit 80% **[doc]**; whether the BE reads the cgroup limit instead of host RAM is not documented in the pages read. The FE JVM heap default (Doris-derived `-Xmx8192m`) is **not confirmed for StarRocks**; if it is 8 GB the S profile (4 GB) would be OOM-killed. Proposal to write in `config/starrocks/` and record in `engine_config`:

| Profile | Container limit | FE heap (`-Xmx`) | BE `mem_limit` |
|---|---|---|---|
| S | 4g | 1g | 2g |
| M | 8g | 2g | 5g |
| L | 12g | 2g | 9g |

  The rest is JVM non-heap + page cache + headroom. `run.sh` prints `fe.conf`/`be.conf` locations so the override can be mounted after the first run; the exact mount path in allin1 (`/data/deploy/starrocks/{fe,be}/conf` is the likely layout, **[verify]**).
- `swap`: `memswap_limit` equal to the limit, as in `compose/engines.yaml`.

## 6. Staleness check (manual part of the proof)

After the first run, with the stack still up: (1) EXPLAIN Q1_three_tables shows `mv_weather_wide`; (2) write a batch to `fct_weather_daily` through Trino (or `INSERT` one row); (3) EXPLAIN again: expected NOT rewritten; wait >= 60 s for the catalog cache or use a fresh session; (4) `REFRESH MATERIALIZED VIEW ... WITH SYNC MODE`; (5) EXPLAIN again: expected rewritten. Try `ALTER MATERIALIZED VIEW sleipnir_mv.mv_weather_wide SET ("mv_rewrite_staleness_second" = "3600")` to see the tolerant mode (not for the benchmark; INVALID-run risk). Optional debugging: `TRACE LOGS MV <query>` **[verify, command name from memory]**.

## 7. Impact on SPEC

- §14/§15 V3: record version `4.1.6`; status `documented as supported`, three open checks (View Delta Join on Iceberg constraints, v2 change detection, post-refresh metadata cache), proof ready in `spikes/V3`.
- §10.3 B5a: keep `force_external_table_query_rewrite=true`; add `query_rewrite_consistency=checked`, partition by `date_trunc('month', date)` is correct; add: the harness runs a warm-up EXPLAIN after the refresh, validates per query (invalid if `mv_weather_wide` is absent), and sets `enable_materialized_view_union_rewrite=false` (bug #79345). Say that Q1/Q3 may need View Delta Join and might not rewrite on a single wide MV; fallback: one MV per join shape, or record them as not accelerated (§15 fallback "document the limitation; Cube points at the MV" stays valid: Cube's `sql_table` can point at `sleipnir_mv.mv_weather_wide`, but then the StarRocks base cube changes shape).
- §10.1: StarRocks profile = one allin1 container; FE heap / BE `mem_limit` per profile in `config/starrocks/`.
- §4: StarRocks pinned `STARROCKS_VERSION=4.1.6` in `.env`.

## 8. Files and how to run

`compose.starrocks.yaml`, `01_catalog.sql`, `02_mv.sql`, `03_queries.sql`, `run.sh` (run from the repo root; needs the base stack and Trino gold tables; never during a benchmark, §benchmark-integrity 1). Cleanup: `docker compose -f compose.yaml -f spikes/V3/compose.starrocks.yaml --profile starrocks down -v`.

## Sources

- StarRocks 4.1 release notes: https://docs.starrocks.io/releasenotes/release-4.1/
- Docker Hub tags: https://hub.docker.com/r/starrocks/allin1-ubuntu/tags
- Query rewrite with MVs: https://docs.starrocks.io/docs/using_starrocks/async_mv/use_cases/query_rewrite_with_materialized_views/
- Data lake acceleration with MVs: https://docs.starrocks.io/docs/using_starrocks/async_mv/use_cases/data_lake_query_acceleration_with_materialized_views/
- CREATE MATERIALIZED VIEW: https://docs.starrocks.io/docs/sql-reference/sql-statements/materialized_view/CREATE_MATERIALIZED_VIEW/
- Async MV feature support: https://docs.starrocks.io/docs/using_starrocks/async_mv/feature-support-asynchronous-materialized-views/
- Iceberg quick start (REST + MinIO, compose): https://docs.starrocks.io/docs/quick_start/iceberg/
- All-in-one quick start: https://docs.starrocks.io/docs/quick_start/shared-nothing/
- Iceberg REST security (vended credentials): https://docs.starrocks.io/docs/data_source/catalog/iceberg/iceberg_rest_security/
- Iceberg REST (Glue/S3 Tables properties): https://docs.starrocks.io/docs/data_source/catalog/iceberg/iceberg_rest_s3/
- Data lake analytics feature support (metadata cache, delete files): https://docs.starrocks.io/docs/data_source/feature-support-data-lake-analytics/
- Memory management: https://docs.starrocks.io/docs/administration/management/resource_management/Memory_management/
- Issue #79345: https://github.com/StarRocks/starrocks/issues/79345

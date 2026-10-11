# V3: does StarRocks rewrite queries to an async MV defined as a join over Iceberg (REST catalog)?

**Result: PARTIAL.** The MV is created, refreshes and is used for queries whose join shape equals the MV's (fact + station + date). Queries that join fewer tables, which is every shape Cube generates, are not rewritten; View Delta Join did not work on Iceberg tables. Sections 1-8 are the research (2026-10-10); section 9 has the proof run on 4.1.6.

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

## 4. MV DDL (SPEC §10.3), see `mv_weather_wide.sql`

- `PARTITION BY date_trunc('month', date)` is the supported form for Iceberg `month(date)` partitioning: hour/day/month/year transforms map to `date_trunc('<unit>', col)`; bucket/truncate are not supported. **[doc: CREATE MATERIALIZED VIEW]** `fct_weather_daily` is `month(date)` partitioned (`partitioned_by_month`), so MV partitions align 1:1 with base partitions. The partition column must come from the partitioned base table (`f.date`); the unpartitioned dims (`dim_station`, `dim_date`) join in unpartitioned, so a change in a dim marks all partitions stale. **[doc] [inf]**
- `DISTRIBUTED BY HASH(station_id) BUCKETS n`, sort key `ORDER BY (country_code, date, station_id)`, `REFRESH MANUAL` (default). External-table MVs cannot refresh on base-table change anyway; only manual or fixed-interval. **[doc]**
- `PROPERTIES`: `force_external_table_query_rewrite=true`, `query_rewrite_consistency=checked` (default; values `disable|checked|loose|force_mv`), optional `mv_rewrite_staleness_second`. **[doc]**
- Refresh: `REFRESH MATERIALIZED VIEW sleipnir_mv.mv_weather_wide WITH SYNC MODE;` (blocks; time it). Partitions per refresh default `partition_refresh_number=1` since 3.3, so a first full build is N sequential month tasks; consider `"partition_refresh_number" = "-1"`? **[verify]** (the value semantics for "all" are not in the pages read).
- No `CREATE OR REPLACE`: `DROP MATERIALIZED VIEW IF EXISTS` then `CREATE`. **[doc]**
- Session: `enable_materialized_view_rewrite=true` (default for default-catalog MVs). Cube's MySQL connection must keep the default or the harness must `SET` it per connection.
- LEFT JOINs match Cube's SQL (many_to_one joins from the fact cube). Inner-join queries against a left-join MV are covered by Join Derivability with added `IS NOT NULL` predicates. **[doc]**

## 5. Compose and sizing

Recommendation: **`starrocks/allin1-ubuntu`, one service** (now `compose/engines.yaml`). One cgroup limit is exactly "FE+BE sum" from SPEC §10.1 with no extra split knob, and a single `memswap_limit`. Separate `fe-ubuntu` + `be-ubuntu` (as in the quick start compose, with `depends_on` the FE healthcheck) is the alternative if allin1's config paths cannot be overridden; then the profile limit must be split FE/BE and recorded. Single-node: the allin1 image runs one FE and one BE; no replication issue (replication_num=1). **[doc: quick start uses allin1 and requires >= 4 GB Docker RAM]**

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

`03_queries.sql` and `run.sh` (from the repo root, after `make engine-up ENGINE=starrocks PROFILE=m` and `make starrocks-init`; needs the Trino gold tables; never during a benchmark, §benchmark-integrity 1). Cleanup: `make engine-down ENGINE=starrocks` and `docker volume rm sleipnir_starrocks-meta sleipnir_starrocks-storage`.

## 9. Proof run (StarRocks 4.1.6, profile M, scale r2, 190,214,772 fact rows)

Service, catalog and Cube source are now part of the repo (`compose/engines.yaml`, `scripts/starrocks-init.sh`, `config/starrocks/entrypoint.sh`); the MV DDL of this proof is `mv_weather_wide.sql`. `03_queries.sql` has the hand-written shapes and the SQL Cube generates for Q1-Q3 (`Cube_Q1..3`); `run.sh` runs the proof. The first drafts (compose snippet, catalog and MV SQL) were replaced by those files.

### Answers to the open questions
| Question | Answer |
|---|---|
| FE heap default | `-Xmx8192m` (`start_fe.sh` default when `JAVA_OPTS` is unset; `fe.conf` of the image sets it to 8192m). It would not fit profile S, hence the entrypoint sets it to 25% of `ENGINE_MEMORY` (M: 2g). |
| Does the BE respect the limit | The BE has no `mem_limit` in the image's `be.conf`; the entrypoint sets it to 62.5% of `ENGINE_MEMORY` (M: `5G`) and `SHOW BACKENDS` reports `MemLimit: 4.500GB` (90% of it is the BE process limit). A query over the limit fails with `Memory of process exceed limit ... Limit: 4831838208` instead of killing the container. Whether the BE would read the cgroup on its own was not tested. |
| Config paths in allin1 | `/data/deploy/starrocks/{fe,be}/conf/{fe,be}.conf`; the image entrypoint appends `priority_networks` to them, so they are edited by a wrapper entrypoint (a read-only mount would break it), not mounted. |
| Vended credentials | `iceberg.catalog.vended-credentials-enabled=false` plus static keys works against RustFS (path style, region set); direct counts match Trino (190,214,772 / 133,039 / 5,844). |
| Catalog creation | `CREATE EXTERNAL CATALOG IF NOT EXISTS` is idempotent. |
| `REFRESH MANUAL` | Populates the MV at creation unless `DEFERRED` is given; the DDL uses `REFRESH DEFERRED MANUAL` so the first refresh is the measured one. The property `force_external_table_query_rewrite = true` is stored as `CHECKED`. |
| Metadata cache after the refresh | The first EXPLAIN after the refresh already used the MV (pass 1 = pass 2). |
| v2 change detection | Not a problem for this flow: after a full refresh the MV is rewritable (`query_rewrite_status: VALID`, trace says `NO_COMPENSATE`). |

### Refresh and storage
- `REFRESH ... WITH SYNC MODE` needs `SET query_timeout = 3600` in the same session: the SYNC statement itself is killed at 300 s (the first attempt failed at 301-303 s; a refresh that continued in the background took 158 s once most partitions were loaded).
- Clean refresh of 192 monthly partitions, 8 per task (`partition_refresh_number` default 8 in 4.1): **540 s and 589 s** in two runs (rows loaded: 190,214,772).
- After the refresh the BE compacts for about 10 minutes at 2-3 cores and up to 6.9 GiB of the 8 GiB container; a query issued during that time failed with BE memory exceeded. `run.sh` waits for the container CPU to drop below 10% before reading.
- MV size: 7.9 GB right after the refresh, **4.8 GB after compaction** (3072 tablets). Dropping an MV leaves its files in the BE trash for `catalog_trash_expire_second=3600`, so the volume peaked at 18 GB during the proof. The MV is the biggest storage item of one execution; it counts against the 10 GB budget (benchmark-integrity §6) together with bronze/silver/gold.

### Rewrite per query (`EXPLAIN` shows `mv_weather_wide`; session `enable_materialized_view_rewrite=true`, `enable_materialized_view_union_rewrite=false`)
| Query | Joined tables | Rewritten | Results equal with/without MV |
|---|---|---|---|
| Q1, hand-written, fact + `dim_date` | 2 | no | yes |
| Q1, hand-written, all three tables | 3 | **yes** | yes |
| Q2, hand-written (three tables) | 3 | **yes** | yes |
| Q3, hand-written, fact + station | 2 | no | yes |
| Q3, hand-written, fact only | 1 | no | yes |
| Q4 control (inner join with bounding box) | 2 | no | yes |
| **Cube Q1** (fact only, `DATE_FORMAT(CONVERT_TZ(...))` + `count(CONCAT(...))`) | 1 | **no** | not run (not rewritten) |
| **Cube Q2** (fact + station) | 2 | **no** | not run |
| **Cube Q3** (fact only) | 1 | **no** | not run |

Equality is on sorted rows with a 1e-9 relative tolerance: double sums change in the last digits depending on the order (e.g. `5036.999999999999` vs `5037.000000000001`).

Cube only joins the cubes a query touches, so its SQL never has the three tables of the MV: only an exact join shape is rewritten. Everything else needs View Delta Join. Tried on Iceberg: `ALTER TABLE lakehouse.trino_gold.dim_station SET ("unique_constraints" = "station_id")`, `dim_date` likewise, `foreign_key_constraints` on `fct_weather_daily` and on the MV. StarRocks accepts them on external tables and the MV trace changes from "no FK constraints" to "Rewrite ViewDelta failed: cannot compensate query by using PK/FK constraints", but no query is rewritten (the constraints were then cleared; the property stays on the table with an empty value). The unresolved part is whether outer-join elimination needs non-null FK columns, which Iceberg tables written by Trino cannot declare.

Consequence for B5a: with one wide MV, the benchmark rewrite check (SPEC §10.3) marks Cube Q1-Q3 invalid. Options: one MV per join shape Cube emits (fact only, fact + station, fact + date, fact + station + date), or point the Cube starrocks cube at the MV (`sql_table: sleipnir_mv.mv_weather_wide`, the cost is that the base cube changes shape), or record B5a as not accelerated for those queries.

### Cube on StarRocks (MySQL driver)
- Cube Q1-Q4 and Q6-Q10 return rows on the `starrocks_weather` view (16, 1951, 20, 5, 30, 192, 16, 192, 2246 rows).
- Q1-Q3 match a DuckDB reference over the same Iceberg tables (Q1 counts equal, Q2 1951 keys with 0 mismatches at 1e-9, Q3 20 stations with 0 mismatches).
- **Q5 (rolling 7 days) fails**: Cube's rolling window SQL uses `WITH RECURSIVE` and `CAST(... AS DATETIME(6))`; StarRocks 4.1.6 answers "Recursive CTE is not supported" and a syntax error on `DATETIME(6)`.

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

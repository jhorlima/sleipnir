# V4: does dbt-trino support `microbatch`?

**Result: SUPPORTED.** Checked against documentation and source code only, with nothing run locally. Research date: 2026-10-09.

Labels used below:
- **[doc]**: stated in official docs, a changelog or release notes.
- **[src]**: read in the adapter's source at a release tag.
- **[inf]**: inferred, not yet checked.

## 1. `microbatch` in dbt-trino

- Supported since **dbt-trino 1.9.0** (2024-12-20). The CHANGELOG lists it under Features as "Microbatch incremental strategy". **[doc]**
- `TrinoAdapter.valid_incremental_strategies()` returns `["append", "merge", "delete+insert", "microbatch"]`. **[src]**
- The dbt docs table "Supported incremental strategies by adapter" marks microbatch as supported for dbt-trino. **[doc]**
- How it works: `trino__get_incremental_microbatch_sql` runs a **delete+insert for each batch**. **[src]**
  1. `DELETE FROM target WHERE <event_time> >= TIMESTAMP '<batch start>' AND <event_time> < TIMESTAMP '<batch end>'`, plus any `incremental_predicates`.
  2. `INSERT INTO target SELECT ... FROM <temp relation>`.
  - It is **not** a MERGE, and it ignores `unique_key`.
- Requirements: dbt-core's standard microbatch configs, meaning `event_time`, `batch_size` and `begin`. Upstream models also need `event_time` so their inputs get filtered. **[doc]**
- Iceberg-only? No. The macro is plain DELETE + INSERT, so it works on any Trino connector that supports row-level `DELETE`. For Iceberg, row-level deletes need format v2. **[src] + [doc]**
- `concurrent_batches`: `Capability.MicrobatchConcurrency: Support.Full` is present at tag **v1.10.2** (2026-05-22) and missing at v1.10.0 and v1.10.1. It came from commit `95647b8f` ("Add microbatch concurrency capability support"). **[src]**
  - The CHANGELOG does not mention it.
  - The docs page "Parallel batch execution" still lists only Snowflake and BigQuery. That page is out of date. **[doc]**
  - dbt-core rules still apply. The first and last batch always run sequentially. Without an explicit override, a model that references `{{ this }}` runs its batches sequentially. **[doc]**
- Temp relation: `get_incremental_tmp_relation_type` returns `table` (not `view`) for multi-statement strategies, which are delete+insert, microbatch, and any strategy with a `unique_key`. Each batch therefore writes a temporary table before the DELETE + INSERT. This costs time that the per-batch timing will include. **[src]** The cost itself is **[inf]**.

### Caveats to check when the stack is up

1. **[inf]** SPEC §7.1 uses `event_time = date` (a DATE column). The macro compares it against `TIMESTAMP '<...>'` literals. Trino should coerce DATE to TIMESTAMP implicitly, but two things need confirming:
   - that the comparison is correct at batch boundaries, since dbt passes UTC datetimes;
   - that Iceberg still prunes partitions when the predicate applies to a coerced column.
2. **[inf]** Every batch commits two Iceberg snapshots, one for the DELETE and one for the INSERT.
   - The DELETE writes position-delete files unless the predicate lines up with identity partitions. If the table is partitioned by `month(date)`, the delete is row-level, not metadata-only.
   - Expect delete files to pile up, and plan compaction with `maintain_table`.
3. **[inf]** With `concurrent_batches=true`, several batches commit to the same Iceberg table at once. Optimistic concurrency can fail a commit through a conflict on the same partition or a REST catalog commit conflict. Test this before turning it on for the benchmark.

## 2. Latest stable versions (2026-10-09)

| Component | Version | Source |
|---|---|---|
| dbt-core 1.x | **1.12.5** (2026-09-15) | PyPI |
| dbt-adapters | 1.24.5 | PyPI |
| dbt-trino | **1.10.6** (2026-10-01) | PyPI, GitHub releases |
| dbt-trino dependency bound | `dbt-core>=1.8.0,<2.0` (set in 1.10.3); `dbt-adapters>=1.16,<2.0` (set in 1.10.1) | CHANGELOG |
| Trino (tested by dbt-trino) | **478**, plus Starburst Enterprise 482-e.1 and Starburst Galaxy | dbt-trino README, "Compatibility" |
| Trino (latest) | **483** (2026-07-17) | trino.io release notes |

dbt-trino uses the major.minor numbering of dbt, but 1.10.x is the newest dbt-trino line. Pairing it with dbt-core 1.12 falls inside the declared bound (`<2.0`). That pairing is not stated as tested anywhere. **[inf]**

## 3. Incremental strategies on Iceberg

| Strategy | dbt-trino | Notes |
|---|---|---|
| `append` (default) | yes | Plain INSERT. The temp relation is a view. |
| `merge` | yes | Trino `MERGE` on `unique_key`. The temp relation is a view (when `views_enabled`). |
| `delete+insert` | yes | DELETE matching keys or predicates, then INSERT. The temp relation is a table. |
| `microbatch` | yes (≥ 1.9.0) | delete+insert per batch on `event_time`. Concurrency is declared from 1.10.2. |
| `insert_overwrite` | **no** | Not in `valid_incremental_strategies`. |

Iceberg notes from the Trino 483 docs: **[doc]**
- v2 tables delete individual rows by writing **position delete files**. Format v2 is required for row-level deletes, and v2 is the default.
- v3 is experimental: row-level UPDATE, DELETE and OPTIMIZE are not supported. This fits the "keep v2" fallback for V6.
- A DELETE whose filter touches only identity-partition columns can drop whole partitions without row-level deletes.
- The docs do not describe how MERGE and UPDATE are executed internally. The usual Trino behaviour is position deletes plus new data files (merge-on-read). **[inf]**

## 4. Trino 483 Iceberg REST catalog (Lakekeeper) and S3 properties

```properties
connector.name=iceberg
iceberg.catalog.type=rest
iceberg.rest-catalog.uri=http://lakekeeper:8181/catalog
iceberg.rest-catalog.warehouse=<warehouse-name>
# optional: iceberg.rest-catalog.security=OAUTH2 (default NONE)
# optional: iceberg.rest-catalog.vended-credentials-enabled=true (default false)
# optional: iceberg.rest-catalog.nested-namespace-enabled=true (default false)
fs.s3.enabled=true
s3.endpoint=http://rustfs:9000
s3.region=us-east-1
s3.path-style-access=true
s3.aws-access-key=...
s3.aws-secret-key=...
```

- `iceberg.rest-catalog.uri`, `warehouse`, `security` (NONE, SIGV4, GOOGLE or OAUTH2), `vended-credentials-enabled` and `nested-namespace-enabled` are all documented for Trino 483. **[doc]**
- **The native S3 switch has been renamed.** The Trino 478 docs use `fs.native-s3.enabled`. The 481 and 483 docs use only `fs.s3.enabled`. The release notes for 479–483 do not mention the rename. **[doc]**
  - Whether the old name still works as an alias is **[inf]**, so use `fs.s3.enabled` on 481 and later.
  - Legacy S3 support (`hive.s3.*`) was removed in 481.
- `s3.endpoint`, `s3.region`, `s3.path-style-access`, `s3.aws-access-key` and `s3.aws-secret-key` exist under those names in the 483 docs. **[doc]**
- 483 adds `s3.auth-type`. Breaking change: `s3.iam-role` now needs `s3.auth-type=IAM_ROLE`. Static keys are not affected. **[doc]**
- Trino says only AWS S3 and MinIO are tested for S3 compatibility, so any other S3-compatible store is the user's own responsibility. **[doc]**
- The Lakekeeper URI path (`/catalog`) and the warehouse name come from Lakekeeper's own conventions, not from the Trino docs. **[inf]**

## Impact on the SPEC

- §15 V4: resolved as **supported**. The ⚠️ on the Trino `microbatch` cell in §7.1 can become ✅, and the fallback is no longer needed.
- §7.1: on Trino, microbatch is delete+insert per batch, so in this benchmark it is "delete+insert driven by event_time".
- `concurrent_batches` requires dbt-trino ≥ 1.10.2. Pin 1.10.6.
- Pins: dbt-core 1.12.5, dbt-trino 1.10.6, Trino 483. Trino 483 is newer than the 478 that dbt-trino tests against.
- Trino catalog config: use `fs.s3.enabled`, not `fs.native-s3.enabled`.

## Sources

- dbt-trino CHANGELOG: https://github.com/starburstdata/dbt-trino/blob/master/CHANGELOG.md
- dbt-trino 1.9.0 CHANGELOG: https://github.com/starburstdata/dbt-trino/blob/v1.9.0/CHANGELOG.md
- Microbatch macro: https://github.com/starburstdata/dbt-trino/blob/master/dbt/include/trino/macros/materializations/incremental.sql
- Strategies and capabilities: https://github.com/starburstdata/dbt-trino/blob/v1.10.2/dbt/adapters/trino/impl.py
- Commit adding microbatch: https://github.com/starburstdata/dbt-trino/commit/dc7338ba
- Commit adding concurrency: https://github.com/starburstdata/dbt-trino/commit/95647b8f
- dbt-trino README (Compatibility): https://github.com/starburstdata/dbt-trino
- dbt incremental strategy table: https://docs.getdbt.com/docs/build/incremental-strategy
- dbt Trino configs: https://docs.getdbt.com/reference/resource-configs/trino-configs
- dbt parallel batch execution: https://docs.getdbt.com/docs/build/parallel-batch-execution
- PyPI: https://pypi.org/project/dbt-core/ and https://pypi.org/project/dbt-trino/
- Trino release notes: https://trino.io/docs/current/release.html (481, 483)
- Trino metastores (REST): https://trino.io/docs/current/object-storage/metastores.html
- Trino S3 file system: https://trino.io/docs/483/object-storage/file-system-s3.html and https://trino.io/docs/478/object-storage/file-system-s3.html
- Trino Iceberg connector: https://trino.io/docs/current/connector/iceberg.html

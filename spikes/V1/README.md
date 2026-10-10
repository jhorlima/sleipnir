# V1: can DuckDB write Iceberg tables through the Lakekeeper REST catalog?

**Result: SUPPORTED**, with a static S3 secret and `ACCESS_DELEGATION_MODE 'none'`. Tested locally on 2026-10-09.

Labels used below:
- **[local]**: verified with `run.sh` against the running storage stack.
- **[doc]**: stated in official docs.
- **[inf]**: inferred, not yet checked.

## Versions

| Component | Version |
|---|---|
| DuckDB (pip) | 1.5.6 (2026-09-28, latest stable) |
| iceberg / httpfs / avro extensions | `890b78a9c` / `4bc690d` / `f9d5902` |
| Lakekeeper | v0.14.0 |
| RustFS | 1.0.1 |
| Container | `python:3.12.15-slim` |

## Statements that work [local]

```sql
INSTALL iceberg; LOAD iceberg; INSTALL httpfs; LOAD httpfs;

CREATE SECRET rustfs (
    TYPE s3, KEY_ID '<S3_ACCESS_KEY>', SECRET '<S3_SECRET_KEY>',
    REGION 'local-01', ENDPOINT 'rustfs:9000', URL_STYLE 'path', USE_SSL false
);

ATTACH 'lakehouse' AS lakehouse (
    TYPE iceberg,
    ENDPOINT 'http://lakekeeper:8181/catalog',
    AUTHORIZATION_TYPE 'none',
    ACCESS_DELEGATION_MODE 'none',
    PURGE_REQUESTED true          -- DROP TABLE also removes the files
);

CREATE SCHEMA lakehouse.duckdb_bronze;
CREATE TABLE lakehouse.duckdb_bronze.ghcn_daily_raw (...)
    PARTITIONED BY (_batch_id)
    WITH ('format-version' = '2', 'write.parquet.compression-codec' = 'zstd');
INSERT INTO lakehouse.duckdb_bronze.ghcn_daily_raw SELECT ... FROM read_csv(...);
```

## Findings

| Check | Result |
|---|---|
| ATTACH with no auth | Works with `AUTHORIZATION_TYPE 'none'`. **[local]** |
| `CREATE SCHEMA`, `CREATE TABLE AS`, `INSERT` (append) | Work. Two batches of 100k rows read back as 100k + 100k, with one `append` snapshot per statement. **[local]** |
| Format version | `format-version: 2` in every `metadata.json`, both by default and with an explicit `WITH ('format-version' = '2')`. The default comes from `iceberg_default_format_version = 2`. **[local] + [doc]** |
| File format and codec | Parquet. The default codec is SNAPPY. `write.parquet.compression-codec = 'zstd'` is honored and the files are written as ZSTD. **[local]** |
| `PARTITIONED BY (_batch_id)` | Works. Files are written to `data/_batch_id=N/`, with an identity transform. DuckDB names the partition field `identity__batch_id_9`, not `_batch_id`. **[local]** That this name is harmless for Trino, Spark and StarRocks is **[inf]**. |
| Other writes | `UPDATE`, `DELETE` and `MERGE INTO` are supported, but only as merge-on-read with positional deletes, not copy-on-write. Other supported operations: `ALTER TABLE` schema evolution, `ALTER TABLE ... SET PARTITIONED BY`, and the transforms year/month/day/hour/bucket/truncate. **[doc]** Bronze is append-only, so none of these were tested. |
| `write.target-file-size-bytes` / `write.parquet.row-group-size-bytes` | Raise an error on partitioned tables unless `ignore_*_for_partitioned_tables` is set. **[doc]** |
| Vended credentials (the default `ACCESS_DELEGATION_MODE`) | **Fails.** The error is `Could not refresh Iceberg vended credentials ... NotFound_404`. The warehouse has `sts-enabled: false` and `remote-signing-enabled: true`, so Lakekeeper cannot vend credentials. Lakekeeper's docs (engines.md) say "DuckDB does not support remote signing". **[local] + [doc]** |
| Metadata files | Lakekeeper writes `*.gz.metadata.json` (gzip). DuckDB reads them with `read_json(..., compression = 'gzip')`. **[local]** |
| `DROP TABLE` with `PURGE_REQUESTED true` + `DROP SCHEMA` | Removes the catalog entries and empties the bucket. Lakekeeper purges the files asynchronously. **[local]** |

### Rough write throughput [local]

Single DuckDB process with no CPU or memory limit, writing to RustFS limited to 1 CPU. CSV generated locally. The numbers are an indication only, not a benchmark.

| Rows | Operation | Time | Rows/s | CSV MB/s |
|---|---|---|---|---|
| 100k (~3.6 MB CSV) | CTAS | 0.08–0.19 s | 0.5–1.2 M | 19–44 |
| 100k | INSERT | 0.06–0.10 s | 1.0–1.6 M | 35–56 |
| 2M (~72 MB CSV) | CTAS | 0.91 s | 2.2 M | 79 |
| 2M | INSERT | 0.33 s | 6.1 M | 219 |

A 100k-row file is about 136 KB of Parquet (SNAPPY).

## Impact on SPEC

- §15 V1 is resolved. Ingestion writes `duckdb_bronze` directly through the REST catalog. The fallback (Parquet on S3 + CTAS via Trino) is not needed.
- §3.1: DuckDB attaches with `ACCESS_DELEGATION_MODE 'none'`, a static S3 secret (path-style, no SSL) and `AUTHORIZATION_TYPE 'none'`. Vended credentials would require STS on the warehouse. **[inf]** Whether RustFS supports STS for this was not checked.
- §4 and §7: `format-version` is 2 by default. Set it explicitly anyway, together with the codec chosen by B6, in the `WITH (...)` clause of the bronze DDL.
- The DDL must be created explicitly with `PARTITIONED BY (_batch_id)`. CTAS cannot declare a partition spec in the same statement (**[inf]**, not tested), so the order is `CREATE TABLE ... PARTITIONED BY`, then `INSERT`.
- Still open: Trino, Spark and StarRocks reading a DuckDB-written table, including the `identity__batch_id_9` partition field name. Check this in phase 1 once Trino is up. **[inf]**

## Files

- `spike.py`: the proof. It covers ATTACH, CTAS + append, a partitioned and zstd table, metadata and Parquet inspection, and cleanup.
- `run.sh`: runs `spike.py` in a throwaway container on `sleipnir_default`. Example: `MODE=static|vended ROWS=100000 KEEP=0 spikes/V1/run.sh`.

## Sources

- DuckDB Iceberg docs: [writing](https://duckdb.org/docs/current/core_extensions/iceberg/writing.html), [options](https://duckdb.org/docs/current/core_extensions/iceberg/iceberg_options.html), [catalogs](https://duckdb.org/docs/current/core_extensions/iceberg/catalogs.html).
- Lakekeeper: `docs/docs/engines.md` (DuckDB section and the remote-signing note) and `examples/minimal/notebooks/DuckDB.ipynb`, in [lakekeeper/lakekeeper](https://github.com/lakekeeper/lakekeeper).

# V13: Cube `duckdb` driver reading Iceberg through Lakekeeper

Tested with `cubejs/cube:v1.7.50` (linux/arm64 image, inspected read-only; probe ran on the default Docker bridge, never on the compose network).

## Verdict

PARTIAL / feasible with one `cube.js`. Plain env vars can install and load `iceberg` + `httpfs`, but the `CREATE SECRET` + `ATTACH` need the driver's `initSql` option, which has no env var; it is only reachable from `cube.js` (`driverFactory`). Not yet verified: a real ATTACH against Lakekeeper/RustFS (the stack was off limits) and a running Cube server using the proof in `cube-proof/`.

## (1) Bundled DuckDB version: 1.5.5 (verified locally)

- `@cubejs-backend/duckdb-driver` 1.7.50 depends on `@duckdb/node-api` `1.5.5-r.5` (`node_modules/@cubejs-backend/duckdb-driver/package.json`).
- `SELECT version()` through the driver returned `v1.5.5` (`probe.js`).
- V1 used DuckDB 1.5.6. Cube's DuckDB is one patch older; the driver cannot be upgraded independently of the Cube image.
- Extensions loaded by the driver: iceberg `45163a28`, httpfs `827222f`, avro `f9d5902`.

## (2) REST ATTACH with `ACCESS_DELEGATION_MODE 'none'` on 1.5.5: accepted (verified locally, partially)

- `ATTACH 'lakehouse' AS lakehouse (TYPE iceberg, ENDPOINT ..., AUTHORIZATION_TYPE 'none', ACCESS_DELEGATION_MODE 'none')` parsed and executed on 1.5.5: the only error was `Could not connect to server error for HTTP GET to '.../v1/config?warehouse=lakehouse'` against a dead endpoint. An unknown option would have failed earlier with a binder error.
- Data reads (the part V1 proved on 1.5.6) are not re-proven on 1.5.5. Re-check in step 4 below.
- Docs: https://duckdb.org/docs/current/core_extensions/iceberg/iceberg_rest_catalogs (redirects to the Iceberg catalogs page; I could not fetch the option list, only the local behaviour above).
- INSTALL needs internet (`extensions.duckdb.org`) at every Cube start, because the in-memory instance has no persistent extension directory unless the container does. Fine locally; mention it in the article for offline runs.

## (3) Running secret + ATTACH at connection time

Source: the driver in the image (`dist/src/DuckDBDriver.js`, `shared/dist/src/env.js`); upstream: https://github.com/cube-js/cube/tree/v1.7.50/packages/cubejs-duckdb-driver and docs https://cube.dev/docs/product/configuration/data-sources/duckdb.

| Mechanism | Available | Notes |
|---|---|---|
| `CUBEJS_DB_DUCKDB_EXTENSIONS` (comma list) | yes | `INSTALL x; LOAD x` per name, on every connection init. Per source: `CUBEJS_DS_<NAME>_DB_DUCKDB_EXTENSIONS`. |
| `CUBEJS_DB_DUCKDB_S3_*` (region, endpoint, access key, secret, use_ssl, url_style, session token) | yes | Emits legacy `SET s3_*` settings, not a secret. httpfs falls back to them, but Iceberg REST ATTACH with delegation `none` is only proven with a `CREATE SECRET` (V1), so use the secret. |
| `CUBEJS_DB_DUCKDB_MEMORY_LIMIT`, `_SCHEMA`, `_DATABASE_PATH` | yes | All have `CUBEJS_DS_<NAME>_DB_DUCKDB_*` variants. |
| Init SQL env var | **no** | Only `config.initSql` in the driver constructor. |
| `driverFactory` in `cube.js` returning `{ type: 'duckdb', initSql }` | yes | Verified: `initSql` with two statements (CREATE SECRET; ATTACH) runs as written (`duckdb_secrets()` showed the secret). |

Gotchas found in the driver source and by the probe:
- Multi-statement `initSql` works (one string, `;`-separated).
- **Init SQL errors are swallowed** (logged as `DuckDB - error on init sql (skipping)`, level of `CUBEJS_LOG_LEVEL`), and the init promise is cached. If Lakekeeper is down when the first query arrives, the driver stays up without the `lakehouse` catalog until the process restarts; queries then fail with "catalog lakehouse does not exist". Start Lakekeeper before Cube, or restart Cube after it.
- A `driverFactory` must return either drivers or config objects for all data sources, never a mix; the proof returns config objects and rebuilds `type` from `CUBEJS_DS_<NAME>_DB_TYPE` for the other sources.
- A data source other than `default` is needed because the driver is one in-process instance per data source; do not reuse `default` (it has to exist but stays unused, see compose/serving.yaml).

Trade-off: a `cube.js` file (~20 lines, JS and secrets read from env) vs plain env-only config. Without it there is no way to ATTACH, so the repo's "plain config" rule has to bend for this one file. Alternative with no cube.js: `CUBEJS_DB_DUCKDB_DATABASE_PATH` pointing at a `.duckdb` file prepared out-of-band whose catalog persists the ATTACH; DuckDB does not persist ATTACH/secrets across sessions unless the secret is `CREATE PERSISTENT SECRET` and the ATTACH is re-run, so this does not remove the need for init SQL. Not recommended.

## (4) Concurrency, caching, resources

- One `DuckDBInstance` per driver (= per data source, per process); `query()` shares one default connection; `stream()` (used for pre-aggregation builds) opens a new connection per call and closes it at the end (driver source). Cube's own query queue limits concurrency (`CUBEJS_CONCURRENCY`; pre-aggregation queue has its own limit), so DuckDB work runs inside the Node process of the container that executes the query: the **cube-api** container for live queries, the **cube-refresh-worker** container for scheduled pre-aggregation builds.
- **Fairness caveat:** the DuckDB engine runs in-process inside the Cube container and counts against that container's cgroup limits (`CUBE_API_CPUS/MEMORY`, `CUBE_REFRESH_WORKER_*`), shared with Node/Cube. Verified in a `--cpus 1 --memory 1g` container: DuckDB set `threads=1` and `memory_limit=819.1 MiB` (80 percent of the cgroup limit), so it honours the container limit. Trino/StarRocks have their own containers with the S/M/L profile limits; DuckDB-via-Cube gets whatever the Cube services get (default API 1 cpu/1g, worker 0.5 cpu/512m), which is small and shared with Cube's own work. For a fair DuckDB-in-Cube comparison either raise the Cube limits for that run (record it in `engine_config`) or label the result as "DuckDB embedded in Cube, Cube limits". Set `CUBEJS_DS_LAKEHOUSE_DB_DUCKDB_MEMORY_LIMIT` explicitly to make the limit recorded rather than implicit (leave headroom for Node).
- Caching: no result cache inside the driver. The Iceberg metadata is re-read from the REST catalog per attached-table scan by DuckDB's iceberg extension (inferred, not measured). Cube's own caches (query result cache, pre-aggregations in Cube Store) are the only caches; they apply to every engine equally.
- Concurrency: with `CUBEJS_DB_DUCKDB_...` one shared instance, parallel Cube queries share the DuckDB thread pool, so p95 under concurrency (B5 style) is bounded by the container CPU, unlike a separate DuckDB server.

## Proof (not run against the stack)

Files:
- `probe.js`: ran as shown below against a dead endpoint; produced the evidence above.
- `cube-proof/cube.js` + `cube-proof/model/probe.yml`: Cube-side proof, not executed (the throwaway Cube container was blocked by the permission classifier).

`probe.js` command (default bridge network, dead endpoint, limits `--cpus 1 --memory 1g`):

```
docker run --rm --cpus 1 --memory 1g --entrypoint node \
  -v "$PWD/spikes/V13/probe.js:/probe.js:ro" \
  -e CUBEJS_DB_DUCKDB_EXTENSIONS=iceberg,httpfs \
  cubejs/cube:v1.7.50 /probe.js
```

Cube proof steps (to run when the stack may be used; Lakekeeper and RustFS up, Trino not needed):

1. In `compose/serving.yaml` for the proof only, add to `cube-env-common`:
   ```
   CUBEJS_DATASOURCES: default,lakehouse
   CUBEJS_DS_LAKEHOUSE_DB_TYPE: duckdb
   CUBEJS_DS_LAKEHOUSE_DB_DUCKDB_EXTENSIONS: iceberg,httpfs
   CUBEJS_DS_LAKEHOUSE_DB_DUCKDB_MEMORY_LIMIT: 512MB
   S3_ACCESS_KEY / S3_SECRET_KEY / S3_REGION / S3_ENDPOINT: rustfs:9000
   LAKEKEEPER_ENDPOINT: http://lakekeeper:8181/catalog
   ```
   and mount `cube-proof/cube.js` at `/cube/conf/cube.js` (the proof cube.js reads those env names; adjust to the repo's `.env` names).
2. Replace `cube-proof/model/probe.yml` with a cube on the DuckDB-written gold table: `data_source: lakehouse`, `sql_table: lakehouse.duckdb_gold.<table>`.
3. Start only the `cube` profile; query `/cubejs-api/v1/load` for the cube; expect rows equal to the DuckDB reference.
4. Check the logs for `error on init sql (skipping)`: it must be absent. Confirm `SELECT version()` is `v1.5.5` and that a row-count query returns data (this is the 1.5.5 data-read re-check).
5. Remove the proof changes.

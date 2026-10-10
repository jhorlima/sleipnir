# Cube models

Modelling and runtime rules for the Cube semantic layer.

## Layout
- Cube reads only through the query engines; it does not consume dbt artifacts.
- YAML only. One cube per file under `cube/model/cubes/`, views under `cube/model/views/`.
- Cubes are `public: false`; views are the public surface.
- One template per cube, rendered per data source (Jinja); cube names carry the data source prefix (`trino_weather_daily`).

## Advanced measures (Cube ≥ 1.7, Tesseract)
Use the native patterns from the Cube data-modeling recipes instead of hand-written SQL:
- **Percentiles/median:** `type: number` with the engine's function — Trino `approx_percentile(x, p)`, StarRocks `PERCENTILE_CONT(x, p)`, DuckDB/Postgres `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY x)`.
- **Nested aggregates:** inner measure exposed as a dimension with `sub_query: true` in an outer cube (joined `one_to_many`); the outer measure aggregates that dimension.
- **Share of total:** `multi_stage: true` helper with `grain: keep_only: []` (or `[<dimension>]` for a subtotal), ratio with `NULLIF`, `format: percent`; hide the helper from views with `excludes`. Use `filter` on the helper when the share dimension is also filtered.
- **Period over period:** `multi_stage: true` measure with `time_shift: [{interval: 1 year, type: prior}]`, combined in a multi-stage ratio/delta with `NULLIF`.
- Non-additive measures (percentiles, medians, ratios) are not re-aggregated by Cube Store; only a rollup at the exact query grain can serve them.

## Jinja
- Cube's Jinja auto-escapes strings: return `SafeString` from Python helpers and use `| safe` on built `{cube}` references, or names render as `"trino"_stations`.
- Engine-specific SQL lives in `cube/model/globals.py` helpers keyed by data source; YAML templates stay engine-agnostic.

## Precision in pre-aggregations
Cube's SQL drivers send DECIMAL columns to Cube Store as `Decimal(18,5)`: sums lose everything past 5 decimals and values below 1e-5 become 0. `CUBEJS_DB_PRECISE_DECIMAL_IN_CUBESTORE` does not fix it.

- Cast every measure that feeds a rollup to a double: `CAST(x AS DOUBLE)` on Trino/StarRocks/DuckDB, `CAST(x AS DOUBLE PRECISION)` on Postgres. Cube Store then stores it as `Float`.
- Never scale by an integer literal (`x * 1000`): the result stays DECIMAL. Scale after the cast.
- Row-level comparisons and thresholds stay on the original DECIMAL with a DECIMAL literal (`0.0000000001`, not `1e-10`).
- Ratios and `number` measures that are never rolled up do not need the cast.
- After building a rollup, confirm its measure columns are `Float` in Cube Store.

## StarRocks (MySQL driver)
- `CUBEJS_DS_STARROCKS_DB_TYPE=mysql`, port 9030 (FE MySQL protocol).
- External catalog tables use three-part names: `lakehouse.<namespace>.<table>`.
- `PERCENTILE_CONT(expr, p)` takes two arguments (no `WITHIN GROUP`).
- Weighted averages: `CAST(SUM(a) AS DOUBLE) / NULLIF(CAST(SUM(b) AS DOUBLE), 0.0)`.

## Runtime
- Cube and Cube Store on the same pinned version.
- API with `CUBEJS_REFRESH_WORKER=false`; a separate refresh worker with `true`.
- `CUBEJS_SCHEDULED_REFRESH_TIMEZONES=UTC`.

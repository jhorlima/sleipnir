# Cube models

Modelling and runtime rules for the Cube semantic layer.

## Layout
- Cube reads only through the query engines; it does not consume dbt artifacts.
- Plain YAML only: no Jinja, no generators. One cube per file; views under `cube/model/views/`.
- Cubes are `public: false`; views are the public surface.
- `cube/model/cubes/base/*.yml`: the engine-agnostic cubes (`base_weather_daily`, ...) with every member written out, on the placeholder `default` data source and never queried. Each file's header says which engines extend it.
- `cube/model/cubes/<engine>/*.yml`: short files with `extends: base_<cube>`, `data_source`, the table path written out (`sql_table: lakehouse.trino_gold.<table>`; the gold schema is fixed per engine) and only what differs: the percentile measures and, if the double type is not spelled `DOUBLE`, the casts. Cube names carry the engine prefix (`trino_weather_daily`).
- A child cube inherits `public: false` and merges members by name (a child member replaces the parent's). Cube does not rewrite cube names inside inherited members, so whatever references another cube by name (joins, `grain.keep_only: [<cube>.<dim>]`, `sub_query` dimensions) is restated in the engine file.
- Views are written out per engine (`views/<engine>_weather.yml`).

## Advanced measures (Cube ≥ 1.7, Tesseract)
Use the native patterns from the Cube data-modeling recipes instead of hand-written SQL:
- **Percentiles/median:** `type: number` with the engine's function — Trino `approx_percentile(x, p)`, StarRocks `PERCENTILE_CONT(x, p)`, DuckDB/Postgres `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY x)`.
- **Nested aggregates:** inner measure exposed as a dimension with `sub_query: true` in an outer cube (joined `one_to_many`); the outer measure aggregates that dimension.
- **Share of total:** `multi_stage: true` helper with `grain: keep_only: []` (or `[<dimension>]` for a subtotal), ratio with `NULLIF`, `format: percent`; hide the helper from views with `excludes`. Use `filter` on the helper when the share dimension is also filtered.
- **Period over period:** `multi_stage: true` measure with `time_shift: [{interval: 1 year, type: prior}]`, combined in a multi-stage ratio/delta with `NULLIF`.
- Non-additive measures (percentiles, medians, ratios) are not re-aggregated by Cube Store; only a rollup at the exact query grain can serve them.

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

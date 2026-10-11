# V9: can Cube v1.7.50 (Tesseract) serve multi-stage / non-additive measures from Cube Store pre-aggregations?

**Result: PARTIAL (proved on Trino, see section 8).** Research 2026-10-10; local proof 2026-10-11.
Labels: **[doc]** official docs/release notes/PRs, **[inf]** inferred, **[?]** unproven, needs the local proof.

## 1. What the docs say (applies to all four questions)

- Tesseract is the default planner from v1.7.0 and `CUBEJS_TESSERACT_PRE_AGGREGATIONS` was removed: pre-aggregation matching follows `CUBEJS_TESSERACT_SQL_PLANNER` (already `true` in `compose/serving.yaml`). **[doc]** [v1.7 post](https://cube.dev/blog/cube-core-v1-7-tesseract-ga-data-modeling-performance)
- Multi-stage on pre-aggregations became possible with Cube Store on DataFusion 46 (CTE support), v1.6. A multi-stage query reading a rollup runs its CTEs **in Cube Store**, not in the source. **[doc]** [v1.6 post](https://cube.dev/blog/cube-core-v1-6-cube-store-upgrade-multi-stage-pre-aggregations)
- Each subquery of the query (one per stage of a multi-stage measure) is matched against the rollups **independently**, so one query can use several. Matching is **all-or-nothing**: if one stage finds no rollup, the whole query runs on the source (the source then runs the CTEs). **[doc]** [matching rules](https://docs.cube.dev/docs/pre-aggregations/matching-pre-aggregations.md)
- Matching rules, in order: all leaf measures additive; rollup contains every query dimension, filter dimension and leaf measure; no measure multiplied through a `one_to_many` join; **the query must set a granularity for its time dimension**; every filter dimension must also be a query dimension. Time dimension + granularity acts as a dimension; the date range must align to the rollup granularity (`allow_non_strict_date_range_match` defaults to true). Pass ranges in `timeDimensions.dateRange`, not as a filter. **[doc]** same page
- Additive: `count`, `sum`, `min`, `max`, `count_distinct_approx`. `avg` and exact `count_distinct` are non-additive and "cannot use an aggregating index". **[doc]** [using](https://docs.cube.dev/docs/pre-aggregations/using-pre-aggregations), [reference](https://docs.cube.dev/reference/data-modeling/pre-aggregations)
- Non-additive recipe (includes a `number` measure `PERCENTILE_CONT(0.9) ...`): a rollup containing the measures **and exactly the query's dimensions** matches; the same query without that dimension does not. The recipe's workarounds: approximate additive measures, decompose `avg` into `sum`/`count`, or add extra rollups at the exact grain. **[doc]** [non-additivity](https://docs.cube.dev/recipes/pre-aggregations/non-additivity.md)
- `rollup_lambda` (union of rollups, must be defined first) and `original_sql` (`use_original_sql_pre_aggregations`, "multi-stage pre-aggregations by reusing original SQL pre-aggregations") exist, but nothing in the matching docs requires them for rollup-served multi-stage. Storing `original_sql` in Cube Store is "not recommended". **[doc]** reference + using pages. **Not needed here.** **[inf]**
- Time shift: PR #12010 (in 1.7.46, so in 1.7.50) rolls up a *stored* time-shift proxy (`{other_measure}` + `time_shift`) when the target is a plain additive measure; proxies of `count`/`count_distinct`, rolling windows, `reduce_by`/`group_by`, `filter` directive and expressions over the shift are not rolled up and fall back. **[doc]** [PR #12010](https://github.com/cube-js/cube/pull/12010) (release mapping from the [releases page](https://github.com/cube-js/cube/releases) via search, not opened)
- Related fixes: #11812 (retry matching inside one external type, prefers Cube Store), #12091 (bound multi-stage stages, in 1.7.50). Open bug [#12086](https://github.com/cube-js/cube/issues/12086): "Can't find join path" when the query has **only** multi-stage measures and dimensions from two cubes joined only through the fact cube and a rollup matches. Workaround: add one plain additive fact measure. q9 and q10 already contain a plain measure (`total_prcp`, `avg_tmax`), so they should not hit it. **[doc]** / **[inf]** for q9/q10
- DOUBLE-cast rule: unchanged. Drivers send DECIMAL as `Decimal(18,5)` to Cube Store; `CUBEJS_DB_PRECISE_DECIMAL_IN_CUBESTORE` exists (default false; may need partition rebuilds) but `.claude/rules/cube-models.md` records it did not fix the problem here. Cast every rollup measure to DOUBLE. Existing `avg_tmax`, `avg_tmin`, `total_prcp` already cast. **The percentile measures are not cast yet** (`approx_percentile({CUBE}.tmax, 0.5)`): `approx_percentile` over a DECIMAL returns DECIMAL **[inf]**, so cast the input (`CAST({CUBE}.tmax AS DOUBLE)`) before putting them in a rollup. Same for `median_station_annual_prcp`, whose input `annual_prcp` comes from the already-cast `total_prcp`.

## 2. Verdict per question

| Q | Measure | Verdict | Rollup needed | Why |
|---|---|---|---|---|
| Q7 | `median_tmax`, `p95_tmax` (`number`, percentile) | **PARTIAL**: only at exact grain | `yearly_country_percentiles` (country, `date` year); the query must set `granularity: year` | Non-additive: no re-aggregation, so `monthly_country` cannot answer a per-year median. q7 as written has a `dateRange` with no granularity (rule 4: granularity required) **[doc]**, and a per-country-per-year query is not served by a country x month rollup. The variant `queries/q7_year_granularity.json` returns one extra `date` column. |
| Q8 | `median_station_annual_prcp` (`sub_query` dim) | **UNPROVEN, expect OUT** | at best `yearly_median_station_prcp` (dimension `year`, exact grain) | No doc covers `sub_query` dimensions in rollups. The measure is a `number` over a sub_query dimension; the rollup would have to run the correlated aggregate at build time. **[?]** |
| Q9 | `prcp_share_of_total` (`multi_stage`, `grain.keep_only: []`) | **LIKELY SUPPORTED** | `monthly_country` (additive only: `total_prcp`, dimension `country`, month) | Stages are `total_prcp` by country and `total_prcp_all` with no dimension; both are sums and re-aggregate from a month x country rollup, and the ratio is computed in Cube Store CTEs. Open points **[?]**: q9 has `dateRange` without granularity (see section 3), and the all-or-nothing rule. |
| Q10 | `avg_tmax_prior_year`, `tmax_yoy_delta` (`time_shift`) | **LIKELY SUPPORTED at exact grain** | `monthly_country_avg` (`avg_tmax`, country, month) | `avg_tmax` is non-additive, so every stage (current, shifted 2024) must hit exactly country x month: q10 is exactly that. The #12010 "stored shift" path does not apply (target is `avg`, not additive) but the shifted stage is an ordinary subquery over 2024 months **[inf]**. Build range must include 2024. Robust fallback: decompose into `sum_tmax` / `count_tmax` (additive) and make `avg_tmax` a calculated measure (model change, outside this spike). |

Not needed for any of them: `rollup_lambda`, `original_sql`, `rollup_join`.

## 3. Risks to settle in the proof (all marked [?])

1. **Granularity-less time dimension.** The matching doc says the query must set a granularity. q3, q4, q7, q8, q9 pass only `dateRange`. If a granularity-less `dateRange` does not match a rollup, q9 needs the `queries/q9_month_granularity.json` variant (output shape changes: country x month rows) and q3/q4 are not accelerated as written. Settle this first: it also affects B5c for q3.
2. Whether q10's shifted stage hits `monthly_country_avg` and the rollup partitions for 2024 are built.
3. `sub_query` + rollup (q8).
4. Rollup-level DECIMAL leaks: confirm all measure columns are `Float` in Cube Store (run.sh step 4).
5. q4 filters on `latitude`/`longitude` (stations dimensions not in any rollup): not accelerated unless added as rollup dimensions; out of scope for V9.

## 4. How to verify a hit

- REST `/cubejs-api/v1/load` response: `usedPreAggregations` is an object keyed by the Cube Store table (`<schema>.<cube>_<rollup>…`) with `preAggregationId` (`trino_weather_daily.monthly_country`), `type: rollup`, `lastUpdatedAt`. Empty/absent means the source ran. (Field documented for SQL API [cubesql](https://docs.cube.dev/api-reference/data/sql-query.md); the `/load` field is known behavior, not found in the pages fetched.) **[doc]/[inf]**
- `/cubejs-api/v1/sql` (`make cube-query Q=9 ENDPOINT=sql`): generated SQL reads a `*_pre_aggregations` schema when served by Cube Store, `lakehouse.trino_gold.*` otherwise. For multi-stage queries check **every** CTE reads the rollup (all-or-nothing). **[inf]**
- SQL API (`make cube-sql`): the first line of the `/v1/cubesql` stream carries `usedPreAggregations`; with the Postgres protocol use the REST route instead. **[doc]**
- Optional hard check: `CUBEJS_ROLLUP_ONLY=true` makes a non-matching query fail instead of silently falling back. **[doc]** (do not leave it on for B3/B4.)

## 5. Proposed rollups

See `pre_aggregations.proposal.yml` (engine cube, `trino_weather_daily`): `monthly_country` (additive, country x month, Q9), `monthly_country_avg` (non-additive avg, exact country x month, Q2/Q10), `yearly_station` (station x year, Q3), optional `yearly_country_percentiles` (Q7 at exact grain) and a commented `yearly_median_station_prcp` (Q8). The StarRocks cubes need the same block with `starrocks_stations`.

## 6. What stays out of B5c

- **Q8** unless the proof shows a rollup builds and matches: nested aggregates over a `sub_query` dimension are undocumented for rollups.
- **Q7** as written: median/p95 by country over a year is non-additive; it can be accelerated only with a dedicated exact-grain rollup and a different query shape (`granularity: year`). Keep out of the main B5c set, or report it as a separate "exact-grain rollup" case.
- Q9 and Q10: keep in if the proof passes (they are the interesting multi-stage cases). Share-of-total and PoP over **additive** measures are the supported path; PoP over `avg` works only at exact grain.
- Any query hitting a rollup-less member (q4 lat/lon filters, `station_count`, `avg_tmax_7d` rolling window, q5) falls back to the source.

## 7. Proof steps (ready to run, not run)

1. Copy the rollups from `pre_aggregations.proposal.yml` into `cube/model/cubes/trino/weather_daily.yml`; change the percentile measures to `approx_percentile(CAST({CUBE}.tmax AS DOUBLE), p)`. Start Trino with gold tables loaded (Trino must be the only engine up, benchmark-integrity 1).
2. `make cube-up`
3. `spikes/V9/run.sh` (builds the rollups via `POST /v1/pre-aggregations/jobs` or the refresh worker, runs q2, q3, q4, q7..q10 plus the variants in `queries/`, prints `usedPreAggregations` per query).
4. Compare each accelerated result with the unaccelerated result (rename the rollup or query a model without it); fill the per-question verdicts above and SPEC 8.4 / 10.3 B5c.
5. `make cube-down`; remove the Cube Store volume if the proof leaves large rollups.

## 8. Proof (Trino, Cube + Cube Store 1.7.50, run 2026-10-11)

**Verified locally.** Gold tables at the small scale (190,214,772 daily rows, 133,039 stations). The rollups of `pre_aggregations.proposal.yml` were applied to `trino_weather_daily` / `trino_station_years` with the build range narrowed to 2024-01-01..2025-12-31 (enough for q2..q10 and the 2024 prior-year stage); the exact diff is `proof_model.diff` (it also casts the percentile inputs to DOUBLE). `cube/model` was reverted afterwards. Helpers: `cube_post.sh`, `proof.sh`, `compare.py`, `trino_builds.sh`, `cubestore_sql.sh`.

Method: accelerated pass (rollups built by the refresh worker), then the same queries with the rollups removed from the model and `renewQuery: true` (baseline, source on Trino), compared per row with a 5 % tolerance (benchmark-integrity 5). `usedPreAggregations` read from the `/v1/load` response.

### 8.1 Granularity answer

A `dateRange` **without** `granularity` matches a rollup when every measure is additive: q3 (`yearly_station`) and q9 (`monthly_country`, both stages) hit as written. The docs' "the query must set a granularity" is not enforced for that case in 1.7.50 (a year/month rollup is re-aggregated over the range). It does **not** match for non-additive measures: q7 as written (percentiles, no granularity) went to Trino; q7 with `granularity: year` hit `yearly_country_percentiles`. The `q9_month_granularity` variant is therefore unnecessary for the hit (it also changes the output shape).

### 8.2 Per question

| Q | Rollup hit | Rollup used | Result equal to source | Notes |
|---|---|---|---|---|
| Q2 | yes | `monthly_country_avg` | yes (1951 rows, max rel. diff 2e-16) | exact grain country x month |
| Q3 | yes | `yearly_station` | yes (20 rows, 3e-16) | `dateRange` only, no granularity |
| Q4 | **no** | none | n/a (source both, equal) | `latitude`/`longitude` filters are not in any rollup; stays on Trino |
| Q7 as written | **no** | none | n/a | non-additive + no granularity |
| Q7 `granularity: year` | yes | `yearly_country_percentiles` | within tolerance (192 rows, max rel. diff 1.9 %) | extra `date` column; `approx_percentile` differs between plans (the unaccelerated q7 vs the source baseline already differs by 1.4 %) |
| Q8 | yes | `trino_station_years.yearly_median_station_prcp` | within tolerance (16 rows, max rel. diff 4.6 %) | the rollup **builds** from a `sub_query` dimension (22 s) and is matched at exact grain (`station_year`); 4.6 % is `approx_percentile` over 133k per-station sums in two plans, close to the 5 % limit |
| Q9 as written | yes | `monthly_country` (used twice: both stages) | yes (192 rows, 6e-16) | share of total computed by Cube Store CTEs; the month-granularity variant took 711 s on the source vs seconds from the rollup |
| Q10 | yes | `monthly_country_avg` (used three times, incl. the 2024 stage) | yes (2246 rows, 2e-16) | exact grain only; the shifted stage needs the 2024 partitions built |

Additional: `q9_month_granularity` hits `monthly_country`, equal (1951 rows).

Not needed: `rollup_lambda`, `original_sql`, `rollup_join`, decomposition of `avg`.

### 8.3 Float check

Cube Store `information_schema.columns` for `prod_pre_aggregations`: 79 `float`, 51 `int`, 52 `text`, 52 `timestamp`; **no decimal column**. Includes the casted percentiles and the `sub_query` rollup (`median_station_annual_prcp` is `float`). Percentile inputs must be `CAST(... AS DOUBLE)` (done in the diff).

### 8.4 Build time and storage

Trino `m` profile, Cube refresh worker at 0.5 CPU, builds run by the scheduler, 53 partitions in total: all rollups finished about 3 min 20 s after the first build started. Per rollup (Cube Store `created_at`): `yearly_median_station_prcp` 1 partition, 22 s; `yearly_station` 2 partitions, about 15 s; `yearly_country_percentiles` 2 partitions, about 10 s; `monthly_country` and `monthly_country_avg` 24 partitions each, about 2.5 to 3 min each, interleaved (a partition costs 1 to 6 s of Trino). Cube Store `/cube/data`: 28 MB after the builds (31 MB after the queries) for the 2024-2025 range. Extrapolation to 2010..2025 (192 partitions per monthly rollup) is not measured.

### 8.5 Gotchas found

- **Stale query cache across runs.** Cube Store persists Cube's query result cache in the `cubestore-data` volume: two baseline answers (q8, q9) were the previous day's results (older `lastRefreshTime`, older model) until `renewQuery: true` was sent. B3/B4 must send `renewQuery: true` (or start from a fresh volume) so a cold Cube run is not a cache hit.
- **`cube/cube.js` driverFactory error in the refresh worker.** `dataSource` is `undefined` for some scheduler calls (`Cannot read properties of undefined (reading 'toUpperCase')` at `cube.js:20`, logged as "Refresh Scheduler Error" once per cycle). The rollups still built; the fix is `(dataSource || 'default')`. Not touched here (outside scope).
- `POST /v1/pre-aggregations/jobs` answers "API scope is missing: jobs" with the signed JWT (a `scope` claim did not help); the refresh worker builds on its own, so `run.sh` step 1 does not work as written.
- Cube Store SQL is reachable on the router port 3306 (MySQL protocol) from a throwaway `mysql:8` container on `sleipnir_default`; `information_schema.columns` and `system.tables` work, `substr` over `table_name` does not (Utf8View).

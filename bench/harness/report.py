"""Prints p50/p95 per engine x profile x scenario and the time per step of the latest run, from results/*.parquet."""

import duckdb

from results import RESULTS_DIR

# Total rows are one per run; the percentiles are over the steps (batches, models) inside the runs.
# Read suites (b3-b5) have cold and warm runs per query: they are reported apart, and the discarded
# warm-up never counts. n_not_ok counts invalid, failed and timeout runs, which stay out of the percentiles.
LATENCY_PERCENTILES = """
    SELECT
        suite, dataset, engine, profile, scenario, data_scale, run_type,
        count(*) FILTER (WHERE status = 'ok') AS n,
        count(*) FILTER (WHERE status <> 'ok') AS n_not_ok,
        round(quantile_cont(latency_ms, 0.5) FILTER (WHERE status = 'ok'), 1) AS p50_ms,
        round(quantile_cont(latency_ms, 0.95) FILTER (WHERE status = 'ok'), 1) AS p95_ms,
        round(max(peak_mem_mb), 1) AS peak_mem_mb,
        round(avg(avg_cpu_pct), 1) AS avg_cpu_pct
    FROM results
    WHERE step <> 'total' AND coalesce(run_type, '') <> 'warmup'
    GROUP BY suite, dataset, engine, profile, scenario, data_scale, run_type
    ORDER BY suite, dataset, engine, profile, scenario, data_scale, run_type
"""

TIME_PER_STEP = """
    WITH latest_run AS (
        SELECT suite, dataset, engine, profile, scenario, data_scale, arg_max(run_id, ts) AS run_id
        FROM results
        GROUP BY suite, dataset, engine, profile, scenario, data_scale
    )
    SELECT
        results.suite, results.dataset, results.engine, results.profile, results.scenario, results.run_id,
        results.step, results.run_type, results.batch AS run_no, results.status, results.checksum_ok,
        round(results.latency_ms, 1) AS latency_ms,
        results.rows
    FROM results
    JOIN latest_run USING (suite, dataset, engine, profile, scenario, data_scale, run_id)
    ORDER BY results.suite, results.dataset, results.engine, results.profile, results.scenario, results.ts
"""


def main():
    files = sorted(RESULTS_DIR.glob("*.parquet"))
    if not files:
        print(f"no results in {RESULTS_DIR}")
        return
    con = duckdb.connect()
    all_rows = f"SELECT * FROM read_parquet('{RESULTS_DIR}/*.parquet', union_by_name = true)"
    # Results are never edited (benchmark-integrity §4): a run found wrong afterwards is listed here and left out.
    invalidated = RESULTS_DIR / "invalidated_runs.csv"
    if invalidated.exists():
        all_rows += f" WHERE run_id NOT IN (SELECT run_id FROM read_csv('{invalidated}'))"
    con.execute(f"CREATE VIEW results AS {all_rows}")

    print("\nLatency percentiles per engine x profile x scenario (over steps)")
    con.sql(LATENCY_PERCENTILES).show(max_rows=200, max_width=200)
    print("\nTime per step (latest run of each group)")
    con.sql(TIME_PER_STEP).show(max_rows=500, max_width=200)


if __name__ == "__main__":
    main()

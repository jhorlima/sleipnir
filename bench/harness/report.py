"""Prints p50/p95 per engine x profile x scenario and the time per step of the latest run, from results/*.parquet."""

import duckdb

from results import RESULTS_DIR

# Total rows are one per run; the percentiles are over the steps (batches, models) inside the runs.
LATENCY_PERCENTILES = """
    SELECT
        suite, engine, profile, scenario, data_scale,
        count(*) AS n,
        round(quantile_cont(latency_ms, 0.5), 1) AS p50_ms,
        round(quantile_cont(latency_ms, 0.95), 1) AS p95_ms,
        round(max(peak_mem_mb), 1) AS peak_mem_mb,
        round(avg(avg_cpu_pct), 1) AS avg_cpu_pct
    FROM results
    WHERE step <> 'total' AND status = 'ok'
    GROUP BY suite, engine, profile, scenario, data_scale
    ORDER BY suite, engine, profile, scenario, data_scale
"""

TIME_PER_STEP = """
    WITH latest_run AS (
        SELECT suite, engine, profile, scenario, data_scale, arg_max(run_id, ts) AS run_id
        FROM results
        GROUP BY suite, engine, profile, scenario, data_scale
    )
    SELECT
        results.suite, results.engine, results.profile, results.scenario, results.run_id,
        results.step, results.status,
        round(results.latency_ms, 1) AS latency_ms,
        results.rows
    FROM results
    JOIN latest_run USING (suite, engine, profile, scenario, data_scale, run_id)
    ORDER BY results.suite, results.engine, results.profile, results.scenario, results.ts
"""


def main():
    files = sorted(RESULTS_DIR.glob("*.parquet"))
    if not files:
        print(f"no results in {RESULTS_DIR}")
        return
    con = duckdb.connect()
    con.execute(f"CREATE VIEW results AS SELECT * FROM read_parquet('{RESULTS_DIR}/*.parquet', union_by_name = true)")

    print("\nLatency percentiles per engine x profile x scenario (over steps)")
    con.sql(LATENCY_PERCENTILES).show(max_rows=200, max_width=200)
    print("\nTime per step (latest run of each group)")
    con.sql(TIME_PER_STEP).show(max_rows=500, max_width=200)


if __name__ == "__main__":
    main()

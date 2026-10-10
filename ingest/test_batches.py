"""Self-check for the batch layout: python test_batches.py (exits non-zero on failure)."""

import os
import tempfile

os.environ["LANDING_DIR"] = tempfile.mkdtemp()

import duckdb  # noqa: E402

import batches  # noqa: E402


def make_observations(con):
    # One station, one element, every day from 2024-12-01 to 2025-03-31.
    con.execute("""
        CREATE TEMP TABLE observations AS
        SELECT
            'XX000000001' AS id,
            strftime(day, '%Y%m%d') AS date,
            'TMAX' AS element,
            100 AS value,
            NULL::VARCHAR AS m_flag,
            NULL::VARCHAR AS q_flag,
            'X' AS s_flag,
            NULL::VARCHAR AS obs_time
        FROM range(DATE '2024-12-01', DATE '2025-04-01', INTERVAL 1 DAY) t(day)
    """)


def read_batch(con, batch_id):
    path = batches.batch_path(batch_id)
    columns = batches.csv_columns_sql()
    return con.execute(f"SELECT * FROM read_csv('{path}', header = false, columns = {columns})").fetchall()


def main():
    assert batches.batch_window(202503) == ("20250222", "20250301", "20250401")
    assert batches.batch_window(202512) == ("20251124", "20251201", "20260101")

    con = duckdb.connect()
    make_observations(con)
    assert batches.write_batch(con, 202503)
    first = read_batch(con, 202503)
    assert batches.write_batch(con, 202503)
    second = read_batch(con, 202503)
    assert first == second, "batch files must be identical across runs"

    # 31 days of March plus 7 days of overlap (Feb 22 - Feb 28).
    assert len(first) == 38, len(first)
    revised = 0
    for row in first:
        if row[3] != 100:
            revised += 1
            assert row[1] < "20250301", "only overlap rows are revised"
    assert revised < 5, revised

    assert not batches.write_batch(con, 202506), "a month without rows writes no batch"
    print("test_batches OK")


if __name__ == "__main__":
    main()

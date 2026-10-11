"""Copy the `small` scale (GHCN 2025) of duckdb_bronze into the benchmark Postgres (SPEC §6, D-23).

Reads the Iceberg tables through DuckDB and writes postgres_bronze.* through DuckDB's postgres extension.
Every run drops and recreates the three tables, so a re-run replaces the data.
Each measured step prints one JSON line on stdout; progress messages go to stderr.
"""

import os
import time

from batches import batch_ids_for_year
from load import COUNTRIES_TABLE, DAILY_TABLE, STATIONS_TABLE, connect, log, print_step

SMALL_YEAR = 2025
TARGET_SCHEMA = "bench.postgres_bronze"


def attach_postgres(con):
    host = os.environ["POSTGRES_BENCH_HOST"]
    con.execute(f"ATTACH 'host={host} user=sleipnir dbname=sleipnir' AS bench (TYPE postgres)")
    con.execute(f"CREATE SCHEMA IF NOT EXISTS {TARGET_SCHEMA}")


def analyze(con, table_name):
    started = time.perf_counter()
    con.execute(f"CALL postgres_execute('bench', 'ANALYZE postgres_bronze.{table_name}')")
    seconds = time.perf_counter() - started
    print_step(f"{table_name}:analyze", 0, None, seconds)


def copy_daily(con):
    target = f"{TARGET_SCHEMA}.ghcn_daily_raw"
    con.execute(f"DROP TABLE IF EXISTS {target}")
    con.execute(f"CREATE TABLE {target} AS SELECT * FROM {DAILY_TABLE} LIMIT 0")

    expected_rows = 0
    for batch_id in batch_ids_for_year(SMALL_YEAR):
        started = time.perf_counter()
        rows = con.execute(f"""
            INSERT INTO {target}
            SELECT * FROM {DAILY_TABLE} WHERE _batch_id = {batch_id}
        """).fetchone()[0]
        seconds = time.perf_counter() - started
        print_step(f"ghcn_daily_raw:{batch_id}", rows, None, seconds)
        expected_rows += rows

    copied_rows = con.execute(f"SELECT count(*) FROM {target}").fetchone()[0]
    first_batch = SMALL_YEAR * 100 + 1
    last_batch = SMALL_YEAR * 100 + 12
    lake_rows = con.execute(f"""
        SELECT count(*) FROM {DAILY_TABLE} WHERE _batch_id BETWEEN {first_batch} AND {last_batch}
    """).fetchone()[0]
    if copied_rows != lake_rows:
        raise SystemExit(f"row count mismatch: Iceberg {lake_rows}, Postgres {copied_rows}")
    log(f"ghcn_daily_raw: {copied_rows} rows, equal to Iceberg")
    analyze(con, "ghcn_daily_raw")


def copy_reference_table(con, source_table, table_name):
    target = f"{TARGET_SCHEMA}.{table_name}"
    started = time.perf_counter()
    con.execute(f"DROP TABLE IF EXISTS {target}")
    rows = con.execute(f"CREATE TABLE {target} AS SELECT * FROM {source_table}").fetchone()[0]
    seconds = time.perf_counter() - started
    print_step(table_name, rows, None, seconds)
    analyze(con, table_name)


def main():
    con = connect()
    attach_postgres(con)
    copy_daily(con)
    copy_reference_table(con, STATIONS_TABLE, "ghcn_stations_raw")
    copy_reference_table(con, COUNTRIES_TABLE, "ghcn_countries_raw")


if __name__ == "__main__":
    main()

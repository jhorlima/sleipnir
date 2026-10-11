"""Generate TPC-H (D2) with DuckDB's dbgen into the duckdb_tpch Iceberg namespace.

Derived from TPC-H, not comparable to published TPC-H results.
Set TPCH_SF=<n> (integer). dbgen runs in TPCH_SF slices (children/step) so memory stays
near 1 GB per slice. The tables are dropped and recreated, so running twice is safe.
Prints one JSON line per table on stdout; progress goes to stderr.
"""

import json
import os
import time

from load import TABLE_PROPERTIES, connect, log

NAMESPACE = "lakehouse.duckdb_tpch"
TABLES = ["region", "nation", "supplier", "customer", "part", "partsupp", "orders", "lineitem"]


def create_table(con, table):
    columns = con.execute(
        """
        SELECT column_name || ' ' || data_type
        FROM duckdb_columns()
        WHERE schema_name = 'gen' AND table_name = ?
        ORDER BY column_index
        """,
        [table],
    ).fetchall()
    column_definitions = []
    for column in columns:
        column_definitions.append(column[0])
    con.execute(f"DROP TABLE IF EXISTS {NAMESPACE}.{table}")
    con.execute(f"CREATE TABLE {NAMESPACE}.{table} ({', '.join(column_definitions)}) {TABLE_PROPERTIES}")


def main():
    scale_factor = int(os.environ.get("TPCH_SF", "1"))
    slices = scale_factor
    con = connect()
    con.execute("LOAD tpch")
    con.execute(f"CREATE SCHEMA IF NOT EXISTS {NAMESPACE}")
    con.execute("CREATE SCHEMA gen")

    # sf=0 creates the empty tables, which give the column definitions.
    con.execute("CALL dbgen(sf = 0, schema = 'gen')")
    rows = {}
    seconds = {}
    for table in TABLES:
        create_table(con, table)
        rows[table] = 0
        seconds[table] = 0.0

    for step in range(slices):
        log(f"slice {step + 1}/{slices}")
        for table in TABLES:
            con.execute(f"DROP TABLE IF EXISTS gen.{table}")
        con.execute(f"CALL dbgen(sf = {scale_factor}, children = {slices}, step = {step}, schema = 'gen')")
        for table in TABLES:
            started = time.perf_counter()
            rows[table] += con.execute(f"INSERT INTO {NAMESPACE}.{table} SELECT * FROM gen.{table}").fetchone()[0]
            seconds[table] += time.perf_counter() - started

    for table in TABLES:
        record = {"step": f"tpch_sf{scale_factor}:{table}", "rows": rows[table], "seconds": round(seconds[table], 3)}
        print(json.dumps(record), flush=True)


if __name__ == "__main__":
    main()

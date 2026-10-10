"""Load GHCN-Daily batches and reference files into the duckdb_bronze Iceberg namespace.

Each measured step prints one JSON line on stdout; progress messages go to stderr.
Set BATCH=<YYYYMM> to load a single batch.
"""

import json
import os
import sys
import time

import duckdb

from batches import (
    SOURCE_COLUMNS,
    batch_ids_for_year,
    batch_path,
    csv_columns_sql,
    stage_year,
    write_batch,
)
from settings import LANDING_DIR, ghcn_years

NAMESPACE = "lakehouse.duckdb_bronze"
DAILY_TABLE = f"{NAMESPACE}.ghcn_daily_raw"
STATIONS_TABLE = f"{NAMESPACE}.ghcn_stations_raw"
COUNTRIES_TABLE = f"{NAMESPACE}.ghcn_countries_raw"
TABLE_PROPERTIES = "WITH ('format-version' = '2', 'write.parquet.compression-codec' = 'zstd')"


def log(message):
    print(message, file=sys.stderr, flush=True)


def print_step(step, rows, input_bytes, seconds):
    record = {
        "step": step,
        "rows": rows,
        "input_bytes": input_bytes,
        "seconds": round(seconds, 3),
        "rows_per_s": round(rows / seconds) if seconds > 0 else None,
    }
    print(json.dumps(record), flush=True)


def connect():
    con = duckdb.connect()
    con.execute("LOAD iceberg")
    con.execute("LOAD httpfs")
    con.execute(f"""
        CREATE SECRET rustfs (
            TYPE s3,
            KEY_ID '{os.environ["S3_ACCESS_KEY"]}',
            SECRET '{os.environ["S3_SECRET_KEY"]}',
            REGION '{os.environ["S3_REGION"]}',
            ENDPOINT '{os.environ["S3_ENDPOINT"]}',
            URL_STYLE 'path',
            USE_SSL false
        )
    """)
    # The warehouse has STS and remote signing off (SPEC §3.1), so DuckDB uses the static secret.
    con.execute(f"""
        ATTACH '{os.environ["LAKEKEEPER_WAREHOUSE"]}' AS lakehouse (
            TYPE iceberg,
            ENDPOINT '{os.environ["LAKEKEEPER_CATALOG_URL"]}',
            AUTHORIZATION_TYPE 'none',
            ACCESS_DELEGATION_MODE 'none',
            PURGE_REQUESTED true
        )
    """)
    settings = con.execute(
        "SELECT current_setting('threads'), current_setting('memory_limit')"
    ).fetchone()
    log(f"duckdb {duckdb.__version__}, threads={settings[0]}, memory_limit={settings[1]}")
    return con


def table_exists(con, table_name):
    count = con.execute(
        """
        SELECT count(*) FROM duckdb_tables()
        WHERE database_name = 'lakehouse' AND schema_name = 'duckdb_bronze' AND table_name = ?
        """,
        [table_name],
    ).fetchone()[0]
    return count > 0


def ensure_daily_table(con):
    con.execute(f"CREATE SCHEMA IF NOT EXISTS {NAMESPACE}")
    if table_exists(con, "ghcn_daily_raw"):
        return
    column_definitions = []
    for name, sql_type in SOURCE_COLUMNS.items():
        column_definitions.append(f"{name} {sql_type}")
    column_definitions.append("_source_file VARCHAR")
    column_definitions.append("_batch_id INTEGER")
    column_definitions.append("_ingested_at TIMESTAMPTZ")
    con.execute(f"""
        CREATE TABLE {DAILY_TABLE} ({", ".join(column_definitions)})
        PARTITIONED BY (_batch_id)
        {TABLE_PROPERTIES}
    """)
    log(f"created {DAILY_TABLE}")


def loaded_batch_ids(con):
    rows = con.execute(f"SELECT DISTINCT _batch_id FROM {DAILY_TABLE}").fetchall()
    batch_ids = set()
    for row in rows:
        batch_ids.add(row[0])
    return batch_ids


def requested_batch_ids():
    single_batch = os.environ.get("BATCH", "").strip()
    if single_batch:
        return [int(single_batch)]
    batch_ids = []
    for year in ghcn_years():
        batch_ids.extend(batch_ids_for_year(year))
    return batch_ids


def prepare_batch_files(con, batch_ids):
    """Write the batch CSVs that are missing. Not measured: it stands in for the source system."""
    configured_years = ghcn_years()
    missing_by_year = {}
    for batch_id in batch_ids:
        if batch_path(batch_id).exists():
            continue
        year = batch_id // 100
        missing_by_year.setdefault(year, []).append(batch_id)

    written = []
    for year, missing in sorted(missing_by_year.items()):
        log(f"staging {year} to write batches {missing}")
        stage_year(con, year, configured_years)
        for batch_id in missing:
            if write_batch(con, batch_id):
                written.append(batch_id)
            else:
                log(f"batch {batch_id} has no rows yet, skipped")
        con.execute("DROP TABLE observations")
    return written


def insert_batch(con, batch_id):
    path = batch_path(batch_id)
    source_file = str(path.relative_to(LANDING_DIR))
    started = time.perf_counter()
    rows = con.execute(f"""
        INSERT INTO {DAILY_TABLE}
        SELECT
            *,
            '{source_file}' AS _source_file,
            {batch_id} AS _batch_id,
            now() AS _ingested_at
        FROM read_csv('{path}', header = false, columns = {csv_columns_sql()})
    """).fetchone()[0]
    seconds = time.perf_counter() - started
    print_step(f"ghcn_daily_raw:{batch_id}", rows, path.stat().st_size, seconds)


def replace_table(con, table, columns_sql, select_sql, source_path, step):
    started = time.perf_counter()
    con.execute(f"DROP TABLE IF EXISTS {table}")
    con.execute(f"CREATE TABLE {table} ({columns_sql}) {TABLE_PROPERTIES}")
    rows = con.execute(f"INSERT INTO {table} {select_sql}").fetchone()[0]
    seconds = time.perf_counter() - started
    print_step(step, rows, source_path.stat().st_size, seconds)


def load_stations(con):
    # Fixed-width layout from the GHCN-Daily readme, section IV (1-based columns).
    path = LANDING_DIR / "ghcnd-stations.txt"
    columns_sql = """
        id VARCHAR, latitude DOUBLE, longitude DOUBLE, elevation DOUBLE, state VARCHAR,
        name VARCHAR, gsn_flag VARCHAR, hcn_crn_flag VARCHAR, wmo_id VARCHAR
    """
    select_sql = f"""
        WITH lines AS (
            SELECT unnest(string_split(content, chr(10))) AS line
            FROM read_text('{path}')
        )
        SELECT
            trim(substr(line, 1, 11)),
            trim(substr(line, 13, 8))::DOUBLE,
            trim(substr(line, 22, 9))::DOUBLE,
            trim(substr(line, 32, 6))::DOUBLE,
            nullif(trim(substr(line, 39, 2)), ''),
            trim(substr(line, 42, 30)),
            nullif(trim(substr(line, 73, 3)), ''),
            nullif(trim(substr(line, 77, 3)), ''),
            nullif(trim(substr(line, 81, 5)), '')
        FROM lines
        WHERE length(line) > 0
    """
    replace_table(con, STATIONS_TABLE, columns_sql, select_sql, path, "ghcn_stations_raw")


def load_countries(con):
    # Fixed-width layout from the GHCN-Daily readme, section V.
    path = LANDING_DIR / "ghcnd-countries.txt"
    columns_sql = "code VARCHAR, name VARCHAR"
    select_sql = f"""
        WITH lines AS (
            SELECT unnest(string_split(content, chr(10))) AS line
            FROM read_text('{path}')
        )
        SELECT trim(substr(line, 1, 2)), trim(substr(line, 4))
        FROM lines
        WHERE length(line) > 0
    """
    replace_table(con, COUNTRIES_TABLE, columns_sql, select_sql, path, "ghcn_countries_raw")


def main():
    con = connect()
    ensure_daily_table(con)

    already_loaded = loaded_batch_ids(con)
    pending = []
    for batch_id in requested_batch_ids():
        if batch_id in already_loaded:
            log(f"batch {batch_id} already loaded, skipped")
        else:
            pending.append(batch_id)

    prepare_batch_files(con, pending)
    for batch_id in pending:
        if batch_path(batch_id).exists():
            insert_batch(con, batch_id)

    load_stations(con)
    load_countries(con)


if __name__ == "__main__":
    main()

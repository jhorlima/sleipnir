"""Split the GHCN year files into monthly gzipped batch CSVs that simulate an incremental source (SPEC §5).

Batch YYYYMM holds the rows of month MM plus the 7 days before it (the tail of the previous
batch). About 1% of the batch's rows are revisions: overlap rows re-sent with a changed value.
Revisions replace the overlap copy instead of being added next to it, because two versions
of a row in the same batch would share `_ingested_at` and "latest wins" would be ambiguous.

Batches are written once and never rewritten, so every run loads byte-identical files.
Rows keep the source file order (DuckDB preserves insertion order): sorting them would make
bronze compress better than a faithful copy of the source.
"""

import datetime
import os

from settings import BATCHES_DIR, LANDING_DIR, year_file_name

OVERLAP_DAYS = 7
# Overlap rows are about a fifth of a batch, so revising 1 in 18 of them is about 1% of the batch.
REVISION_MODULUS = 18

SOURCE_COLUMNS = {
    "id": "VARCHAR",
    "date": "VARCHAR",
    "element": "VARCHAR",
    "value": "INTEGER",
    "m_flag": "VARCHAR",
    "q_flag": "VARCHAR",
    "s_flag": "VARCHAR",
    "obs_time": "VARCHAR",
}


def csv_columns_sql():
    pairs = []
    for name, sql_type in SOURCE_COLUMNS.items():
        pairs.append(f"'{name}': '{sql_type}'")
    return "{" + ", ".join(pairs) + "}"


def batch_id_for(year, month):
    return year * 100 + month


def batch_ids_for_year(year):
    batch_ids = []
    for month in range(1, 13):
        batch_ids.append(batch_id_for(year, month))
    return batch_ids


def batch_path(batch_id):
    return BATCHES_DIR / f"{batch_id}.csv.gz"


def batch_window(batch_id):
    """Return (window_start, month_start, next_month_start) as YYYYMMDD strings."""
    year = batch_id // 100
    month = batch_id % 100
    month_start = datetime.date(year, month, 1)
    if month == 12:
        next_month_start = datetime.date(year + 1, 1, 1)
    else:
        next_month_start = datetime.date(year, month + 1, 1)
    window_start = month_start - datetime.timedelta(days=OVERLAP_DAYS)
    return (
        window_start.strftime("%Y%m%d"),
        month_start.strftime("%Y%m%d"),
        next_month_start.strftime("%Y%m%d"),
    )


def stage_year(con, year, configured_years):
    """Load one year (plus the previous December, if that year is configured) into `observations`."""
    columns = csv_columns_sql()
    year_file = LANDING_DIR / year_file_name(year)
    sql = f"""
        CREATE OR REPLACE TEMP TABLE observations AS
        SELECT * FROM read_csv('{year_file}', header = false, columns = {columns})
    """
    previous_year = year - 1
    if previous_year in configured_years:
        previous_file = LANDING_DIR / year_file_name(previous_year)
        sql += f"""
        UNION ALL
        SELECT * FROM read_csv('{previous_file}', header = false, columns = {columns})
        WHERE date >= '{previous_year}1201'
        """
    con.execute(sql)


def write_batch(con, batch_id):
    """Write one batch CSV from `observations`. Returns False when the month has no rows yet."""
    window_start, month_start, next_month_start = batch_window(batch_id)
    month_rows = con.execute(
        "SELECT count(*) FROM observations WHERE date >= ? AND date < ?",
        [month_start, next_month_start],
    ).fetchone()[0]
    if month_rows == 0:
        return False

    BATCHES_DIR.mkdir(parents=True, exist_ok=True)
    target = batch_path(batch_id)
    partial = target.with_name(target.name + ".part")
    # hash() is deterministic for a pinned DuckDB version, so reruns pick the same revisions.
    con.execute(f"""
        COPY (
            SELECT
                id,
                date,
                element,
                CASE
                    WHEN date < '{month_start}' AND hash(id, date, element, {batch_id}) % {REVISION_MODULUS} = 0
                    THEN value + 1
                    ELSE value
                END AS value,
                m_flag,
                q_flag,
                s_flag,
                obs_time
            FROM observations
            WHERE date >= '{window_start}' AND date < '{next_month_start}'
        ) TO '{partial}' (FORMAT csv, HEADER false, COMPRESSION gzip)
    """)
    os.replace(partial, target)
    return True

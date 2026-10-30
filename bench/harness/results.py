"""Append-only writer for results/<suite>.parquet (SPEC §10.7). Reusable by any suite runner."""

import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

import duckdb

REPO_ROOT = Path(__file__).resolve().parents[2]
RESULTS_DIR = Path(os.environ.get("RESULTS_DIR", REPO_ROOT / "results"))

COLUMNS = {
    "run_id": "VARCHAR",
    "ts": "TIMESTAMPTZ",
    "suite": "VARCHAR",
    "scenario": "VARCHAR",
    "step": "VARCHAR",
    "dataset": "VARCHAR",
    "data_scale": "VARCHAR",
    "engine": "VARCHAR",
    "engine_version": "VARCHAR",
    "engine_config": "VARCHAR",
    "profile": "VARCHAR",
    "strategy": "VARCHAR",
    "query_id": "VARCHAR",
    "batch": "INTEGER",
    "run_type": "VARCHAR",
    "latency_ms": "DOUBLE",
    "rows": "BIGINT",
    "files_written": "BIGINT",
    "checksum_ok": "BOOLEAN",
    "status": "VARCHAR",
    "peak_mem_mb": "DOUBLE",
    "avg_cpu_pct": "DOUBLE",
    "file_count": "BIGINT",
    "storage_bytes": "BIGINT",
    "notes": "VARCHAR",
}


def new_run_id():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:6]


def make_row(**values):
    unknown = set(values) - set(COLUMNS)
    assert not unknown, f"columns not in SPEC §10.7: {sorted(unknown)}"
    row = {name: None for name in COLUMNS}
    row["ts"] = datetime.now(timezone.utc)
    row.update(values)
    return row


def append_rows(suite, rows):
    """Write existing rows + new rows to a temp file, then rename it over the parquet (atomic)."""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    target = RESULTS_DIR / f"{suite}.parquet"
    temp = RESULTS_DIR / f"{suite}.parquet.tmp"

    con = duckdb.connect()
    column_definitions = []
    for name, sql_type in COLUMNS.items():
        column_definitions.append(f'"{name}" {sql_type}')
    con.execute(f"CREATE TABLE new_rows ({', '.join(column_definitions)})")
    placeholders = ", ".join(["?"] * len(COLUMNS))
    for row in rows:
        con.execute(f"INSERT INTO new_rows VALUES ({placeholders})", list(row.values()))

    if target.exists():
        select_all = f"SELECT * FROM read_parquet('{target}') UNION ALL BY NAME SELECT * FROM new_rows"
    else:
        select_all = "SELECT * FROM new_rows"
    con.execute(f"COPY ({select_all}) TO '{temp}' (FORMAT parquet, COMPRESSION zstd)")
    os.replace(temp, target)
    return target

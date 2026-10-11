"""Correctness gate for the TPC-H queries (benchmark-integrity §5). Validation only, not measured.

Usage: python3 bench/queries/tpch/check.py duckdb|trino|starrocks

Runs the 22 queries of one engine, runs the DuckDB reference (ingest container), and compares
row count + an order-insensitive checksum. Numbers are rounded to 2 decimals, as TPC-H answers are.
Trino and StarRocks must be up (make engine-up ENGINE=<engine>). Standard library only.
Results are derived from TPC-H, not comparable to published TPC-H results.
"""

import csv
import hashlib
import io
import json
import subprocess
import sys
from pathlib import Path

QUERY_DIR = Path(__file__).resolve().parent
REPO_DIR = QUERY_DIR.parent.parent.parent


def run(command, stdin_text=None):
    completed = subprocess.run(
        command, input=stdin_text, capture_output=True, text=True, cwd=REPO_DIR
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip()[-2000:])
    return completed.stdout


def normalize(cell):
    cell = cell.strip()
    if cell == "NULL":
        return ""
    try:
        return f"{float(cell):.2f}"
    except ValueError:
        return cell


def checksum(rows):
    total = 0
    for row in rows:
        normalized = "|".join(normalize(cell) for cell in row)
        total += int(hashlib.md5(normalized.encode()).hexdigest()[:16], 16)
    return total % (1 << 64)


def duckdb_rows():
    output = run([
        "docker", "compose", "--profile", "ingest", "run", "--rm", "--no-deps", "-T",
        "-v", f"{QUERY_DIR}:/queries:ro", "ingest", "tpch_duckdb.py",
    ])
    # connect() logs to stderr; stdout is the single JSON line.
    return json.loads(output)


def trino_rows(sql):
    output = run([
        "docker", "compose", "exec", "-T", "trino", "trino",
        "--catalog", "lakehouse", "--schema", "duckdb_tpch",
        "--output-format", "CSV", "--execute", sql,
    ])
    return list(csv.reader(io.StringIO(output)))


def starrocks_rows(sql):
    output = run(
        [
            "docker", "compose", "exec", "-T", "starrocks",
            "mysql", "-h", "127.0.0.1", "-P", "9030", "-u", "root", "--batch", "--skip-column-names",
        ],
        stdin_text=f"USE lakehouse.duckdb_tpch;\n{sql}\n",
    )
    rows = []
    for line in output.splitlines():
        rows.append(line.split("\t"))
    return rows


def engine_rows(engine, path):
    sql = path.read_text().strip().rstrip(";")
    if engine == "trino":
        return trino_rows(sql)
    if engine == "starrocks":
        return starrocks_rows(sql + ";")
    raise ValueError(engine)


def main():
    engine = sys.argv[1]
    reference = duckdb_rows()
    second_duckdb_run = duckdb_rows() if engine == "duckdb" else None
    print(f"{'query':<6} {'rows':>7} {'ref rows':>9}  result   (derived from TPC-H, not comparable to published results)")
    failures = 0
    for path in sorted(QUERY_DIR.glob(f"q*.{engine}.sql")):
        name = path.name.split(".")[0]
        reference_rows = reference[name]
        try:
            if engine == "duckdb":
                rows = second_duckdb_run[name]
            else:
                rows = engine_rows(engine, path)
        except RuntimeError as error:
            failures += 1
            print(f"{name:<6} {'-':>7} {len(reference_rows):>9}  ERROR {error.args[0][-200:]!r}")
            continue
        matches = len(rows) == len(reference_rows) and checksum(rows) == checksum(reference_rows)
        if not matches:
            failures += 1
        print(f"{name:<6} {len(rows):>7} {len(reference_rows):>9}  {'ok' if matches else 'MISMATCH'}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()

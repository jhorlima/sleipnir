"""Run bench/queries/tpch/q*.duckdb.sql (mounted at /queries) on the duckdb_tpch Iceberg tables.

Prints one JSON object on stdout: {"q01": [[cell, ...], ...], ...}, every cell as text.
Used by bench/queries/tpch/check.py as the reference; not a measured step.
"""

import json
from pathlib import Path

from load import connect


def main():
    con = connect()
    con.execute("USE lakehouse.duckdb_tpch")
    results = {}
    for path in sorted(Path("/queries").glob("q*.duckdb.sql")):
        rows = con.execute(path.read_text()).fetchall()
        text_rows = []
        for row in rows:
            cells = []
            for value in row:
                cells.append("" if value is None else str(value))
            text_rows.append(cells)
        results[path.name.split(".")[0]] = text_rows
    print(json.dumps(results))


if __name__ == "__main__":
    main()

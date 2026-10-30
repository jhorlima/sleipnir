"""Pure parsers for tool output: load.py JSON lines, dbt run_results.json, dbt microbatch log lines,
docker stats cells. Self-check: `uv run python parsers.py`."""

import json
import re

UNIT_MB = {
    "B": 1 / 1024 / 1024,
    "KB": 1 / 1000,
    "KIB": 1 / 1024,
    "MB": 1.0,
    "MIB": 1.0,
    "GB": 1000.0,
    "GIB": 1024.0,
}

# dbt >= 1.9 logs one line per microbatch batch; run_results.json only has per-model times.
BATCH_LINE = re.compile(
    r"Batch (\d+) of (\d+) OK created .*?batch (\d{4})-(\d{2})(?:-\d{2})?\b(?: of (\S+))?.*?\bin ([\d.]+)s"
)


def parse_load_line(line):
    """A load.py step record, or None when the line is any other output."""
    line = line.strip()
    if not line.startswith("{"):
        return None
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        return None
    if "step" not in record or "seconds" not in record:
        return None
    return record


def batch_from_step(step):
    """'ghcn_daily_raw:201003' -> 201003; steps without a batch -> None."""
    if ":" not in step:
        return None
    return int(step.split(":")[1])


def parse_run_results(run_results):
    """One dict per node: name, status, seconds, rows. `run_results` is the loaded JSON."""
    steps = []
    for result in run_results["results"]:
        name = result["unique_id"].split(".")[-1]
        rows = result.get("adapter_response", {}).get("rows_affected")
        if rows is not None and rows < 0:
            rows = None
        status = "ok" if result["status"] in ("success", "pass") else result["status"]
        steps.append({"name": name, "status": status, "seconds": result["execution_time"], "rows": rows})
    return steps


def parse_batch_line(line):
    """A microbatch 'Batch N of M OK created batch YYYY-MM...' line -> dict, or None."""
    match = BATCH_LINE.search(line)
    if match is None:
        return None
    return {
        "model": match.group(5),
        "batch": int(match.group(3) + match.group(4)),
        "seconds": float(match.group(6)),
    }


def parse_mem_mb(cell):
    """docker stats MemUsage '925.5MiB / 8GiB' -> 925.5."""
    used = cell.split("/")[0].strip()
    match = re.match(r"([\d.]+)\s*([A-Za-z]+)", used)
    return float(match.group(1)) * UNIT_MB[match.group(2).upper()]


def parse_cpu_pct(cell):
    return float(cell.strip().rstrip("%"))


def _self_check():
    assert parse_load_line('{"step": "ghcn_daily_raw:201003", "rows": 5, "seconds": 1.5}')["rows"] == 5
    assert parse_load_line("duckdb 1.5.6, threads=4") is None
    assert parse_load_line("{broken") is None
    assert batch_from_step("ghcn_daily_raw:201003") == 201003
    assert batch_from_step("ghcn_stations_raw") is None

    run_results = {
        "results": [
            {"unique_id": "model.sleipnir.dim_date", "status": "success", "execution_time": 2.5,
             "adapter_response": {"rows_affected": 7000}},
            {"unique_id": "model.sleipnir.dim_station", "status": "error", "execution_time": 0.1,
             "adapter_response": {"rows_affected": -1}},
        ]
    }
    steps = parse_run_results(run_results)
    assert steps[0] == {"name": "dim_date", "status": "ok", "seconds": 2.5, "rows": 7000}
    assert steps[1]["status"] == "error" and steps[1]["rows"] is None

    line = "12:00:01  Batch 3 of 192 OK created batch 2010-03-01 of trino_silver.ghcn_daily ... [SUCCESS in 4.21s]"
    assert parse_batch_line(line) == {"model": "trino_silver.ghcn_daily", "batch": 201003, "seconds": 4.21}
    assert parse_batch_line("Batch 4 of 192 OK created batch 2010-04 in 2s")["batch"] == 201004
    assert parse_batch_line("1 of 1 OK created sql view model x in 1.0s") is None

    assert parse_mem_mb("925.5MiB / 8GiB") == 925.5
    assert parse_mem_mb("1.5GiB / 8GiB") == 1536.0
    assert parse_cpu_pct("53.22%") == 53.22
    print("parsers ok")


if __name__ == "__main__":
    _self_check()

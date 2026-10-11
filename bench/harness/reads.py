"""Runs one read suite for one engine and appends results/<suite>.parquet (SPEC §10.2, §10.6).
Runs inside the `bench` compose container (started by `make bench`, see run.py), on the compose network.

  b3  direct SQL on the engine                       (scenario "direct")
  b4  the same questions through the Cube REST API   (scenario "cube")
  b5  accelerated runs, --scenario b5a|b5b|b5c

Per query: restart the engine (cold) -> 1 cold run, 1 discarded warm-up, 5 measured warm runs.
Every run is compared with the DuckDB reference; a run that does not match is recorded as invalid.
Env: DATA_SCALE, QUERY_TIMEOUT_S (default 300), ENGINE_CPUS/ENGINE_MEMORY (DuckDB limits), BENCH_IMAGE.
"""

import argparse
import json
import os
import subprocess
import sys
import threading
import time

import duckdb

from checks import (
    compare_results,
    explain_reads_base_tables,
    explain_uses_mvs,
    pre_aggregations_gate,
    protocol_plan,
    rows_to_text,
)
from clients import (
    CubeClient,
    DuckDBClient,
    PostgresClient,
    StarRocksClient,
    TrinoClient,
    duckdb_memory_limit_gb,
    duckdb_threads,
)
from results import REPO_ROOT, append_rows, make_row, new_run_id
from run import read_engine_config, read_engine_image
from sampling import StatsSampler, container_ids

QUERIES_DIR = REPO_ROOT / "bench" / "queries"
SQL_DIR = QUERIES_DIR / "sql"
TPCH_DIR = QUERIES_DIR / "tpch"
CUBE_DIR = QUERIES_DIR / "cube"

# The in-process DuckDB runs inside the bench container, so that is the service whose stats are sampled.
ENGINE_SERVICE = {"trino": "trino", "starrocks": "starrocks", "postgres": "postgres-bench", "duckdb": "bench"}
CUBE_SERVICE = "cube-api"
GOLD_TABLES = ("fct_weather_daily", "dim_station", "dim_date")
D1_QUERIES = ["q1", "q2", "q3", "q4", "q5", "q6"]
# Trino's approx_percentile is not deterministic: the last N columns of these Cube queries match within 5%.
APPROX_MEASURE_COLUMNS = {"q7": 2, "q8": 1}
HEALTHY_TIMEOUT_SECONDS = 900


def log(message):
    print(message, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- docker (restart, limits, caches)

def docker(*command):
    return subprocess.run(["docker", *command], capture_output=True, text=True)


def container_id(service):
    ids = container_ids(service)
    if not ids:
        raise RuntimeError(f"no running container for service {service}")
    return ids[0]


def wait_healthy(service):
    identifier = container_id(service)
    deadline = time.monotonic() + HEALTHY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        health = docker("inspect", "--format", "{{.State.Health.Status}}", identifier).stdout.strip()
        if health == "healthy":
            return
        time.sleep(3)
    raise RuntimeError(f"{service} not healthy after {HEALTHY_TIMEOUT_SECONDS} s")


def restart_and_wait(service):
    docker("restart", container_id(service))
    wait_healthy(service)


def drop_page_cache():
    """Best effort: a privileged container writes the VM's drop_caches. Returns a note for the row."""
    result = docker(
        "run", "--rm", "--privileged", os.environ["BENCH_IMAGE"],
        "sh", "-c", "sync; echo 3 > /proc/sys/vm/drop_caches",
    )
    if result.returncode == 0:
        return "page cache dropped"
    return "page cache NOT dropped"


def container_limits(service):
    inspected = json.loads(docker("inspect", container_id(service)).stdout)[0]
    cpus = inspected["HostConfig"]["NanoCpus"] / 1e9
    memory_gb = inspected["HostConfig"]["Memory"] / 1024**3
    environment = dict(entry.split("=", 1) for entry in inspected["Config"]["Env"])
    return f"limits: cpus={cpus:g}, memory={memory_gb:g}GB", environment


# ---------------------------------------------------------------- what a run needs

class Setup:
    """Everything that depends on suite, scenario, engine and dataset; built once per run."""

    def __init__(self, args):
        self.args = args
        self.engine = args.engine
        self.suite = args.suite
        self.dataset = args.dataset
        self.via_cube = args.suite == "b4" or args.scenario in ("b5b", "b5c")
        self.scenario = {"b3": "direct", "b4": "cube"}.get(args.suite, args.scenario)
        self.timeout_seconds = float(os.environ.get("QUERY_TIMEOUT_S", "300"))
        self.explain_gate = args.scenario == "b5a"
        self.pre_aggregation_gate = args.scenario == "b5c"
        self.data_scale = os.environ.get("DATA_SCALE") or self.default_data_scale()
        self.schema = self.lake_schema() if self.engine != "postgres" else "postgres_gold"
        if self.engine == "postgres":
            self.reference_source = "postgres"
        else:
            self.reference_source = "lakehouse"
        self.stats_service = ENGINE_SERVICE[self.engine]
        self.restart_services = self.services_to_restart()

    def default_data_scale(self):
        if self.dataset == "tpch":
            return f"sf{os.environ.get('SF', '1')}"
        if self.engine == "postgres":
            return "small"
        return "r2"

    def lake_schema(self):
        if self.dataset == "tpch":
            return "duckdb_tpch"
        return os.environ.get("GOLD_NAMESPACE", "trino_gold")

    def services_to_restart(self):
        services = []
        if self.engine != "duckdb":
            services.append(ENGINE_SERVICE[self.engine])
        if self.via_cube:
            services.append(CUBE_SERVICE)
        return services

    def new_client(self):
        if self.via_cube:
            return CubeClient(self.timeout_seconds)
        if self.engine == "trino":
            return TrinoClient(self.schema)
        if self.engine == "starrocks":
            return StarRocksClient(self.schema, mv_rewrite=self.explain_gate)
        if self.engine == "duckdb":
            return DuckDBClient(self.schema)
        return PostgresClient(self.schema)

    def engine_metadata(self):
        """engine_version and engine_config, recorded like B2 (benchmark-integrity §3); D-22 for DuckDB via Cube."""
        if self.engine == "duckdb" and not self.via_cube:
            limits, _ = container_limits("bench")
            config = f"threads={duckdb_threads()}; memory_limit={duckdb_memory_limit_gb()}GB; {limits}"
            return f"duckdb {duckdb.__version__}", config
        service = ENGINE_SERVICE[self.engine]
        if not self.via_cube:
            limits, _ = container_limits(service)
            return read_engine_image(service), f"{read_engine_config(service) or ''}\n{limits}".strip()

        cube_limits, cube_environment = container_limits(CUBE_SERVICE)
        cube_image = read_engine_image(CUBE_SERVICE)
        if self.engine == "duckdb":
            memory = cube_environment.get("CUBEJS_DS_DUCKDB_DB_DUCKDB_MEMORY_LIMIT")
            threads = cube_environment.get("CUBE_DUCKDB_THREADS")
            config = f"duckdb embedded in {CUBE_SERVICE}: threads={threads}; memory_limit={memory}; {cube_limits}"
            return f"{cube_image} (embedded duckdb)", config
        engine_limits, _ = container_limits(service)
        engine_config = f"{read_engine_config(service) or ''}\n{engine_limits}".strip()
        config = f"{engine_config}\ncube-api {cube_limits}"
        return f"{read_engine_image(service)}; {cube_image}", config


# ---------------------------------------------------------------- queries and references

def query_ids(setup):
    if setup.args.queries:
        return setup.args.queries.split(",")
    if setup.dataset == "tpch":
        paths = sorted(TPCH_DIR.glob(f"q*.{setup.engine}.sql"))
        return [path.name.split(".")[0] for path in paths]
    return D1_QUERIES


def load_queries(setup):
    """[(query_id, query, reference_sql)] where query is SQL text or a Cube query dict."""
    sql_dir = TPCH_DIR if setup.dataset == "tpch" else SQL_DIR
    queries = []
    for query_id in query_ids(setup):
        reference_path = sql_dir / f"{query_id}.duckdb.sql"
        if setup.via_cube:
            query_path = CUBE_DIR / f"{query_id}.json"
        else:
            query_path = sql_dir / f"{query_id}.{setup.engine}.sql"
        if not query_path.exists() or not reference_path.exists():
            log(f"skip {query_id}: needs {query_path.name} and {reference_path.name}")
            continue
        if setup.via_cube:
            # The query files name the trino view; the engine picks its own (as in scripts/cube-query.sh).
            query = json.loads(query_path.read_text().replace("trino_weather", f"{setup.engine}_weather"))
        else:
            query = query_path.read_text().strip().rstrip(";")
        queries.append((query_id, query, reference_path.read_text().strip().rstrip(";")))
    return queries


def reference_rows(setup, reference_sql):
    """DuckDB answer on the same data, outside the measured steps."""
    client = DuckDBClient(setup.schema, source=setup.reference_source)
    try:
        return rows_to_text(client.execute(reference_sql))
    finally:
        client.close()


# ---------------------------------------------------------------- one measured run

def measure_once(client, query, setup):
    timed_out = threading.Event()

    def on_timeout():
        timed_out.set()
        client.cancel()

    rows = None
    error = None
    with StatsSampler(setup.stats_service) as sampler:
        timer = threading.Timer(setup.timeout_seconds, on_timeout)
        timer.start()
        started = time.perf_counter()
        try:
            rows = client.execute(query)
        except Exception as caught:  # noqa: BLE001 - any driver error is a failed run, recorded as such
            error = caught
        latency_ms = (time.perf_counter() - started) * 1000
        timer.cancel()
    timed_out_flag = timed_out.is_set() or isinstance(error, TimeoutError)
    return {
        "rows": rows, "error": error, "timed_out": timed_out_flag, "latency_ms": latency_ms,
        "peak_mem_mb": sampler.peak_mem_mb, "avg_cpu_pct": sampler.avg_cpu_pct,
    }


def judge(measurement, setup, query_id, reference, client):
    """(status, checksum_ok, notes, row_count) for one run."""
    if measurement["timed_out"]:
        return "timeout", None, f"timeout after {setup.timeout_seconds:g} s", None
    if measurement["error"] is not None:
        return "failed", None, f"{type(measurement['error']).__name__}: {str(measurement['error'])[:300]}", None

    text_rows = rows_to_text(measurement["rows"])
    approx_columns = 0
    if setup.via_cube and setup.engine == "trino":
        approx_columns = APPROX_MEASURE_COLUMNS.get(query_id, 0)
    matches, note = compare_results(text_rows, reference, approx_columns)
    notes = [note] if note else []
    status = "ok" if matches else "invalid"
    if setup.pre_aggregation_gate:
        used, gate_note = pre_aggregations_gate(client.last_response)
        notes.append(gate_note)
        if not used:
            status = "invalid"
    return status, matches, "; ".join(notes), len(text_rows)


def explain_gate(client, sql):
    """B5a: the EXPLAIN must scan the MV of every gold table the query reads (SPEC §10.3)."""
    tables = [table for table in GOLD_TABLES if table in sql]
    plan = client.explain(sql)
    uses_mvs, note = explain_uses_mvs(plan, tables)
    base_reads = explain_reads_base_tables(plan, tables)
    if base_reads:
        return False, f"EXPLAIN still scans the base table(s): {', '.join(base_reads)}"
    if not uses_mvs:
        return False, note
    return True, f"EXPLAIN scans {', '.join('mv_' + table for table in tables)}"


def run_query(setup, query_id, query, reference, base):
    rows = []
    client = None
    cold_note = ""
    for run_type, repetition in protocol_plan():
        if run_type == "cold":
            if client is not None:
                client.close()
            cold_note = cold_start(setup)
            client = setup.new_client()
        measurement = measure_once(client, query, setup)
        status, checksum_ok, notes, row_count = judge(measurement, setup, query_id, reference, client)
        notes_parts = [notes]
        if run_type == "cold":
            notes_parts.append(cold_note)
        if setup.scenario == "b5b":
            notes_parts.append("label only: mv_weather_wide does not exist yet, reads the gold tables")
        if setup.via_cube:
            notes_parts.append("renewQuery=true, cache=no-cache")
        if setup.engine == "starrocks" and setup.via_cube:
            notes_parts.append("StarRocks MV rewrite disabled globally for the Cube path")
        row = make_row(
            **base,
            step=query_id, query_id=query_id, batch=repetition, run_type=run_type,
            latency_ms=measurement["latency_ms"], rows=row_count, checksum_ok=checksum_ok, status=status,
            peak_mem_mb=measurement["peak_mem_mb"], avg_cpu_pct=measurement["avg_cpu_pct"],
            notes="; ".join(part for part in notes_parts if part),
        )
        rows.append(row)
        log(f"  {query_id} {run_type}#{repetition}: {status} {measurement['latency_ms']:.0f} ms")

        if run_type == "cold" and setup.explain_gate and status == "ok":
            gate_ok, gate_note = explain_gate(client, query)
            row["notes"] = "; ".join(part for part in (row["notes"], gate_note) if part)
            if not gate_ok:
                row["status"] = "invalid"
        if row["status"] in ("timeout", "failed") or (setup.explain_gate and row["status"] == "invalid"):
            break
    if client is not None:
        client.close()
    return rows


def cold_start(setup):
    """Restart the engine (and Cube) and drop the page cache; the DuckDB engine is a fresh connection."""
    if not setup.restart_services:
        return "fresh in-process connection"
    note = drop_page_cache()
    for service in setup.restart_services:
        restart_and_wait(service)
    return f"restarted {', '.join(setup.restart_services)}; {note}"


def prepare_starrocks_for_cube():
    """The Cube path reads through the engine's global session defaults: MV rewrite is off for B4 and B5b/c."""
    client = StarRocksClient("trino_gold", mv_rewrite=False)
    client.cursor.execute("SET GLOBAL enable_materialized_view_rewrite = false")
    client.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=["b3", "b4", "b5"], required=True)
    parser.add_argument("--engine", choices=list(ENGINE_SERVICE), required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--dataset", choices=["ghcn", "tpch"], default="ghcn")
    parser.add_argument("--scenario", choices=["", "b5a", "b5b", "b5c"], default="")
    parser.add_argument("--queries", default="", help="comma list, e.g. q1,q2 (default: all of the dataset)")
    args = parser.parse_args()
    if args.suite == "b5" and not args.scenario:
        parser.error("b5 needs --scenario b5a|b5b|b5c")
    if args.suite == "b4" and args.dataset == "tpch":
        parser.error("b4 runs the Cube questions (ghcn only)")
    if args.scenario == "b5a" and args.engine != "starrocks":
        parser.error("b5a is the StarRocks MV scenario")

    setup = Setup(args)
    queries = load_queries(setup)
    engine_version, engine_config = setup.engine_metadata()
    if setup.engine == "starrocks" and setup.via_cube:
        prepare_starrocks_for_cube()

    base = {
        "run_id": new_run_id(), "suite": setup.suite, "scenario": setup.scenario, "dataset": setup.dataset,
        "data_scale": setup.data_scale, "engine": setup.engine, "engine_version": engine_version,
        "engine_config": engine_config, "profile": args.profile,
    }
    counts = {}
    for query_id, query, reference_sql in queries:
        log(f"{setup.suite}/{setup.scenario} {setup.engine} {query_id}")
        try:
            reference = reference_rows(setup, reference_sql)
        except Exception as caught:  # noqa: BLE001 - no reference means the query cannot be validated
            log(f"  reference failed: {caught}")
            rows = [make_row(
                **base, step=query_id, query_id=query_id, run_type="cold", status="invalid",
                notes=f"DuckDB reference failed: {str(caught)[:300]}",
            )]
        else:
            rows = run_query(setup, query_id, query, reference, base)
        target = append_rows(setup.suite, rows)
        for row in rows:
            counts[row["status"]] = counts.get(row["status"], 0) + 1
    log(f"done, rows by status: {counts}; results in {target if queries else 'nothing run'}")


if __name__ == "__main__":
    main()

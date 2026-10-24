"""Runs one measured suite (b1..b5) and appends its rows. b1/b2 wrap the existing make targets;
b3/b4/b5 start the `bench` container, which runs reads.py on the compose network.

Usage: python run.py b1|b2 --engine <engine> --profile <s|m|l> [--args "<dbt args>"]
       python run.py b3|b4|b5 --engine <engine> --profile <s|m|l> [--dataset ghcn|tpch] [--scenario b5a|b5b|b5c] [--queries q1,q2]
Env: DATA_SCALE (default r2), STRATEGY (dbt incremental_strategy var, default: model default),
     SCENARIO (default per suite), DBT_MAKE_TARGET (b2 only, default dbt-run), REPROCESS_FROM_BATCH and
     MICROBATCH_BEGIN (b2 only, dbt vars of the same name), SCHEMA_SUFFIX (b2: _small, read by dbt).
b2.py drives this module for the whole B2 campaign (`make b2-campaign`).
Measure microbatch with STRATEGY=microbatch and ARGS='--event-time-start ... --event-time-end ...',
not with dbt-backfill: its maintenance run-operations would be timed and overwrite run_results.json.
"""

import argparse
import json
import os
import platform
import subprocess
import sys
import time

from parsers import (
    batch_from_step,
    parse_batch_line,
    parse_load_line,
    parse_run_results,
)
from results import REPO_ROOT, append_rows, make_row, new_run_id
from sampling import StatsSampler, container_ids

DBT_RUN_RESULTS = REPO_ROOT / "dbt" / "target" / "run_results.json"


def reexec_under_caffeinate():
    # Host sleep freezes the Docker VM and Trino abandons its tasks (ABANDONED_TASK),
    # so a measurement on macOS must run with idle sleep prevented.
    if platform.system() != "Darwin":
        return
    if os.environ.get("SLEIPNIR_CAFFEINATED") == "1":
        return
    os.environ["SLEIPNIR_CAFFEINATED"] = "1"
    os.execvp("caffeinate", ["caffeinate", "-i", sys.executable, *sys.argv])


def run_measured(command, service):
    """Run `command`, echo its output, and return (output_lines, returncode, wall_seconds, sampler)."""
    output_lines = []
    started = time.perf_counter()
    with StatsSampler(service) as sampler:
        process = subprocess.Popen(
            command, cwd=REPO_ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
        )
        for line in process.stdout:
            print(line, end="", file=sys.stderr, flush=True)
            output_lines.append(line)
        returncode = process.wait()
    wall_seconds = time.perf_counter() - started
    return output_lines, returncode, wall_seconds, sampler


def read_docker_vm():
    """CPUs and memory of the Docker VM: the page cache and headroom around the engine depend on it."""
    info = subprocess.run(
        ["docker", "info", "--format", "{{.NCPU}} {{.MemTotal}}"], capture_output=True, text=True, check=True
    )
    cpus, memory_bytes = info.stdout.split()
    vm = f"docker_vm: cpus={cpus} memory_gib={int(memory_bytes) / 2**30:.1f}"
    # The object store is shared infrastructure, but its limits move the numbers (D-26), so they are recorded too.
    rustfs = subprocess.run(
        ["docker", "inspect", "--format", "{{.HostConfig.NanoCpus}} {{.HostConfig.Memory}}", "sleipnir-rustfs-1"],
        capture_output=True, text=True,
    )
    if rustfs.returncode != 0:
        return vm
    nano_cpus, rustfs_memory_bytes = rustfs.stdout.split()
    return f"{vm} rustfs_cpus={int(nano_cpus) / 1e9:g} rustfs_memory_gib={int(rustfs_memory_bytes) / 2**30:g}"


def read_engine_config(engine):
    """Docker VM size plus the non-comment lines of the files directly under config/<engine>/ (benchmark-integrity §3)."""
    settings = [read_docker_vm()]
    config_dir = REPO_ROOT / "config" / engine
    if not config_dir.is_dir():
        return "\n".join(settings)
    for path in sorted(config_dir.iterdir()):
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                settings.append(f"{path.name}: {line}")
    return "\n".join(settings)


def read_engine_image(service):
    """Image of the running engine container (carries the pinned version tag)."""
    ids = container_ids(service)
    if not ids:
        return None
    result = subprocess.run(
        ["docker", "inspect", "--format", "{{.Config.Image}}", ids[0]], capture_output=True, text=True
    )
    return result.stdout.strip()


def base_fields(args, run_id, suite, scenario):
    return {
        "run_id": run_id,
        "suite": suite,
        "scenario": scenario,
        "dataset": "ghcn",
        "data_scale": os.environ.get("DATA_SCALE", "r2"),
        "engine": args.engine,
        "profile": args.profile,
        "strategy": os.environ.get("STRATEGY") or "default",
        "run_type": "measured",
    }


def stats_fields(sampler):
    return {"peak_mem_mb": sampler.peak_mem_mb, "avg_cpu_pct": sampler.avg_cpu_pct}


def run_b1(args):
    """B1: `make ingest`; one row per load.py JSON line plus a total."""
    run_id = new_run_id()
    base = base_fields(args, run_id, "b1", os.environ.get("SCENARIO", "ingest"))
    command = ["make", "ingest", f"PROFILE={args.profile}"]
    lines, returncode, wall_seconds, sampler = run_measured(command, service="ingest")

    engine_version = None
    engine_config = None
    for line in lines:
        if line.startswith("duckdb "):
            engine_version = line.split(",")[0].strip()
            engine_config = line.strip()

    rows = []
    total_seconds = 0.0
    for line in lines:
        record = parse_load_line(line)
        if record is None:
            continue
        total_seconds += record["seconds"]
        rows.append(make_row(
            **base, **stats_fields(sampler),
            step=record["step"],
            batch=batch_from_step(record["step"]),
            latency_ms=record["seconds"] * 1000,
            rows=record["rows"],
            status="ok",
            engine_version=engine_version,
            engine_config=engine_config,
            notes=f"input_bytes={record['input_bytes']}; mem/cpu sampled over the whole command",
        ))

    status = "ok" if returncode == 0 else "error"
    rows.append(make_row(
        **base, **stats_fields(sampler),
        step="total",
        latency_ms=total_seconds * 1000,
        status=status,
        engine_version=engine_version,
        engine_config=engine_config,
        notes=f"sum of steps; wall={wall_seconds:.1f}s",
    ))
    return rows, returncode


def dbt_vars():
    # benchmark-integrity §8: no maintenance inside a measured run.
    entries = ["maintenance: false"]
    if os.environ.get("STRATEGY"):
        entries.append(f"incremental_strategy: {os.environ['STRATEGY']}")
    if os.environ.get("REPROCESS_FROM_BATCH"):
        entries.append(f"reprocess_from_batch: {os.environ['REPROCESS_FROM_BATCH']}")
    if os.environ.get("MICROBATCH_BEGIN"):
        entries.append(f'microbatch_begin: "{os.environ["MICROBATCH_BEGIN"]}"')
    if os.environ.get("MICROBATCH_BATCH_SIZE"):
        entries.append(f"microbatch_batch_size: {os.environ['MICROBATCH_BATCH_SIZE']}")
    return "{" + ", ".join(entries) + "}"


def compose_service(engine):
    # The service `postgres` is the catalog Postgres; the benchmark one is postgres-bench.
    return "postgres-bench" if engine == "postgres" else engine


def run_b2(args):
    """B2: a dbt make target; one row per node from run_results.json, one per microbatch batch, plus a total."""
    run_id = new_run_id()
    make_target = os.environ.get("DBT_MAKE_TARGET", "dbt-run")
    base = base_fields(args, run_id, "b2", os.environ.get("SCENARIO", make_target))
    command = [
        "make", make_target,
        f"PROFILE={args.profile}", f"DBT_TARGET={args.engine}",
        f"VARS={dbt_vars()}", f"ARGS={args.args}",
    ]
    # A stale file from an earlier run must never be read as this run's result.
    DBT_RUN_RESULTS.unlink(missing_ok=True)
    lines, returncode, wall_seconds, sampler = run_measured(command, service=compose_service(args.engine))

    common = {
        **base, **stats_fields(sampler),
        "engine_version": read_engine_image(compose_service(args.engine)),
        "engine_config": read_engine_config(args.engine),
    }
    rows = []
    total_seconds = None
    if DBT_RUN_RESULTS.exists():
        run_results = json.loads(DBT_RUN_RESULTS.read_text())
        total_seconds = run_results["elapsed_time"]
        for step in parse_run_results(run_results):
            rows.append(make_row(
                **common,
                step=step["name"],
                latency_ms=step["seconds"] * 1000,
                rows=step["rows"],
                status=step["status"],
                notes="mem/cpu sampled over the whole command",
            ))
    for line in lines:
        batch = parse_batch_line(line)
        if batch is None:
            continue
        rows.append(make_row(
            **common,
            step=f"{batch['model']}:{batch['batch']}",
            batch=batch["batch"],
            latency_ms=batch["seconds"] * 1000,
            status="ok",
            notes="microbatch batch, from the dbt log",
        ))

    rows.append(make_row(
        **common,
        step="total",
        latency_ms=(total_seconds if total_seconds is not None else wall_seconds) * 1000,
        status="ok" if returncode == 0 else "error",
        notes=f"dbt elapsed_time; wall={wall_seconds:.1f}s",
    ))
    return rows, returncode


def run_reads(args):
    """b3/b4/b5: reads.py runs in the bench container (engine restarts and docker stats go through its socket)."""
    # B6 labels the rows of a variant through these (see reads.py); GOLD_NAMESPACE and RESULTS_DIR go through compose.
    passthrough = []
    for name in ("RESULTS_SUITE", "SCENARIO_LABEL", "ENGINE_CONFIG_EXTRA"):
        if name in os.environ:
            passthrough += ["-e", name]
    command = [
        "docker", "compose", "--env-file", ".env", "--env-file", f"env/{args.profile}.env",
        "--profile", "bench", "run", "--rm", "-T", *passthrough, "bench",
        "python", "reads.py", "--suite", args.suite, "--engine", args.engine, "--profile", args.profile,
        "--dataset", args.dataset, "--scenario", args.scenario, "--queries", args.queries,
    ]
    return subprocess.run(command, cwd=REPO_ROOT).returncode


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("suite", choices=["b1", "b2", "b3", "b4", "b5"])
    parser.add_argument("--engine", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--args", default="", help="b2: extra dbt args, e.g. '--select dim_date'")
    parser.add_argument("--dataset", default="ghcn", help="b3: ghcn (D1) or tpch (D2)")
    parser.add_argument("--scenario", default="", help="b5: b5a, b5b or b5c")
    parser.add_argument("--queries", default="", help="b3/b4/b5: comma list, e.g. q1,q2 (default: all)")
    args = parser.parse_args()

    reexec_under_caffeinate()

    if args.suite in ("b3", "b4", "b5"):
        sys.exit(run_reads(args))

    if args.suite == "b1":
        rows, returncode = run_b1(args)
    else:
        rows, returncode = run_b2(args)

    # Failed runs are recorded too (status=error), never dropped.
    target = append_rows(args.suite, rows)
    print(f"appended {len(rows)} rows to {target}", file=sys.stderr)
    sys.exit(returncode)


if __name__ == "__main__":
    main()

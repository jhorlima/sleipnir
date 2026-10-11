"""B2 campaign (transformation, SPEC §7.1, §10.2) for one writer engine and one data scale:
  full           silver + gold built from scratch with microbatch (one batch per month), maintenance off
  maintenance    maintain_table on each incremental table, one row per operation (its own measured step)
  incremental_*  the latest bronze batch reprocessed on the fully built tables, once per strategy, N warm runs each

Reprocessing the same bronze data is idempotent, so the correctness gate (benchmark-integrity §5) is: row count
and checksums of every incremental table after the run equal the values before it. A mismatch records the run's
rows as status=invalid with checksum_ok=false (never dropped) and stops the campaign, because the tables are no
longer the reference state; rebuild with the full scenario and resume.

Resumable: a step whose `total` row is already status=ok in results/b2.parquet (same engine, scale, profile,
scenario, strategy, repeat) is skipped.

Usage: python b2.py --engine trino|spark|postgres --profile s|m|l --scale r2|small
         [--only full,maintenance,incremental] [--strategies merge,microbatch] [--repeats 3] [--reprocess-batch 202512]
Env: RESULTS_DIR (see results.py).
"""

import argparse
import os
import re
import subprocess
import sys
from argparse import Namespace
from datetime import date

import duckdb

import run
from results import REPO_ROOT, RESULTS_DIR, append_rows, make_row, new_run_id

STRATEGIES = {
    "trino": ["merge", "delete+insert", "microbatch"],
    "spark": ["merge", "insert_overwrite", "microbatch"],
    "postgres": ["merge", "delete+insert", "microbatch"],
}
# B5b has its own measured refresh of this table; it is not part of the transformation.
EXCLUDE_MV = "--exclude mv_weather_wide"
# Full build window per scale: the microbatch begin and the exclusive end of the last batch.
SCALE_WINDOW = {"r2": ("2010-01-01", "2026-01-01"), "small": ("2025-01-01", "2026-01-01")}

MAINTAIN_LINE = re.compile(r"maintain_table (\S+): (.+) in ([\d.]+) s")


def log(message):
    print(f"[b2] {message}", file=sys.stderr, flush=True)


def schema_suffix(engine, scale):
    # Postgres is small-only and keeps postgres_silver / postgres_gold.
    if scale == "small" and engine != "postgres":
        return "_small"
    return ""


def tables(engine, scale):
    """Incremental tables with the aggregates that make up their checksum (integers, so order never matters)."""
    suffix = schema_suffix(engine, scale)
    catalog = "" if engine == "postgres" else "lakehouse."
    silver = f"{engine}_silver{suffix}"
    gold = f"{engine}_gold{suffix}"
    return {
        f"{silver}.ghcn_daily": (
            f"{catalog}{silver}.ghcn_daily",
            "count(*), sum(cast(round(value * 10) as bigint))",
        ),
        f"{gold}.fct_weather_daily": (
            f"{catalog}{gold}.fct_weather_daily",
            "count(*), sum(cast(round(prcp * 10) as bigint)), sum(cast(round(tmax * 10) as bigint))",
        ),
        f"{gold}.agg_weather_monthly_country": (
            f"{catalog}{gold}.agg_weather_monthly_country",
            "count(*), sum(cast(station_day_count as bigint)), sum(cast(round(total_prcp * 10) as bigint))",
        ),
    }


def query_line(engine, sql):
    """Run one statement in the engine's CLI and return the last data line as a list of cells."""
    if engine == "trino":
        command = ["docker", "compose", "exec", "-T", "trino", "trino", "--output-format", "TSV", "--execute", sql]
    elif engine == "spark":
        command = ["docker", "compose", "exec", "-T", "spark", "/opt/spark/bin/beeline", "-u",
                   "jdbc:hive2://localhost:10000", "--silent=true", "--outputformat=tsv2", "-e", sql]
    else:
        command = ["docker", "compose", "exec", "-T", "postgres-bench", "psql", "-U", "sleipnir", "-d", "sleipnir",
                   "-At", "-F", "\t", "-c", sql]
    result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"{engine} query failed: {result.stderr[-500:]}")
    # beeline prints the header and prompts around the answer; the answer is the last line starting with a digit.
    data_lines = [line for line in result.stdout.splitlines() if line.strip().strip('"')[:1].isdigit()]
    return [cell.strip('"') for cell in data_lines[-1].split("\t")]


def read_checksums(engine, scale):
    checksums = {}
    for name, (relation, aggregates) in tables(engine, scale).items():
        checksums[name] = query_line(engine, f"select {aggregates} from {relation}")
    return checksums


def ensure_engine(engine, profile):
    """Only one engine at a time (benchmark-integrity §1)."""
    for other in ("trino", "spark", "postgres"):
        if other != engine:
            subprocess.run(["make", "engine-down", f"ENGINE={other}"], cwd=REPO_ROOT, check=True, capture_output=True)
    subprocess.run(["make", "engine-up", f"ENGINE={engine}", f"PROFILE={profile}"], cwd=REPO_ROOT, check=True)


def is_done(args, scenario, strategy, repeat):
    target = RESULTS_DIR / "b2.parquet"
    if not target.exists():
        return False
    count = duckdb.connect().execute(
        f"select count(*) from read_parquet('{target}') where suite = 'b2' and step = 'total' and status = 'ok' "
        "and engine = ? and data_scale = ? and profile = ? and scenario = ? and strategy = ? and notes like ?",
        [args.engine, args.scale, args.profile, scenario, strategy, f"repeat={repeat};%"],
    ).fetchone()[0]
    return count > 0


def set_run_environment(args, scenario, strategy, reprocess_batch=""):
    os.environ["DATA_SCALE"] = args.scale
    os.environ["SCHEMA_SUFFIX"] = schema_suffix(args.engine, args.scale)
    os.environ["SCENARIO"] = scenario
    os.environ["STRATEGY"] = strategy
    os.environ["REPROCESS_FROM_BATCH"] = reprocess_batch
    os.environ["MICROBATCH_BEGIN"] = SCALE_WINDOW[args.scale][0] if scenario == "full" else ""


def tag_rows(rows, repeat):
    for row in rows:
        row["notes"] = f"repeat={repeat}; {row['notes'] or ''}".strip()


def run_full(args):
    begin, end = SCALE_WINDOW[args.scale]
    set_run_environment(args, "full", "microbatch")
    dbt_args = f"--full-refresh --event-time-start {begin} --event-time-end {end} {EXCLUDE_MV}"
    rows, returncode = run.run_b2(Namespace(engine=args.engine, profile=args.profile, args=dbt_args))
    tag_rows(rows, 1)
    append_rows("b2", rows)
    if returncode != 0:
        sys.exit("full build failed (rows recorded with status=error)")


def run_maintenance(args):
    set_run_environment(args, "maintenance", "")
    base = run.base_fields(args, new_run_id(), "b2", "maintenance")
    rows = []
    total_seconds = 0.0
    failed = False
    for name in tables(args.engine, args.scale):
        command = ["make", "dbt-maintain", f"PROFILE={args.profile}", f"DBT_TARGET={args.engine}", f"RELATION={name}"]
        lines, returncode, wall_seconds, sampler = run.run_measured(command, service=run.compose_service(args.engine))
        common = {
            **base, **run.stats_fields(sampler),
            "engine_version": run.read_engine_image(run.compose_service(args.engine)),
            "engine_config": run.read_engine_config(args.engine),
        }
        operations = []
        for line in lines:
            match = MAINTAIN_LINE.search(line)
            # The Trino session settings are not maintenance work.
            if match and not match.group(2).startswith("set session"):
                operations.append((match.group(2), float(match.group(3))))
        if returncode != 0 or not operations:
            failed = True
        for operation, seconds in operations:
            total_seconds += seconds
            rows.append(make_row(**common, step=f"maintain:{name}:{operation}", latency_ms=seconds * 1000,
                                 status="ok", notes="dbt run-operation maintain_table"))
    rows.append(make_row(**base, step="total", latency_ms=total_seconds * 1000,
                         status="error" if failed else "ok", notes="sum of the maintenance operations"))
    tag_rows(rows, 1)
    append_rows("b2", rows)
    if failed:
        sys.exit("maintenance failed (rows recorded)")


def month_start(year, month):
    return date(year, month, 1)


def microbatch_window(batch_id):
    """Whole months covering the batch and its overlap: from the month before the batch to the end of its month."""
    year, month = divmod(int(batch_id), 100)
    start = month_start(year - 1, 12) if month == 1 else month_start(year, month - 1)
    end = month_start(year + 1, 1) if month == 12 else month_start(year, month + 1)
    return start, end


def run_incremental(args, strategy, repeat):
    before = read_checksums(args.engine, args.scale)
    set_run_environment(args, f"incremental_{strategy}", strategy, reprocess_batch=args.reprocess_batch)
    dbt_args = EXCLUDE_MV
    if strategy == "microbatch":
        start, end = microbatch_window(args.reprocess_batch)
        dbt_args = f"--event-time-start {start} --event-time-end {end} {EXCLUDE_MV}"
    rows, returncode = run.run_b2(Namespace(engine=args.engine, profile=args.profile, args=dbt_args))
    tag_rows(rows, repeat)

    verdict = "checksum not evaluated (run failed)"
    if returncode == 0:
        after = read_checksums(args.engine, args.scale)
        checksum_ok = before == after
        for row in rows:
            row["checksum_ok"] = checksum_ok
        if checksum_ok:
            verdict = "checksum equal to the state before the run"
        else:
            verdict = f"checksum mismatch: before={before} after={after}"
            for row in rows:
                row["status"] = "invalid"
    for row in rows:
        row["notes"] = f"{row['notes']}; {verdict}"
    append_rows("b2", rows)
    log(verdict)
    if returncode != 0 or verdict.startswith("checksum mismatch"):
        sys.exit(f"incremental_{strategy} run {repeat} not valid; rebuild with --only full and resume")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", required=True, choices=list(STRATEGIES))
    parser.add_argument("--profile", required=True)
    parser.add_argument("--scale", default="r2", choices=list(SCALE_WINDOW))
    parser.add_argument("--only", default="full,maintenance,incremental")
    parser.add_argument("--strategies", default="")
    parser.add_argument("--repeats", type=int, default=3)
    # The latest bronze batch of both scales; its window starts in the month before it (batch overlap).
    parser.add_argument("--reprocess-batch", default="202512")
    args = parser.parse_args()
    if args.engine == "postgres" and args.scale != "small":
        parser.error("postgres runs the small scale only (SPEC D-23)")

    run.reexec_under_caffeinate()
    steps = args.only.split(",")
    strategies = args.strategies.split(",") if args.strategies else STRATEGIES[args.engine]
    ensure_engine(args.engine, args.profile)

    if "full" in steps:
        if is_done(args, "full", "microbatch", 1):
            log("full: already done, skipping")
        else:
            log("full: building silver + gold from scratch")
            run_full(args)
    if "maintenance" in steps:
        if is_done(args, "maintenance", "default", 1):
            log("maintenance: already done, skipping")
        else:
            log("maintenance: one measured step per table")
            run_maintenance(args)
    if "incremental" in steps:
        for strategy in strategies:
            for repeat in range(1, args.repeats + 1):
                if is_done(args, f"incremental_{strategy}", strategy, repeat):
                    log(f"incremental_{strategy} run {repeat}: already done, skipping")
                    continue
                log(f"incremental_{strategy} run {repeat} of {args.repeats}")
                run_incremental(args, strategy, repeat)
    log("done; the engine is still up (make engine-down ENGINE=...)")


if __name__ == "__main__":
    main()

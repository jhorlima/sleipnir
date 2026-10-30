"""B6 (layout and maintenance, SPEC §10.4): copies trino_gold.fct_weather_daily into bench_<run>_<variant>
with one layout factor changed, measures write time / size / file count, reads the copy with B3, optionally
measures maintenance and re-reads, then drops the namespace and waits for the purge.
Runs on the host (it starts and stops engines, like the Makefile does).

Usage: python b6.py <variant|all> --engine <reader engine> --profile <s|m|l> [--maintain trino|spark]
Env: RESULTS_DIR (rows go to <RESULTS_DIR>/b6.parquet), DATA_SCALE (default r2).

Each variant namespace holds the fact with the variant's layout plus plain copies (default layout) of the
two dims, so the B3 SQL, the DuckDB reference and every reader work unchanged with GOLD_NAMESPACE=<namespace>
(a view on trino_gold would not be readable by DuckDB). The dims are small and not part of the measurement.
"""

import argparse
import os
import re
import subprocess
import sys
import time

from results import REPO_ROOT, append_rows, make_row, new_run_id
from run import read_engine_config, read_engine_image, reexec_under_caffeinate

SOURCE = "trino_gold.fct_weather_daily"
DIMS = ("dim_station", "dim_date")
MONTH = "month(date)"

# variant -> writer, Trino table properties (CTAS WITH), Spark partition transform and note.
# One factor per variant against the baseline (Trino defaults: zstd from the catalog, 1GB target size, month, no sort).
VARIANTS = {
    "baseline": {"writer": "trino", "partitioning": MONTH, "properties": {}},
    "file128": {"writer": "trino", "partitioning": MONTH, "properties": {"target_max_file_size": "'128MB'"}},
    "file256": {"writer": "trino", "partitioning": MONTH, "properties": {"target_max_file_size": "'256MB'"}},
    "file512": {"writer": "trino", "partitioning": MONTH, "properties": {"target_max_file_size": "'512MB'"}},
    "snappy": {"writer": "trino", "partitioning": MONTH, "properties": {"compression_codec": "'SNAPPY'"}},
    "gzip": {"writer": "trino", "partitioning": MONTH, "properties": {"compression_codec": "'GZIP'"}},
    "year": {"writer": "trino", "partitioning": "year(date)", "properties": {}},
    "sorted": {"writer": "trino", "partitioning": MONTH, "properties": {"sorted_by": "ARRAY['station_id', 'date']"}},
    "zorder": {"writer": "spark", "partitioning": MONTH, "properties": {}},
    # Second round (sort order against partitions, SPEC D-25): partitioning None means an unpartitioned table.
    "sorted_nopart": {"writer": "trino", "partitioning": None, "properties": {"sorted_by": "ARRAY['station_id', 'date']"}},
    "sorted_date_nopart": {"writer": "trino", "partitioning": None, "properties": {"sorted_by": "ARRAY['date', 'station_id']"}},
    "year_sorted": {"writer": "trino", "partitioning": "year(date)", "properties": {"sorted_by": "ARRAY['station_id', 'date']"}},
}
ZORDER_SORT = "zorder(station_id, date)"
# rewrite-all: without it the procedure skips a month that holds a single file, which is every month here.
MAINTAIN_LINE = re.compile(r"maintain_table \S+: (.+) in ([\d.]+) s")


def log(message):
    print(message, file=sys.stderr, flush=True)


def make(*arguments):
    subprocess.run(["make", *arguments], cwd=REPO_ROOT, check=True)


def ensure_engine(engine, profile):
    """Only one engine at a time (benchmark-integrity §1)."""
    for other in ("trino", "spark"):
        if other != engine:
            make("engine-down", f"ENGINE={other}")
    make("engine-up", f"ENGINE={engine}", f"PROFILE={profile}")


def run_sql(engine, sql):
    """Statements separated by `;`, run in one CLI session. Returns (stdout, wall_seconds)."""
    if engine == "trino":
        command = ["docker", "compose", "exec", "-T", "trino", "trino", "--catalog", "lakehouse",
                   "--output-format", "TSV", "--execute", sql]
    else:
        command = ["docker", "compose", "exec", "-T", "spark", "/opt/spark/bin/beeline",
                   "-u", "jdbc:hive2://localhost:10000", "--silent=true", "--outputformat=tsv2", "-e", sql]
    started = time.perf_counter()
    result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
    seconds = time.perf_counter() - started
    if result.returncode != 0:
        raise RuntimeError(f"{engine} failed: {result.stderr[-800:]}")
    return result.stdout.strip(), seconds


def trino_properties(spec):
    properties = {}
    if spec["partitioning"] is not None:
        properties["partitioning"] = f"ARRAY['{spec['partitioning']}']"
    properties.update(spec["properties"])
    return properties


def table_properties_text(variant):
    spec = VARIANTS[variant]
    if spec["writer"] == "spark":
        return f"writer=spark; partitioning={spec['partitioning']}; write ordered: none; rewrite_data_files sort_order={ZORDER_SORT}"
    properties = trino_properties(spec)
    text =", ".join(f"{key}={value}" for key, value in properties.items())
    return f"writer=trino; {text}; catalog default codec ZSTD when compression_codec is not set"


def write_trino(namespace, variant):
    spec = VARIANTS[variant]
    properties = trino_properties(spec)
    with_clause = ", ".join(f"{key} = {value}" for key, value in properties.items())
    run_sql("trino", f"create schema if not exists lakehouse.{namespace}")
    first_year, last_year = run_sql("trino", f"select min(year(date)), max(year(date)) from {SOURCE}")[0].split()
    target = f"lakehouse.{namespace}.fct_weather_daily"
    # One INSERT per year in a single CLI session: a sorted write buffers every open partition in memory,
    # so one CTAS over 192 months exceeds the per-node limit of profile M. Every variant is written the same way.
    statements = [f"create table {target} WITH ({with_clause}) as select * from {SOURCE} with no data"]
    for year in range(int(first_year), int(last_year) + 1):
        statements.append(f"insert into {target} select * from {SOURCE} where year(date) = {year}")
    _, seconds = run_sql("trino", "; ".join(statements))
    for dim in DIMS:
        run_sql("trino", f"create table lakehouse.{namespace}.{dim} as select * from trino_gold.{dim}")
    return seconds


def write_spark(namespace):
    spec = VARIANTS["zorder"]
    run_sql("spark", f"create namespace if not exists lakehouse.{namespace}")
    statement = (
        f"create table lakehouse.{namespace}.fct_weather_daily using iceberg "
        f"partitioned by ({spec['partitioning'].replace('month', 'months')}) "
        f"as select * from lakehouse.{SOURCE}"
    )
    _, write_seconds = run_sql("spark", statement)
    for dim in DIMS:
        run_sql("spark", f"create table lakehouse.{namespace}.{dim} using iceberg as select * from lakehouse.trino_gold.{dim}")
    rewrite = (
        f"call lakehouse.system.rewrite_data_files(table => '{namespace}.fct_weather_daily', "
        f"strategy => 'sort', sort_order => '{ZORDER_SORT}', "
        f"options => map('rewrite-all', 'true'))"
    )
    _, rewrite_seconds = run_sql("spark", rewrite)
    return write_seconds, rewrite_seconds


def last_data_line(output):
    """beeline prints the header and prompts around the result; the answer is the last line starting with a digit."""
    lines = [line for line in output.splitlines() if line[:1].isdigit() or line[:1] == '"']
    return lines[-1]


def measure_files(engine, namespace):
    """(rows, file_count, storage_bytes) of the live data files of the fact."""
    if engine == "trino":
        files_query = f'select count(*), sum(file_size_in_bytes) from lakehouse.{namespace}."fct_weather_daily$files"'
        rows_query = f"select count(*) from lakehouse.{namespace}.fct_weather_daily"
    else:
        files_query = f"select count(*), sum(file_size_in_bytes) from lakehouse.{namespace}.fct_weather_daily.files"
        rows_query = f"select count(*) from lakehouse.{namespace}.fct_weather_daily"
    files_text = last_data_line(run_sql(engine, files_query)[0])
    rows_text = last_data_line(run_sql(engine, rows_query)[0])
    file_count, storage_bytes = [int(value) for value in files_text.replace('"', "").replace(",", "\t").split("\t")]
    return int(rows_text.replace('"', "")), file_count, storage_bytes


def maintain(engine, namespace):
    """The dbt macro (same retention and thresholds as every other maintenance run); one (operation, seconds) per step."""
    command = [
        "docker", "compose", "--env-file", ".env", "--env-file", f"env/{os.environ['PROFILE']}.env",
        "--profile", "dbt", "run", "--rm", "-e", f"DBT_TARGET={engine}", "-e", "RUN_ID=", "dbt",
        "run-operation", "maintain_table", "--args", f"{{relation: {namespace}.fct_weather_daily}}",
    ]
    result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
    steps = []
    for line in result.stdout.splitlines():
        match = MAINTAIN_LINE.search(line)
        if match:
            steps.append((match.group(1), float(match.group(2))))
    if result.returncode != 0 or not steps:
        raise RuntimeError(f"maintenance failed: {(result.stdout + result.stderr)[-800:]}")
    return steps


def read_b3(engine, profile, namespace, variant, label_suffix=""):
    environment = {
        **os.environ,
        "GOLD_NAMESPACE": namespace,
        "RESULTS_SUITE": "b6",
        "SCENARIO_LABEL": f"{variant}{label_suffix}",
        "ENGINE_CONFIG_EXTRA": f"variant {variant}: {table_properties_text(variant)}{label_suffix}",
    }
    command = [sys.executable, "run.py", "b3", "--engine", engine, "--profile", profile]
    result = subprocess.run(command, cwd=REPO_ROOT / "bench" / "harness", env=environment)
    if result.returncode != 0:
        raise RuntimeError(f"B3 on {namespace} exited with {result.returncode}")


def run_variant(variant, reader, profile, maintain_engine, run_id):
    spec = VARIANTS[variant]
    namespace = f"bench_{run_id}_{variant}"
    base = {
        "run_id": run_id, "suite": "b6", "scenario": variant, "dataset": "ghcn",
        "data_scale": os.environ.get("DATA_SCALE", "r2"), "profile": profile,
    }

    def record(step, engine, engine_config, **values):
        row = make_row(
            **base, step=step, engine=engine, engine_version=read_engine_image(engine),
            engine_config=engine_config, status="ok", **values,
        )
        append_rows("b6", [row])

    def record_files(step, engine, engine_config, seconds=None, note=""):
        rows, file_count, storage_bytes = measure_files(engine, namespace)
        average_mb = storage_bytes / file_count / 1e6
        record(step, engine, engine_config, latency_ms=None if seconds is None else seconds * 1000,
               rows=rows, file_count=file_count, storage_bytes=storage_bytes,
               notes=f"avg_file_mb={average_mb:.1f}; {note}".strip("; "))
        log(f"  {variant} {step}: {rows} rows, {file_count} files, {storage_bytes / 1e9:.3f} GB, avg {average_mb:.1f} MB")

    config = f"{table_properties_text(variant)}\n{read_engine_config(spec['writer']) or ''}".strip()
    try:
        ensure_engine(spec["writer"], profile)
        if spec["writer"] == "trino":
            write_seconds = write_trino(namespace, variant)
            record_files("write", "trino", config, write_seconds, "one create + one INSERT per year, wall time incl. CLI start; dims copied unmeasured")
        else:
            write_seconds, rewrite_seconds = write_spark(namespace)
            # The size is taken after the rewrite; the write step carries the CTAS time only.
            record_files("write", "spark", config, write_seconds, "CTAS + zorder rewrite_data_files; size after the rewrite")
            record("zorder_rewrite", "spark", config, latency_ms=rewrite_seconds * 1000, notes=ZORDER_SORT)

        ensure_engine("trino", profile)
        read_b3(reader, profile, namespace, variant)

        if maintain_engine:
            ensure_engine(maintain_engine, profile)
            for operation, seconds in maintain(maintain_engine, namespace):
                record(f"maintain:{operation}", maintain_engine, config, latency_ms=seconds * 1000,
                       notes="dbt run-operation maintain_table")
            record_files("size_after_maintenance", maintain_engine, config)
            ensure_engine("trino", profile)
            read_b3(reader, profile, namespace, variant, f"+maintained-{maintain_engine}")
    finally:
        ensure_engine("trino", profile)
        make("drop-run", f"RUN_ID={run_id}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("variant", help=f"all or one of {', '.join(VARIANTS)}")
    parser.add_argument("--engine", default="trino", help="reader engine for the B3 queries")
    parser.add_argument("--profile", default="m")
    parser.add_argument("--maintain", default="", choices=["", "trino", "spark"])
    args = parser.parse_args()
    reexec_under_caffeinate()
    os.environ["PROFILE"] = args.profile

    if args.variant == "all":
        names = list(VARIANTS)
    elif args.variant in VARIANTS:
        names = [args.variant]
    else:
        parser.error(f"unknown variant {args.variant}")

    # A reader other than Trino needs its own engine up while it reads; ponytail: only trino is wired here.
    if args.engine != "trino":
        parser.error("only --engine trino is wired for now (the runner needs the reader started after the write)")

    # Sequential and one namespace alive at a time; drop + purge wait happen inside run_variant.
    for name in names:
        run_variant(name, args.engine, args.profile, args.maintain, "b6" + new_run_id().split("-")[1])


if __name__ == "__main__":
    main()

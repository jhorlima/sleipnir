#!/usr/bin/env bash
# Drops every bench_<run_id>_* namespace through Trino and waits until the object store no longer
# holds their table files: Lakekeeper purges dropped tables asynchronously (benchmark-integrity §9).
# Runs on the host; needs the trino container up. Usage: scripts/drop-run-namespaces.sh <run_id>
set -euo pipefail

run_id="${1:-}"
if [ -z "$run_id" ]; then
  echo "usage: $0 <run_id>" >&2
  exit 2
fi

timeout_seconds="${PURGE_TIMEOUT_SECONDS:-600}"

trino_sql() {
  docker compose exec -T trino trino --catalog lakehouse --output-format TSV --execute "$1"
}

# Object count under one S3 location, listed with the storage stack's aws-cli image.
object_count() {
  local location="$1"
  docker compose --profile ingest run --rm --no-deps --entrypoint aws storage-report \
    s3 ls --recursive "$location/" | wc -l | tr -d ' '
}

namespaces=$(trino_sql "show schemas like 'bench\_${run_id}\_%' escape '\\'")
if [ -z "$namespaces" ]; then
  echo "No bench_${run_id}_* namespaces"
  exit 0
fi

locations=()
for namespace in $namespaces; do
  tables=$(trino_sql "show tables from ${namespace}")
  for table in $tables; do
    location=$(trino_sql "select value from ${namespace}.\"${table}\$properties\" where key = 'location'" || true)
    if [ -z "$location" ]; then
      # Views have no $properties table and no data files.
      trino_sql "drop view if exists ${namespace}.${table}"
      continue
    fi
    locations+=("$location")
    trino_sql "drop table ${namespace}.${table}"
    echo "Dropped ${namespace}.${table} (${location})"
  done
  trino_sql "drop schema ${namespace}"
  echo "Dropped schema ${namespace}"
done

waited=0
for location in "${locations[@]}"; do
  while [ "$(object_count "$location")" -gt 0 ]; do
    if [ "$waited" -ge "$timeout_seconds" ]; then
      echo "FAIL: ${location} still has objects after ${timeout_seconds} s" >&2
      exit 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
  echo "Purged ${location}"
done

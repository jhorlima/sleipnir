#!/usr/bin/env bash
# Runs inside the aws-cli container (bash, curl, jq; see compose/ingest.yaml).
# Sums the object-store bytes of every table in duckdb_bronze and the <ENGINE>_* namespaces
# and fails when they exceed STORAGE_BUDGET_GB (SPEC §6).
# Lakekeeper stores tables under UUID paths, so the catalog maps each table to its location.
set -euo pipefail

catalog_url="$LAKEKEEPER_URL/catalog/v1"
prefix=$(curl -fsS "$catalog_url/config?warehouse=$LAKEKEEPER_WAREHOUSE" | jq -r '.overrides.prefix // .defaults.prefix')

# Bytes under one S3 location, from the summary line of a recursive listing.
location_bytes() {
  local location="$1"
  local summary
  summary=$(aws s3 ls --recursive --summarize "$location/" | grep 'Total Size:' || true)
  if [ -z "$summary" ]; then
    echo 0
    return
  fi
  echo "$summary" | awk '{print $3}'
}

namespace_bytes() {
  local namespace="$1"
  local total=0
  local table
  local location
  local tables
  # ponytail: first page of tables only; follow next-page-token if a namespace grows past it.
  tables=$(curl -fsS "$catalog_url/$prefix/namespaces/$namespace/tables" | jq -r '.identifiers[].name')
  for table in $tables; do
    location=$(curl -fsS "$catalog_url/$prefix/namespaces/$namespace/tables/$table" | jq -r '.metadata.location')
    total=$((total + $(location_bytes "$location")))
  done
  echo "$total"
}

to_gb() {
  awk -v bytes="$1" 'BEGIN {printf "%.3f", bytes / 1e9}'
}

namespaces=$(curl -fsS "$catalog_url/$prefix/namespaces" | jq -r '.namespaces[] | join(".")')

printf "%-24s %16s %10s\n" "namespace" "bytes" "GB"
budget_bytes_used=0
for namespace in $namespaces; do
  if [ "$namespace" != "duckdb_bronze" ] && [[ "$namespace" != "${ENGINE}_"* ]]; then
    continue
  fi
  bytes=$(namespace_bytes "$namespace")
  budget_bytes_used=$((budget_bytes_used + bytes))
  printf "%-24s %16s %10s\n" "$namespace" "$bytes" "$(to_gb "$bytes")"
done

budget_bytes=$(awk -v gb="$STORAGE_BUDGET_GB" 'BEGIN {printf "%.0f", gb * 1e9}')
printf "%-24s %16s %10s\n" "duckdb_bronze+${ENGINE}_*" "$budget_bytes_used" "$(to_gb "$budget_bytes_used")"
printf "%-24s %16s %10s\n" "budget" "$budget_bytes" "$(to_gb "$budget_bytes")"

if [ "$budget_bytes_used" -gt "$budget_bytes" ]; then
  echo "FAIL: duckdb_bronze + ${ENGINE}_* exceeds ${STORAGE_BUDGET_GB} GB" >&2
  exit 1
fi
echo "OK: within ${STORAGE_BUDGET_GB} GB"

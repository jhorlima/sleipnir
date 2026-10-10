#!/usr/bin/env bash
# V2 proof: CREATE MATERIALIZED VIEW on the Lakekeeper REST catalog fails in Trino 483.
# Creates only the bench_v2 schema and drops it at the end. Run from the repo root.
set -uo pipefail

run_sql() {
    docker compose exec -T trino trino --execute "$1"
}

run_sql "CREATE SCHEMA IF NOT EXISTS lakehouse.bench_v2"
run_sql "CREATE TABLE lakehouse.bench_v2.src AS SELECT 1 AS id, DOUBLE '1.5' AS value"

echo "--- expected: NOT_SUPPORTED"
run_sql "CREATE MATERIALIZED VIEW lakehouse.bench_v2.mv AS SELECT id, sum(value) AS total FROM lakehouse.bench_v2.src GROUP BY id"

echo "--- control: logical views"
run_sql "CREATE VIEW lakehouse.bench_v2.v AS SELECT id FROM lakehouse.bench_v2.src"
run_sql "SELECT * FROM lakehouse.bench_v2.v"
run_sql "DROP VIEW lakehouse.bench_v2.v"

run_sql "DROP TABLE lakehouse.bench_v2.src"
run_sql "DROP SCHEMA lakehouse.bench_v2"

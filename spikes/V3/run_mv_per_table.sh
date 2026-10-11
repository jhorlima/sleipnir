#!/usr/bin/env bash
# V3 proof of D-24 (one MV per gold table): does EXPLAIN replace every Iceberg scan with its MV, and are the results equal?
# Prerequisites (from the repo root): StarRocks up, `make starrocks-init`, then
#   make starrocks-mv-create && make starrocks-mv-refresh && scripts/starrocks-mv.sh wait-compaction
# Queries: the hand-written shapes (03_queries.sql, Q1-Q4 only) and the SQL Cube generates (04_cube_queries.sql,
# produced by cube_sql.sh). Never during a benchmark run.
# Usage: bash spikes/V3/run_mv_per_table.sh
set -euo pipefail

spike_dir=spikes/V3
session="SET query_timeout=3600; SET enable_materialized_view_rewrite=true; SET enable_materialized_view_union_rewrite=false;"
base_tables="fct_weather_daily|dim_station|dim_date"

run_sql() {
    docker compose exec -T starrocks mysql -h 127.0.0.1 -P 9030 -u root "$@"
}

# Prints the SQL of one "-- @name" block of a query file.
query_sql() {
    local query_file="$1"
    local query_name="$2"
    awk -v name="${query_name}" '
        /^-- @/ { in_block = ($0 == "-- @" name); next }
        in_block && !/^--/ { print }
    ' "${query_file}"
}

# Summing doubles in a different order changes the last digits, so numbers are compared with a 1e-9 relative tolerance.
rows_match() {
    paste -d'\t' "$1" "$2" | awk -F'\t' '
        {
            columns = NF / 2
            for (i = 1; i <= columns; i++) {
                a = $i; b = $(i + columns)
                if (a == b) continue
                if (a !~ /^-?[0-9.eE+-]+$/ || b !~ /^-?[0-9.eE+-]+$/) { bad = 1; continue }
                diff = a - b; if (diff < 0) diff = -diff
                scale = (a < 0 ? -a : a); if (scale < 1) scale = 1
                if (diff / scale > 1e-9) bad = 1
            }
        }
        END { exit bad }'
}

# Prints "<query file>:<name>" for every block to prove; ONLY=<regex> keeps the matching ones.
list_queries() {
  {
    grep '^-- @Q[1-4]' "${spike_dir}/03_queries.sql" | sed "s|^-- @|${spike_dir}/03_queries.sql:|"
    grep '^-- @Cube_Q' "${spike_dir}/04_cube_queries.sql" | sed "s|^-- @|${spike_dir}/04_cube_queries.sql:|"
  } | grep -E "${ONLY:-.}"
}

echo "== EXPLAIN: scans on MVs vs on the Iceberg tables"
for query in $(list_queries); do
    query_file="${query%%:*}"
    query_name="${query##*:}"
    sql=$(query_sql "${query_file}" "${query_name}")
    explain_output=$(run_sql -e "${session} EXPLAIN ${sql}" 2>&1 || true)
    mv_scans=$(echo "${explain_output}" | grep -cE "TABLE: mv_(${base_tables})" || true)
    base_scans=$(echo "${explain_output}" | grep -cE "TABLE: trino_gold\.(${base_tables})\$" || true)
    echo "${query_name}: scans on MV=${mv_scans} scans on Iceberg=${base_scans}"
done

echo "== results with and without the MVs (sorted, 1e-9 tolerance)"
for query in $(list_queries); do
    query_file="${query%%:*}"
    query_name="${query##*:}"
    sql=$(query_sql "${query_file}" "${query_name}")
    if ! run_sql -e "${session} ${sql}" 2> /tmp/v3_with_mv.err | sort > /tmp/v3_with_mv.txt; then
        echo "${query_name}: FAILED with MV: $(head -c 200 /tmp/v3_with_mv.err)"
        continue
    fi
    run_sql -e "SET query_timeout=3600; SET enable_materialized_view_rewrite=false; ${sql}" 2> /tmp/v3_without_mv.err | sort > /tmp/v3_without_mv.txt || true
    if [ -s /tmp/v3_without_mv.err ]; then
        echo "${query_name}: FAILED without MV: $(head -c 200 /tmp/v3_without_mv.err)"
    elif rows_match /tmp/v3_with_mv.txt /tmp/v3_without_mv.txt; then
        echo "${query_name}: results equal ($(wc -l < /tmp/v3_with_mv.txt) lines)"
    else
        echo "${query_name}: RESULTS DIFFER"
    fi
done

echo "== MV sizes"
run_sql -e "SHOW DATA FROM mv_fct_weather_daily; SHOW DATA FROM mv_dim_station; SHOW DATA FROM mv_dim_date" sleipnir_mv

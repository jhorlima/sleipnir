#!/usr/bin/env bash
# V3 proof against the repo's StarRocks service. Prerequisites (from the repo root):
#   make engine-up ENGINE=starrocks PROFILE=m && make starrocks-init
# and the Trino gold tables (fct_weather_daily, dim_station, dim_date). Never during a benchmark run.
# Usage: bash spikes/V3/run.sh
set -euo pipefail

spike_dir=spikes/V3
mv_ddl=spikes/V3/mv_weather_wide.sql
session="SET enable_materialized_view_rewrite=true; SET enable_materialized_view_union_rewrite=false;"

run_sql() {
    docker compose exec -T starrocks mysql -h 127.0.0.1 -P 9030 -u root "$@"
}

query_sql() {
    local query_name="$1"
    awk -v name="${query_name}" '
        /^-- @/ { in_block = ($0 == "-- @" name); next }
        in_block && !/^--/ { print }
    ' "${spike_dir}/03_queries.sql"
}

echo "== MV create + timed refresh"
run_sql < "${mv_ddl}"
start_seconds=$(date +%s)
run_sql -e "SET query_timeout=3600; REFRESH MATERIALIZED VIEW sleipnir_mv.mv_weather_wide WITH SYNC MODE;"
echo "refresh seconds: $(( $(date +%s) - start_seconds ))"
run_sql -e "SHOW DATA FROM mv_weather_wide" sleipnir_mv

echo "== EXPLAIN per query (first pass, then second pass after the refresh settled)"
query_names=$(grep '^-- @' "${spike_dir}/03_queries.sql" | sed 's/^-- @//')
for query_name in ${query_names}; do
    sql=$(query_sql "${query_name}")
    for pass in 1 2; do
        explain_output=$(run_sql -e "${session} EXPLAIN ${sql}")
        if echo "${explain_output}" | grep -q "mv_weather_wide"; then
            echo "${query_name} (pass ${pass}): REWRITTEN to mv_weather_wide"
        else
            echo "${query_name} (pass ${pass}): NOT rewritten"
        fi
    done
done

# Summing doubles in a different order changes the last digits, so numbers are compared with a 1e-9 relative tolerance.
rows_match() {
    paste -d'\t' "$1" "$2" | awk -F'\t' '
        {
            columns = NF / 2
            for (i = 1; i <= columns; i++) {
                a = $i; b = $(i + columns)
                if (a == b) continue
                if (a !~ /^-?[0-9.]+$/ || b !~ /^-?[0-9.]+$/) { bad = 1; continue }
                diff = a - b; if (diff < 0) diff = -diff
                scale = (a < 0 ? -a : a); if (scale < 1) scale = 1
                if (diff / scale > 1e-9) bad = 1
            }
        }
        END { exit bad }'
}

# Wait until the BE finished compacting the MV after the refresh; a query meanwhile can exceed the BE memory limit.
until [ "$(docker stats --no-stream --format '{{.CPUPerc}}' "$(docker compose ps -q starrocks)" | cut -d. -f1)" -lt 10 ]; do
    sleep 10
done

echo "== results with and without the MV (sorted, 1e-9 tolerance)"
for query_name in ${query_names}; do
    sql=$(query_sql "${query_name}")
    run_sql -e "${session} ${sql}" | sort > /tmp/v3_with_mv.txt
    run_sql -e "SET enable_materialized_view_rewrite=false; ${sql}" | sort > /tmp/v3_without_mv.txt
    if rows_match /tmp/v3_with_mv.txt /tmp/v3_without_mv.txt; then
        echo "${query_name}: results equal"
    else
        echo "${query_name}: RESULTS DIFFER"
    fi
done

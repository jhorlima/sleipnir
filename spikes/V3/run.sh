#!/usr/bin/env bash
# NOT YET RUN. Needs rustfs + lakekeeper up and the Trino gold tables built (fct_weather_daily, dim_station, dim_date).
# Run from the repo root:  bash spikes/V3/run.sh
set -euo pipefail

spike_dir=spikes/V3
compose_args="-f compose.yaml -f ${spike_dir}/compose.starrocks.yaml --profile starrocks"

set -a
source .env
set +a

run_sql() {
    docker compose ${compose_args} exec -T starrocks mysql -h 127.0.0.1 -P 9030 -u root "$@"
}

docker compose ${compose_args} up -d --wait starrocks

echo "== version, memory limit, config file paths"
run_sql -e "SELECT current_version();"
run_sql -e "SHOW BACKENDS\G" | grep -E "Version|MemLimit|Alive"
docker compose ${compose_args} exec -T starrocks sh -c 'find /data /opt -name fe.conf -o -name be.conf 2>/dev/null'

echo "== catalog"
envsubst < "${spike_dir}/01_catalog.sql" | run_sql --table

echo "== MV create + timed refresh"
run_sql < "${spike_dir}/02_mv.sql"
start_seconds=$(date +%s)
run_sql -e "REFRESH MATERIALIZED VIEW sleipnir_mv.mv_weather_wide WITH SYNC MODE;"
echo "refresh seconds: $(( $(date +%s) - start_seconds ))"
run_sql -e "SHOW MATERIALIZED VIEWS FROM sleipnir_mv\G"
run_sql -e "SELECT count(*) FROM sleipnir_mv.mv_weather_wide;"

echo "== EXPLAIN per query"
query_names=$(grep '^-- @' "${spike_dir}/03_queries.sql" | sed 's/^-- @//')
for query_name in ${query_names}; do
    query_sql=$(awk -v name="${query_name}" '
        /^-- @/ { in_block = ($0 == "-- @" name); next }
        in_block && !/^--/ { print }
    ' "${spike_dir}/03_queries.sql")
    explain_output=$(run_sql -e "SET enable_materialized_view_rewrite=true; EXPLAIN ${query_sql}")
    if echo "${explain_output}" | grep -q "mv_weather_wide"; then
        echo "${query_name}: REWRITTEN to mv_weather_wide"
    else
        echo "${query_name}: NOT rewritten"
    fi
done

echo "== correctness: Q1_three_tables with and without the MV"
query_sql=$(awk '/^-- @Q1_three_tables/ { in_block = 1; next } /^-- @/ { in_block = 0 } in_block && !/^--/ { print }' "${spike_dir}/03_queries.sql")
run_sql -e "SET enable_materialized_view_rewrite=true; ${query_sql}" | sort > /tmp/v3_with_mv.txt
run_sql -e "SET enable_materialized_view_rewrite=false; ${query_sql}" | sort > /tmp/v3_without_mv.txt
diff /tmp/v3_with_mv.txt /tmp/v3_without_mv.txt
echo "results match"

echo "== staleness (manual steps in README section 'Staleness check')"
echo "cleanup: docker compose ${compose_args} down -v"

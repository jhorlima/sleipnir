#!/usr/bin/env bash
# B5a materialized views (SPEC §10.3, D-24): one StarRocks async MV per gold table, DDL in bench/sql/.
# Usage: scripts/starrocks-mv.sh create|refresh|wait-compaction|drop
#   create           create the missing MVs (idempotent; REFRESH DEFERRED MANUAL, so they start empty)
#   refresh          refresh each MV WITH SYNC MODE; prints one JSON line per MV with the seconds
#   wait-compaction  block until the container CPU is under 10% for COMPACTION_SAMPLES samples in a row
#   drop             drop the MVs (their files stay in the BE trash for 1 h)
set -euo pipefail

mv_database=sleipnir_mv
mv_names="mv_fct_weather_daily mv_dim_station mv_dim_date"
ddl_files="bench/sql/b5a_fct_weather_daily.starrocks.sql bench/sql/b5a_dim_station.starrocks.sql bench/sql/b5a_dim_date.starrocks.sql"
compaction_samples="${COMPACTION_SAMPLES:-3}"

run_sql() {
    docker compose exec -T starrocks mysql -h 127.0.0.1 -P 9030 -u root "$@"
}

create_mvs() {
    run_sql -e "CREATE DATABASE IF NOT EXISTS ${mv_database}"
    for ddl_file in ${ddl_files}; do
        run_sql < "${ddl_file}"
    done
    run_sql -e "SELECT TABLE_NAME, REFRESH_TYPE, IS_ACTIVE FROM information_schema.materialized_views WHERE TABLE_SCHEMA = '${mv_database}'"
}

refresh_mvs() {
    for mv_name in ${mv_names}; do
        start_seconds=$(date +%s)
        # The SYNC statement itself is killed at the default query_timeout of 300 s.
        run_sql -e "SET query_timeout=${MV_REFRESH_TIMEOUT_SECONDS:-3600}; REFRESH MATERIALIZED VIEW ${mv_database}.${mv_name} WITH SYNC MODE" > /dev/null
        seconds=$(( $(date +%s) - start_seconds ))
        echo "{\"step\": \"refresh_${mv_name}\", \"seconds\": ${seconds}}"
    done
}

container_cpu() {
    docker stats --no-stream --format '{{.CPUPerc}}' "$(docker compose ps -q starrocks)" | cut -d. -f1
}

wait_compaction() {
    quiet_samples=0
    while [ "${quiet_samples}" -lt "${compaction_samples}" ]; do
        if [ "$(container_cpu)" -lt 10 ]; then
            quiet_samples=$((quiet_samples + 1))
        else
            quiet_samples=0
        fi
        sleep 10
    done
}

drop_mvs() {
    for mv_name in ${mv_names}; do
        run_sql -e "DROP MATERIALIZED VIEW IF EXISTS ${mv_database}.${mv_name}"
    done
}

case "${1:-}" in
    create) create_mvs ;;
    refresh) refresh_mvs ;;
    wait-compaction) wait_compaction ;;
    drop) drop_mvs ;;
    *)
        echo "usage: $0 create|refresh|wait-compaction|drop" >&2
        exit 2
        ;;
esac

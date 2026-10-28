#!/usr/bin/env bash
# Measured refresh step of B5b and B5c (SPEC §9 step 6, §10.3); appends it to results/b5.parquet as its own row.
# Usage: ENGINE=trino|starrocks PROFILE=m scripts/cube-b5-refresh.sh b5b|b5c
#   b5b  `dbt run --select mv_weather_wide --full-refresh` on Trino (one year per microbatch); seconds = dbt's own execution time of the model
#   b5c  builds the Cube Store rollups of ENGINE with a one-off refresh worker; seconds = worker start until every
#        partition of the engine's rollups is ready in Cube Store
# Needs the engine under test and Cube (cube-api, Cube Store) up, without the stock refresh worker. Run after the
# transformation and before `make bench`.
# (The jobs API would be more exact, but it needs the `jobs` API scope: CUBEJS_DEFAULT_API_SCOPES.)
set -euo pipefail

scenario="${1:-}"
engine="${ENGINE:-trino}"
profile="${PROFILE:-m}"
build_timeout_seconds="${BUILD_TIMEOUT_SECONDS:-7200}"
run_results=dbt/target/run_results.json
# 4 rollups x one partition per year of the build range (1998-2025).
expected_partitions=112
model_dir=""

record_step() {
  local step_json="$1"
  uv run --directory bench/harness python reads.py --suite b5 --scenario "$scenario" \
    --engine "$engine" --profile "$profile" --record-step "$step_json"
}

# First year of the yearly microbatches of mv_weather_wide: the scale's first bronze date (bench/harness/b2.py SCALE_WINDOW).
microbatch_begin() {
  case "${DATA_SCALE:-r2}" in
    local) echo "1763-01-01" ;;
    r2_1998) echo "1998-01-01" ;;
    small) echo "2025-01-01" ;;
    *) echo "2010-01-01" ;;
  esac
}

refresh_table() {
  rm -f "$run_results"
  make dbt-run PROFILE="$profile" DBT_TARGET=trino \
    VARS="{maintenance: false, microbatch_begin: '$(microbatch_begin)'}" ARGS='--select mv_weather_wide --full-refresh'
  local seconds storage_bytes
  seconds=$(jq '.results[0].execution_time' "$run_results")
  storage_bytes=$(docker compose exec -T trino trino --catalog lakehouse --schema trino_gold --output-format CSV_UNQUOTED \
    --execute 'SELECT sum(file_size_in_bytes) FROM "mv_weather_wide$files"')
  record_step "{\"step\": \"refresh_mv_weather_wide\", \"seconds\": ${seconds}, \"storage_bytes\": ${storage_bytes}, \"notes\": \"dbt run --select mv_weather_wide --full-refresh, one year per microbatch; storage = Iceberg data files\"}"
}

# A refresh worker that sees only ENGINE's rollups: the stock worker builds every engine's rollups and its scheduler
# stops at the first failure, so it never reaches Trino's while StarRocks is down (and the other way round).
start_builder() {
  model_dir=$(mktemp -d)
  cp -R cube/model/. "$model_dir"
  if [ "$engine" = trino ]; then
    rm -rf "$model_dir/cubes/starrocks_pa" "$model_dir/views/starrockspa_weather.yml"
  else
    rm -rf "$model_dir/cubes/trino_pa" "$model_dir/views/trinopa_weather.yml"
  fi
  docker rm -f sleipnir-cube-builder > /dev/null 2>&1 || true
  docker compose --profile cube run -d --no-deps --name sleipnir-cube-builder \
    -v "${model_dir}:/cube/conf/model:ro" cube-refresh-worker > /dev/null
}

stop_builder() {
  docker rm -f sleipnir-cube-builder > /dev/null 2>&1 || true
  if [ -n "$model_dir" ]; then
    rm -rf "$model_dir"
  fi
}

# Partitions that Cube Store marks ready (the volume holds only this build's rollups). Cube Store speaks the MySQL
# protocol; the Cube API image has the client library, and a failed query (Cube Store still starting) counts as 0.
ready_partitions() {
  docker compose exec -T cube-api node -e "
    const mysql = require('/cube/node_modules/mysql2/promise');
    (async () => {
      const connection = await mysql.createConnection({host: 'cubestore-router', port: 3306, user: 'root'});
      const [rows] = await connection.query(
        \"SELECT count(*) AS ready FROM system.tables WHERE is_ready = 'true'\");
      console.log(rows[0].ready);
      await connection.end();
    })().catch(() => console.log(0));
  "
}

build_rollups() {
  trap stop_builder EXIT
  local started ready
  started=$(date +%s)
  start_builder

  ready=0
  while [ "$ready" -lt "$expected_partitions" ]; do
    if [ $(($(date +%s) - started)) -ge "$build_timeout_seconds" ]; then
      echo "FAIL: ${ready}/${expected_partitions} partitions ready after ${build_timeout_seconds} s" >&2
      exit 1
    fi
    sleep 10
    ready=$(ready_partitions)
  done

  local seconds storage_bytes
  seconds=$(($(date +%s) - started))
  storage_bytes=$(docker compose exec -T cubestore-worker du -sb /cube/data | cut -f1)
  record_step "{\"step\": \"build_rollups\", \"seconds\": ${seconds}, \"storage_bytes\": ${storage_bytes}, \"notes\": \"refresh worker (0.5 CPU) started until ${ready} partitions ready, polled every 10 s; storage = Cube Store volume\"}"
}

case "$scenario" in
  b5b) refresh_table ;;
  b5c) build_rollups ;;
  *)
    echo "usage: ENGINE=trino|starrocks $0 b5b|b5c" >&2
    exit 2
    ;;
esac

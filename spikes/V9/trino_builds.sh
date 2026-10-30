#!/usr/bin/env bash
# Prints the Trino queries Cube ran to build rollups (state, seconds, start of SQL); with "wait" blocks until none is running.
set -euo pipefail

trino_sql() {
  docker exec sleipnir-trino-1 trino --execute "$1"
}

if [ "${1:-}" = "wait" ]; then
  until [ "$(trino_sql "select count(*) from system.runtime.queries where state='RUNNING' and query like '%trino_weather_daily%' and query not like '%system.runtime%'" | tr -d '"')" = "0" ]; do
    sleep 5
  done
fi

trino_sql "select state, date_diff('second', created, coalesce(\"end\", now())) as seconds, substr(replace(query, chr(10), ' '), 1, 200) from system.runtime.queries where query like '%trino_weather_daily%' and query not like '%system.runtime%' order by created"

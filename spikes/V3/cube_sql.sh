#!/usr/bin/env bash
# Prints the SQL Cube generates for bench/queries/cube/q1..q10 on the starrocks view, parameters inlined,
# as "-- @Cube_Qn" blocks (the format of 03_queries.sql). Needs Cube up. Run from the repo root.
# Usage: bash spikes/V3/cube_sql.sh > /tmp/cube_queries.sql
set -euo pipefail

for query_number in 1 2 3 4 5 6 7 8 9 10; do
    echo "-- @Cube_Q${query_number}"
    ENGINE=starrocks scripts/cube-query.sh "${query_number}" sql \
        | jq -r --arg quote "'" '.sql.sql as [$statement, $params]
                 | reduce $params[] as $value ($statement; sub("\\?"; $quote + ($value | tostring) + $quote))'
    echo ";"
    echo
done

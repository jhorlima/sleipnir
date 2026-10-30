#!/usr/bin/env bash
# V9 proof (NOT RUN YET). Run from anywhere; needs Trino up with the gold tables loaded.
# Prerequisite: copy spikes/V9/pre_aggregations.proposal.yml into cube/model/cubes/trino/weather_daily.yml
# (and station_years.yml for q8) and cast the percentile measures to DOUBLE, then run this script.
set -euo pipefail

cd "$(dirname "$0")/../.."
variants_dir="spikes/V9/queries"

make cube-up

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

api_secret=$(docker compose exec -T cube-api printenv CUBEJS_API_SECRET)
now=$(date +%s)
header=$(printf '{"alg":"HS256","typ":"JWT"}' | base64url)
payload=$(printf '{"iat":%d,"exp":%d}' "$now" "$((now + 3600))" | base64url)
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -hmac "$api_secret" -binary | base64url)
token="${header}.${payload}.${signature}"

cube_post() {
  local path="$1"
  local body="$2"
  curl -sS -H 'Host: cube.localhost' -H "Authorization: ${token}" -H 'Content-Type: application/json' \
    --data "$body" "http://127.0.0.1/cubejs-api/v1/${path}"
}

# 1. Build every rollup now instead of waiting for the refresh worker's timer.
cube_post pre-aggregations/jobs '{"action": "post", "selector": {"timezones": ["UTC"], "contexts": [{"securityContext": {}}]}}' | jq .
# Poll the returned tokens with:
#   cube_post pre-aggregations/jobs '{"action": "get", "resType": "object", "tokens": ["<token>"]}'
# Or watch the worker: docker compose logs -f cube-refresh-worker
echo "Wait until every job is 'done' (or the worker log is quiet), then press Enter."
read -r _

# 2. Run each query and print which pre-aggregation served it ({} or null = it went to Trino).
run_query() {
  local label="$1"
  local file="$2"
  local query
  query=$(cat "$file")
  local deadline=$((SECONDS + 300))
  local response
  while true; do
    response=$(cube_post load "{\"query\": ${query}}")
    if ! grep -q '"Continue wait"' <<< "$response"; then
      break
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "FAIL ${label}: still running" >&2
      return 1
    fi
    sleep 1
  done
  echo "== ${label}: rows=$(jq '.data | length' <<< "$response") used=$(jq -c '.usedPreAggregations' <<< "$response") error=$(jq -r '.error // "none"' <<< "$response")"
}

for q in 2 3 4 7 8 9 10; do
  run_query "q${q} (bench/queries/cube as written)" "bench/queries/cube/q${q}.json"
done
for variant in "$variants_dir"/*.json; do
  run_query "$(basename "$variant")" "$variant"
done

# 3. Where did the SQL run? The generated SQL of a query reads either a Cube Store schema
#    (dev_pre_aggregations / prod_pre_aggregations) or lakehouse.trino_gold:
#      scripts/cube-query.sh 9 sql | jq '.sql.sql, .sql.preAggregations'
#
# 4. Rollup measure column types in Cube Store (must be Float, never Decimal). Cube Store speaks the
#    MySQL protocol on 3306 inside the compose network (port from Cube Store docs; not verified here):
#      docker run --rm --network <compose network> mysql:8 mysql -h cubestore-router -P 3306 -e \
#        "SELECT table_name, column_name, data_type FROM information_schema.columns \
#         WHERE table_schema LIKE '%pre_aggregations%'"
#
# 5. Correctness gate (benchmark-integrity 5): compare each accelerated result with the same query
#    on a model without pre_aggregations (or CUBEJS_ROLLUP_ONLY unset and the rollup renamed) before
#    recording a time. Percentiles: 5 % relative tolerance.

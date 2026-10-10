#!/usr/bin/env bash
# Sends one Cube REST query (bench/queries/cube/q<n>.json) through Traefik and prints the JSON answer.
# The JWT is signed (HS256) with the API secret read from the running cube-api container.
# Usage: scripts/cube-query.sh <n> [load|sql]   (sql returns the SQL Cube generates instead of rows)
set -euo pipefail

query_number="${1:-}"
endpoint="${2:-load}"
query_file="bench/queries/cube/q${query_number}.json"
if [ -z "$query_number" ] || [ ! -f "$query_file" ]; then
  echo "usage: $0 <n> [load|sql]  (no ${query_file})" >&2
  exit 2
fi

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

api_secret=$(docker compose exec -T cube-api printenv CUBEJS_API_SECRET)
now=$(date +%s)
header=$(printf '{"alg":"HS256","typ":"JWT"}' | base64url)
payload=$(printf '{"iat":%d,"exp":%d}' "$now" "$((now + 3600))" | base64url)
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -hmac "$api_secret" -binary | base64url)
token="${header}.${payload}.${signature}"

# Cube answers "Continue wait" while a long query is still running; ask again until it is done.
timeout_seconds="${CUBE_QUERY_TIMEOUT_SECONDS:-300}"
started=$(date +%s)
while true; do
  response=$(curl -sS -H 'Host: cube.localhost' -H "Authorization: ${token}" \
    -H 'Content-Type: application/json' \
    --data "{\"query\": $(cat "$query_file")}" \
    "http://127.0.0.1/cubejs-api/v1/${endpoint}")
  if ! grep -q '"Continue wait"' <<< "$response"; then
    break
  fi
  if [ $(($(date +%s) - started)) -ge "$timeout_seconds" ]; then
    echo "FAIL: q${query_number} still running after ${timeout_seconds} s" >&2
    exit 1
  fi
  sleep 1
done

echo "$response" | jq .
if jq -e 'has("error")' <<< "$response" > /dev/null; then
  exit 1
fi

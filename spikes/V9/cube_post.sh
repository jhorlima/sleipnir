#!/usr/bin/env bash
# Usage: cube_post.sh <path> <json-body-or-@file>   e.g. cube_post.sh load '{"query": {...}}'
# Prints the response; for `load`, loops over "Continue wait".
set -euo pipefail
cd "$(dirname "$0")/../.."

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

api_secret=$(docker compose exec -T cube-api printenv CUBEJS_API_SECRET)
now=$(date +%s)
header=$(printf '{"alg":"HS256","typ":"JWT"}' | base64url)
payload=$(printf '{"iat":%d,"exp":%d,"scope":["data","meta","jobs"]}' "$now" "$((now + 3600))" | base64url)
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -hmac "$api_secret" -binary | base64url)
token="${header}.${payload}.${signature}"

path="$1"
body="$2"
deadline=$((SECONDS + ${TIMEOUT:-900}))
while true; do
  response=$(curl -sS -H 'Host: cube.localhost' -H "Authorization: ${token}" -H 'Content-Type: application/json' \
    --data "$body" "http://127.0.0.1/cubejs-api/v1/${path}")
  if ! grep -q '"Continue wait"' <<< "$response" || [ "$SECONDS" -ge "$deadline" ]; then
    break
  fi
  sleep 2
done
echo "$response"

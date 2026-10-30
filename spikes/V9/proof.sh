#!/usr/bin/env bash
# Usage: proof.sh <label> <query.json>...   Runs each query on /load and stores the answer in /tmp/v9/<label>/<name>.json.
# Prints rows, usedPreAggregations (ids) and elapsed seconds per query.
set -euo pipefail
cd "$(dirname "$0")/../.."

label="$1"
shift
mkdir -p "/tmp/v9/${label}"

for query_file in "$@"; do
  name=$(basename "$query_file" .json)
  started=$SECONDS
  response=$(spikes/V9/cube_post.sh load "{\"query\": $(cat "$query_file"), \"renewQuery\": true}")
  echo "$response" > "/tmp/v9/${label}/${name}.json"
  rows=$(jq '.data | length' <<< "$response")
  used=$(jq -c '[.usedPreAggregations // {} | to_entries[] | .value.preAggregationId]' <<< "$response")
  error=$(jq -r '.error // "none"' <<< "$response")
  echo "${label} ${name}: rows=${rows} used=${used} error=${error} seconds=$((SECONDS - started))"
done

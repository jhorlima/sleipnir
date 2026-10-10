#!/usr/bin/env bash
# Runs spike.py in a throwaway container on the storage stack network.
# Usage: MODE=static|vended KEEP=0|1 spikes/V1/run.sh   (from the repo root)
set -euo pipefail
cd "$(dirname "$0")"

docker run --rm --name sleipnir-spike-v1 --network sleipnir_default \
  -e MODE="${MODE:-static}" -e KEEP="${KEEP:-0}" -e ROWS="${ROWS:-100000}" \
  -e S3_ACCESS_KEY=rustfs-local-user -e S3_SECRET_KEY=rustfs-local-password -e S3_REGION=local-01 \
  -v "$PWD/spike.py:/spike.py:ro" \
  python:3.12.15-slim \
  sh -c 'pip install -q --root-user-action=ignore duckdb==1.5.6 && python /spike.py'

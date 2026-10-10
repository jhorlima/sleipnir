#!/usr/bin/env bash
# Runs inside the aws-cli container (bash + curl, see compose/storage.yaml).
# Bootstraps Lakekeeper once and creates the warehouse if it is missing.
set -euo pipefail

# Single-project mode: Lakekeeper's default project.
project_id="00000000-0000-0000-0000-000000000000"

server_info=$(curl -fsS "$LAKEKEEPER_URL/management/v1/info")
if echo "$server_info" | grep -q '"bootstrapped":true'; then
  echo "Lakekeeper already bootstrapped"
else
  curl -fsS -X POST "$LAKEKEEPER_URL/management/v1/bootstrap" \
    -H "Content-Type: application/json" \
    --data '{"accept-terms-of-use": true}'
  echo "Lakekeeper bootstrapped"
fi

warehouses=$(curl -fsS "$LAKEKEEPER_URL/management/v1/warehouse" -H "x-project-id: $project_id")
if echo "$warehouses" | grep -q "\"name\":\"$WAREHOUSE_NAME\""; then
  echo "Warehouse $WAREHOUSE_NAME already exists"
  exit 0
fi

# RustFS has no STS, so credential vending stays off; engines use remote signing or their own keys.
warehouse_request=$(cat <<JSON
{
  "warehouse-name": "$WAREHOUSE_NAME",
  "project-id": "$project_id",
  "storage-profile": {
    "type": "s3",
    "flavor": "s3-compat",
    "bucket": "$S3_BUCKET",
    "region": "$S3_REGION",
    "endpoint": "$S3_ENDPOINT",
    "path-style-access": true,
    "sts-enabled": false
  },
  "storage-credential": {
    "type": "s3",
    "credential-type": "access-key",
    "access-key-id": "$S3_ACCESS_KEY",
    "secret-access-key": "$S3_SECRET_KEY"
  }
}
JSON
)

curl -fsS -X POST "$LAKEKEEPER_URL/management/v1/warehouse" \
  -H "Content-Type: application/json" \
  --data "$warehouse_request"
echo
echo "Warehouse $WAREHOUSE_NAME created"

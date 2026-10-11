#!/usr/bin/env bash
# Creates the `lakehouse` external catalog (Iceberg REST on Lakekeeper) in StarRocks and the internal
# database that holds the materialized views. Idempotent. Static S3 keys, no vended credentials (SPEC §3.1).
set -euo pipefail

set -a
source .env
set +a

run_sql() {
    docker compose exec -T starrocks mysql -h 127.0.0.1 -P 9030 -u root "$@"
}

run_sql <<SQL
CREATE EXTERNAL CATALOG IF NOT EXISTS lakehouse
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "rest",
    "iceberg.catalog.uri" = "http://lakekeeper:8181/catalog",
    "iceberg.catalog.warehouse" = "${LAKEKEEPER_WAREHOUSE}",
    "iceberg.catalog.vended-credentials-enabled" = "false",
    "aws.s3.endpoint" = "http://rustfs:9000",
    "aws.s3.enable_path_style_access" = "true",
    "aws.s3.region" = "${S3_REGION}",
    "aws.s3.access_key" = "${S3_ACCESS_KEY}",
    "aws.s3.secret_key" = "${S3_SECRET_KEY}"
);
CREATE DATABASE IF NOT EXISTS sleipnir_mv;
SQL

run_sql --table -e "SHOW CATALOGS"

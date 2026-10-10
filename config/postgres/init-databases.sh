#!/usr/bin/env bash
# Runs once, on an empty data volume. Add one create_database line per new service.
set -euo pipefail

create_database() {
  local name="$1"
  local password="$2"
  psql --username postgres --set ON_ERROR_STOP=1 \
    --set name="$name" --set password="$password" <<'SQL'
CREATE ROLE :"name" LOGIN PASSWORD :'password';
CREATE DATABASE :"name" OWNER :"name";
SQL
}

create_database lakekeeper "$LAKEKEEPER_DB_PASSWORD"

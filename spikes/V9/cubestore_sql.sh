#!/usr/bin/env bash
# Usage: cubestore_sql.sh "<sql>"   Runs SQL on Cube Store (MySQL protocol, router port 3306) from a throwaway container.
set -euo pipefail
docker run --rm --network sleipnir_default mysql:8 mysql -h cubestore-router -P 3306 -e "$1"

#!/usr/bin/env bash
# Starts the Spark Thrift Server as a single JVM sized from the resource profile (SPEC §4.1).
set -euo pipefail

cpus="${ENGINE_CPUS:?set by env/<profile>.env}"
memory="${ENGINE_MEMORY:?set by env/<profile>.env}"

if [[ "${memory}" != *g ]]; then
    echo "ENGINE_MEMORY must be in gigabytes (e.g. 8g), got ${memory}" >&2
    exit 1
fi

memory_gb="${memory%g}"
# 75% of the container: the rest is JVM overhead, off-heap buffers and Parquet writers.
driver_memory_mb=$((memory_gb * 1024 * 3 / 4))
# 3 x N: within the 2-3 x N range of SPEC §4.1.
shuffle_partitions=$((cpus * 3))

# Derby metastore of the Hive-enabled session lands in the working directory.
cd /tmp

/opt/spark/bin/spark-submit \
    --class org.apache.spark.sql.hive.thriftserver.HiveThriftServer2 \
    --name sleipnir-thriftserver \
    --master "local[${cpus}]" \
    --driver-memory "${driver_memory_mb}m" \
    --conf "spark.sql.shuffle.partitions=${shuffle_partitions}" \
    --conf "spark.sql.catalog.lakehouse.warehouse=${LAKEKEEPER_WAREHOUSE}" \
    --conf "spark.sql.catalog.lakehouse.s3.endpoint=http://rustfs:9000" \
    --conf "spark.sql.catalog.lakehouse.client.region=${S3_REGION}" \
    --conf "spark.sql.catalog.lakehouse.s3.access-key-id=${S3_ACCESS_KEY}" \
    --conf "spark.sql.catalog.lakehouse.s3.secret-access-key=${S3_SECRET_KEY}" \
    --hiveconf hive.server2.thrift.bind.host=0.0.0.0 \
    --hiveconf hive.server2.thrift.port=10000 \
    spark-internal &
server_pid=$!
trap 'kill -TERM "${server_pid}"' TERM INT

# PyHive (dbt-spark) runs `USE default` on every connection and gives no way to change it, and the
# Lakekeeper catalog has no such namespace. Created once the server accepts connections; the
# healthcheck connects to `default`, so the container is healthy only after this.
until /opt/spark/bin/beeline -u "jdbc:hive2://localhost:10000/duckdb_bronze" \
    -e 'CREATE NAMESPACE IF NOT EXISTS lakehouse.`default`' > /dev/null 2>&1
do
    kill -0 "${server_pid}"
    sleep 2
done

wait "${server_pid}"

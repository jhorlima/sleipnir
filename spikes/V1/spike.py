"""V1 spike: DuckDB writes Iceberg tables through the Lakekeeper REST catalog.

Run inside a throwaway container on the compose network (see run.sh).
MODE=vended  -> rely on Lakekeeper access delegation (no S3 secret).
MODE=static  -> ACCESS_DELEGATION_MODE 'none' + a static S3 secret.
"""

import os
import time

import duckdb

MODE = os.environ.get("MODE", "static")
ROWS = int(os.environ.get("ROWS", "100000"))

con = duckdb.connect()
print("duckdb", duckdb.__version__)
con.sql("INSTALL iceberg; LOAD iceberg; INSTALL httpfs; LOAD httpfs;")
print(con.sql("SELECT extension_name, extension_version FROM duckdb_extensions() "
              "WHERE extension_name IN ('iceberg','httpfs','avro')").fetchall())


def run(sql):
    print(">>", " ".join(sql.split()))
    return con.sql(sql)


if MODE == "static":
    run(f"""
        CREATE SECRET rustfs (
            TYPE s3, KEY_ID '{os.environ["S3_ACCESS_KEY"]}', SECRET '{os.environ["S3_SECRET_KEY"]}',
            REGION '{os.environ["S3_REGION"]}', ENDPOINT 'rustfs:9000', URL_STYLE 'path', USE_SSL false
        )""")
    delegation = "ACCESS_DELEGATION_MODE 'none',"
else:
    delegation = ""

run(f"""
    ATTACH 'lakehouse' AS lakehouse (
        TYPE iceberg, ENDPOINT 'http://lakekeeper:8181/catalog',
        AUTHORIZATION_TYPE 'none', {delegation} PURGE_REQUESTED true
    )""")

run("CREATE SCHEMA IF NOT EXISTS lakehouse.spike_v1")

# GHCN-Daily shaped rows, written to a local CSV first (like landing/).
run(f"""
    COPY (
        SELECT
            'USW000' || lpad((i % 500)::VARCHAR, 5, '0')           AS id,
            strftime(DATE '2024-01-01' + (i // 500)::INT, '%Y%m%d') AS date,
            ['TMAX','TMIN','PRCP','SNOW','SNWD'][(i % 5) + 1]      AS element,
            (random() * 400 - 100)::INT                            AS value,
            CASE WHEN i % 97 = 0 THEN 'T' END                      AS m_flag,
            CASE WHEN i % 211 = 0 THEN 'I' END                     AS q_flag,
            'W'                                                    AS s_flag,
            CASE WHEN i % 3 = 0 THEN '0700' END                    AS obs_time
        FROM range({ROWS}) t(i)
    ) TO '/tmp/batch.csv' (HEADER false)""")
csv_mb = os.path.getsize("/tmp/batch.csv") / 1e6

SRC = """
    SELECT *, {batch}::INT AS _batch_id, now()::TIMESTAMPTZ AS _ingested_at
    FROM read_csv('/tmp/batch.csv', header = false, columns = {{
        'id': 'VARCHAR', 'date': 'VARCHAR', 'element': 'VARCHAR', 'value': 'INTEGER',
        'm_flag': 'VARCHAR', 'q_flag': 'VARCHAR', 's_flag': 'VARCHAR', 'obs_time': 'VARCHAR'}})
"""


def timed(sql):
    t = time.perf_counter()
    run(sql)
    return time.perf_counter() - t


# 1. Unpartitioned: CTAS + append.
run("DROP TABLE IF EXISTS lakehouse.spike_v1.ghcn_daily_raw")
t1 = timed("CREATE TABLE lakehouse.spike_v1.ghcn_daily_raw AS " + SRC.format(batch=1))
t2 = timed("INSERT INTO lakehouse.spike_v1.ghcn_daily_raw " + SRC.format(batch=2))
print("count by batch:", run("SELECT _batch_id, count(*) FROM lakehouse.spike_v1.ghcn_daily_raw "
                             "GROUP BY ALL ORDER BY 1").fetchall())
print(f"CTAS  {ROWS} rows: {t1:.2f}s  {ROWS / t1:,.0f} rows/s  {csv_mb / t1:.1f} CSV-MB/s")
print(f"INSERT {ROWS} rows: {t2:.2f}s  {ROWS / t2:,.0f} rows/s  {csv_mb / t2:.1f} CSV-MB/s")
print("properties:", run("SELECT * FROM iceberg_table_properties(lakehouse.spike_v1.ghcn_daily_raw)").fetchall())
print("snapshots:", run("SELECT * FROM iceberg_snapshots(lakehouse.spike_v1.ghcn_daily_raw)").fetchall())
files = run("SELECT * FROM iceberg_metadata(lakehouse.spike_v1.ghcn_daily_raw)").fetchall()
print("data files:", files)

# 2. Partitioned by _batch_id (SPEC §7 bronze layout), explicit v2, zstd requested.
run("DROP TABLE IF EXISTS lakehouse.spike_v1.ghcn_daily_part")
run("""
    CREATE TABLE lakehouse.spike_v1.ghcn_daily_part (
        id VARCHAR, date VARCHAR, element VARCHAR, value INTEGER, m_flag VARCHAR,
        q_flag VARCHAR, s_flag VARCHAR, obs_time VARCHAR, _batch_id INTEGER, _ingested_at TIMESTAMPTZ
    ) PARTITIONED BY (_batch_id)
    WITH ('format-version' = '2', 'write.parquet.compression-codec' = 'zstd')""")
t3 = timed("INSERT INTO lakehouse.spike_v1.ghcn_daily_part " + SRC.format(batch=1))
t4 = timed("INSERT INTO lakehouse.spike_v1.ghcn_daily_part " + SRC.format(batch=2))
print(f"partitioned INSERT x2: {t3:.2f}s / {t4:.2f}s")
print("part count:", run("SELECT _batch_id, count(*) FROM lakehouse.spike_v1.ghcn_daily_part "
                         "GROUP BY ALL ORDER BY 1").fetchall())
part_files = run("SELECT file_path, record_count FROM iceberg_metadata(lakehouse.spike_v1.ghcn_daily_part)").fetchall()
print("part files:", part_files)
# Table roots, e.g. s3://lakehouse/<table-uuid>; earlier runs may still be purging other roots.
roots = sorted({f[5].split("/data/")[0] for f in files} | {f[0].split("/data/")[0] for f in part_files})

# 3. Inspect the files in the bucket (needs the static S3 secret).
if MODE == "static":
    for root in roots:
        print("table root:", root)
        print("metadata.json:", run(f"""
            SELECT filename, "format-version", "partition-specs"
            FROM read_json('{root}/metadata/*.metadata.json', compression = 'gzip',
                           filename = true, union_by_name = true)
            ORDER BY filename""").fetchall())
        print("parquet:", run(f"""
            SELECT DISTINCT compression, row_group_num_rows
            FROM parquet_metadata('{root}/data/**/*.parquet')""").fetchall())

if os.environ.get("KEEP") != "1":
    run("DROP TABLE lakehouse.spike_v1.ghcn_daily_raw")
    run("DROP TABLE lakehouse.spike_v1.ghcn_daily_part")
    run("DROP SCHEMA lakehouse.spike_v1")
print("OK")

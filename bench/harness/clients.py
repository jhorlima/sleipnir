"""One client per engine, all with the same three methods: execute(query) -> rows, cancel(), close().
Runs inside the `bench` container, so every host name is a compose service name (SPEC D-11)."""

import base64
import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.request


class TrinoClient:
    def __init__(self, schema):
        import trino

        connection = trino.dbapi.connect(
            host="trino", port=8080, user="bench", catalog="lakehouse", schema=schema
        )
        self.cursor = connection.cursor()

    def execute(self, sql):
        self.cursor.execute(sql)
        return self.cursor.fetchall()

    def cancel(self):
        self.cursor.cancel()

    def close(self):
        self.cursor.close()


class StarRocksClient:
    """FE MySQL protocol. The MV rewrite is switched explicitly: off for B3/B4 (the baseline), on for B5a."""

    def __init__(self, schema, mv_rewrite):
        import pymysql

        self.connection = pymysql.connect(host="starrocks", port=9030, user="root", autocommit=True)
        self.connection_id = self.connection.thread_id()
        cursor = self.connection.cursor()
        cursor.execute(f"USE lakehouse.{schema}")
        cursor.execute(f"SET enable_materialized_view_rewrite = {str(mv_rewrite).lower()}")
        # Union rewrite stays off: StarRocks bug #79345 (SPEC §10.3).
        cursor.execute("SET enable_materialized_view_union_rewrite = false")
        self.cursor = cursor

    def execute(self, sql):
        self.cursor.execute(sql)
        return self.cursor.fetchall()

    def explain(self, sql):
        self.cursor.execute(f"EXPLAIN {sql}")
        return "\n".join(row[0] for row in self.cursor.fetchall())

    def cancel(self):
        import pymysql

        killer = pymysql.connect(host="starrocks", port=9030, user="root", autocommit=True)
        killer.cursor().execute(f"KILL QUERY {self.connection_id}")
        killer.close()

    def close(self):
        self.connection.close()


def duckdb_memory_limit_gb():
    """75% of ENGINE_MEMORY (like the Cube-hosted DuckDB, SPEC D-22); ENGINE_MEMORY is '8g' style."""
    memory_gb = int(os.environ.get("ENGINE_MEMORY", "8g").rstrip("gG"))
    return max(1, memory_gb * 3 // 4)


def duckdb_threads():
    return int(os.environ.get("ENGINE_CPUS", "4"))


class DuckDBClient:
    """In-process DuckDB reading the Iceberg tables through Lakekeeper, or Postgres for the small scale."""

    def __init__(self, schema, source="lakehouse"):
        import duckdb

        self.connection = duckdb.connect()
        self.connection.execute(f"SET threads = {duckdb_threads()}")
        self.connection.execute(f"SET memory_limit = '{duckdb_memory_limit_gb()}GB'")
        if source == "lakehouse":
            self._attach_lakehouse()
        else:
            self._attach_postgres()
        self.connection.execute(f"USE {source}.{schema}")

    def _attach_lakehouse(self):
        self.connection.execute("LOAD iceberg")
        self.connection.execute("LOAD httpfs")
        self.connection.execute(f"""
            CREATE SECRET rustfs (
                TYPE s3,
                KEY_ID '{os.environ["S3_ACCESS_KEY"]}',
                SECRET '{os.environ["S3_SECRET_KEY"]}',
                REGION '{os.environ["S3_REGION"]}',
                ENDPOINT '{os.environ["S3_ENDPOINT"]}',
                URL_STYLE 'path',
                USE_SSL false
            )
        """)
        # The warehouse has STS and remote signing off (SPEC §3.1), so DuckDB uses the static secret.
        self.connection.execute(f"""
            ATTACH '{os.environ["LAKEKEEPER_WAREHOUSE"]}' AS lakehouse (
                TYPE iceberg,
                ENDPOINT '{os.environ["LAKEKEEPER_CATALOG_URL"]}',
                AUTHORIZATION_TYPE 'none',
                ACCESS_DELEGATION_MODE 'none'
            )
        """)

    def _attach_postgres(self):
        self.connection.execute("LOAD postgres")
        self.connection.execute(
            "ATTACH 'host=postgres-bench user=sleipnir dbname=sleipnir' AS postgres (TYPE postgres, READ_ONLY)"
        )

    def execute(self, sql):
        return self.connection.execute(sql).fetchall()

    def cancel(self):
        self.connection.interrupt()

    def close(self):
        self.connection.close()


class PostgresClient:
    def __init__(self, schema):
        import psycopg

        self.connection = psycopg.connect(
            host="postgres-bench", user="sleipnir", dbname="sleipnir", autocommit=True,
            options=f"-c search_path={schema}",
        )

    def execute(self, sql):
        return self.connection.execute(sql).fetchall()

    def cancel(self):
        self.connection.cancel()

    def close(self):
        self.connection.close()


def base64url(raw_bytes):
    return base64.urlsafe_b64encode(raw_bytes).rstrip(b"=").decode()


def cube_token(secret):
    """HS256 JWT signed with the API secret (same as scripts/cube-query.sh)."""
    now = int(time.time())
    header = base64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = base64url(json.dumps({"iat": now, "exp": now + 3600}).encode())
    signature = hmac.new(secret.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest()
    return f"{header}.{payload}.{base64url(signature)}"


def cube_columns(query):
    """Result columns in the order the reference SQL selects them: dimensions, time dimensions, measures."""
    columns = list(query.get("dimensions", []))
    for time_dimension in query.get("timeDimensions", []):
        if "granularity" in time_dimension:
            columns.append(f"{time_dimension['dimension']}.{time_dimension['granularity']}")
    columns.extend(query.get("measures", []))
    return columns


class CubeClient:
    """Cube REST API straight on cube-api:4000, not through Traefik (SPEC D-11).
    Cube's result cache lives in the Cube Store volume and survives restarts. The body sends `renewQuery: true`
    and `cache: no-cache`: renewQuery alone only re-checks the refresh key (measured: still a cache hit within
    its window), while no-cache always executes, so every run reaches the engine (B4) or the rollup (B5c)."""

    def __init__(self, timeout_seconds):
        self.token = cube_token(os.environ["CUBEJS_API_SECRET"])
        self.timeout_seconds = timeout_seconds
        self.last_response = None

    def execute(self, query):
        columns = cube_columns(query)
        body = json.dumps({"query": query, "renewQuery": True, "cache": "no-cache"}).encode()
        deadline = time.monotonic() + self.timeout_seconds
        while True:
            response = self._post(body, max(1.0, deadline - time.monotonic()))
            if response.get("error") != "Continue wait":
                break
            if time.monotonic() > deadline:
                raise TimeoutError("Cube still answering 'Continue wait' at the deadline")
            time.sleep(0.5)
        if "error" in response:
            raise RuntimeError(f"Cube error: {response['error']}")
        self.last_response = response
        rows = []
        for record in response["data"]:
            rows.append(tuple(record.get(column) for column in columns))
        return rows

    def _post(self, body, timeout):
        request = urllib.request.Request(
            "http://cube-api:4000/cubejs-api/v1/load", data=body,
            headers={"Authorization": self.token, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as reply:
                return json.load(reply)
        except urllib.error.HTTPError as error:
            try:
                return json.loads(error.read())
            except json.JSONDecodeError:
                return {"error": f"HTTP {error.code}"}

    def cancel(self):
        # The request is blocking and bounded by `timeout_seconds`; there is nothing to kill on the Cube side.
        pass

    def close(self):
        pass

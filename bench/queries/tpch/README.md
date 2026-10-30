# TPC-H queries (D2)

Derived from TPC-H, not comparable to published TPC-H results.

The 22 queries per engine (`qNN.duckdb.sql`, `qNN.trino.sql`, `qNN.starrocks.sql`) use the standard
default substitution parameters, with two deliberate edits: Q11's threshold fraction is 0.0001 / SF
(SF 8 = 0.0000125, so the result is not empty) and Q15 uses a CTE instead of a view.
Engine differences are limited to `substr` in Q22 and `GROUP BY l_suppkey` in Q15 (Trino and StarRocks).

Data: `make tpch SF=8` writes `lakehouse.duckdb_tpch`. Correctness gate (row count + order-insensitive
checksum, numbers rounded to 2 decimals, against DuckDB): `make tpch-check ENGINE=duckdb|trino|starrocks`
with the engine up.

# Benchmark integrity

Non-negotiable. These protect the published numbers. If a request conflicts with one of them, stop and ask for an explicit override.

1. **One engine under test at a time.** Never run two transformations (or two engines' suites) concurrently. dbt `threads` is allowed but must be the same `DBT_THREADS` for every engine.
2. **Same resources for every engine.** Limits come from the active profile (`env/s|m|l.env`); never tune one engine's limits without re-running the others.
3. **Engine config is recorded, not hidden.** Any non-default setting lives in `config/<engine>/` and is written to `results` (`engine_config`).
4. **Results are produced, never edited.** `results/*.parquet` is written only by the harness. A wrong run is re-run or marked invalid, never patched.
5. **Correctness gates speed.** A query whose row count/checksum differs from the DuckDB reference, or a B5a query whose `EXPLAIN` does not use the MV, is recorded as invalid. Approximate measures (e.g. Trino `approx_percentile`) are compared with a 5% relative tolerance, recorded with the result.
6. **Storage budget.** One execution (bronze + one writer's silver/gold + TPC-H) stays ≤ 10 GB; check with `make storage-report ENGINE=<engine>` before declaring a phase done.
7. **TPC-H naming.** Results derived from TPC-H are labelled "derived from TPC-H, not comparable to published TPC-H results" (TPC fair-use policy).
8. **No hidden work inside measured steps.** Measured dbt runs pass `--vars '{maintenance: false}'`; maintenance runs only as its own measured step (`dbt run-operation maintain_table`).
9. **Resets are complete before the next run.** `DROP TABLE ... PURGE` deletes files asynchronously in Lakekeeper; a reset waits until the table prefix is empty (or wipes it) before the next measured step.

#!/usr/bin/env bash
# Sizes Postgres from the resource profile (SPEC §10.1), then starts the image's own entrypoint.
# The flags are printed so they can be recorded as engine_config; SHOW ALL on the running server has the same values.
set -euo pipefail

memory="${ENGINE_MEMORY:?set by env/<profile>.env}"
cpus="${ENGINE_CPUS:?set by env/<profile>.env}"

if [[ "${memory}" != *g ]]; then
    echo "ENGINE_MEMORY must be in gigabytes (e.g. 8g), got ${memory}" >&2
    exit 1
fi

memory_mb=$((${memory%g} * 1024))

# 25% of the container: the usual starting point; the rest is left to the OS page cache.
shared_buffers_mb=$((memory_mb / 4))
# 75%: tells the planner how much data the OS cache plus shared_buffers can hold; allocates nothing.
effective_cache_size_mb=$((memory_mb * 3 / 4))
# 1/64 of the container per sort/hash node; with the profile's dbt threads and parallel workers it stays under the limit.
work_mem_mb=$((memory_mb / 64))
# 1/16: speeds up the index builds and VACUUM that maintain_table runs.
maintenance_work_mem_mb=$((memory_mb / 16))
# One parallel worker per CPU of the profile, the same cores the other engines get.
parallel_workers="${cpus}"

flags=(
    -c "shared_buffers=${shared_buffers_mb}MB"
    -c "effective_cache_size=${effective_cache_size_mb}MB"
    -c "work_mem=${work_mem_mb}MB"
    -c "maintenance_work_mem=${maintenance_work_mem_mb}MB"
    -c "max_parallel_workers_per_gather=${parallel_workers}"
    -c "max_parallel_workers=${parallel_workers}"
    -c "max_worker_processes=$((parallel_workers > 8 ? parallel_workers : 8))"
    # Bulk loads and delete+insert write many GB of WAL; a larger limit avoids a checkpoint every few seconds.
    -c "max_wal_size=8GB"
)

echo "postgres-bench settings: ${flags[*]}"
exec docker-entrypoint.sh postgres "${flags[@]}"

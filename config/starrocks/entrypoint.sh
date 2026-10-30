#!/usr/bin/env bash
# Sizes the FE and the BE from the resource profile, then starts the image's own entrypoint (SPEC §10.1).
# FE and BE share one container limit; without this the FE heap is 8 GB and the BE sizes itself from the host.
set -euo pipefail

memory="${ENGINE_MEMORY:?set by env/<profile>.env}"

if [[ "${memory}" != *g ]]; then
    echo "ENGINE_MEMORY must be in gigabytes (e.g. 8g), got ${memory}" >&2
    exit 1
fi

memory_gb="${memory%g}"
# 25% of the container: the FE only plans queries and holds catalog metadata; the rest is JVM off-heap.
fe_heap_gb=$((memory_gb / 4))
# 62.5% of the container: set explicitly because the BE default (90%) is not derived from the container limit.
be_mem_limit_gb=$((memory_gb * 5 / 8))

fe_conf="${SR_HOME}/fe/conf/fe.conf"
be_conf="${SR_HOME}/be/conf/be.conf"

sed -i "s/-Xmx[0-9]*[mg]/-Xmx${fe_heap_gb}g/" "${fe_conf}"

sed -i '/^mem_limit/d' "${be_conf}"
echo "mem_limit = ${be_mem_limit_gb}G" >> "${be_conf}"

cd /data/deploy
exec ./entrypoint.sh

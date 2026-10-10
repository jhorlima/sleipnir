# Code style

Readable over compact. The reader must understand a file without running it, even if that costs more lines.

## General
- Clear names; small functions; no speculative abstractions or "for later" scaffolding.
- Comments only for the non-obvious *why* (an engine quirk, a workaround, a deliberate deviation). Never narrate what the code does.
- Pin every version (`.env`); no `latest` tags.
- Scripts are idempotent: running twice neither duplicates data nor fails.

## Bash and Makefile
- One command per line; clear variable names (`engine`, `batch_id`, `target_namespace`).
- No nested loops, no chained one-liners, no clever parameter expansion when a plain `if` reads better.
- More than a few lines of logic → `scripts/<task>.sh` with `set -euo pipefail`; the Makefile target only calls the script.
- Every Makefile target has a `## description` so `make help` lists it.

## Python
- No nested comprehensions or clever one-liners; explicit loops and well-named functions.
- Managed with `uv`; dependencies pinned.

## SQL / dbt
- One model per file; CTEs named after what they hold (`deduplicated_observations`, not `cte2`).
- Engine-specific SQL lives in adapter-dispatched macros, never copy-pasted per engine.

## Docker Compose
- One file per domain under `compose/`, joined by `include` in `compose.yaml`; `profiles` per engine.
- Resource limits from variables with defaults (`${TRINO_CPUS:-4}`); S/M/L values in `env/*.env`.
- No published ports by default (UIs via Traefik); database ports only on `127.0.0.1` when needed.

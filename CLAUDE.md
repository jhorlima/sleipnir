# Sleipnir — ELT Lakehouse + Query Engine Benchmark

Local lakehouse (DuckDB → Iceberg on RustFS/Lakekeeper → dbt on Trino/Spark/Postgres → StarRocks/Trino/DuckDB readers → Cube) built to benchmark ingestion, transformation and read latency. The end goal is a **public repo + article** (blog/LinkedIn) with reproducible numbers.

**`docs/SPEC.md` is the source of truth.** Read the relevant section before changing anything; cite it instead of restating it. When a decision changes, update the SPEC (decisions §14, spikes §15) in the same change.

## Language

- Code, comments, commit messages, README and agent prompts: **English** (public repo).
- `docs/SPEC.md`: Portuguese; `docs/SPEC.en.md` is generated once the SPEC stabilizes.
- Chat: the user's language.

## Public repo

This repo will be published. Never reference private projects, companies, clients, internal hosts, local paths or personal data in code, docs, commits or Claude config. Lessons from other work are written as generic patterns, without naming where they came from.

## Specs

- Specs describe the **current** state only. When something changes, rewrite the affected text; never leave superseded options, strike-throughs or "previously" notes. History lives in git.
- `docs/SPEC.md` is the project overview; detailed specs per phase/feature go to `docs/specs/<topic>.md` and are linked from it.

## Article notebook

`docs/blog/post.md` is the article draft and the project's lab notebook. Whenever a decision is made, a spike is resolved, a gotcha is found or a suite produces numbers, add it to the matching section in the same change (story tone, no internal references). The author writes the motivation section.

## Rules

- `.claude/rules/code-style.md` — readability rules for bash, Makefile, Python, SQL, Compose.
- `.claude/rules/benchmark-integrity.md` — non-negotiable rules that keep the numbers trustworthy.
- `.claude/rules/cube-models.md` — Cube layout, DOUBLE cast for pre-aggregations, StarRocks via MySQL.

## Workers

Delegate to keep the main context small; the main session plans and reviews.

| Agent | Use for |
|---|---|
| `stack-worker` | One scoped implementation task (a compose service, an ingest script, a dbt model set, a Cube schema) end-to-end with its validation. |
| `spike-researcher` | One validation item from SPEC §15 (V1…V8): docs research + the smallest local proof. |
| `bench-runner` | Run a benchmark suite, watch the long output, return only the summary. |

- Independent tasks (e.g. two spikes, or Trino config + ingest script) → dispatch workers in parallel.
- Never dispatch two workers that start engines at the same time while a benchmark is running (benchmark-integrity §1).
- Every worker prompt states TASK / SCOPE (paths it may touch) / DONE WHEN. Workers answer `DONE — …` or `BLOCKED — …`.

## Commands

The `Makefile` is the entry point; run `make help` for the current targets. Phase status lives in SPEC §13.

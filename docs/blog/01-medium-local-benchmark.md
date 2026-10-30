# Four query engines, four billion weather rows, one laptop

*What I learned racing Trino, Spark, StarRocks and DuckDB on the same Iceberg lakehouse, and everything that broke along the way.*

## Why I built this

It started small. I was looking for a public dataset to build a fact layer on and push Cube's pre-aggregations to their limits. Once I found one, I thought: why stop there?

I've worked with these tools for years: Trino, Spark, dbt, partitioning, cluster by, incremental models, delete+insert, table maintenance. I know how they behave in the projects I've worked on. What I wanted was to look at them from a different angle: new compression and partitioning choices, a bigger dataset than I'd usually throw at DuckDB, and every engine with exactly the same limits. And I wanted to see how far AI could take me on the scaffolding, so I could spend my time on the tests instead of the plumbing.

The benchmarks I found that tested things the way I wanted were on older engine versions and different data volumes. Spark 4 was out, Trino and StarRocks had moved a lot, and I had three questions I couldn't answer from what was already published:

- **How far does Postgres go** before you actually need a lakehouse stack?
- **Do the new versions of Spark and Trino** change the picture?
- **Is DuckDB a good option for ingestion and compression** at billions of rows?

## What I wanted to find out

Put simply: if every engine gets the same machine, the same tables and the same semantic layer, how fast does each one load, transform and serve the data? And what do the usual acceleration tricks (materialized views, pre-aggregations, compaction) actually buy you?

I wanted the boring version: the same files, the same limits, the same questions, and every answer checked before its time counts. And I wanted it on a **single worker** first, on purpose. Before adding replicas, I want a baseline to compare against: what one node can do, so that the multi-worker version (in the cloud, with network and throughput in the picture) has something to be measured against.

So I built a small lakehouse on a laptop and called it Sleipnir (Odin's eight-legged horse... several engines, one body).

## The data

Everything runs on **NOAA GHCN-Daily**, the Global Historical Climatology Network: daily weather observations from stations all over the world, published by NOAA's National Centers for Environmental Information as one CSV per year ([ncei.noaa.gov/pub/data/ghcn/daily](https://www.ncei.noaa.gov/pub/data/ghcn/daily/)).

A few things I didn't know before starting:

- The history starts in **1763**. There are no yearly files for 1750–1762 on the server.
- The early centuries are tiny compared with recent years, which reach ~28 M rows each. That difference ends up mattering (more on that later).
- In 1797 so few stations reported that an *approximate* median came out 12% off the exact one. Fine for a dashboard, but it fails a correctness check.

I loaded it at four scales:

| Scale | Years | Bronze rows |
|---|---|---|
| `small` | 2025 | 44 M (used for the Postgres baseline) |
| `r2` | 2010–2025 | 742 M |
| `r2_1998` | 1998–2025 | 1.29 B |
| `local` | 1763–2025 | **3.97 B** |

To give the incremental strategies real work, the ingestion creates duplicates on purpose: each batch repeats the last 7 days of the previous one, and ~1% of the rows come back with a revised value.

For a second, more standard workload I also generated **TPC-H** at SF8 with DuckDB. Those results are derived from TPC-H and are not comparable to published TPC-H results.

## The stack

| Layer | Choice |
|---|---|
| Object storage | RustFS (S3-compatible) |
| Catalog | Lakekeeper (Iceberg REST) |
| Table format | Apache Iceberg v2 |
| Ingestion | DuckDB |
| Transformation | dbt on Trino and on Spark (Postgres as a small baseline) |
| Readers | Trino, StarRocks, DuckDB |
| Semantic layer | Cube + Cube Store |
| Runtime | Docker Compose, one engine at a time |

One writer, many readers on the same files. Every engine reads the same Iceberg tables through the same catalog.

A note on how this got built: most of the stack was written with an AI coding assistant. I wrote a spec first (architecture, suites, rules, open questions), then worked through it with the assistant, with small agents doing scoped tasks and spikes in parallel. That made it possible to stand up a stack with seven moving parts in days instead of weeks. It did **not** make it right by default: a good part of this post is about bugs that only showed up when the numbers looked weird. AI makes building fast; checking is still on you :)

## The machine

Everything ran on one laptop:

| | |
|---|---|
| Laptop | MacBook Pro, Apple M4 Pro |
| CPU | 12 cores (8 performance + 4 efficiency) |
| Memory | 24 GB |
| Internal disk | 512 GB SSD |
| Source CSVs | external USB SSD |
| Software (at the end of the runs) | macOS 27, Docker Desktop 4.97 (engine 29.9) |
| Docker VM, profile M campaigns | 8 CPU, 16 GB, 2 GB swap, 103 GB disk limit |
| Docker VM, profile L campaigns | 10 CPU, 20 GB, 2 GB swap, 103 GB disk limit |

Two things worth knowing before reading the numbers. The engines run inside a Linux VM, not on macOS directly, and the VM's CPUs are scheduled by macOS on whatever core is free: there's no way to pin them to the performance cores, so a run can land partly on the slower ones. And the VM size itself moves the numbers a little: going from 16 to 20 GB made the same queries 2–13% faster with the same engine limits, so every result records the VM size next to it.

## Keeping it fair

These rules made the numbers worth publishing, and they also caused most of the extra work:

- **One engine under test at a time.** Never two transformations in parallel.
- **Same CPU and memory for every engine.** Profile **M** = 4 CPU / 8 GB, profile **L** = 8 CPU / 12 GB, as container limits.
- **Correctness before speed.** Every query result is compared (row count + checksum) with a DuckDB reference. A fast wrong answer is recorded as invalid.
- **Results are produced, never edited.** A bad run is re-run or listed as invalidated, with the reason. The original rows stay.
- **Every engine-specific setting is recorded** next to the numbers.

## Results

> All of this is **for this setup**: one node inside a Docker VM on a Mac, this dataset (append-heavy time series), these queries. If your workload is different, test it. The point of the repo is that you can.

### Loading

DuckDB loaded the 3.97 B rows (3,156 batches) in 1,292 s, about 3 M rows/s, reading gzipped CSVs from a USB SSD. At the 742 M scale it was 5 M rows/s; the early centuries are thousands of tiny batches that each pay a fixed cost.

### Transforming (dbt, build from scratch at 3.97 B rows)

| | Profile M | Profile L |
|---|---|---|
| Trino | 12,639 s | 9,351 s |
| Spark | failed | 13,803 s |

Spark's failures turned out to be a session leak and then the object store running out of memory, not the size of the profile (see "What went wrong"). With both fixed it finished on L; it hasn't been re-run on M yet.

Reprocessing one batch (delete+insert, merge, microbatch) took 27–44 s on Trino at both profiles. It only touches one window, so more CPU doesn't help much.

### Reading: direct SQL and through Cube

Yearly count over the whole fact table (Q1), warm median:

| 3.97 B rows | M | L | L, object store with 2 CPUs |
|---|---|---|---|
| Trino, direct | 2.7 s | 3.1 s | 3.5 s |
| StarRocks, direct | 3.8 s | 1.8 s | 2.2 s |
| DuckDB, direct | 5.9 s | 3.1 s | 3.1 s |
| Trino, through Cube | 32.4 s | 65.3 s | **24.6 s** |
| StarRocks, through Cube | 70.5 s | 44.5 s | 40.8 s |
| DuckDB inside Cube | 60.5 s | 37.4 s | 30.6 s |

Filtered questions (a station, a country, a period) stayed in the tens to hundreds of milliseconds. On Trino they took 109–452 ms at 742 M rows and 121–466 ms at 3.97 B: partition pruning plus a sort order means they barely notice the table growing 5×.

On TPC-H SF8 (742 M scale, profile M), the warm geometric mean was 304 ms for DuckDB, 551 ms for StarRocks and 1,874 ms for Trino.

### Acceleration

- **Cube Store pre-aggregations** answered in **16–34 ms** at every scale, whichever engine built them. The cost moves to the build: 846 s on Trino at 3.97 B rows.
- **StarRocks materialized views** (one plain copy per gold table) refreshed in 909 s on M and ~600 s on L... and did not make the reads faster than StarRocks reading Iceberg directly (Q1: 2.5 s with the MV, 1.8 s without). A copy saves no work. An MV pays off when it pre-joins or pre-aggregates something, which is a different test.

## The M → L surprise

I expected profile L (twice the CPU) to be faster everywhere. For DuckDB and StarRocks it mostly was. For Trino, the whole-table query through Cube got **2× slower**: 32 s → 65 s.

The filtered queries didn't move, and the object store sat at 1 CPU in every profile (shared infrastructure held constant, as the rules say). An engine with 8 CPUs was just sending more requests to an object store that couldn't keep up.

So I ran profile L again with the object store at 2 CPUs. Same Trino query: **24.6 s**. Faster than M, finally.

Where this matters: if you benchmark (or size) an engine against a self-hosted object store, the object store can be the thing you're measuring. Where it doesn't: managed object storage scales on its own, so in the cloud this specific bottleneck should mostly go away. That is one of the things the next round will check.

## What went wrong (the fun part)

Most of the time on this project went here. Each of these looked like an engine problem at first.

**1. The laptop fell asleep.** Trino threw `ABANDONED_TASK` in the middle of a run, twice. The clue was query IDs lagging behind the log clock. macOS went into idle sleep and froze the Docker VM, once mid-run and once in a gap *between* runs, where the per-command `caffeinate` didn't cover. Now the whole campaign runs under one keep-awake, and a run only starts when the machine is idle.

**2. Swap.** Profile L needs a 20 GB Docker VM on a 24 GB Mac. On the first night with that VM I was also using the Mac, macOS ended up with 15.7 of 16 GB of swap in use, and the build came out 17% slower than the same build on profile L a few days earlier. Those runs are invalidated, and the campaign script now logs free memory and swap before and after each measured step. If you run something like this on a laptop: run it at night, with nothing else open xD

**3. Spark's heap kept growing.** On the long build, each batch got slower: 10 s, then 30, then 190. The object store was idle, Spark was at 770% CPU and 11 of 12 GB, mostly doing garbage collection. A heap histogram showed **4.4 million Iceberg snapshot objects**. The Spark Thrift Server keeps every closed JDBC session alive, dbt opens one per batch, and each kept session held its own catalog with a cached copy of the table metadata (with the full snapshot list). Memory grew with commits × sessions. Turning off two catalog caches fixed it, and the same pattern had slowed down and killed the earlier run on profile M.

**4. Then the object store ran out of memory.** With Spark fixed, RustFS got OOM-killed after a couple of hours of writes, at 3 GB and then at 5 GB. Its background scanner holds metadata for every object it walks, and Iceberg writes a lot of small files. A newer release fixes part of it; with the scanner off, the object store stayed under 3 GB for the whole build.

**5. StarRocks' MV refresh blew up.** Out of memory on M and on L. The DDL had 16 buckets, sized for the 742 M scale. In StarRocks buckets count *per partition*, and the table has 3,156 monthly partitions at the full scale: ~50,000 tablets, each with its own write buffer. With 2 buckets per partition it refreshed on both profiles.

**6. The disk filled up.** Spark's `MERGE` on the 3.97 B-row silver table spilled ~33 GB of shuffle data and filled the Docker disk. That is where this round stopped.

**7. My own bugs.** A result table showed the *median* of the two build passes instead of their sum (6,320 s instead of 12,639 s). A pre-aggregation build check counted rollups that another engine had left behind and declared victory after 10 seconds. Both were caught because the numbers looked too good... which is a pretty good rule of thumb.

## Things that surprised me

- **Sorting beat partitioning, but partitions still earned their keep.** Sorting the fact table halved the storage and made the yearly count 37% faster. Dropping the monthly partitions made period filters 60–80% slower, even with partitions of 2–4 MB. The rule I ended with: sort first, partition by time when queries filter by time.
- **Approximate functions fail correctness checks.** Trino's `approx_percentile` was 19% off the exact median for one small group. Fine for a chart; not fine if you compare engines on "the same answer".
- **A row store pays for it in disk.** The 2025 data takes 0.23 GB as Iceberg/Parquet and 8.15 GB inside Postgres, about 35× more. That's why Postgres only runs at the smallest scale.
## Back to my three questions

**How far does Postgres go?** Further than people usually assume, for queries. With one year of data (44 M rows) the same dbt project built from scratch in 279 s on Postgres against 66 s on Trino, and Postgres answered the weather questions in 137 ms–1 s, against 32–511 ms for the columnar engines. That's slower, but fine for a lot of real use. What stopped it was **storage**: that year takes 8.15 GB in Postgres and 0.23 GB as Parquet, so 742 M rows would need ~90 GB, more than the whole Docker disk. If your data is in the tens of millions of rows, Postgres is probably enough. In the hundreds of millions and up, the disk makes the decision before the queries do.

One thing I didn't test, and should have: Postgres with **columnar storage**. Extensions like TigerData's columnstore (TimescaleDB), `pg_duckdb` or Citus columnar go straight at the storage problem, and could move the line where Postgres stops being enough. That goes into the next round.

**Do the new versions of Spark and Trino change the picture?** I can only half answer this one, because I didn't run the old versions side by side (that's a fair next test). What I can say: Spark 4.1 with Iceberg 1.12 ran the same dbt project as Trino 483 with no model changes, and at 3.97 B rows it needed two fixes that had nothing to do with its query engine (a session leak and the object store). Trino 483 was the steadiest writer of the whole project: when it failed, it was its per-query memory limit on a write that was too big at once (a yearly batch of ~28 M rows, a single `CREATE TABLE AS` of 1.1 B rows), and writing in smaller batches fixed it every time.

**Is DuckDB good for ingestion and compression?** Yes, for this shape of data. It loaded 742 M rows in 146 s (5 M rows/s) and wrote the bronze layer at 1.98 GB from 3.36 GB of gzipped CSV. As a reader it surprised me too: the fastest on three of the five filtered questions and on TPC-H at SF8, while running inside the benchmark process. Where it wouldn't fit: many concurrent users, or several services reading the same tables, which is exactly where a server engine earns its place.

All of this is DuckDB 1.5. DuckDB 2.0 came out on October 21, with these runs already going, so it isn't here: not for compatibility reasons, it just didn't exist yet when I pinned the versions. It brings async I/O for Parquet and a client-server mode, which touches both answers above, so it gets its own side-by-side run.

## What these numbers can and can't tell you

They can tell you how these engines behave relative to each other, on one node, with the same limits, on an append-heavy time series, and which tricks moved which questions.

They can't tell you how the engines behave on a cluster, on a different data shape (heavy updates, wide joins, high concurrency), or with each engine tuned by someone who knows it well. Some results here (the object store bottleneck, the Spark session leak, the disk filling up) are about this setup as much as about the engines.

## What's next

The next step is to run the same benchmark in the cloud, with managed object storage and more workers, to see whether the results change when the laptop is out of the picture: does Trino scale differently with more workers, does Spark's merge still need that much local disk, does the object store stop being the bottleneck? I'm testing that now, and when I have results I'll write a new post.

Before or along with it: DuckDB 1.5 against 2.0 on the same data, which is the closest I'll get to answering "do new versions change the picture?" for at least one engine, and Postgres with a columnar extension, to see how far that pushes the "how far does Postgres go" line.

After that comes orchestration (Airflow) on top of the same stack.

The code, the spec, every result file and the list of invalidated runs are in the repo: [github.com/jhorlima/sleipnir](https://github.com/jhorlima/sleipnir)

If you've run something similar and got different numbers, I'd really like to hear about it :D

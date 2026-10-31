# Storylines

Three ~30 s films for the README (1920×1080, 30 fps, no narration, effects only), stills for the Medium post, and a square cut for LinkedIn. All share `LOOK.md`; every number comes from `shared/data.json`.

## A — The race (`film-race/`)

- **Device / form:** a number lands; one continuous take. Four pens, one per engine, trace on the same chart paper while the drum turns; the camera never cuts, it follows the paper.
- **The viewer sees and feels:** a race they can read at a glance, where the result they expected (more CPU wins) gets turned over by the object store.
- **First 2 s:** four pens resting on the paper, the four engine logos at the left margin like a legend on a recorder, and "3.97 billion weather rows" stamped huge in graphite, "3.97" in pen red.
- **Beats:** hook (rows stamped) → load: DuckDB's pen runs, "742 M rows in 146 s" → build from scratch at 3.97 B: Trino 12,639 s → 9,351 s (M → L), Spark "failed" on M then 13,803 s → the turn: Trino's whole-table query through Cube climbs to 65.3 s on L, the pen hesitates, "object store +1 CPU", it drops to 24.6 s → payoff: Cube Store pen flat on the zero line, "16-34 ms", the one `impact-bass-1` → claim "Same data. Same limits. Different stories." → end: "Sleipnir" stamped, repo URL.
- **Sound:** `click-soft` pens down, `whoosh-short` paper advancing, `pop` on each stamped number, `impact-bass-1` on the Cube Store payoff.

## B — One row, four engines (`film-stack/`)

- **Device / form:** the worked example; object-to-object chain. One real CSV row travels through the stack; each stage's object becomes the next one.
- **The viewer sees and feels:** what the stack is, without a diagram slide, by following one row they can read.
- **First 2 s:** the oldest row of the dataset typed on the paper, `ITE00100554,17630101,TMAX,-36`, and under it "Milan, 1 January 1763. -3.6 °C."
- **Beats:** hook (1763 row) → the paper runs forward to 2025: `USW00094728,20250601,TMAX,189` "New York, Central Park, 18.9 °C" → DuckDB logo: the row lands in bronze as an Iceberg/Parquet file on RustFS (logos) → dbt logo: the 7-day overlap duplicate is struck through, silver, then the gold fact row → the same gold row read by Trino, StarRocks, DuckDB (logos), Spark wrote it too → Cube logo: the question "Central Park, June 2025" answered from Cube Store in "16-34 ms" → claim "One row. Four engines. Same answer." → end: "Sleipnir", repo URL.
- **Sound:** `typing` / `key-press` for typed rows, `whoosh-short` between stages, `pop` as each logo is stamped, `impact-bass-1` on the answer.

## C — The night shift (`film-night-shift/`)

- **Device / form:** a moment in someone's night; cut on the paper's sheets. The chart becomes a log book of one real night, time stamps in the margin.
- **The viewer sees and feels:** the honest, funny side of benchmarking on a laptop; every incident is real.
- **First 2 s:** "22:50" stamped in the margin, a laptop drawn in graphite line on the paper, lid open, the drum starting to turn.
- **Beats:** hook (22:50, the run starts) → the laptop "falls asleep": Trino "ABANDONED_TASK" (`glitch-3`) → swap gauge drawn filling to "15.7 / 16 GB" → Spark's heap: snapshot marks piling up to "4.4 M" (`error`) → object store "OOM at 3 GB… then 5 GB" → disk gauge to "103 GB full" → fixed, line by line (struck through as each is fixed) → "10:37" stamped → claim "~40 h, 8 days, 261 runs. Next stop: the cloud." → end: "Sleipnir", repo URL.
- **Sound:** `glitch-3` sleep, `error` on each failure, `pop` on each fix stamp, `whoosh-short` sheet turns, `impact-bass-1` on the claim.

## Stills for Medium (`medium-cards/`, 1400×788 PNG)

1. **Cover:** the race's opening frame (four pens, four logos, "3.97 billion weather rows").
2. **M → L → L with object store at 2 CPU:** Trino, StarRocks and DuckDB, whole-table query through Cube (from `q1_whole_table_through_cube_local`), Trino's trace in pen red.
3. **Build from scratch at 3.97 B rows:** Trino M / L / L2 and Spark L2, with Spark M marked "failed".
4. **Sort vs partition:** 0.73 → 0.38 GB, and the yearly unsorted count 197.5 s against 0.51 s sorted.
5. **Cube Store:** "16-34 ms" against Trino through Cube "3-4 s".
6. **Effort:** "~40 h · 8 days · 261 runs" with the night run 22:50 → 10:37.

Each card reads as a finished poster (information on screen at once, no animation needed).

## LinkedIn square cut (from A, after approval)

1080×1080, 10-15 s, silent: the hook, the M → L turn and the Cube Store payoff, ending on "Sleipnir". MP4 for the feed; a GIF only if asked.

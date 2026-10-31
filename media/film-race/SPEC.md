# Film A: The race

```text
GOAL:    the viewer reads a race at a glance and leaves knowing that more CPU did not make
         Trino faster through Cube; the object store did, and Cube Store answers in 16-34 ms.
OUTPUT:  HyperFrames, 1920 x 1080, 30 fps; a silent copy for muted autoplay.
TIME:    31 s x 30 fps = 930 frames. No music; effects only.
```

## LOOK (copied from `media/LOOK.md`)

- **Paper (ground):** `#F5F7F3`, flat, with a 1.5% fibre noise. Printed grid in `#BFD8D2`: minor lines 1 px every 24 px, major lines 2 px every 120 px. Never a gradient.
- **Graphite ink:** `#1E2A2F`, every word that must be read and every structural line (axes, frames, arrows).
- **Pen red (accent):** `#D9382B`, one focus per frame only: the number that matters, the trace that matters, the stamp.
- **Muted pens (other engines):** `#5E6B70` and `#8A979B`, for series that are not the focus.
- **Display:** League Gothic 400, numbers at 14-22% of the frame height, tracking +1%, `font-variant-numeric: tabular-nums`.
- **Labels and lines:** Oswald 500, 36-56 px at 1080p, tracking +2%, sentence case (no all-caps micro labels).
- **Logos:** the official marks in `media/shared/logos/` (never redrawn), sitting on the paper with `mix-blend-mode: multiply`, at least 120 px tall when they are the subject.
- **Depth:** none. No shadows, no glass. The paper is the only surface; things are printed or drawn on it.

Added for this film:

- **The instrument (fixed, never moves):** a left margin 0-240 px holding the pen key (four logos, 120 px tall, rows centred at y 330 / 510 / 690 / 870, a 4 px swatch line under each in that pen's current ink); a graphite 2 px rule at x 240; the pen rail, a graphite 4 px vertical line at x 1704 from y 96 to 984.
- **The chart on each sheet:** zero line graphite 3 px at y 840 from x 240 to 1704; the scale's top at y 240 (600 px of height); no numeric ticks (every number on screen is a label from `data.json`). Profile sections are 240 px wide, split by 2 px graphite dashed lines (12 on, 8 off), labelled under the zero line: "M" / "L" / "L2" in League Gothic 52 px, the profile from `data.json` in Oswald 36 px under it. On the query sheet, L2 is named by the stamped "object store at 2 CPU" above it instead.
- **Sheet title:** Oswald 500, 48 px, graphite, left edge x 288, cap line y 120.
- **Stamp sizes:** the hero number 220-238 px League Gothic (20-22% of the height); a secondary stamp 150-190 px; small labels on a trace Oswald 500 40-44 px.
- **Leader lines:** graphite 2 px, dotted (2 on, 8 off, round caps), from a stamp to its mark, horizontal at the mark's height.
- **Ink focus per sheet:** the focus pen's trace and its number are red together (one focus); everything already printed keeps its ink.

## OBJECTS

- **The recorder paper:** the paper above, carried on a drum to the right of the rail; fresh sheets enter from the right, drawn paper leaves to the left under the margin.
- **The four pens:** one per engine, each a capillary pen on a horizontal arm: a nib (an 18 x 14 px triangle in the pen's ink, tip on the paper), a body (70 x 18 px, 4 px radius, graphite 3 px outline on paper), an arm (graphite 3 px) to a pivot (7 px radius circle) on the rail. Tips sit at x 1560 when down; a lifted pen is drawn whole in `#8A979B` with its tip at x 1600. Rest and parking positions: the four key rows (y 330 / 510 / 690 / 870).
- **The logos:** DuckDB, Trino, Apache Spark, StarRocks in the margin key (that order, top to bottom); Cube stamped on the payoff sheet at 150 px. Copied to `assets/logos/`.
- **Traces:** step lines (5 px, round joins): a vertical rise from the zero line at the start of the first section, a flat run per section at the value's height, a vertical step at each section boundary. A failed run is a rising line that breaks into a 3-stroke pen skip and an "x" (two 4 px graphite strokes, 28 px).

## MOTION (copied from `media/LOOK.md`)

- **The drum:** the paper advances right to left, linear, 120 px/s when it moves; it never eases.
- **The pen:** traces draw on with `stroke-dashoffset`, ease `power2.inOut`, 18-36 frames per trace; the pen tip leads the line.
- **The stamp:** numbers and key words are stamped: scale 1.12 → 1 in 6 frames (`power3.out`), 2 px ink spread, no fade.
- **Typed lines:** CSV rows are typed character by character, 1 frame per character, with `key-press`.
- **Cuts:** the paper tears or advances to the next sheet; never a cross-fade.
- **One hero move per shot**; secondary moves start 4-6 frames later and travel 50-70% as far.

Added for this film:

- **Nothing is read on moving paper:** the drum stops before a stamp lands and stays still until the stamp has been read (0.5 s + 0.3 s a word).
- **Sheet change:** the drawn sheet tears off to the left in 8 frames (`power3.in`, travel 1500 px), the fresh sheet is already under the pens; `whoosh-short` on the tear.
- **Pens:** put down in 4 frames (`power3.out`, 10 px travel in x) with `click-soft`; lifted in 4 frames to x 1600.
- **The camera** never cuts and never moves: the paper moves under it.

## SOUND (copied from `media/LOOK.md`)

Effects only, from `media/shared/sfx/` (copied to `assets/sfx/`): `click-soft` pen down, `whoosh-short` the paper advancing or tearing, `pop` a stamp, `impact-bass-1` once on the Cube Store payoff. Volume 0.35; hits land one frame after their picture.

## SHOTS

Frame ranges at 30 fps; one continuous take.

| # | Frames | Hero move | The viewer reads (window) | Sound | Hand-off |
|---|---|---|---|---|---|
| 01 Hook | 0-77 | "3.97 billion" stamped over the paper, "3.97" in red | "3.97 billion weather rows" (0.4-2.4 s); the four logos in the key | `click-soft` x4 at 0.1 s, `pop` at 0.4 s | the drum starts at 2.4 s; DuckDB's pen goes down |
| 02 Load | 78-179 | DuckDB's red trace climbs as the drum runs 2.6-4.6 s | "DuckDB loads 2010-2025 into Iceberg" (2.7-4.6 s); "742 M rows in 146 s" (4.7-6.0 s) | `whoosh-short` drum, `pop` at 4.7 s | the sheet tears at 6.0 s |
| 03 Trino build | 180-329 | Trino's red step drops from M to L as the drum runs 6.25-10.25 s | "Build from scratch, 3.97 B rows" (6.3-8.0 s); M / L profiles (8.0-10.2 s); "9,351 s" (10.3-11.0 s), "12,639 s" on the M run | `whoosh-short` tear, `pop` at 10.3 s | the drum runs on into L2 |
| 04 Spark | 330-425 | Spark's L2 trace rises to 13,803 s while the drum runs 11.0-13.0 s | "failed" on Spark's M break (13.05-13.6 s); "13,803 s" (13.3-14.2 s) | `pop` at 13.05 s and 13.3 s | the sheet tears at 14.2 s |
| 05 Climb | 426-569 | Trino's red trace steps up from 32.4 to 65.3 s at L, the pen hesitates 0.4 s at the top | "Whole table through Cube, 3.97 B rows" (14.5-16.0 s); "65.3 s" (18.45-19.0 s) | `whoosh-short` tear, `pop` at 18.45 s | the drum stops; "object store at 2 CPU" is stamped |
| 06 Turn | 570-665 | Trino's red trace drops to 24.6 s in L2 | "object store at 2 CPU" (19.05-20.3 s); "24.6 s" (21.35-22.2 s) | `pop` at 19.05 s and 21.35 s | the sheet tears at 22.2 s |
| 07 Payoff | 666-779 | the Cube Store pen draws flat on the zero line | "Served from Cube Store" (22.5-24.0 s); "16-34 ms" (24.5-26.0 s) | `whoosh-short` tear, `pop` on the Cube logo at 24.0 s, `impact-bass-1` at 24.5 s | the sheet tears at 26.0 s |
| 08 Claim | 780-857 | the claim stamped in three groups, 0.3 s apart | "Same data. Same limits. Different stories." (26.3-28.6 s) | `whoosh-short` tear, `pop` x3 | the sheet tears at 28.6 s |
| 09 End | 858-929 | "Sleipnir" stamped in red | "Sleipnir" (28.9-31.0 s); "github.com/jhorlima/sleipnir" (29.2-31.0 s) | `whoosh-short` tear, `pop` at 28.9 s | holds to the end |

Every number on screen is a value from `media/shared/data.json`: `dataset.bronze_rows_local`, `scales.r2`, `load_duckdb.r2`, `build_from_scratch_local`, `q1_whole_table_through_cube_local`, `profiles`, `cube_store_ms`, `repo`.

## BANNED (copied from `media/LOOK.md`)

A dark or navy void; glow, bloom, neon, particles; purple/blue or mesh gradients; glass cards; a cream paper with a serif display and small mono caps labels; everything centred; everything fading and sliding up; text moving while it is read; corner brackets, HUD readouts; three cards in a row, KPI grids; a docked logo; cross-fades between shots; any number not in `media/shared/data.json`.

Added for this film: numeric axis ticks; a legend box or frame around the pen key; more than one red focus in a frame; a stamp or label clipped by the margin while it is read.

## QA

| Frame (s) | Must show |
|---|---|
| 2.0 | "3.97 billion" ≥ 20% of the height, "3.97" red; four logos in the key; four pens resting |
| 5.5 | DuckDB's red trace; "742 M rows in 146 s" with only "146 s" red |
| 10.7 | Trino's red step over M and L; "9,351 s" red with its leader; "12,639 s" grey on the M run |
| 13.8 | "failed" graphite on Spark's break; "13,803 s" on Spark's L2 run; the only red is Trino's |
| 18.6 | Trino's red trace at its peak; "65.3 s" graphite with its leader; StarRocks and DuckDB grey and named |
| 21.8 | "object store at 2 CPU" over L2; "24.6 s" red; StarRocks and DuckDB pens lifted |
| 25.4 | "16-34 ms" red ≥ 20% of the height; the red trace on the zero line; the Cube logo |
| 28.2 | the claim on three lines, "Different stories." red |
| 30.4 | "Sleipnir" red, the repo URL readable on a phone |

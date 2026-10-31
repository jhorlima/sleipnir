# Film A: The race

```text
GOAL:    the viewer reads a race at a glance and leaves knowing that more CPU did not make
         Trino faster through Cube; the object store did, and Cube Store answers in 16-34 ms.
OUTPUT:  HyperFrames, 1920 x 1080, 30 fps; a silent copy for muted autoplay.
TIME:    34 s x 30 fps = 1020 frames. No music; effects only.
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

- **The instrument (fixed, never moves):** a left margin plate 0-240 px (the same paper and grid, opaque, so torn sheets pass under it) holding the pen key (four logos, 120 px tall, rows centred at y 330 / 510 / 690 / 870, a 4 px swatch line under each in that pen's current ink); a graphite 2 px rule at x 240; the pen rail, a graphite 4 px vertical line at x 1704 from y 96 to 984.
- **The chart on each sheet:** zero line graphite 3 px at y 840 from x 240 to 1704; the scale's top at y 240 (600 px of height); no numeric ticks (every number on screen is a label from `data.json`). Profile sections are 240 px wide, split by 2 px graphite dashed lines (12 on, 8 off), labelled under the zero line: "M" / "L" / "L2" in League Gothic 52 px, the profile from `data.json` in Oswald 36 px under it. On the query sheet, L2 is named by the stamped "object store at 2 CPU" above it instead.
- **Sheet title:** Oswald 500, 48 px, graphite, left edge x 288, cap line y 120.
- **Stamp sizes:** the hero number 220-238 px League Gothic (20-22% of the height); a secondary stamp 150-190 px; small labels on a trace Oswald 500 40-44 px.
- **Leader lines:** graphite 2 px, dotted (2 on, 8 off, round caps), from a stamp to its mark, horizontal at the mark's height.
- **Ink focus:** one red focus per frame: the focus pen's trace and its number count as one. When the focus moves on a sheet, the previous focus is re-inked at the same instant (red to graphite for a stamp, red to `#5E6B70` for a trace): on the build sheet when "Spark failed" lands, on the query sheet when "24.6 s" lands.

## OBJECTS

- **The recorder paper:** the paper above, carried on a drum to the right of the rail; fresh sheets enter from the right, drawn paper leaves to the left under the margin.
- **The four pens:** one per engine (plus a Cube Store pen that exists only on the payoff sheet), each a capillary pen on a horizontal arm: a nib (an 18 x 14 px triangle in the pen's ink, tip on the paper), a body (70 x 18 px, 4 px radius, graphite 3 px outline on paper), an arm (graphite 3 px) to a pivot (7 px radius circle) on the rail. Tips sit at x 1560 when down; a lifted pen is drawn whole in `#8A979B`, nib hollow, tip at x 1566. Rest and parking positions: the four key rows (y 330 / 510 / 690 / 870).
- **The logos:** DuckDB, Trino, Apache Spark, StarRocks in the margin key (that order, top to bottom); Cube stamped on the payoff sheet at 150 px. Copied to `assets/logos/`.
- **Traces:** step lines (5 px, round joins): a vertical rise from the zero line at the start of the first section, a flat run per section at the value's height, a vertical step at each section boundary. A failed run is a rising line that breaks into a 3-stroke pen skip and an "x" (two 4 px strokes, 28 px). A step between sections is drawn while the drum turns, so it slants 24 px (6 frames).

## MOTION (copied from `media/LOOK.md`)

- **The drum:** the paper advances right to left, linear, 120 px/s when it moves; it never eases.
- **The pen:** traces draw on with `stroke-dashoffset`, ease `power2.inOut`, 18-36 frames per trace; the pen tip leads the line.
- **The stamp:** numbers and key words are stamped: scale 1.12 → 1 in 6 frames (`power3.out`), 2 px ink spread, no fade.
- **Typed lines:** CSV rows are typed character by character, 1 frame per character, with `key-press`.
- **Cuts:** the paper tears or advances to the next sheet; never a cross-fade.
- **One hero move per shot**; secondary moves start 4-6 frames later and travel 50-70% as far.

Added for this film:

- **Nothing is read on moving paper:** the drum stops before a stamp lands and stays still until the stamp has been read (0.5 s + 0.3 s a word).
- **Sheet change:** the drawn sheet tears off to the left in 8 frames (`power3.in`, travel 1980 px, a 14 px saw-tooth torn edge), the fresh sheet is already under the pens; `whoosh-short` on the tear.
- **Traces under a turning drum:** the trace is revealed by a fixed window that ends at the pen tip (x 1558), so the line appears exactly where the nib is while the paper moves; `stroke-dashoffset` is not needed there. The pen's y follows the trace linearly.
- **Pens:** put down or lifted in 4 frames (`power3.out`, 6 px travel in x, ink colours switch on the first frame) with `click-soft` on the pens that start a trace; a lifted pen moves to its next position on `power3.out` in 6 frames.
- **Stamps** are hidden until their frame, then appear at scale 1.12 and settle to 1 in 6 frames; nothing fades.
- **The camera** never cuts and never moves: the paper moves under it.

## SOUND (copied from `media/LOOK.md`)

Effects only, from `media/shared/sfx/` (copied to `assets/sfx/`): `click-soft` pen down, `whoosh-short` the paper advancing or tearing, `pop` a stamp, `impact-bass-1` once on the Cube Store payoff. Volume 0.35; hits land one frame after their picture.

## SHOTS

Times in seconds at 30 fps (frame = s x 30); one continuous take. Each sheet is one sub-composition (`compositions/sheet-*.html`); the key, the rail and the pens are `compositions/instrument.html`.

| # | Time (frames) | Hero move | The viewer reads (window) | Sound | Hand-off |
|---|---|---|---|---|---|
| 01 Hook | 0-2.4 (0-71) | "3.97 billion" stamped on frame 0, "3.97" red; pens already down | "3.97 billion weather rows" (0-2.4); the four logos in the key | `pop` at 0 | the sheet tears at 2.4 |
| 02 Load | 2.4-6.3 (72-188) | DuckDB's red pen climbs as the drum runs 2.7-4.7 | "DuckDB loads 2010-2025 into Iceberg" (2.7-4.7); "742 M rows in 146 s" (4.75-6.3) | `whoosh-short` tear, `click-soft` pen down, `pop` at 4.75 and 5.0 | the sheet tears at 6.3 |
| 03 Trino builds | 6.3-12.1 (189-362) | Trino's red step falls from M to L as the drum runs 6.6-10.6; Spark's grey line breaks off on M at 7.83 | "Build from scratch, 3.97 B rows" (6.6-8.6); M / L labels and "12,639 s" (10.65-11.0); "9,351 s" (11.0-12.1) | `whoosh-short` tear, `click-soft`, `pop` at 11.0 | the drum runs on at 12.1 |
| 04 Spark | 12.1-15.5 (363-464) | Spark's L2 line rises to 13,803 s while the drum runs 12.1-14.1; "Spark failed" lands red on its M break and Trino turns grey | "Spark failed" (14.15-15.5); "L2, object store at 2 CPU" and "13,803 s" (14.45-15.5) | `click-soft`, `pop` at 14.15 and 14.45 | the sheet tears at 15.5 |
| 05 Climb | 15.5-21.05 (465-631) | three pens draw M then L as the drum runs 15.8-19.8; Trino's red pen climbs to 65.3 s | "Whole table through Cube, 3.97 B rows" (15.8-17.8); names and "Trino 32.4 s" (19.85-20.05); "65.3 s" red (20.05-21.05) | `whoosh-short` tear, `click-soft`, `pop` at 20.05 | "object store at 2 CPU" is stamped |
| 06 Turn | 21.05-24.7 (632-740) | StarRocks and DuckDB lift; Trino's red pen drops to 24.6 s in L2 as the drum runs 21.5-23.5 | "object store at 2 CPU" (21.05-23.5); "24.6 s" red, "65.3 s" turns graphite (23.55-24.7) | `pop` at 21.05 and 23.55 | the sheet tears at 24.7 |
| 07 Payoff | 24.7-28.7 (741-860) | the Cube Store pen draws flat on the zero line as the drum runs 25.0-27.0 | "Served from Cube Store" (25.0-27.0); the Cube logo and "16-34 ms" (27.05-28.7) | `whoosh-short` tear, `click-soft`, `pop` on the logo at 27.05, `impact-bass-1` at 27.3 | the sheet tears at 28.7 |
| 08 Claim | 28.7-31.4 (861-941) | the claim stamped in three groups, 0.3 s apart | "Same data. Same limits. Different stories." (29.05-31.4) | `whoosh-short` tear, `pop` x3 | the sheet tears at 31.4 |
| 09 End | 31.4-34.0 (942-1019) | the pens go down; "Sleipnir" stamped in red | "Sleipnir" (31.95-34.0); "github.com/jhorlima/sleipnir" (32.2-34.0) | `whoosh-short` tear, `click-soft`, `pop` at 31.95 | holds to the end |

Every number on screen is a value from `media/shared/data.json`: `dataset.bronze_rows_local`, `dataset.years`, `scales.r2`, `load_duckdb.r2`, `build_from_scratch_local`, `q1_whole_table_through_cube_local`, `profiles`, `cube_store_ms`, `repo`. Trino's L2 build (9,125 s) is drawn without a label.

Mix (added for this film, to match the other films at about -16 LUFS): per-clip volume `pop` 0.32, `click-soft` 0.32, `whoosh-short` 0.24, `impact-bass-1` 0.5, so the single impact stays the loudest hit. Measured on the render: -15.9 LUFS integrated, true peak -5.6 dBTP at the impact.

Sound clips start so their peak lands one frame after the picture (pop 0.12 s, click-soft 0.073 s, whoosh-short 0.162 s, impact-bass-1 0.073 s into the file).

## BANNED (copied from `media/LOOK.md`)

A dark or navy void; glow, bloom, neon, particles; purple/blue or mesh gradients; glass cards; a cream paper with a serif display and small mono caps labels; everything centred; everything fading and sliding up; text moving while it is read; corner brackets, HUD readouts; three cards in a row, KPI grids; a docked logo; cross-fades between shots; any number not in `media/shared/data.json`.

Added for this film: numeric axis ticks; a legend box or frame around the pen key; more than one red focus in a frame; a stamp or label clipped by the margin while it is read.

## QA

| Time (s) | Must show |
|---|---|
| 0 | "3.97 billion" stamped, "3.97" red; four logos in the key; four pens down (the thumbnail) |
| 6.1 | DuckDB's red ramp; "742 M rows in 146 s" with only "146 s" red |
| 11.4 | Trino's red step over M and L; "9,351 s" red with its leader; "12,639 s" grey on the M run |
| 15.1 | "Spark failed" red beside Spark's red break; Trino's line and "9,351 s" graphite/grey; "13,803 s" on Spark's L2 run |
| 20.8 | "65.3 s" red with its leader to Trino's red L run; StarRocks and DuckDB grey and named |
| 24.3 | "object store at 2 CPU" over L2; "24.6 s" red; "65.3 s" graphite; StarRocks and DuckDB pens lifted |
| 28.3 | "16-34 ms" red at 22% of the height; the red trace on the zero line; the Cube logo |
| 31.1 | the claim on three lines, "Different stories." red |
| 33.7 | "Sleipnir" red, the repo URL readable on a phone |

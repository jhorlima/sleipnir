# Medium cards

GOAL:   six stills for the Medium post that each read as a finished poster with one point, no animation needed.
OUTPUT: HyperFrames, composed at 1920 x 1080 (so the sizes in `../LOOK.md` apply as written), one card held per second (0-6 s),
        snapshotted at 0.5, 1.5 ... 5.5 s and resized to 1400 x 788 PNG in `out/`.
DATA:   every number from `../shared/data.json`; no axis tick numbers, values are written on the marks.

## LOOK (from `../LOOK.md`)

- Paper `#F5F7F3` with 1.5% fibre noise; grid `#BFD8D2`, 1 px every 24 px, 2 px every 120 px.
- Graphite ink `#1E2A2F` for every word and structural line; muted pens `#5E6B70` (bars, secondary text) and `#8A979B` (secondary lines only, never text: contrast).
- Pen red `#D9382B`: one focus per card.
- League Gothic 400 for numbers (tabular figures, 2 px ink spread as a 1 px text stroke); Oswald 500/400 for titles, labels and lines.
- Sizes at 1920: title 56 px, subtitle 38 px, labels 34-44 px, source line 34 px. Nothing under 34 px, so nothing under 24 px at 1400.
- Logos from `../shared/logos/` copied to `assets/logos/`, `mix-blend-mode: multiply`, 120 px tall on the cover.
- Every card: title top-left, chart left-aligned on 120 px margins, source line bottom-left:
  "Sleipnir benchmark, single laptop; results/*.parquet".

## BANNED (from `../LOOK.md`)

A dark or navy void; glow, bloom, neon, particles; purple/blue or mesh gradients; glass cards; a cream paper with a serif display and small mono caps labels; everything centred; everything fading and sliding up; text moving while it is read; corner brackets, HUD readouts; three cards in a row, KPI grids; a docked logo; cross-fades between shots; any number not in `../shared/data.json`.
Added for the stills: legends (annotate on the mark), axis tick labels (numbers not in the data), shadows.

## Cards

1. `01-cover` — "3.97 billion weather rows". Red: "3.97". Four engine logos at the left margin with their pens resting on the paper; NOAA GHCN-Daily, 1763-2025; "Sleipnir" signature (Oswald 500, graphite) above the source line.
2. `02-object-store` — "More CPU made Trino slower, until the object store got 2 CPUs". Red: Trino's trace. Whole-table query through Cube at 3.97 B rows: Trino 32.4 / 65.3 / 24.6 s (M / L / L2), StarRocks 70.5 / 44.5 / 40.8 s, DuckDB 60.5 / 37.4 / 30.6 s.
3. `03-build` — "From scratch at 3.97 B rows, Spark failed on M". Red: the "failed" stamp. Trino 12,639 / 9,351 / 9,125 s (M / L / L2), Spark failed (M), 13,803 s (L2).
4. `04-layout` — "Sort first: half the size, and the yearly count in 0.51 s". Red: 0.51 s. Size 0.73 GB unsorted vs 0.38 GB sorted; yearly count 197.5 s (yearly partitions, unsorted) vs 0.51 s (sorted).
5. `05-cube-store` — "Cube Store answers in milliseconds, Trino through Cube in seconds". Red: 16-34 ms. Trino through Cube 3-4 s per question, on one shared axis.
6. `06-effort` — "~40 h · 8 days · 261 runs". Red: the night run trace, 22:50 to 10:37.

## QA

Each PNG: 1400 x 788, every number matches `../shared/data.json`, text at least 24 px, one red focus, nothing from BANNED.

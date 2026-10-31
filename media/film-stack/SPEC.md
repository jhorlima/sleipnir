# Film B: One row, four engines

```text
GOAL:    the viewer follows one real weather row from a CSV line to a 16-34 ms answer and
         leaves knowing what the stack is (DuckDB → Iceberg on RustFS → dbt → Trino, StarRocks,
         DuckDB, Spark → Cube), without ever seeing a diagram slide.
OUTPUT:  HyperFrames, 1920 x 1080, 30 fps. A silent copy is rendered as well.
TIME:    30.5 s x 30 fps = 915 frames. No music, so no beat grid; shots are cut on the paper.
```

## LOOK (from `media/LOOK.md`, unchanged)

- **Paper (ground):** `#F5F7F3`, flat, with a 1.5% fibre noise. Printed grid in `#BFD8D2`: minor lines 1 px every 24 px, major lines 2 px every 120 px. Never a gradient.
- **Graphite ink:** `#1E2A2F`, every word that must be read and every structural line (axes, frames, arrows).
- **Pen red (accent):** `#D9382B`, one focus per frame only: the number that matters, the trace that matters, the stamp.
- **Muted pens (other engines):** `#5E6B70` and `#8A979B`, for series that are not the focus.
- **Display:** League Gothic 400, numbers at 14-22% of the frame height, tracking +1%, `font-variant-numeric: tabular-nums`.
- **Labels and lines:** Oswald 500, 36-56 px at 1080p, tracking +2%, sentence case (no all-caps micro labels).
- **Logos:** the official marks in `media/shared/logos/` (never redrawn), sitting on the paper with `mix-blend-mode: multiply`, at least 120 px tall when they are the subject.
- **Depth:** none. No shadows, no glass. The paper is the only surface; things are printed or drawn on it.

### Added for this film

- **Layout grid:** 120 px margins (the major grid line), everything left-aligned to a major line; the hero of each shot spans at least 40% of the width or height.
- **Typed rows:** the CSV rows are typed in Oswald 500, 72-96 px, tabular figures, graphite; the field the shot is about may be underlined by a pen trace.
- **DuckDB mark:** the official mark is a dark disc with a yellow duck. The bundled SVG is the disc with the duck cut out, so it is shown inked graphite over a `#FFF000` disc behind the cut-out; the file is not edited.
- **Stage words:** `bronze`, `silver`, `gold` are League Gothic 160 px, graphite, the stage's one heading.
- **Accent per shot:** shot 1 `-3.6 °C`; 2 `18.9 °C`; 3 the pen trace from DuckDB into the file; 4 the strike through the duplicate; 5 `18.9` in the gold row; 6 the three `18.9` answers; 7 `16-34 ms`; 8 `Same answer.`; 9 the pen underline under `Sleipnir`.

## OBJECTS

- **The recorder paper:** the whole world. The grid above, printed on it. In shot 2 the drum runs under the pen at 120 px/s, linear, carrying a thin graphite time rule and the 1763 row out to the left while 2025 is stamped at the right.
- **The typed CSV rows:** `ITE00100554,17630101,TMAX,-36` and `USW00094728,20250601,TMAX,189`, exactly as in `media/shared/data.json`, typed one character per frame, graphite; the field the shot is about is underlined as soon as it is typed.
- **A Parquet file:** a sheet printed on the paper with a folded top-right corner (2 px graphite outline, 96 px fold), named `Parquet`, holding the row as four vertical column strips (`id`, `date`, `element`, `value`) so the row reads as columns, not as a line.
- **The struck duplicate:** the same bronze row printed twice, one under the other; a 6 px pen-red stroke strikes the older copy, labelled `duplicate`; the kept copy flows down into the silver row.
- **The gold fact row:** `fct_weather_daily` as one printed table row with a header rule: `station_id`, `date`, `tmax`, values `USW00094728`, `2025-06-01`, `18.9`.
- **The logos:** DuckDB, Apache Iceberg, RustFS, Lakekeeper, dbt, Trino, StarRocks, Apache Spark, Cube, from `assets/logos/` (copies of `media/shared/logos/`), 120 px tall or more, multiply blend, stamped onto the paper.

## MOTION (from `media/LOOK.md`, unchanged)

- **The drum:** the paper advances right to left, linear, 120 px/s when it moves; it never eases.
- **The pen:** traces draw on with `stroke-dashoffset`, ease `power2.inOut`, 18-36 frames per trace; the pen tip leads the line.
- **The stamp:** numbers and key words are stamped: scale 1.12 → 1 in 6 frames (`power3.out`), 2 px ink spread, no fade.
- **Typed lines:** CSV rows are typed character by character, 1 frame per character, with `key-press`.
- **Cuts:** the paper tears or advances to the next sheet; never a cross-fade.
- **One hero move per shot**; secondary moves start 4-6 frames later and travel 50-70% as far.

### Added for this film

- **Sheet advance (every seam):** in the last 0.4 s of a shot the whole sheet, grid included, advances one sheet (1920 px) to the left on `power3.in`; the next shot prints onto the clean sheet. `whoosh-short` peaks on the fastest frame, at volume 0.2 so the eight advances stay under the payoff.
- **Object to object:** each stage prints the row in its next form: the typed row as the Parquet columns; the two bronze rows; the silver row; the gold table row; the gold row traced out to each engine; the engines' traces converging on the Cube mark.
- **Logos** are stamped (the stamp above), 4 frames apart when several land in one shot.
- **Holds:** every line meant to be read holds 0.5 s + 0.3 s a word after it lands; the end card holds at least 2 s.

## SOUND (from `media/LOOK.md`, unchanged)

Effects only, no music, from `assets/sfx/` (copies of `media/shared/sfx/`, Pixabay Content License, bundled with HyperFrames): `typing` / `key-press` typed rows, `whoosh-short` the paper advancing, `pop` a stamp, `impact-bass-1` once on the payoff. Volume 0.35; hits land one frame after their picture. A silent copy is rendered for places that autoplay muted.

### Added for this film

- The sheet-advance whooshes play at 0.2, so the one `impact-bass-1` is the loudest moment of the film.
- Every effect runs through one `sfx` bus (`<hf-audio-group>`): +6.3 dB of gain, then a limiter at -2 dB. The rendered mix measures -16 LUFS integrated with a true peak of -1.8 dBTP.

## SHOTS

| # | Frames | Hero move | The viewer reads (window) | Sound | Hand-off |
|---|---|---|---|---|---|
| 1 | 0-89 (0.0-3.0 s) | the 1763 row is typed across the paper | `ITE00100554,17630101,TMAX,-36` (0.0-1.0 s); `Milan, 1 January 1763.` and `-3.6 °C` stamped (1.2-3.0 s) | `typing`, `pop` on `-3.6 °C` | the drum starts: the paper advances left |
| 2 | 90-194 (3.0-6.5 s) | the paper runs to 2025; the 2025 row is typed | `1763` leaves on the time rule, `2025` lands (3.0-3.8 s); `USW00094728,20250601,TMAX,189` (3.8-4.8 s); `New York, Central Park` and `18.9 °C` (4.9-6.5 s) | `whoosh-short`, `typing`, `pop` | the row splits into four columns |
| 3 | 195-314 (6.5-10.5 s) | the row becomes a Parquet file in bronze | `bronze` (6.6-7.4 s); DuckDB, Iceberg, RustFS, Lakekeeper stamped with their lines (7.4-10.5 s) | `pop` per logo, 4 frames apart | the `value` strip is reprinted as two rows |
| 4 | 315-419 (10.5-14.0 s) | the duplicate is struck through | dbt stamped, `silver` (10.6-10.9 s); two identical rows, the older struck, `duplicate` (10.85-11.8 s); the kept row as silver `18.9` (11.8-13.6 s) | `pop` on dbt, `click-soft` on the strike | the kept row reflows into the gold table |
| 5 | 420-524 (14.0-17.5 s) | the gold fact row is printed | `gold`, `fct_weather_daily` (14.1-15.0 s); `USW00094728 · 2025-06-01 · 18.9` (15.0-17.5 s) | `pop` on `18.9` | `18.9` sends three pen traces right |
| 6 | 525-644 (17.5-21.5 s) | three traces run from the gold row to three readers | `written by` Trino and Spark (17.6-18.6 s); `read by` Trino, StarRocks, DuckDB, each `18.9` (18.6-21.5 s) | `click-soft` pens down, `pop` per logo | the traces converge into the Cube query |
| 7 | 645-764 (21.5-25.5 s) | the answer is stamped | Cube stamped, `Central Park, June 2025?` typed (21.6-23.0 s); `16-34 ms` and `from Cube Store` (23.4-25.5 s) | `typing` under the question, `impact-bass-1` on `16-34 ms` | the paper advances to a clean sheet |
| 8 | 765-839 (25.5-28.0 s) | the claim is stamped line by line | `One row.` `Four engines.` `Same answer.` (25.6-28.0 s) | `pop` per line | the sheet advances |
| 9 | 840-914 (28.0-30.5 s) | `Sleipnir` is stamped, the pen underlines it | `Sleipnir`, `github.com/jhorlima/sleipnir` (28.1-30.5 s) | `pop`, then silence | end, held |

## BANNED

From `media/LOOK.md`, unchanged: a dark or navy void; glow, bloom, neon, particles; purple/blue or mesh gradients; glass cards; a cream paper with a serif display and small mono caps labels; everything centred; everything fading and sliding up; text moving while it is read; corner brackets, HUD readouts; three cards in a row, KPI grids; a docked logo; cross-fades between shots; any number not in `media/shared/data.json`.

Added for this film: a boxes-and-arrows architecture diagram of the whole stack at once; logos in circles or tiles; a number for the overlap window, batch ids, file names with digits or any gold column value other than `tmax` (none of them are in `data.json`); a monospace terminal look for the rows.

## QA

| Frame | Must show |
|---|---|
| 1 @ 2.6 s | the 1763 row readable on a phone, `-3.6 °C` in pen red as the only red |
| 2 @ 6.0 s | `2025` on the time rule, the 2025 row and `18.9 °C` in red; the 1763 row leaving at the left edge |
| 3 @ 10.0 s | the Parquet sheet with four column strips over 40% of the width; four logos at 120 px or more with their lines |
| 4 @ 13.6 s | two identical rows, the older one struck in red, the silver row under them |
| 5 @ 17.0 s | the gold table row with `18.9` in red |
| 6 @ 21.0 s | the gold row, Trino and Spark as writers, Trino, StarRocks and DuckDB as readers, each with `18.9` |
| 7 @ 25.0 s | the whole Cube mark inside the frame (traces may enter from the left edge), the question, `16-34 ms` in red at 14-22% of the frame height |
| 8 @ 27.6 s | the claim, `Same answer.` in red |
| 9 @ 30.2 s | `Sleipnir` and the repo URL, nothing else |

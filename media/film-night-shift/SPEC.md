# Film C: The night shift

```text
GOAL:    the viewer smiles at a laptop that fell asleep mid-benchmark and leaves trusting the numbers,
         because every incident of the real night is on screen, fixed, and the campaign goes on to the cloud.
OUTPUT:  HyperFrames, 1920 x 1080, 30 fps. README film (MP4 + a silent copy), stills for Medium.
TIME:    30 s x 30 fps = 900 frames. No music, effects only, so no beat grid.
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

Added for this film:

- **The log book:** every shot is one sheet. A graphite margin rule (3 px) at x = 560; the margin (x 192-522, right-aligned) holds the time stamp when `data.json` has one (22:50, 10:37), else the engine's logo and its name in muted pen `#5E6B70` (Oswald 44 px), then a one-line note in Oswald 52 px. Content starts at x = 640.
- **Time stamps:** League Gothic 220 px (20% of the frame height) in pen red; a past stamp is 110 px in `#5E6B70`.
- **Hatching:** every filled area (gauge band, memory box, disk bar, the spill) is 45° graphite hatching, 4-5 px lines every 14-16 px. No solid fills except the paper.
- **Strike-through:** a 7 px graphite pen line through an incident once it is fixed.
- **The hero** of each sheet fills at least 40% of the frame width or height (laptop 1040 px wide, dial 1060 px, list 1100 px).

## OBJECTS

- **The recorder paper as a log book:** the sheet above, margin rule, time stamps in the margin.
- **The laptop:** graphite line drawing, 6 px stroke, round joins, filled with paper so the grid does not show through. Open: rounded lid (780 x 500 in a 1000 x 640 box), inner screen, a wedge base with a notch. Asleep: lid shut to a thin slab, three graphite "z" in Oswald (64 / 92 / 128 px) rising to the right. On screen, a graphite pen trace: short at 22:50, run to the top right at 10:37.
- **Swap gauge:** a half dial (radius 480), 16 radial ticks, the band hatched to 98% (15.7 of 16), a graphite needle with a solid hub, reading "15.7 / 16 GB" under it with 15.7 in pen red.
- **Disk gauge:** a horizontal tank 1020 x 200 with 8 ticks on top, hatched to 100%, a spill line running over its right end.
- **Memory boxes (object store):** two hatched boxes, the 5 GB one taller, each overflowing at the top, each labelled on a paper tag, each stamped "OOM"; the second stamp is the red one.
- **Snapshot marks:** tally marks (four strokes and a slash) piled into a heap on a graphite base line; the heap grows as the marks pile up.
- **Logos:** Trino (`trino.svg`), Apache Spark (`spark.svg`), RustFS (`rustfs.png`, cropped to its wordmark, 120 px tall).

## MOTION (from `media/LOOK.md`, unchanged)

- **The drum:** the paper advances right to left, linear, 120 px/s when it moves; it never eases.
- **The pen:** traces draw on with `stroke-dashoffset`, ease `power2.inOut`, 18-36 frames per trace; the pen tip leads the line.
- **The stamp:** numbers and key words are stamped: scale 1.12 → 1 in 6 frames (`power3.out`), 2 px ink spread, no fade.
- **Typed lines:** CSV rows are typed character by character, 1 frame per character, with `key-press`.
- **Cuts:** the paper tears or advances to the next sheet; never a cross-fade.
- **One hero move per shot**; secondary moves start 4-6 frames later and travel 50-70% as far.

Added for this film:

- **Sheet turn:** the outgoing sheet slides off to the left in 12 frames (`power3.in`) while the next one advances in from the right in 14 frames (`expo.out`), with `whoosh-short`. Used for every cut except the sleep (a hard cut on the glitch) and the end (the claim sheet advances at drum speed).
- **The laptop falls asleep:** the lid closes in 10 frames (`power3.in`), lands with a 2-frame squash; the z's appear one by one, 4 frames apart, no float loop.
- **Gauges:** the hatched band and needle sweep in 24 frames (`power2.inOut`), the needle overshoots 2° and settles (damping 0.7).
- **The heap:** tally marks pile up row by row, 2 frames a row, bottom first; "4.4 M" is stamped when the heap peaks.
- **Strike-throughs:** the pen line draws left to right in 8 frames per row, rows 18 frames apart, each "fixed" stamped 3 frames after its line ends.
- **Holds:** a landed word or number holds dead still until its sheet leaves.

## SOUND (from `media/LOOK.md`)

Effects only, from `assets/sfx/` (copied from `media/shared/sfx/`): `click-soft` the pen down, `glitch-3` the laptop falls asleep, `error` on each failure, `pop` on each fix stamp, `whoosh-short` on sheet turns, `impact-bass-1` once on the claim. Volume 0.35; hits land one frame after their picture. A silent copy is rendered too.

## SHOTS

| # | Frames | Hero move | The viewer reads (window) | Sound | Hand-off |
|---|---|---|---|---|---|
| 01 start | 0-89 | "22:50" stamped in the margin; the pen starts its trace on the laptop screen | "22:50" (0.2-1.2 s); "The night run starts" (1.2-3.0 s) | `pop` on the stamp; `click-soft` as the pen touches the screen | the sheet holds; hard cut on the glitch |
| 02 sleep | 90-179 | the lid shuts; "ABANDONED_TASK" stamped across the sheet | Trino logo + "The laptop falls asleep" (3.0-4.2 s); "ABANDONED_TASK" (4.2-5.0 s); "macOS idle sleep froze the Docker VM" (5.0-6.0 s) | `glitch-3` on the lid; `error` on the stamp | sheet turn |
| 03 swap | 180-269 | the dial band and needle sweep to 15.7 | "macOS swap fills up" (6.2-7.0 s); "15.7 / 16 GB swap in use" (7.2-9.0 s) | `whoosh-short` in; `error` when the needle hits the stop | sheet turn |
| 04 heap | 270-359 | tally marks pile into a heap | Spark logo + "Spark's heap piles up" (9.2-10.2 s); "4.4 M" (10.4-11.2 s); "Iceberg snapshot objects in the Spark heap" (11.0-12.0 s) | `whoosh-short` in; `error` on "4.4 M" | sheet turn |
| 05 oom | 360-449 | the 3 GB box overflows and is stamped, then the 5 GB box does the same | RustFS + "The object store runs out of memory" (12.2-13.0 s); "3 GB OOM" (13.0-13.8 s); "5 GB OOM" (13.8-15.0 s) | `error` on each OOM stamp | sheet turn |
| 06 disk | 450-539 | the disk bar hatches to full and spills over its end | Spark logo + "The Docker disk fills up" (15.2-16.0 s); "103 GB full" (16.2-17.0 s); "Spark MERGE spilled ~33 GB" (17.0-18.0 s) | `error` on the spill | sheet turn |
| 07 fixed | 540-659 | each incident struck through, then stamped "fixed" | the five incident lines, one per 0.6 s (18.2-21.2 s); the last red "fixed" (21.2-22.0 s) | `pop` on each "fixed" stamp | sheet turn |
| 08 morning | 660-734 | "10:37" stamped under the grey 22:50; the screen trace finishes | "10:37" (22.2-23.2 s); "The run finishes" (23.2-24.5 s) | `pop` on the stamp | sheet turn |
| 09 claim | 735-839 | "~40 h, 8 days, 261 runs." stamped line by line, then "the cloud." in red | the three lines (24.7-26.2 s); "Next stop: the cloud." (26.2-28.0 s) | `pop` per line; `impact-bass-1` on "the cloud." | the paper advances at drum speed |
| 10 end | 840-899 | "Sleipnir" stamped | "Sleipnir" (28.1-29.0 s); repo URL (29.0-30.0 s, held to the last frame) | none after the impact | end |

## BANNED (from `media/LOOK.md`, unchanged)

A dark or navy void; glow, bloom, neon, particles; purple/blue or mesh gradients; glass cards; a cream paper with a serif display and small mono caps labels; everything centred; everything fading and sliding up; text moving while it is read; corner brackets, HUD readouts; three cards in a row, KPI grids; a docked logo; cross-fades between shots; any number not in `media/shared/data.json`.

Added for this film: a time stamp that `data.json` does not hold (incident sheets carry no clock time); a fix described in words that `data.json` does not hold (fixes are shown only as strike-throughs and stamps); emoji or a photo of a laptop; a floating or breathing "z" loop; more than one red element per sheet.

## QA

- 2.4 s: "22:50" red in the margin, laptop open filling more than half the width.
- 5.4 s: lid shut, three z's, red "ABANDONED_TASK" fully inside the frame, Trino logo and name in the margin.
- 8.4 s: needle at the stop, "15.7" red, "/ 16 GB" graphite.
- 11.4 s: heap complete above its base line, "4.4 M" red, Spark logo and name.
- 14.4 s: RustFS wordmark, two stamped boxes, only the second "OOM" red.
- 17.4 s: "103 GB full" red, bar full with its spill.
- 21.4 s: five struck lines, five stamps, only the last red.
- 24.1 s: "22:50" grey over "10:37" red, trace finished on the screen.
- 27.6 s: "~40 h, 8 days, 261 runs." and "Next stop: the cloud." with "the cloud." red.
- 29.5 s: "Sleipnir" red, repo URL readable.
- Every still: readable at phone width, hero at least 40% of the frame, nothing from BANNED, every number traceable to `media/shared/data.json`.

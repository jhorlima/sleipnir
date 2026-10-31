# Film C: The night shift

```text
GOAL:    the viewer smiles at a laptop that fell asleep mid-benchmark and leaves trusting the numbers,
         because the real incidents of several night runs are on screen, with what was fixed, what was
         worked around and what was not, and the campaign goes on to the cloud.
OUTPUT:  HyperFrames, 1920 x 1080, 30 fps. README film (MP4 + a silent copy), stills for Medium.
TIME:    32.9 s x 30 fps = 987 frames. No music, effects only, so no beat grid.
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
- **Strike-through:** a 7 px graphite pen line through an incident once it is fixed; an incident that was worked around or not fixed keeps its line unstruck.
- **The honest frame:** 22:50 and 10:37 bound the log, but the incidents come from several nights (the laptop sleep from an earlier campaign); the first sheet says "Several nights, one log".
- **The hero** of each sheet fills at least 40% of the frame width or height (laptop 1040 px wide, dial 1060 px, list 1100 px).

## OBJECTS

- **The recorder paper as a log book:** the sheet above, margin rule, time stamps in the margin.
- **The laptop:** graphite line drawing, 6 px stroke, round joins, no fill (the grid shows through, as on a drawing). Open: rounded lid (780 x 500 in a 1000 x 640 box), inner screen, a wedge base with a notch. Asleep: lid shut to a thin slab, three graphite "z" in Oswald (64 / 92 / 128 px) rising to the right. On screen, a graphite pen trace: short at 22:50, run to the top right at 10:37.
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

- **Sheet advance:** the outgoing sheet and the next one move together as one strip of paper, 1920 px to the left in 15 frames (`power2.inOut` on both, so their edges stay butted), with `whoosh-short` peaking on the fastest frame. Consecutive scenes overlap by these 15 frames. Every cut except the sleep, which is a hard cut on the glitch.
- **Writing:** every Oswald line is written by the pen, revealed left to right with `clip-path: inset()` at constant speed (`none`), 0.2-0.7 s per line. No fades.
- **The laptop falls asleep:** the lid closes in 10 frames (`power3.in`), lands with a 2-frame squash; the z's appear one by one, 4 frames apart, no float loop.
- **Gauges:** the hatched band and needle sweep in 24 frames (`power2.inOut`), the needle overshoots 2° and settles (damping 0.7).
- **The heap:** tally marks pile up row by row in 6 steps over 24 frames, bottom first; "4.4 M" is stamped when the heap peaks.
- **Memory boxes and disk bar:** the hatching rises (boxes) or runs right (bar) on `power2.in`, faster as it fills; the box is stamped the moment it spills; the disk spill line draws on in 9 frames.
- **Strike-throughs:** the pen line draws left to right in 8 frames per row, rows 15 frames apart, each label stamped 11 frames after its row starts (rotated -5°).
- **Holds:** a landed word or number holds dead still until its sheet leaves.

## SOUND (from `media/LOOK.md`)

Effects only, from `assets/sfx/` (copied from `media/shared/sfx/`): `click-soft` the pen down, `glitch-3` the laptop falls asleep, `error` on each failure, `pop` on 22:50, each log label, 10:37 and each claim line, `whoosh-short` on sheet advances, `impact-bass-1` once on the claim. Hits peak one frame after their picture (start = picture + 1 frame − the file's measured peak). Mix target shared by the three films: about −16 LUFS integrated, true peak ≤ −1 dBTP, the claim's impact the loudest hit. Volumes: `pop`, `click-soft` and `glitch-3` 0.7; `impact-bass-1` 0.75; `whoosh-short` 0.4, and 0.2 on the last advance, where it lands on the impact's tail; `error` 3.98, because the file peaks at −21 dBTP against −0.4 to −5 dBTP for the others. Trims: `glitch-3` plays 0.2-1.2 s of its file; `error` plays 0.5-0.95 s. A silent copy is the same render with the audio stream dropped.

## SHOTS

Times are film seconds; consecutive scenes overlap by 0.5 s (the sheet advance).

| # | Frames | Hero move | The viewer reads (window) | Sound | Hand-off |
|---|---|---|---|---|---|
| 01 start | 0-89 | "22:50" stamped on frame 0; the pen draws the laptop, then starts a trace on its screen | "22:50" (0.0-3.0 s); "The run starts" (0.7-3.0 s); "Several nights, one log" (1.3-3.0 s) | `pop` on the stamp; `click-soft` as the pen touches the screen | hard cut on the glitch |
| 02 sleep | 90-206 | the lid shuts on its hinge; "ABANDONED_TASK" stamped across the sheet | Trino + "The laptop falls asleep" (3.1-4.2 s); "ABANDONED_TASK" (4.2-6.4 s); "macOS idle sleep froze the Docker VM" (4.4-6.4 s) | `glitch-3` on the cut; `error` on the stamp | sheet advance |
| 03 swap | 192-296 | the dial band and needle sweep to 15.7 and settle | "macOS swap fills up" (6.95-9.4 s); "15.7 / 16 GB swap in use" (7.85-9.4 s) | `whoosh-short`; `error` when the needle hits the stop | sheet advance |
| 04 heap | 282-401 | tally marks pile into a heap | Spark + "Spark's heap piles up" (9.95-12.9 s); "4.4 M" (10.85-12.9 s); "Iceberg snapshot objects in the Spark heap" (10.9-12.9 s) | `whoosh-short`; `error` on "4.4 M" | sheet advance |
| 05 oom | 387-491 | the 3 GB box fills, spills and is stamped OOM; then the 5 GB box | RustFS + "The object store runs out of memory" (13.45-15.9 s); "3 GB OOM" (14.2 s); "5 GB OOM" (15.1-15.9 s) | `whoosh-short`; `error` on each OOM | sheet advance |
| 06 disk | 477-596 | the disk bar hatches to full and spills over its end | Spark + "The Docker disk fills up" (16.45-19.4 s); "103 GB full" (17.7-19.4 s); "Spark MERGE spilled ~33 GB" (17.85-19.4 s) | `whoosh-short`; `error` on the stamp | sheet advance |
| 07 log | 582-716 | each row gets its verdict: struck and "fixed", or "run at night", or the red "next: the cloud" | the five rows, one every 0.5 s (20.1-22.5 s); "next: the cloud" (22.47-23.4 s) | `whoosh-short`; `pop` on each label | sheet advance |
| 08 morning | 702-799 | the screen trace runs to the top; "10:37" stamped under the grey 22:50 | "10:37" (24.9-26.15 s); "The run finishes" (25.05-26.15 s) | `whoosh-short`; `pop` on the stamp | sheet advance |
| 09 claim | 784-904 | "~40 h, 8 days, 261 runs." stamped line by line, then "the cloud." in red | the three lines (26.85-29.65 s); "Next stop: the cloud." (28.05-29.65 s) | `whoosh-short`; `pop` per line; `impact-bass-1` on "the cloud." | sheet advance |
| 10 end | 889-986 | "Sleipnir" stamped | "Sleipnir" (30.25-32.9 s); repo URL (30.5-32.9 s, held to the last frame) | `whoosh-short`; the impact's tail | end |

## BANNED (from `media/LOOK.md`, unchanged)

A dark or navy void; glow, bloom, neon, particles; purple/blue or mesh gradients; glass cards; a cream paper with a serif display and small mono caps labels; everything centred; everything fading and sliding up; text moving while it is read; corner brackets, HUD readouts; three cards in a row, KPI grids; a docked logo; cross-fades between shots; any number not in `media/shared/data.json`.

Added for this film: a time stamp that `data.json` does not hold (incident sheets carry no clock time); any frame claiming every incident happened on the 22:50 → 10:37 night; calling an incident fixed when it was worked around (swap: "run at night") or not fixed (disk: "next: the cloud"); emoji or a photo of a laptop; a floating or breathing "z" loop; more than one red element per sheet.

## QA

- 2.9 s: "22:50" red in the margin, laptop open filling more than half the width, "Several nights, one log" written.
- 4.5 s: lid shut, three z's, red "ABANDONED_TASK" fully inside the frame, Trino logo and name in the margin.
- 9.0 s: needle at the stop, "15.7" red, "/ 16 GB" graphite.
- 12.5 s: heap complete above its base line, "4.4 M" red, Spark logo and name.
- 15.8 s: RustFS wordmark, two stamped boxes, only the second "OOM" red.
- 19.0 s: "103 GB full" red, bar full with its spill.
- 23.0 s: three struck rows stamped "fixed", "Swap" unstruck with "run at night", "Docker disk full" unstruck with the red "next: the cloud".
- 25.8 s: "22:50" grey over "10:37" red, trace finished on the screen.
- 29.0 s: "~40 h, 8 days, 261 runs." and "Next stop: the cloud." with "the cloud." red.
- 32.8 s: "Sleipnir" red, repo URL readable.
- Every frame: readable at phone width, hero at least 40% of the frame, nothing from BANNED, every number traceable to `media/shared/data.json`.

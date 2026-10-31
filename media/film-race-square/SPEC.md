# Film A, LinkedIn square cut

```text
GOAL:    in a muted feed, the viewer sees the turn: Trino through Cube goes from 65.3 s to 24.6 s
         when the object store gets 2 CPU, and Cube Store answers in 16-34 ms.
OUTPUT:  HyperFrames, 1080 x 1080, 30 fps, silent (no audio elements).
TIME:    14.9 s x 30 fps = 447 frames.
```

LOOK, MOTION, OBJECTS and BANNED are those of `../film-race/SPEC.md` (itself a copy of `media/LOOK.md` plus additions). Only these numbers change for the square canvas:

- Margin plate 0-150 px, logos 84 px, key rows at y 380 / 520 / 660 / 800; rail at x 980; pen tips at x 860.
- Zero line at y 790, scale top at y 330; profile sections 200 px wide (1.67 s of drum at 120 px/s).
- Sheet titles Oswald 40 px at x 186; hero stamps 160-200 px (15-19% of the height); "Sleipnir" 300 px.
- Only Trino is drawn on the query sheet, so the hero numbers sit above the chart instead of on leaders.

## SHOTS

| # | Time (s) | Hero move | The viewer reads |
|---|---|---|---|
| 01 Hook | 0-1.9 | "3.97 billion" stamped on frame 0, "3.97" red | "3.97 billion weather rows" |
| 02 Turn | 1.9-9.6 | Trino's red pen draws M then L (2.2-5.53), climbing to 65.3 s; then L2 (6.93-8.6), dropping to 24.6 s | "Trino through Cube, 3.97 B rows"; "65.3 s" red (5.78); "object store at 2 CPU" (6.58); "24.6 s" red, "65.3 s" graphite (8.65) |
| 03 Payoff | 9.6-12.4 | the Cube Store pen draws flat on the zero line (9.9-10.9) | "Served from Cube Store"; the Cube logo (10.95); "16-34 ms" red (11.15) |
| 04 End | 12.4-14.9 | the pens go down; "Sleipnir" stamped in red | "Sleipnir" (12.85); "github.com/jhorlima/sleipnir" (13.1) |

Sheet changes are tears (8 frames). Every number comes from `media/shared/data.json`.

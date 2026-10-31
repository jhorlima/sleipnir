---
format: 1920x1080
duration: 34s
message: "More CPU did not make Trino faster through Cube; the object store did, and Cube Store answers in 16-34 ms."
arc: Hook → Load → Build → Turn → Payoff → Claim → End
audience: data engineers reading the Sleipnir README
---

## Frame 1: Hook (0-2.4s)

- act: Act 1: The hook
- status: animated
- duration: 2.4s
- poster: 2.0
- transition_in: cut
- src: compositions/sheet-hook.html
- scene: Four pens down beside the engine key; "3.97 billion weather rows" stamped huge, "3.97" in red
- reads: "3.97 billion" on frame 0 (0-1.0s); "weather rows" and the source line (1.0-2.4s); the four logos in the key (0-2.4s)
- sound: pop on the first frame

The thumbnail. The key in the margin names the four engines before any number about them appears.

## Frame 2: Load (2.4-6.3s)

- act: Act 2: The race
- status: animated
- duration: 3.9s
- poster: 6.1
- transition_in: sheet tear
- src: compositions/sheet-load.html
- scene: DuckDB's red pen climbs while the drum turns; "742 M rows in 146 s" stamped, "146 s" in red
- reads: "DuckDB loads 2010-2025 into Iceberg" (2.7-4.7s); "742 M rows in 146 s" (4.75-6.3s)
- sound: whoosh-short on the tear; click-soft as DuckDB's pen goes down; pop at 4.75s and 5.0s

## Frame 3: Trino builds (6.3-12.1s)

- act: Act 2: The race
- status: animated
- duration: 5.8s
- poster: 11.4
- transition_in: sheet tear
- src: compositions/sheet-build.html
- scene: Trino's red step falls from 12,639 s on M to 9,351 s on L; Spark's grey line breaks off on M
- reads: "Build from scratch, 3.97 B rows" (6.6-8.6s); M / L labels and "12,639 s" (10.65-11.0s); "9,351 s" (11.0-12.1s)
- sound: whoosh-short on the tear; click-soft as the pens go down; pop on "9,351 s" (11.0s)

Sets up the expectation: more CPU, faster build.

## Frame 4: Spark fails, then finishes (12.1-15.5s)

- act: Act 2: The race
- status: animated
- duration: 3.4s
- poster: 15.1
- transition_in: the drum runs on
- src: compositions/sheet-build.html
- scene: Spark's L2 line reaches 13,803 s; "Spark failed" lands in red beside its break on M, and Trino's line and "9,351 s" turn graphite
- reads: "Spark failed" (14.15-15.5s); "L2, object store at 2 CPU" and "13,803 s" (14.45-15.5s)
- sound: click-soft as Spark's pen goes down; pop on "Spark failed" (14.15s) and on "13,803 s" (14.45s)

## Frame 5: More CPU, slower (15.5-21.05s)

- act: Act 3: The turn
- status: animated
- duration: 5.55s
- poster: 20.8
- transition_in: sheet tear
- src: compositions/sheet-query.html
- scene: Through Cube, StarRocks and DuckDB get faster on L; Trino's red pen climbs from 32.4 s to "65.3 s", stamped in red
- reads: "Whole table through Cube, 3.97 B rows" (15.8-17.8s); the three pens step at L (17.8-19.8s); names and "Trino 32.4 s" (19.85-20.05s); "65.3 s" (20.05-21.05s)
- sound: whoosh-short on the tear; click-soft as the pens go down; pop on "65.3 s" (20.05s)

The expectation from frame 3 breaks.

## Frame 6: The object store (21.05-24.7s)

- act: Act 3: The turn
- status: animated
- duration: 3.65s
- poster: 24.3
- transition_in: the drum runs on
- src: compositions/sheet-query.html
- scene: "object store at 2 CPU" stamped over L2; Trino's red line drops to "24.6 s" in red, and "65.3 s" turns graphite
- reads: "object store at 2 CPU" (21.05-23.5s); "24.6 s" (23.55-24.7s)
- sound: pop on the label (21.05s) and on "24.6 s" (23.55s)

## Frame 7: Cube Store (24.7-28.7s)

- act: Act 4: Payoff and end
- status: animated
- duration: 4.0s
- poster: 28.3
- transition_in: sheet tear
- src: compositions/sheet-cube.html
- scene: A red line runs flat on the zero line; the Cube logo and "16-34 ms" stamped
- reads: "Served from Cube Store" (25.0-27.0s); "16-34 ms" (27.3-28.7s)
- sound: whoosh-short on the tear; click-soft as the Cube Store pen goes down; pop on the Cube logo (27.05s); impact-bass-1 on "16-34 ms" (27.3s)

The payoff, and the film's only bass hit.

## Frame 8: Claim (28.7-31.4s)

- act: Act 4: Payoff and end
- status: animated
- duration: 2.7s
- poster: 31.1
- transition_in: sheet tear
- src: compositions/sheet-claim.html
- scene: Pens lifted; "Same data. Same limits. Different stories." stamped in three beats, the last in red
- reads: "Same data. Same limits. Different stories." stamped in three beats 0.3 s apart, read as one line (29.05-31.4s)
- sound: whoosh-short on the tear; pop x3

## Frame 9: End (31.4-34.0s)

- act: Act 4: Payoff and end
- status: animated
- duration: 2.6s
- poster: 33.7
- transition_in: sheet tear
- src: compositions/sheet-end.html
- scene: Pens back down; "Sleipnir" stamped in red over the repo URL
- reads: "Sleipnir" (31.95-34.0s); "github.com/jhorlima/sleipnir" (32.2-34.0s)
- sound: whoosh-short on the tear; click-soft as the pens go down; pop on "Sleipnir" (31.95s)

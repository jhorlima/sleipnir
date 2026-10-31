---
format: 1920x1080
duration: 31s
message: "More CPU did not make Trino faster through Cube; the object store did, and Cube Store answers in 16-34 ms."
arc: Hook → Load → Build → Turn → Payoff → Claim → End
audience: data engineers reading the Sleipnir README
---

## Frame 1: Hook (0-2.6s)

- act: Act 1: The hook
- status: built
- duration: 2.6s
- poster: 2.0
- transition_in: cut
- scene: Four pens rest beside the engine key; "3.97 billion weather rows" stamped huge, "3.97" in red
- reads: "3.97 billion" lands (0.4-1.4s); "weather rows" and the source line (1.4-2.4s); the four logos in the key (0.4-2.6s)
- sound: click-soft x4 as the pens go down (0.1s); pop on the stamp (0.4s)

The thumbnail. The key in the margin names the four engines before any number about them appears.

## Frame 2: Load (2.6-6.0s)

- act: Act 2: The race
- status: built
- duration: 3.4s
- poster: 5.5
- transition_in: the drum starts turning
- scene: DuckDB's red pen climbs while the drum turns; "742 M rows in 146 s" stamped, "146 s" in red
- reads: "DuckDB loads 2010-2025 into Iceberg" (2.7-4.6s); "742 M rows in 146 s" (4.7-6.0s)
- sound: whoosh-short as the drum runs; pop on the stamp (4.7s)

## Frame 3: Trino builds (6.0-11.0s)

- act: Act 2: The race
- status: built
- duration: 5.0s
- poster: 10.7
- transition_in: sheet tear
- scene: Trino's red step falls from 12,639 s on M to 9,351 s on L; Spark's grey line breaks off on M
- reads: "Build from scratch, 3.97 B rows" (6.3-8.0s); M and L profiles (8.0-10.2s); "9,351 s" (10.3-11.0s)
- sound: whoosh-short on the tear; pop on "9,351 s" (10.3s)

Sets up the expectation: more CPU, faster build.

## Frame 4: Spark fails, then finishes (11.0-14.2s)

- act: Act 2: The race
- status: built
- duration: 3.2s
- poster: 13.8
- transition_in: the drum runs on
- scene: The drum runs into L2; "failed" stamped on Spark's break, Spark's L2 line reaches 13,803 s
- reads: "failed" (13.05-13.6s); "13,803 s" (13.3-14.2s)
- sound: pop on "failed" (13.05s) and on "13,803 s" (13.3s)

## Frame 5: More CPU, slower (14.2-19.0s)

- act: Act 3: The turn
- status: built
- duration: 4.8s
- poster: 18.6
- transition_in: sheet tear
- scene: Through Cube, StarRocks and DuckDB get faster on L; Trino's red pen climbs from 32.4 s to 65.3 s and hesitates
- reads: "Whole table through Cube, 3.97 B rows" (14.5-16.0s); the three pens step at L (16.0-18.4s); "65.3 s" (18.45-19.0s)
- sound: whoosh-short on the tear; pop on "65.3 s" (18.45s)

The expectation from frame 3 breaks.

## Frame 6: The object store (19.0-22.2s)

- act: Act 3: The turn
- status: built
- duration: 3.2s
- poster: 21.8
- transition_in: the drum runs on
- scene: "object store at 2 CPU" stamped over L2; Trino's red line drops to 24.6 s
- reads: "object store at 2 CPU" (19.05-20.3s); "24.6 s" (21.35-22.2s)
- sound: pop on the label (19.05s) and on "24.6 s" (21.35s)

## Frame 7: Cube Store (22.2-26.0s)

- act: Act 4: Payoff and end
- status: built
- duration: 3.8s
- poster: 25.4
- transition_in: sheet tear
- scene: A red line runs flat on the zero line; the Cube logo and "16-34 ms" stamped
- reads: "Served from Cube Store" (22.5-24.0s); "16-34 ms" (24.5-26.0s)
- sound: whoosh-short on the tear; pop on the Cube logo (24.0s); impact-bass-1 on "16-34 ms" (24.5s)

The payoff, and the film's only bass hit.

## Frame 8: Claim (26.0-28.6s)

- act: Act 4: Payoff and end
- status: built
- duration: 2.6s
- poster: 28.2
- transition_in: sheet tear
- scene: Pens lifted; "Same data. Same limits. Different stories." stamped in three beats, the last in red
- reads: "Same data. Same limits. Different stories." stamped in three beats 0.3 s apart, read as one line (26.3-28.6s)
- sound: whoosh-short on the tear; pop x3

## Frame 9: End (28.6-31.0s)

- act: Act 4: Payoff and end
- status: built
- duration: 2.4s
- poster: 30.4
- transition_in: sheet tear
- scene: Pens back down; "Sleipnir" stamped in red over the repo URL
- reads: "Sleipnir" (28.9-31.0s); "github.com/jhorlima/sleipnir" (29.2-31.0s)
- sound: whoosh-short on the tear; pop on "Sleipnir" (28.9s)

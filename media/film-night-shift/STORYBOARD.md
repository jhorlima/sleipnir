---
format: 1920x1080
duration: 30s
message: "One real night of benchmarking on a laptop: everything that broke, fixed, and next stop the cloud."
arc: Hook (22:50) → Incidents (sleep, swap, heap, OOM, disk) → Fixed → Morning (10:37) → Claim → End
audience: data engineers reading the Sleipnir README
---

## Frame 1: 22:50 (0-3s)

- act: Act 1: The run starts
- scene: "22:50" stamped in the margin; a line-drawn laptop, lid open, the pen starts its trace on the screen
- duration: 3s
- poster: 2.4
- transition_in: cut
- status: built
- src: compositions/start.html
- reads: "22:50" (0.2-1.2s); "The night run starts" (1.2-3.0s)
- sound: pop on the stamp; click-soft as the pen touches the screen

The log book opens. The time is the hook: someone started a benchmark at ten to eleven at night.

## Frame 2: The laptop falls asleep (3-6s)

- act: Act 2: The night goes wrong
- scene: the lid shuts, three z's, Trino's "ABANDONED_TASK" stamped in red
- duration: 3s
- poster: 5.4
- transition_in: cut
- status: built
- src: compositions/sleep.html
- reads: Trino + "The laptop falls asleep" (3.0-4.2s); "ABANDONED_TASK" (4.2-5.0s); "macOS idle sleep froze the Docker VM" (5.0-6.0s)
- sound: glitch-3 on the lid; error on the stamp

The joke of the film: the laptop went to sleep and took Trino's workers with it.

## Frame 3: Swap (6-9s)

- act: Act 2: The night goes wrong
- scene: a hatched half dial sweeps to its stop; "15.7 / 16 GB" with 15.7 in red
- duration: 3s
- poster: 8.4
- transition_in: sheet turn
- status: built
- src: compositions/swap.html
- reads: "macOS swap fills up" (6.2-7.0s); "15.7 / 16 GB swap in use" (7.2-9.0s)
- sound: whoosh-short on the sheet turn; error when the needle hits the stop

## Frame 4: Spark's heap (9-12s)

- act: Act 2: The night goes wrong
- scene: snapshot tally marks pile into a heap; "4.4 M" stamped red
- duration: 3s
- poster: 11.4
- transition_in: sheet turn
- status: built
- src: compositions/heap.html
- reads: Spark + "Spark's heap piles up" (9.2-10.2s); "4.4 M" (10.4-11.2s); "Iceberg snapshot objects in the Spark heap" (11.0-12.0s)
- sound: whoosh-short on the sheet turn; error on "4.4 M"

## Frame 5: Object store OOM (12-15s)

- act: Act 2: The night goes wrong
- scene: RustFS wordmark; a 3 GB box overflows and is stamped OOM, a taller 5 GB box overflows and is stamped OOM in red
- duration: 3s
- poster: 14.4
- transition_in: sheet turn
- status: built
- src: compositions/oom.html
- reads: RustFS + "The object store runs out of memory" (12.2-13.0s); "3 GB OOM" (13.0-13.8s); "5 GB OOM" (13.8-15.0s)
- sound: error on each OOM stamp

## Frame 6: Disk full (15-18s)

- act: Act 2: The night goes wrong
- scene: "103 GB full" in red over a hatched disk bar spilling over its end
- duration: 3s
- poster: 17.4
- transition_in: sheet turn
- status: built
- src: compositions/disk.html
- reads: Spark + "The Docker disk fills up" (15.2-16.0s); "103 GB full" (16.2-17.0s); "Spark MERGE spilled ~33 GB" (17.0-18.0s)
- sound: error on the spill

## Frame 7: Fixed, line by line (18-22s)

- act: Act 3: Morning
- scene: the five incidents listed, each struck through and stamped "fixed"; the last stamp is red
- duration: 4s
- poster: 21.4
- transition_in: sheet turn
- status: built
- src: compositions/fixed.html
- reads: the five incident lines, one per 0.6s (18.2-21.2s); the last red "fixed" (21.2-22.0s)
- sound: pop on each "fixed" stamp

Fixes are shown as strikes and stamps only: `data.json` holds the incidents, not the fixes.

## Frame 8: 10:37 (22-24.5s)

- act: Act 3: Morning
- scene: "10:37" stamped red under a grey "22:50"; the laptop open, its trace finished
- duration: 2.5s
- poster: 24.1
- transition_in: sheet turn
- status: built
- src: compositions/morning.html
- reads: "10:37" (22.2-23.2s); "The run finishes" (23.2-24.5s)
- sound: pop on the stamp

## Frame 9: The claim (24.5-28s)

- act: Act 3: Morning
- scene: "~40 h, 8 days, 261 runs." stamped line by line; "Next stop: the cloud." with "the cloud." in red
- duration: 3.5s
- poster: 27.6
- transition_in: sheet turn
- status: built
- src: compositions/claim.html
- reads: the three lines (24.7-26.2s); "Next stop: the cloud." (26.2-28.0s)
- sound: pop per line; impact-bass-1 on "the cloud."

## Frame 10: Sleipnir (28-30s)

- act: Act 3: Morning
- scene: "Sleipnir" stamped red, the repo URL under it
- duration: 2s
- poster: 29.5
- transition_in: the paper advances at drum speed
- status: built
- src: compositions/end.html
- reads: "Sleipnir" (28.1-29.0s); "github.com/jhorlima/sleipnir" (29.0-30.0s, held)
- sound: none after the impact

---
format: 1920x1080
duration: 33s
message: "Real night runs of benchmarking on a laptop: what broke, what was fixed, what was not, and next stop the cloud."
arc: Hook (22:50, several nights, one log) → Incidents (sleep, swap, heap, OOM, disk) → Verdicts → Morning (10:37) → Claim → End
audience: data engineers reading the Sleipnir README
---

## Frame 1: 22:50 (0-3s)

- act: Act 1: The run starts
- scene: "22:50" stamped in the margin; the pen draws the laptop, lid open, and starts its trace; "Several nights, one log" under it
- duration: 3s
- poster: 2.9
- transition_in: cut
- status: animated
- src: compositions/start.html
- reads: "22:50" (0.0-3.0s); "The run starts" (0.7-3.0s); "Several nights, one log" (1.3-3.0s)
- sound: pop on the stamp; click-soft as the pen touches the screen

The log book opens. The time is the hook: someone started a benchmark at ten to eleven at night. The incidents that follow come from several night runs (the laptop sleep from an earlier campaign), so the first sheet says so.

## Frame 2: The laptop falls asleep (3-6.9s)

- act: Act 2: The night goes wrong
- scene: the lid shuts, three z's, Trino's "ABANDONED_TASK" stamped in red
- duration: 3.9s
- poster: 4.5
- transition_in: cut
- status: animated
- src: compositions/sleep.html
- reads: Trino + "The laptop falls asleep" (3.1-4.2s); "ABANDONED_TASK" (4.2-6.4s); "macOS idle sleep froze the Docker VM" (4.4-6.4s)
- sound: glitch-3 on the lid; error on the stamp

The joke of the film: the laptop went to sleep and took Trino's workers with it.

## Frame 3: Swap (6.4-9.9s)

- act: Act 2: The night goes wrong
- scene: a hatched half dial sweeps to its stop; "15.7 / 16 GB" with 15.7 in red
- duration: 3.5s
- poster: 9.0
- transition_in: sheet advance
- status: animated
- src: compositions/swap.html
- reads: "macOS swap fills up" (6.95-9.4s); "15.7 / 16 GB swap in use" (7.85-9.4s)
- sound: whoosh-short on the sheet turn; error when the needle hits the stop

## Frame 4: Spark's heap (9.4-13.4s)

- act: Act 2: The night goes wrong
- scene: snapshot tally marks pile into a heap; "4.4 M" stamped red
- duration: 4s
- poster: 12.5
- transition_in: sheet advance
- status: animated
- src: compositions/heap.html
- reads: Spark + "Spark's heap piles up" (9.95-12.9s); "4.4 M" (10.85-12.9s); "Iceberg snapshot objects in the Spark heap" (10.9-12.9s)
- sound: whoosh-short on the sheet turn; error on "4.4 M"

## Frame 5: Object store OOM (12.9-16.4s)

- act: Act 2: The night goes wrong
- scene: RustFS wordmark; a 3 GB box overflows and is stamped OOM, a taller 5 GB box overflows and is stamped OOM in red
- duration: 3.5s
- poster: 15.8
- transition_in: sheet advance
- status: animated
- src: compositions/oom.html
- reads: RustFS + "The object store runs out of memory" (13.45-15.9s); "3 GB OOM" (14.2-15.9s); "5 GB OOM" (15.1-15.9s)
- sound: error on each OOM stamp

## Frame 6: Disk full (15.9-19.9s)

- act: Act 2: The night goes wrong
- scene: "103 GB full" in red over a hatched disk bar spilling over its end
- duration: 4s
- poster: 19.0
- transition_in: sheet advance
- status: animated
- src: compositions/disk.html
- reads: Spark + "The Docker disk fills up" (16.45-19.4s); "103 GB full" (17.7-19.4s); "Spark MERGE spilled ~33 GB" (17.85-19.4s)
- sound: error on the spill

## Frame 7: The log, line by line (19.4-23.9s)

- act: Act 3: The morning after
- scene: the five incidents listed; laptop sleep, Spark heap and object store OOM struck and stamped "fixed"; swap stamped "run at night"; Docker disk full left open with the red "next: the cloud"
- duration: 4.5s
- poster: 23.0
- transition_in: sheet advance
- status: animated
- src: compositions/fixed.html
- reads: the five rows, one every 0.5s (20.1-22.5s); "next: the cloud" (22.47-23.4s)
- sound: pop on each "fixed" stamp

Fixed: laptop sleep (keep-awake), Spark heap (catalog caches off), object store OOM (a newer RustFS with its scanner off). Swap was worked around by running at night. The Docker disk was not fixed: Spark's MERGE still needs more disk, which is why the campaign stopped and moves to the cloud.

## Frame 8: 10:37 (23.4-26.65s)

- act: Act 3: The morning after
- scene: "10:37" stamped red under a grey "22:50"; the laptop open, its trace finished
- duration: 3.25s
- poster: 25.8
- transition_in: sheet advance
- status: animated
- src: compositions/morning.html
- reads: "10:37" (24.9-26.15s); "The run finishes" (25.05-26.15s)
- sound: pop on the stamp

## Frame 9: The claim (26.15-30.15s)

- act: Act 3: The morning after
- scene: "~40 h, 8 days, 261 runs." stamped line by line; "Next stop: the cloud." with "the cloud." in red
- duration: 4s
- poster: 29.0
- transition_in: sheet advance
- status: animated
- src: compositions/claim.html
- reads: the three lines (26.85-29.65s); "Next stop: the cloud." (28.05-29.65s)
- sound: pop per line; impact-bass-1 on "the cloud."

## Frame 10: Sleipnir (29.65-32.9s)

- act: Act 3: The morning after
- scene: "Sleipnir" stamped red, the repo URL under it
- duration: 3.25s
- poster: 32.8
- transition_in: sheet advance
- status: animated
- src: compositions/end.html
- reads: "Sleipnir" (30.25-32.9s); "github.com/jhorlima/sleipnir" (30.5-32.9s, held)
- sound: whoosh-short on the sheet advance; the impact's tail

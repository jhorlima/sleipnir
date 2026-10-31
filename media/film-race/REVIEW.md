# Review: Film A, The race

34 s, 1920 x 1080, 30 fps. Renders: `renders/race.mp4` (with effects) and `renders/race-silent.mp4` (same video stream, audio removed); copies in `docs/assets/films/`.

## Creative calls

- Storyline A as approved, with the two board fixes: on the build sheet the red focus moves to Spark's failure on M ("Spark failed" stamped beside its break, its M line re-inked red) while Trino's line and "9,351 s" turn grey/graphite; on the query sheet "65.3 s" is the red stamp, and it turns graphite when "24.6 s" lands.
- "object store +1 CPU" from the storyline is written "object store at 2 CPU" (the L2 profile in `data.json`); "+1" is not in `data.json`.
- Every sheet change is a tear (8 frames, saw-tooth edge): at 120 px/s the drum would need 11 s to advance a full sheet.
- The drum stops before anything is stamped, so no number is read on moving paper.
- The Cube Store payoff has its own pen (only on that sheet) instead of reusing an engine pen.
- Not built: storylines B (one row, four engines) and C (the night shift); they are separate films.

## Measured

- `npx hyperframes check --json`: ok, 0 errors, 0 warnings (lint, runtime, layout, motion, contrast, craft, audio).
- `snapshot --review`: beat sheet, 12 seam strips, phone sheet (360 px). Key frames re-snapped into `boards/stills/`.
- `hyperframes audio` on the render: integrated -15.9 LUFS, true peak -5.6 dBTP, no clipping, the loudest moment at 27.33 s (the impact on "16-34 ms"). Per-clip volumes: pop and click-soft 0.32, whoosh-short 0.24, impact-bass-1 0.5. The onsets land 0.02-0.05 s after their pictures (stamp at 4.75 s → hit at 4.78 s; "65.3 s" at 20.05 s → 20.07 s; impact at 27.3 s → 27.30 s). The sound was measured, not heard.

## Found and fixed

- P0 · tears · the torn sheet's content slid visibly behind the logos in the margin → the margin is now an opaque plate of the same paper and grid.
- P0 · t=0 · the first frame showed only pens and logos (the README thumbnail) → the pens start down and "3.97 billion" is stamped on frame 0.
- P1 · t=6.3 · "742 M rows in 146 s" was on screen for 1.3 s, shorter than its five words → the load sheet holds 0.5 s longer (the film went from 33.5 s to 34 s).
- P1 · build and query sheets · the slanted 24 px steps crossed the first letters of "12,639 s", "13,803 s", "DuckDB" and "Trino 32.4 s" → the labels moved 32 px into their runs.
- P1 · t=15.1 · "Spark failed" sat on the L divider → moved 52 px right, clear of the divider and of Spark's L2 rise.
- P1 · t=28.3 · the Cube Store red line was hidden under the graphite zero line → the zero line is now drawn under the ink and the trace sits 4 px above it.
- P2 · query sheet · the L2 divider showed at the pen tip before L2 was drawn → the reveal window ends 2 px before the tip.

## Weakest shot and what I would change

- The query sheet opens with three pens rising from the same point; for a few frames their vertical steps overlap. Staggering the three pens by a few pixels in x, as real multi-pen recorders do, would separate them.
- The film is 34 s against a ~30 s target. The 4 s drum runs on the build and query sheets carry it; 180 px sections would save about 2 s but would need two-line profile labels.
- `whoosh-short` is the only whoosh in the shared library, so all six tears use the same take. A second take would remove the repetition.
- Integrated loudness is dominated by the 2 s impact (the other hits are short and mostly fall under the gate), so the impact's volume sets the film's LUFS.

## Warnings kept

None. The silent copy is the same render with its audio stream removed (`ffmpeg -c:v copy -an`).

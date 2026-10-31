# Review: One row, four engines

30.5 s, 1920×1080, 30 fps. Built from the approved storyboard (`boards/storyboard.html`). Rendered as `stack.mp4` (with effects) and `stack-silent.mp4` (the same picture, audio stream dropped).

## Creative calls

- **Seams are sheet advances.** Every one of the eight seams is the same move from `media/LOOK.md` ("the paper advances to the next sheet"): in the last 0.4 s of a shot the whole sheet, grid included, leaves left on `power3.in`, and the next shot prints onto clean paper. The one shot where the drum runs at 120 px/s linear is shot 2, the run from 1763 to 2025.
- **Printing, not fading.** Words and logos are stamped (scale 1.12 → 1 in 6 frames, 2 px ink spread through `-webkit-text-stroke`). Rows are typed at one character per frame. Lines are drawn as pen traces. The Parquet column strips are printed top to bottom. Nothing fades or slides up.
- **Drift from the storyboard:** frame 07's Cube mark sits fully inside the frame, with the traces still coming in from the left edge (the requested fix). Silver now prints about 0.6 s earlier, so the silver row is on screen long enough to read. The end card's URL lands earlier, so it is held for more than 2 s. There is no typing caret.
- **Not built:** storylines A (the race) and C (the night shift) are separate projects.

## Measured

- `npx hyperframes check --json`: 0 errors. Two warnings were fixed during review: `line_unread` on the silver row and on the closing URL. One warning was kept on purpose:
  - `duplicate_media_discovery_risk`: the Trino mark appears twice in shot 6, once as a writer and once as a reader.
- The review sheets (`snapshot --review`: scene starts and middles, five frames across each of the 8 seams, phone width) were read frame by frame. Every line that has to be read is at least 36 px at 1080p and can be read on the 360 px phone sheet.
- Sound (`npx hyperframes audio`): onsets land one frame after their pictures (pop on Milan at 1.08 s, on 2025 at 3.52 s, the logos at 8.34–8.72 s, the impact's steepest point at 23.41 s for the 23.4 s stamp). The mix measures -16.0 LUFS integrated and -1.8 dBTP true peak, with no clipping, and the loudest moment is the impact at 23.43 s. Nobody has listened to it.

## Fixed in review

- P0 · every pen trace · the traces appeared all at once instead of drawing on (the dash was normalised with `pathLength`, which did not animate in the renderer) → the dash is now the path's real length (`getTotalLength`), with a gap longer than the path so no round cap shows as a dot before the pen arrives.
- P1 · t=12.4 s · silver row on screen 1.6 s, under its read floor → the silver beat starts earlier (strike at 0.65 s, row at 1.3 s into the shot).
- P1 · t=28.7 s · repo URL on screen 1.8 s at the end → stamped at 0.45 s into the shot and held to the last frame.
- P2 · `#paper` was a timed clip with nested children (lint) → it is now an untimed full-bleed background.

## Weakest shot and next changes

- **Shot 3 (bronze)** carries the most: the sheet, four column strips and four logos with labels in about 2 s. The logos land 4 frames apart, so the labels cannot all be read on one viewing. With more time: give bronze 1 s more, taken from shot 8.
- **Sound (fixed after the first render):** the loudest sample was a sheet-advance whoosh, which overlapped the impact's tail, and the mix sat at -21.9 LUFS. The whooshes are now at 0.2, and an `sfx` bus adds +6.3 dB into a -2 dB limiter. The impact is now the loudest moment, at -16.0 LUFS and -1.8 dBTP.
- **Deviation from LOOK MOTION:** there is no visible pen tip leading the traces. Adding one means moving a small graphite dot along each path.

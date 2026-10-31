# Review: The night shift

Film: 32.9 s, 1920 x 1080, 30 fps, effects only. Delivered as `docs/assets/films/night-shift.mp4` (with sound) and `night-shift-silent.mp4` (the same render with the audio stream dropped).

## Creative calls

- **The log book device:** every shot is a sheet of the recorder paper with a margin rule. The margin holds a time stamp only where `data.json` has one (22:50, 10:37); incident sheets carry the engine's logo instead, so no invented clock times.
- **Honest framing:** the incidents come from several night runs (the laptop sleep from an earlier campaign), so the first sheet says "Several nights, one log". 22:50 and 10:37 stay as the bounds of the log.
- **Honest verdicts:** the log sheet strikes and stamps "fixed" only on laptop sleep, Spark heap and object store OOM; swap is "run at night" (worked around, not struck); Docker disk full is not struck and carries the red "next: the cloud", which hands off to the claim.
- **Cuts:** every cut is the paper advancing (outgoing and incoming sheets butted, 15 frames, `power2.inOut`), except the hard cut on the glitch into the sleep. The same move on every seam is deliberate: it is the recorder drum, the film's one transition. With more time, the sheet into the claim could tear instead of advance.
- **Motion inside a sheet:** stamps (scale 1.12 → 1, no fade), pen writing (left-to-right clip reveal), pen drawing (stroke-dashoffset), hatching that fills (stepped for the tally heap, accelerating for boxes and the disk bar), a needle sweep with a 2° overshoot, and the laptop lid closing on its hinge with a two-frame squash.
- **Length:** 32.9 s instead of 30 s. The check's read floor (`line_unread`) flagged four lines on the 30 s cut; the sleep, heap, disk and morning sheets were held longer rather than cutting words.
- Not built: the slow drum drift during a sheet and the pen tip leading each trace (LOOK MOTION). The paper only moves on sheet advances.

## Measured vs looked at

- `npx hyperframes check --json`: 0 errors, 0 warnings. 12 info findings, all expected: canvas overflow and an escaped container while a sheet is mid-advance (its contents are off-canvas by design), and one `text_occluded` on the sleep stamp sampled mid-scale.
- `snapshot --review`: beat, seam and phone sheets read; render frames at 4.5, 8.5, 12.5, 23.0, 29.7 and 32.8 s match the snapshots.
- Sound, measured on the rendered MP4 with `hyperframes audio`, not heard: integrated −15.8 LUFS, true peak −2.8 dBTP, no clipping; the loudest moment is the claim's impact at 28.58 s (the mix target shared by the three films: about −16 LUFS, true peak ≤ −1 dBTP). Volumes were set with an ffmpeg simulation of the placed clips, which matched the render to 0.1 dB. Onsets land on their pictures: errors 4.2 / 7.85 / 10.85 / 14.2 / 15.1 / 17.7 s, label pops 20.5 to 22.5 s every 0.5 s, the impact at 28.55 s.
- `error.mp3` peaks at −21 dBTP, far below the other effects, so it plays at volume 3.98 (trimmed to 0.5-0.95 s of the file). The last whoosh drops to 0.2 so the impact it lands on stays the loudest hit.

## Notes found and fixed

- P0 · t=4-23 s · four lines were on screen under their read floor → sleep, heap, disk and morning sheets held 0.25-0.65 s longer; heap line written 0.05 s earlier · nothing else moved.
- P1 · audio · whoosh and other clips without a duration were counted as running to the end of the film (overlap warnings) → every clip has an explicit `data-duration` · peaks unchanged.
- P1 · t=26.9-27.7 s · claim pops overlapped on one track → pops trimmed to 0.4 s.
- P1 · claim · League Gothic has no tilde, so "~40 h" fell back to a system glyph → the tilde is set in Oswald.

## Weakest shot, and what I would change

The object store sheet (12.9-16.4 s): two hatched boxes read as "memory" only through their labels. With more time: give the boxes a drawn RAM-stick edge (contacts along the bottom) so they read without the label.

## Kept on purpose

- Margin notes are Oswald 52 px: readable on desktop, small on a 360 px phone. They sit inside LOOK's 36-56 px range; the hero number on each sheet is 190-260 px.
- The identical sheet advance on eight seams (the medium's transition, see above).
- `boards/.posed.html` holds the still poses from the storyboard pass; `index.html` is now the animated film.

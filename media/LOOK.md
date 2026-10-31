# Look: the weather recorder chart

Shared by every film and still in `media/`. The medium is the instrument that produced the data: a recorder drum with printed chart paper and pens tracing the measurement. Every film's `SPEC.md` copies this LOOK, MOTION and BANNED and only adds to them.

## LOOK

- **Paper (ground):** `#F5F7F3`, flat, with a 1.5% fibre noise. Printed grid in `#BFD8D2`: minor lines 1 px every 24 px, major lines 2 px every 120 px. Never a gradient.
- **Graphite ink:** `#1E2A2F`, every word that must be read and every structural line (axes, frames, arrows).
- **Pen red (accent):** `#D9382B`, one focus per frame only: the number that matters, the trace that matters, the stamp.
- **Muted pens (other engines):** `#5E6B70` and `#8A979B`, for series that are not the focus.
- **Display:** League Gothic 400, numbers at 14-22% of the frame height, tracking +1%, `font-variant-numeric: tabular-nums`.
- **Labels and lines:** Oswald 500, 36-56 px at 1080p, tracking +2%, sentence case (no all-caps micro labels).
- **Logos:** the official marks in `media/shared/logos/` (never redrawn), sitting on the paper with `mix-blend-mode: multiply`, at least 120 px tall when they are the subject.
- **Depth:** none. No shadows, no glass. The paper is the only surface; things are printed or drawn on it.

## MOTION

- **The drum:** the paper advances right to left, linear, 120 px/s when it moves; it never eases.
- **The pen:** traces draw on with `stroke-dashoffset`, ease `power2.inOut`, 18-36 frames per trace; the pen tip leads the line.
- **The stamp:** numbers and key words are stamped: scale 1.12 → 1 in 6 frames (`power3.out`), 2 px ink spread, no fade.
- **Typed lines:** CSV rows are typed character by character, 1 frame per character, with `key-press`.
- **Cuts:** the paper tears or advances to the next sheet; never a cross-fade.
- **One hero move per shot**; secondary moves start 4-6 frames later and travel 50-70% as far.

## SOUND (effects only, no music)

From `media/shared/sfx/` (Pixabay Content License, bundled with HyperFrames): `click-soft` pen down, `typing` / `key-press` typed rows, `pop` a stamp, `whoosh-short` the paper advancing, `error` / `glitch-3` a failure (film C only), `impact-bass-1` once per film on the payoff, the loudest hit. Hits land one frame after their picture; each film's mix is brought to about -16 LUFS with true peak ≤ -1 dBTP (measured with `npx hyperframes audio`, per-clip volumes in each film's `SPEC.md`). A silent copy of each film is rendered for places that autoplay muted.

## BANNED

A dark or navy void; glow, bloom, neon, particles; purple/blue or mesh gradients; glass cards; a cream paper with a serif display and small mono caps labels; everything centred; everything fading and sliding up; text moving while it is read; corner brackets, HUD readouts; three cards in a row, KPI grids; a docked logo; cross-fades between shots; any number not in `media/shared/data.json`.

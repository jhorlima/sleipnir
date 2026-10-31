# Media

The films and stills that go with the article and the README. They are [HyperFrames](https://github.com/heygen-com/hyperframes) compositions: HTML, CSS and a seekable timeline rendered frame by frame, so the same source always renders the same video. Nothing in them is AI-generated imagery.

| Folder | What |
|---|---|
| `LOOK.md` | The shared look (a weather recorder chart), motion, sound and banned defaults |
| `STORYLINES.md` | The three films, the Medium stills and the LinkedIn cut |
| `shared/data.json` | Every number that appears on screen, taken from `results/*.parquet` |
| `shared/logos/` | Official marks of each project in the stack |
| `film-race/`, `film-stack/`, `film-night-shift/` | One HyperFrames project per film |
| `film-race-square/` | The 1080×1080, 15 s silent cut of the race for LinkedIn |
| `medium-cards/` | The stills for the Medium post |

Rendered outputs live in `docs/assets/`: `films/<name>.mp4` (with sound), `films/<name>-silent.mp4`, `films/<name>-poster.png`, `films/race-square.mp4`, and `medium/*.png`.

## Render

From a film's folder:

```sh
npx hyperframes check
npx hyperframes render
```

The sound effects are not in the repo (see Credits): copy `click-soft`, `error`, `glitch-3`, `impact-bass-1`, `key-press`, `pop`, `typing` and `whoosh-short` from the HyperFrames `media-use` skill's bundled library (`audio/assets/sfx/`) into `shared/sfx/` and each film's `assets/sfx/` before rendering.

## Credits

- **Logos** are trademarks of their owners (DuckDB, Trino, Apache Spark, StarRocks, Apache Iceberg, dbt Labs, Cube, PostgreSQL, RustFS, Lakekeeper), used only to name the tools that were benchmarked.
- **Sound effects** come from [Pixabay](https://pixabay.com/sound-effects/) via the HyperFrames bundled library, under the [Pixabay Content License](https://pixabay.com/service/license-summary/). They are used inside the rendered videos and not redistributed here.
- **Data:** NOAA GHCN-Daily ([ncei.noaa.gov](https://www.ncei.noaa.gov/pub/data/ghcn/daily/)).

# Datawrapper tables

Every table of the Medium post (`docs/blog/01-medium-local-benchmark.md`) published as a Datawrapper table, so Medium embeds it from the pasted link. They live in the Datawrapper folder "Sleipnir — Medium 01".

```sh
DATAWRAPPER_TOKEN=... uv run media/datawrapper/publish_tables.py
```

A re-run updates and republishes the charts listed in `charts.json` instead of creating new ones; each publish bumps the version in the public URL, so paste the new URLs into the post afterwards.

The charts are responsive: the width follows the column, the height is what to check. The embed size is the one stored in each chart's metadata (`publish.embed-width` / `publish.embed-height`). The API never measures it (it stays at the 600 × 400 default), so the script measures each published table at 600 px wide and writes that height back.

| # | Title | Public URL | Embed size (px) |
|---|---|---|---|
| t01 | The data | https://datawrapper.dwcdn.net/n9qRl/3/ | 600 × 530 |
| t02 | The stack | https://datawrapper.dwcdn.net/YKOkR/3/ | 600 × 422 |
| t03 | The machine | https://datawrapper.dwcdn.net/GrhBf/3/ | 600 × 390 |
| t04 | Loading (DuckDB) | https://datawrapper.dwcdn.net/TMwDy/3/ | 600 × 269 |
| t05 | Transforming: build from scratch (dbt) | https://datawrapper.dwcdn.net/WAYVy/3/ | 600 × 430 |
| t06 | Transforming: reprocess the latest batch | https://datawrapper.dwcdn.net/bkhwO/3/ | 600 × 307 |
| t07 | Reading: the questions | https://datawrapper.dwcdn.net/Iuzcs/3/ | 600 × 544 |
| t08 | Reading: direct SQL (warm, ms) | https://datawrapper.dwcdn.net/afeYZ/3/ | 600 × 301 |
| t09 | Reading: direct SQL (warm, ms) | https://datawrapper.dwcdn.net/Lr2uc/3/ | 600 × 269 |
| t10 | Reading: through Cube (warm, ms) | https://datawrapper.dwcdn.net/uQ3jY/3/ | 600 × 378 |
| t11 | Reading: through Cube (warm, ms) | https://datawrapper.dwcdn.net/07ZzD/3/ | 600 × 394 |
| t12 | TPC-H SF8, 22 queries (r2 scale, profile M) | https://datawrapper.dwcdn.net/DrF7P/3/ | 600 × 240 |
| t13 | One year of data, with Postgres (small, 44 M rows, profile M) | https://datawrapper.dwcdn.net/F80qy/3/ | 600 × 349 |
| t14 | One year of data, with Postgres (small, 44 M rows, profile M) | https://datawrapper.dwcdn.net/j7RzO/3/ | 600 × 211 |
| t15 | Acceleration (r2, profile M, warm ms; in parentheses the same question without it) | https://datawrapper.dwcdn.net/HEje3/3/ | 600 × 413 |
| t16 | Table layout and maintenance (B6, Trino, r2, profile M) | https://datawrapper.dwcdn.net/ier0w/3/ | 600 × 636 |
| t17 | Table layout and maintenance (B6, Trino, r2, profile M) | https://datawrapper.dwcdn.net/j7PDP/3/ | 600 × 439 |
| t18 | Table layout and maintenance (B6, Trino, r2, profile M) | https://datawrapper.dwcdn.net/kQtCV/3/ | 600 × 296 |
| t19 | The M → L surprise | https://datawrapper.dwcdn.net/1npII/3/ | 600 × 365 |
| t20 | The M → L surprise | https://datawrapper.dwcdn.net/l3pcb/3/ | 600 × 180 |
| t21 | How long it took | https://datawrapper.dwcdn.net/Epe4f/3/ | 600 × 274 |

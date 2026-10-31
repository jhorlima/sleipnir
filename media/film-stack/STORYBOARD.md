---
format: 1920x1080
duration: 30.5s
message: "One real weather row travels the whole stack and comes back as the same answer from every engine."
arc: Hook (1763) → 2025 row → bronze → silver → gold → four engines → Cube answer → claim → end
audience: data engineers reading the Sleipnir README
mode: collaborative
---

## Frame 1: The oldest row (0-3s)

- act: Act 1: One row
- scene: The 1763 row typed on the recorder paper; Milan, -3.6 °C stamped under it
- duration: 3s
- poster: 2.6s
- transition_in: cut
- status: animated
- reads: `ITE00100554,17630101,TMAX,-36` typed (0.0-1.0s); "Milan, 1 January 1763." and "-3.6 °C" stamped (1.2-3.0s)
- sound: typing under the row; pop on "-3.6 °C"
- src: compositions/s1.html

Cold open on the oldest row of the dataset, readable as it is in the CSV. The pen leader ties `-36` to `-3.6 °C`: values are tenths of a degree.

## Frame 2: The paper runs to 2025 (3-6.5s)

- act: Act 1: One row
- scene: The drum runs from 1763 to 2025; the Central Park row is typed
- duration: 3.5s
- poster: 6s
- transition_in: paper advances
- status: animated
- reads: "1763" leaves and "2025" lands on the time rule (3.0-3.8s); `USW00094728,20250601,TMAX,189` typed (3.8-4.8s); "New York, Central Park" and "18.9 °C" (4.9-6.5s)
- sound: whoosh-short on the run; typing; pop on "18.9 °C"
- src: compositions/s2.html

This is the row the film follows.

## Frame 3: Bronze (6.5-10.5s)

- act: Act 2: The stack
- scene: The row splits into four column strips of a Parquet sheet; DuckDB, Iceberg, RustFS and Lakekeeper stamped with their lines
- duration: 4s
- poster: 10s
- transition_in: object becomes the next object
- status: animated
- reads: "bronze" (6.6-7.4s); "DuckDB writes it", Iceberg "table format", RustFS "object storage", "Lakekeeper catalog" (7.4-10.5s)
- sound: pop per logo, 4 frames apart
- src: compositions/s3.html

The row turns into columns: that is what Parquet is, shown, not said.

## Frame 4: Silver (10.5-14s)

- act: Act 2: The stack
- scene: dbt stamped; the same row twice, the older struck in pen red; the kept row becomes the silver row in °C
- duration: 3.5s
- poster: 13.6s
- transition_in: object becomes the next object
- status: animated
- reads: dbt and "silver" (10.6-10.9s); two identical rows, the older struck, "duplicate" (10.85-11.8s); silver row with "18.9" (11.8-13.6s)
- sound: pop on dbt; click-soft on the strike
- src: compositions/s4.html

The overlap reload brings the row in twice; silver keeps one.

## Frame 5: Gold (14-17.5s)

- act: Act 2: The stack
- scene: The kept row reflows into the gold fact table fct_weather_daily
- duration: 3.5s
- poster: 17s
- transition_in: object becomes the next object
- status: animated
- reads: "gold", "fct_weather_daily" (14.1-15.0s); "USW00094728 · 2025-06-01 · 18.9" (15.0-17.5s)
- sound: pop on "18.9"
- src: compositions/s5.html

## Frame 6: Four engines (17.5-21.5s)

- act: Act 3: Same answer
- scene: Written by Trino and Spark; three pen traces carry the gold row to Trino, StarRocks and DuckDB, each answering 18.9
- duration: 4s
- poster: 21s
- transition_in: pen traces out of the row
- status: animated
- reads: "written by" Trino, Spark (17.6-18.6s); "read by" Trino, StarRocks, DuckDB, each "18.9" (18.6-21.5s)
- sound: click-soft pens down; pop per logo
- src: compositions/s6.html

## Frame 7: The answer (21.5-25.5s)

- act: Act 3: Same answer
- scene: Cube stamped; "Central Park, June 2025?" typed; "16-34 ms" stamped from Cube Store
- duration: 4s
- poster: 25s
- transition_in: traces converge
- status: animated
- reads: Cube and "Central Park, June 2025?" (21.6-23.0s); "16-34 ms" and "from Cube Store" (23.4-25.5s)
- sound: typing under the question; impact-bass-1 on "16-34 ms"
- src: compositions/s7.html

The payoff, the one impact of the film.

## Frame 8: The claim (25.5-28s)

- act: Act 4: End
- scene: "One row. Four engines. Same answer." stamped line by line under the faint row
- duration: 2.5s
- poster: 27.6s
- transition_in: paper advances
- status: animated
- reads: "One row." "Four engines." "Same answer." (25.6-28.0s)
- sound: pop per line
- src: compositions/s8.html

## Frame 9: Sleipnir (28-30.5s)

- act: Act 4: End
- scene: "Sleipnir" stamped, pen-red underline, repo URL
- duration: 2.5s
- poster: 30.2s
- transition_in: paper advances
- status: animated
- reads: "Sleipnir", "github.com/jhorlima/sleipnir" (28.1-30.5s)
- sound: pop, then silence
- src: compositions/s9.html

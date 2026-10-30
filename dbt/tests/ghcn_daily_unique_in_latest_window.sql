-- Natural-key uniqueness, checked only on the dates the latest run can have written (SPEC §7.3).
-- From scale r2 up, grouping the whole table exceeds the engine's spill limit on profile M.
-- Checking the window is enough: delete+insert, merge and microbatch all replace whole dates, so a
-- duplicate can only appear where the run wrote. The whole table is checked year by year with
-- `make dbt-check-unique`, outside the measured steps.
-- Window: the newest month plus the batch overlap, plus the incremental lookback (SPEC §7.1).
{%- set window_days = 31 + 2 * var('overlap_days') %}

with latest_date as (
    select max(date) as max_date from {{ ref('ghcn_daily') }}
),

window_observations as (
    select
        observations.station_id,
        observations.date,
        observations.element
    from {{ ref('ghcn_daily') }} as observations
    cross join latest_date
    where observations.date > latest_date.max_date - interval '{{ window_days }}' day
)

select
    station_id,
    date,
    element,
    count(*) as row_count
from window_observations
group by station_id, date, element
having count(*) > 1

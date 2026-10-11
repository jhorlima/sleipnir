-- Natural-key uniqueness of the fact, checked only on the dates the latest run can have written
-- (same reasoning as ghcn_daily_unique_in_latest_window.sql). From scale r2 up, grouping all 190 M rows
-- runs Trino out of memory on profile M; `make dbt-check-unique` checks the whole table year by year.
{%- set window_days = 31 + 2 * var('overlap_days') %}

with latest_date as (
    select max(date) as max_date from {{ ref('fct_weather_daily') }}
),

window_days_observed as (
    select
        daily_weather.station_id,
        daily_weather.date
    from {{ ref('fct_weather_daily') }} as daily_weather
    cross join latest_date
    where daily_weather.date > latest_date.max_date - interval '{{ window_days }}' day
)

select
    station_id,
    date,
    count(*) as row_count
from window_days_observed
group by station_id, date
having count(*) > 1

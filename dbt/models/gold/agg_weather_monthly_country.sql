{#- Incremental by month: a run recomputes every month touched by the window.
    In a microbatch run dbt filters ref('fct_weather_daily') by its event_time (one month per batch). -#}
{{ config(
    materialized='incremental',
    incremental_strategy=var('incremental_strategy'),
    unique_key=incremental_unique_key(['country_code', 'month'], 'month'),
    event_time='month',
    batch_size='month',
    begin=var('microbatch_begin'),
    concurrent_batches=false,
    on_schema_change='fail',
    post_hook="{{ maintain_table(this) if var('maintenance', true) else '' }}",
) }}

{%- set start_date = incremental_start_date() %}
{%- set start_month = none if start_date is none else start_date.replace(day=1) %}

with daily_weather as (
    select
        station_id,
        date,
        tmax,
        tmin,
        prcp,
        snow,
        _batch_id
    from {{ ref('fct_weather_daily') }}
    {%- if start_month is not none %}
    where date >= date '{{ start_month }}'
    {%- endif %}
),

stations as (
    select station_id, country_code, country_name
    from {{ ref('stations') }}
)

-- Every measure is DOUBLE so Cube rollups keep full precision (.claude/rules/cube-models.md).
select
    stations.country_code,
    max(stations.country_name) as country_name,
    {{ dbt.date_trunc('month', 'daily_weather.date') }} as month,
    cast(avg(daily_weather.tmax) as {{ type_double() }}) as avg_tmax,
    cast(avg(daily_weather.tmin) as {{ type_double() }}) as avg_tmin,
    cast(max(daily_weather.tmax) as {{ type_double() }}) as max_tmax,
    cast(min(daily_weather.tmin) as {{ type_double() }}) as min_tmin,
    cast(avg(daily_weather.prcp) as {{ type_double() }}) as avg_prcp,
    cast(sum(daily_weather.prcp) as {{ type_double() }}) as total_prcp,
    cast(sum(daily_weather.snow) as {{ type_double() }}) as total_snow,
    cast(count(distinct daily_weather.station_id) as {{ type_double() }}) as station_count,
    cast(count(*) as {{ type_double() }}) as station_day_count,
    max(daily_weather._batch_id) as _batch_id
from daily_weather
inner join stations
    on stations.station_id = daily_weather.station_id
group by 1, 3

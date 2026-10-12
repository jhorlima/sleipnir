{#- In a microbatch run dbt filters ref('ghcn_daily') by its event_time, so no window is added here. -#}
{{ config(
    materialized='incremental',
    incremental_strategy=var('incremental_strategy'),
    unique_key=incremental_unique_key(['station_id', 'date'], 'date'),
    event_time='date',
    batch_size=var('microbatch_batch_size'),
    begin=var('microbatch_begin'),
    concurrent_batches=false,
    on_schema_change='fail',
    post_hook="{{ maintain_table(this) if var('maintenance', true) else '' }}",
) }}
{{ config(**partitioned_by_month('date', sort_columns=['station_id', 'date'])) }}

{%- set start_date = incremental_start_date() %}

with observations as (
    select
        station_id,
        date,
        element,
        value,
        _batch_id
    from {{ ref('ghcn_daily') }}
    where element in ('TMAX', 'TMIN', 'PRCP', 'SNOW')
    {%- if start_date is not none %}
        and date >= date '{{ start_date }}'
    {%- endif %}
)

select
    station_id,
    date,
    max(case when element = 'TMAX' then value end) as tmax,
    max(case when element = 'TMIN' then value end) as tmin,
    max(case when element = 'PRCP' then value end) as prcp,
    max(case when element = 'SNOW' then value end) as snow,
    max(_batch_id) as _batch_id
from observations
group by station_id, date

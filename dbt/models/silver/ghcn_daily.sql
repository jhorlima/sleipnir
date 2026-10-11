{#- event_time decision: bronze `date` is VARCHAR, so the source has no event_time and dbt never
    filters it; this model's event_time is the typed DATE column, which is what downstream
    microbatch models filter on. In a microbatch run the model filters bronze itself with the batch
    bounds written as YYYYMMDD (string order equals date order), which keeps Iceberg min/max pruning
    on the raw column without an extra typed staging layer. -#}
{{ config(
    materialized='incremental',
    incremental_strategy=var('incremental_strategy'),
    unique_key=incremental_unique_key(['station_id', 'date', 'element'], 'date'),
    event_time='date',
    batch_size='month',
    begin=var('microbatch_begin'),
    concurrent_batches=false,
    on_schema_change='fail',
    post_hook="{{ maintain_table(this) if var('maintenance', true) else '' }}",
) }}
{{ config(**partitioned_by_month('date')) }}

{%- if var('incremental_strategy') == 'microbatch' and model.batch is defined -%}
    {%- set start_date = model.batch.event_time_start.date() -%}
    {%- set end_date = model.batch.event_time_end.date() -%}
{%- else -%}
    {%- set start_date = incremental_start_date() -%}
    {%- set end_date = none -%}
{%- endif %}

with bronze_observations as (
    select
        id as station_id,
        date as raw_date,
        element,
        value as raw_value,
        q_flag,
        _batch_id,
        _ingested_at
    from {{ source('duckdb_bronze', 'ghcn_daily_raw') }}
    where element in ('TMAX', 'TMIN', 'PRCP', 'SNOW', 'SNWD')
    {%- if start_date is not none %}
        and date >= '{{ start_date.strftime("%Y%m%d") }}'
    {%- endif %}
    {%- if end_date is not none %}
        and date < '{{ end_date.strftime("%Y%m%d") }}'
    {%- endif %}
),

ranked_revisions as (
    select
        *,
        row_number() over (
            partition by station_id, raw_date, element
            order by _ingested_at desc
        ) as revision_rank
    from bronze_observations
),

-- The QC filter runs after dedup: a newer revision that fails QC must hide the older one.
latest_valid_observations as (
    select *
    from ranked_revisions
    where revision_rank = 1
        and (q_flag is null or trim(q_flag) = '')
)

select
    station_id,
    {{ parse_yyyymmdd('raw_date') }} as date,
    element,
    -- GHCN units: TMAX/TMIN in tenths of °C and PRCP in tenths of mm; SNOW/SNWD are already mm.
    case
        when element in ('TMAX', 'TMIN', 'PRCP') then cast(raw_value as {{ type_double() }}) / 10
        else cast(raw_value as {{ type_double() }})
    end as value,
    _batch_id,
    _ingested_at
from latest_valid_observations

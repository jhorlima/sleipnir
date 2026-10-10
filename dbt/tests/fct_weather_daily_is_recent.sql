-- Recency against the data, not the wall clock (GHCN years are historical): the fact must reach
-- the last date of the latest bronze batch.
with latest_bronze_batch as (
    select max(date) as last_raw_date
    from {{ source('duckdb_bronze', 'ghcn_daily_raw') }}
    where _batch_id = (select max(_batch_id) from {{ source('duckdb_bronze', 'ghcn_daily_raw') }})
),

fact_coverage as (
    select max(date) as last_date
    from {{ ref('fct_weather_daily') }}
)

select
    fact_coverage.last_date,
    latest_bronze_batch.last_raw_date
from fact_coverage
cross join latest_bronze_batch
where fact_coverage.last_date is null
    or fact_coverage.last_date < {{ parse_yyyymmdd('latest_bronze_batch.last_raw_date') }}

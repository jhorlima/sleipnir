with observed_dates as (
    select distinct date
    from {{ ref('ghcn_daily') }}
)

select
    date,
    extract(year from date) as year,
    extract(quarter from date) as quarter,
    extract(month from date) as month,
    extract(day from date) as day_of_month,
    {{ dbt.date_trunc('month', 'date') }} as month_start
from observed_dates

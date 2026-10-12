{#- B5b (SPEC §10.3): the table that stands in for the StarRocks MV on Trino, which cannot create MVs on the REST catalog (V2).
    Same wide join as the B5a MV and as the one Cube generates. Only the trino target builds it: on the other
    targets it is disabled, so their `dbt run` is unchanged. Cube reads it through cube/model/cubes/trino_mv/.
    The measured refresh is `dbt run --select mv_weather_wide`.
    Layout: partitioned by year and not sorted. One CTAS writes every partition at once, and the table writer of
    profile M (1.8 GB per query) runs out of memory with monthly partitions, or with a sort order on 28 yearly
    partitions at scale r2_1998 (the fact avoids this by writing one month per microbatch). -#}
{{ config(
    enabled=(target.name == 'trino'),
    properties={
        'partitioning': "ARRAY['year(date)']",
    },
) }}

select
    f.station_id,
    f.date,
    f.tmax,
    f.tmin,
    f.prcp,
    f.snow,
    s.station_name,
    s.country_code,
    s.latitude,
    s.longitude,
    s.elevation,
    d.year,
    d.quarter,
    d.month
from {{ ref('fct_weather_daily') }} as f
left join {{ ref('dim_station') }} as s on f.station_id = s.station_id
left join {{ ref('dim_date') }} as d on f.date = d.date

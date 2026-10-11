{#- B5b (SPEC §10.3): the table that stands in for the StarRocks MV on Trino, which cannot create MVs on the REST catalog (V2).
    Same wide join as the B5a MV and as the one Cube generates. Only the trino target builds it: on the other
    targets it is disabled, so their `dbt run` is unchanged. Cube reads it through cube/model/cubes/trino_mv/.
    The measured refresh is `dbt run --select mv_weather_wide`.
    Layout: sorted like the fact (D-15) but partitioned by year, not month: one CTAS writes every partition at once,
    and 190 monthly partitions exceed the per-query memory of profile M in the table writer (the fact is written
    one month at a time by microbatch). -#}
{{ config(
    enabled=(target.name == 'trino'),
    properties={
        'partitioning': "ARRAY['year(date)']",
        'sorted_by': "ARRAY['station_id', 'date']",
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

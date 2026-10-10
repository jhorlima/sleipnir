with stations as (
    select * from {{ source('duckdb_bronze', 'ghcn_stations_raw') }}
),

countries as (
    select * from {{ source('duckdb_bronze', 'ghcn_countries_raw') }}
)

select
    stations.id as station_id,
    stations.name as station_name,
    stations.state,
    substr(stations.id, 1, 2) as country_code,
    countries.name as country_name,
    stations.latitude,
    stations.longitude,
    -- -999.9 marks a missing elevation in ghcnd-stations.txt.
    nullif(stations.elevation, -999.9) as elevation,
    stations.gsn_flag,
    stations.hcn_crn_flag,
    stations.wmo_id
from stations
left join countries
    on countries.code = substr(stations.id, 1, 2)

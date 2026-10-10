select
    station_id,
    station_name,
    state,
    country_code,
    country_name,
    latitude,
    longitude,
    elevation,
    gsn_flag,
    hcn_crn_flag,
    wmo_id
from {{ ref('stations') }}

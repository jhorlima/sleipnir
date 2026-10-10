-- B5a MV (SPEC §10.3). LEFT JOINs mirror what Cube emits (many_to_one joins from the fact cube).
-- Columns: every column the base cubes use (weather_daily, stations, dates).
CREATE DATABASE IF NOT EXISTS sleipnir_mv;
DROP MATERIALIZED VIEW IF EXISTS sleipnir_mv.mv_weather_wide;

CREATE MATERIALIZED VIEW sleipnir_mv.mv_weather_wide (
    station_id, date, tmax, tmin, prcp, snow,
    station_name, country_code, latitude, longitude, elevation,
    year, quarter, month
)
PARTITION BY date_trunc('month', date)
DISTRIBUTED BY HASH(station_id) BUCKETS 4
ORDER BY (country_code, date, station_id)
REFRESH MANUAL
PROPERTIES (
    "force_external_table_query_rewrite" = "true",
    "query_rewrite_consistency" = "checked"
)
AS
SELECT
    f.station_id, f.date, f.tmax, f.tmin, f.prcp, f.snow,
    s.station_name, s.country_code, s.latitude, s.longitude, s.elevation,
    d.year, d.quarter, d.month
FROM lakehouse.trino_gold.fct_weather_daily AS f
LEFT JOIN lakehouse.trino_gold.dim_station AS s ON f.station_id = s.station_id
LEFT JOIN lakehouse.trino_gold.dim_date AS d ON f.date = d.date;

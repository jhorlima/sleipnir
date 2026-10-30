-- B5a (SPEC §10.3, D-24): plain copy of the station dimension (133k rows -> 4 buckets).
CREATE MATERIALIZED VIEW IF NOT EXISTS sleipnir_mv.mv_dim_station
COMMENT 'dim_station copy for query rewrite'
DISTRIBUTED BY HASH(station_id) BUCKETS 4
REFRESH DEFERRED MANUAL
PROPERTIES ("force_external_table_query_rewrite" = "true")
AS
SELECT
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
FROM lakehouse.trino_gold.dim_station;

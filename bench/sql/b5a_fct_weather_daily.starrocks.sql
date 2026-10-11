-- B5a (SPEC §10.3, D-24): plain copy of the gold fact for StarRocks query rewrite.
-- BUCKETS 16: 190M rows at scale r2 (50-200M rows -> 16).
-- DEFERRED: without it the creation already refreshes and the first measured refresh would do nothing.
CREATE MATERIALIZED VIEW IF NOT EXISTS sleipnir_mv.mv_fct_weather_daily
COMMENT 'fct_weather_daily copy for query rewrite'
PARTITION BY date_trunc('month', `date`)
DISTRIBUTED BY HASH(station_id) BUCKETS 16
REFRESH DEFERRED MANUAL
PROPERTIES ("force_external_table_query_rewrite" = "true")
AS
SELECT
    station_id,
    `date`,
    tmax,
    tmin,
    prcp,
    snow,
    _batch_id
FROM lakehouse.trino_gold.fct_weather_daily;

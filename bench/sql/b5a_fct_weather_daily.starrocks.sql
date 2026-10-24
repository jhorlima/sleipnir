-- B5a (SPEC §10.3, D-24): plain copy of the gold fact for StarRocks query rewrite.
-- BUCKETS 2: buckets count per partition; the fullest month has ~1M rows at every scale.
-- 16 buckets x 3,156 months at scale local made ~50k tablets and ran the BE out of memory on refresh.
-- DEFERRED: without it the creation already refreshes and the first measured refresh would do nothing.
CREATE MATERIALIZED VIEW IF NOT EXISTS sleipnir_mv.mv_fct_weather_daily
COMMENT 'fct_weather_daily copy for query rewrite'
PARTITION BY date_trunc('month', `date`)
DISTRIBUTED BY HASH(station_id) BUCKETS 2
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

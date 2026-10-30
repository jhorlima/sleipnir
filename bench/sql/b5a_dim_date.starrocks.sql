-- B5a (SPEC §10.3, D-24): plain copy of the date dimension (5.8k rows -> 4 buckets).
CREATE MATERIALIZED VIEW IF NOT EXISTS sleipnir_mv.mv_dim_date
COMMENT 'dim_date copy for query rewrite'
DISTRIBUTED BY HASH(`date`) BUCKETS 4
REFRESH DEFERRED MANUAL
PROPERTIES ("force_external_table_query_rewrite" = "true")
AS
SELECT
    `date`,
    `year`,
    quarter,
    `month`,
    day_of_month,
    month_start
FROM lakehouse.trino_gold.dim_date;

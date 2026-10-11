-- @Cube_Q1
SELECT CAST(DATE_FORMAT(CONVERT_TZ(`starrocks_weather_daily`.date, @@session.time_zone, '+00:00'), '%Y-01-01T00:00:00.000') AS DATETIME) `starrocks_weather__date_year`, count(CONCAT(`starrocks_weather_daily`.station_id, '|', CAST(`starrocks_weather_daily`.date AS VARCHAR))) `starrocks_weather__observation_count` 
FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
GROUP BY 1
ORDER BY  1  ASC
LIMIT 10000
;

-- @Cube_Q2
SELECT `starrocks_stations`.country_code `starrocks_weather__country`, CAST(DATE_FORMAT(CONVERT_TZ(`starrocks_weather_daily`.date, @@session.time_zone, '+00:00'), '%Y-%m-01T00:00:00.000') AS DATETIME) `starrocks_weather__date_month`, avg(CAST(`starrocks_weather_daily`.tmax AS DOUBLE)) `starrocks_weather__avg_tmax` 
FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
LEFT JOIN  lakehouse.trino_gold.dim_station  AS `starrocks_stations` ON `starrocks_weather_daily`.station_id = `starrocks_stations`.station_id
WHERE (`starrocks_weather_daily`.date >= TIMESTAMP(convert_tz('2025-01-01T00:00:00.000', '+00:00', @@session.time_zone)) AND `starrocks_weather_daily`.date <= TIMESTAMP(convert_tz('2025-12-31T23:59:59.999', '+00:00', @@session.time_zone)))
GROUP BY 1, 2
ORDER BY  1  ASC,  2  ASC
LIMIT 50000
;

-- @Cube_Q3
SELECT `starrocks_weather_daily`.station_id `starrocks_weather__station_id`, sum(CAST(`starrocks_weather_daily`.prcp AS DOUBLE)) `starrocks_weather__total_prcp` 
FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
WHERE (`starrocks_weather_daily`.date >= TIMESTAMP(convert_tz('2025-01-01T00:00:00.000', '+00:00', @@session.time_zone)) AND `starrocks_weather_daily`.date <= TIMESTAMP(convert_tz('2025-12-31T23:59:59.999', '+00:00', @@session.time_zone)))
GROUP BY 1
HAVING (sum(CAST(`starrocks_weather_daily`.prcp AS DOUBLE)) IS NOT NULL)
ORDER BY  2  DESC,  1  ASC
LIMIT 20
;

-- @Cube_Q4
SELECT `starrocks_stations`.country_code `starrocks_weather__country`, count(CONCAT(`starrocks_weather_daily`.station_id, '|', CAST(`starrocks_weather_daily`.date AS VARCHAR))) `starrocks_weather__observation_count`, avg(CAST(`starrocks_weather_daily`.tmax AS DOUBLE)) `starrocks_weather__avg_tmax` 
FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
LEFT JOIN  lakehouse.trino_gold.dim_station  AS `starrocks_stations` ON `starrocks_weather_daily`.station_id = `starrocks_stations`.station_id
WHERE (`starrocks_weather_daily`.date >= TIMESTAMP(convert_tz('2025-01-01T00:00:00.000', '+00:00', @@session.time_zone)) AND `starrocks_weather_daily`.date <= TIMESTAMP(convert_tz('2025-12-31T23:59:59.999', '+00:00', @@session.time_zone))) AND (`starrocks_stations`.latitude >= '36') AND (`starrocks_stations`.latitude <= '44') AND (`starrocks_stations`.longitude >= '-10') AND (`starrocks_stations`.longitude <= '4')
GROUP BY 1
ORDER BY  1  ASC
LIMIT 10000
;

-- @Cube_Q5
 WITH RECURSIVE 
time_series AS (  SELECT CAST(TIMESTAMP('2025-01-01T00:00:00.000') AS DATETIME(6)) AS date_from,
         CAST(DATE_SUB(DATE_ADD(TIMESTAMP('2025-01-01T00:00:00.000'), INTERVAL 1 DAY), INTERVAL 1000 MICROSECOND) AS DATETIME(6)) AS date_to
  UNION ALL
  SELECT DATE_ADD(date_from, INTERVAL 1 DAY),
         CAST(DATE_SUB(DATE_ADD(DATE_ADD(date_from, INTERVAL 1 DAY), INTERVAL 1 DAY), INTERVAL 1000 MICROSECOND) AS DATETIME(6))
  FROM time_series
  WHERE DATE_ADD(date_from, INTERVAL 1 DAY) <= TIMESTAMP('2025-03-31T23:59:59.999')),
cte_0 AS (  SELECT `starrocks_weather_daily`.station_id `starrocks_weather__station_id`, CAST(DATE_FORMAT(CONVERT_TZ(`starrocks_weather_daily`.date, @@session.time_zone, '+00:00'), '%Y-%m-%dT00:00:00.000') AS DATETIME) `starrocks_weather__date_day`, CAST(`starrocks_weather_daily`.tmax AS DOUBLE) `starrocks_weather_daily__avg_tmax_7d` 
  FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
  WHERE (CONVERT_TZ(`starrocks_weather_daily`.date, @@session.time_zone, '+00:00') >= TIMESTAMP(convert_tz('2024-12-25T00:00:00.000', '+00:00', @@session.time_zone)) AND CONVERT_TZ(`starrocks_weather_daily`.date, @@session.time_zone, '+00:00') <= TIMESTAMP(convert_tz('2025-04-01T23:59:58.999', '+00:00', @@session.time_zone))) AND (`starrocks_weather_daily`.station_id IN ('USW00094728', 'USW00023174', 'GME00127786', 'SPE00120278'))
  ORDER BY  2  ASC),
cte_1 AS (  SELECT `time_series`.`date_from` `starrocks_weather__date_day`, `rolling_source`.`starrocks_weather__station_id` `starrocks_weather__station_id`, avg(`rolling_source`.`starrocks_weather_daily__avg_tmax_7d`) `starrocks_weather_daily__avg_tmax_7d` 
  FROM  time_series  AS `time_series`
  LEFT JOIN  cte_0  AS `rolling_source` ON `rolling_source`.`starrocks_weather__date_day` > DATE_SUB(`time_series`.`date_to`, INTERVAL 7 DAY) AND `rolling_source`.`starrocks_weather__date_day` <= `time_series`.`date_to`
  GROUP BY 1, 2
  ORDER BY  2  ASC)
SELECT `fk_aggregate`.`starrocks_weather__station_id` `starrocks_weather__station_id`, `fk_aggregate`.`starrocks_weather__date_day` `starrocks_weather__date_day`, `fk_aggregate`.`starrocks_weather_daily__avg_tmax_7d` `starrocks_weather__avg_tmax_7d` 
FROM  cte_1  AS `fk_aggregate`
ORDER BY  1  ASC,  2  ASC
LIMIT 50000
;

-- @Cube_Q6
SELECT `starrocks_weather_daily`.station_id `starrocks_weather__station_id`, CAST(DATE_FORMAT(CONVERT_TZ(`starrocks_weather_daily`.date, @@session.time_zone, '+00:00'), '%Y-%m-%dT00:00:00.000') AS DATETIME) `starrocks_weather__date_day`, avg(CAST(`starrocks_weather_daily`.tmax AS DOUBLE)) `starrocks_weather__avg_tmax`, avg(CAST(`starrocks_weather_daily`.tmin AS DOUBLE)) `starrocks_weather__avg_tmin`, sum(CAST(`starrocks_weather_daily`.prcp AS DOUBLE)) `starrocks_weather__total_prcp` 
FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
WHERE (`starrocks_weather_daily`.date >= TIMESTAMP(convert_tz('2025-06-01T00:00:00.000', '+00:00', @@session.time_zone)) AND `starrocks_weather_daily`.date <= TIMESTAMP(convert_tz('2025-06-30T23:59:59.999', '+00:00', @@session.time_zone))) AND (`starrocks_weather_daily`.station_id = 'USW00094728')
GROUP BY 1, 2
ORDER BY  2  ASC
LIMIT 10000
;

-- @Cube_Q7
SELECT `starrocks_stations`.country_code `starrocks_weather__country`, PERCENTILE_CONT(`starrocks_weather_daily`.tmax, 0.5) `starrocks_weather__median_tmax`, PERCENTILE_CONT(`starrocks_weather_daily`.tmax, 0.95) `starrocks_weather__p95_tmax` 
FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
LEFT JOIN  lakehouse.trino_gold.dim_station  AS `starrocks_stations` ON `starrocks_weather_daily`.station_id = `starrocks_stations`.station_id
WHERE (`starrocks_weather_daily`.date >= TIMESTAMP(convert_tz('2025-01-01T00:00:00.000', '+00:00', @@session.time_zone)) AND `starrocks_weather_daily`.date <= TIMESTAMP(convert_tz('2025-12-31T23:59:59.999', '+00:00', @@session.time_zone)))
GROUP BY 1
ORDER BY  1  ASC
LIMIT 50000
;

-- @Cube_Q8
SELECT `starrocks_station_years`.year `starrocks_weather__station_year`, PERCENTILE_CONT(`starrocks_station_years_annual_prcp_subquery`.`annual_prcp`, 0.5) `starrocks_weather__median_station_annual_prcp` 
FROM  (SELECT station.station_id, years.year FROM lakehouse.trino_gold.dim_station AS station CROSS JOIN (SELECT DISTINCT year FROM lakehouse.trino_gold.dim_date) AS years
)  AS `starrocks_station_years`
LEFT JOIN (SELECT CONCAT(`starrocks_station_years`.station_id, '|', CAST(`starrocks_station_years`.year AS VARCHAR)) `starrocks_station_years__id`, sum(CAST(`starrocks_weather_daily`.prcp AS DOUBLE)) `annual_prcp` 
FROM  (SELECT station.station_id, years.year FROM lakehouse.trino_gold.dim_station AS station CROSS JOIN (SELECT DISTINCT year FROM lakehouse.trino_gold.dim_date) AS years
)  AS `starrocks_station_years`
LEFT JOIN  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily` ON `starrocks_station_years`.station_id = `starrocks_weather_daily`.station_id AND `starrocks_station_years`.year = EXTRACT(YEAR FROM `starrocks_weather_daily`.date)
GROUP BY 1) AS `starrocks_station_years_annual_prcp_subquery` ON ((`starrocks_station_years_annual_prcp_subquery`.`starrocks_station_years__id` = CONCAT(`starrocks_station_years`.station_id, '|', CAST(`starrocks_station_years`.year AS VARCHAR))))
GROUP BY 1
ORDER BY  1  ASC
LIMIT 10000
;

-- @Cube_Q9
 WITH 
cte_0 AS (  SELECT `starrocks_stations`.country_code `starrocks_weather__country`, sum(CAST(`starrocks_weather_daily`.prcp AS DOUBLE)) `starrocks_weather_daily__total_prcp` 
  FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
  LEFT JOIN  lakehouse.trino_gold.dim_station  AS `starrocks_stations` ON `starrocks_weather_daily`.station_id = `starrocks_stations`.station_id
  WHERE (`starrocks_weather_daily`.date >= TIMESTAMP(convert_tz('2025-01-01T00:00:00.000', '+00:00', @@session.time_zone)) AND `starrocks_weather_daily`.date <= TIMESTAMP(convert_tz('2025-12-31T23:59:59.999', '+00:00', @@session.time_zone)))
  GROUP BY 1
  ORDER BY  2  DESC),
cte_1 AS (  SELECT `fk_aggregate`.`starrocks_weather__country` `starrocks_weather__country`, sum(sum(`fk_aggregate`.`starrocks_weather_daily__total_prcp`)) OVER () `starrocks_weather_daily__total_prcp_all` 
  FROM  cte_0  AS `fk_aggregate`
  GROUP BY 1
  ORDER BY  2  DESC),
cte_2 AS (  SELECT `fk_aggregate_keys`.`starrocks_weather__country` `starrocks_weather__country`, `q_0`.`starrocks_weather_daily__total_prcp` / NULLIF(`q_1`.`starrocks_weather_daily__total_prcp_all`, 0) `starrocks_weather_daily__prcp_share_of_total` 
  FROM (SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country` 
  FROM (SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country` 
  FROM  cte_0  AS `cte_0`
   UNION ALL 
  SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country` 
  FROM  cte_1  AS `cte_1`) AS `fk_aggregate_keys_source`) AS `fk_aggregate_keys`
  LEFT JOIN  cte_0  AS `q_0` ON ((`fk_aggregate_keys`.`starrocks_weather__country` = `q_0`.`starrocks_weather__country` OR ((`fk_aggregate_keys`.`starrocks_weather__country` IS NULL) AND (`q_0`.`starrocks_weather__country` IS NULL))))
  LEFT JOIN  cte_1  AS `q_1` ON ((`fk_aggregate_keys`.`starrocks_weather__country` = `q_1`.`starrocks_weather__country` OR ((`fk_aggregate_keys`.`starrocks_weather__country` IS NULL) AND (`q_1`.`starrocks_weather__country` IS NULL))))),
cte_3 AS (  SELECT `starrocks_stations`.country_code `starrocks_weather__country`, sum(CAST(`starrocks_weather_daily`.prcp AS DOUBLE)) `starrocks_weather_daily__total_prcp` 
  FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
  LEFT JOIN  lakehouse.trino_gold.dim_station  AS `starrocks_stations` ON `starrocks_weather_daily`.station_id = `starrocks_stations`.station_id
  WHERE (`starrocks_weather_daily`.date >= TIMESTAMP(convert_tz('2025-01-01T00:00:00.000', '+00:00', @@session.time_zone)) AND `starrocks_weather_daily`.date <= TIMESTAMP(convert_tz('2025-12-31T23:59:59.999', '+00:00', @@session.time_zone)))
  GROUP BY 1)
SELECT `fk_aggregate_keys`.`starrocks_weather__country` `starrocks_weather__country`, `q_1`.`starrocks_weather_daily__total_prcp` `starrocks_weather__total_prcp`, `q_0`.`starrocks_weather_daily__prcp_share_of_total` `starrocks_weather__prcp_share_of_total` 
FROM (SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country` 
FROM (SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country` 
FROM  cte_2  AS `cte_2`
 UNION ALL 
SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country` 
FROM  cte_3  AS `cte_3`) AS `fk_aggregate_keys_source`) AS `fk_aggregate_keys`
LEFT JOIN  cte_2  AS `q_0` ON ((`fk_aggregate_keys`.`starrocks_weather__country` = `q_0`.`starrocks_weather__country` OR ((`fk_aggregate_keys`.`starrocks_weather__country` IS NULL) AND (`q_0`.`starrocks_weather__country` IS NULL))))
LEFT JOIN  cte_3  AS `q_1` ON ((`fk_aggregate_keys`.`starrocks_weather__country` = `q_1`.`starrocks_weather__country` OR ((`fk_aggregate_keys`.`starrocks_weather__country` IS NULL) AND (`q_1`.`starrocks_weather__country` IS NULL))))
ORDER BY  3  DESC
LIMIT 50000
;

-- @Cube_Q10
 WITH 
cte_0 AS (  SELECT `starrocks_stations`.country_code `starrocks_weather__country`, CAST(DATE_FORMAT(CONVERT_TZ((DATE_ADD(`starrocks_weather_daily`.date, INTERVAL 1 YEAR)), @@session.time_zone, '+00:00'), '%Y-%m-01T00:00:00.000') AS DATETIME) `starrocks_weather__date_month`, avg(CAST(`starrocks_weather_daily`.tmax AS DOUBLE)) `starrocks_weather_daily__avg_tmax` 
  FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
  LEFT JOIN  lakehouse.trino_gold.dim_station  AS `starrocks_stations` ON `starrocks_weather_daily`.station_id = `starrocks_stations`.station_id
  WHERE ((DATE_ADD(`starrocks_weather_daily`.date, INTERVAL 1 YEAR)) >= TIMESTAMP(convert_tz('2025-01-01T00:00:00.000', '+00:00', @@session.time_zone)) AND (DATE_ADD(`starrocks_weather_daily`.date, INTERVAL 1 YEAR)) <= TIMESTAMP(convert_tz('2025-12-31T23:59:59.999', '+00:00', @@session.time_zone)))
  GROUP BY 1, 2
  ORDER BY  2  ASC),
cte_1 AS (  SELECT `fk_aggregate`.`starrocks_weather__country` `starrocks_weather__country`, `fk_aggregate`.`starrocks_weather__date_month` `starrocks_weather__date_month`, `fk_aggregate`.`starrocks_weather_daily__avg_tmax` `starrocks_weather_daily__avg_tmax_prior_year` 
  FROM  cte_0  AS `fk_aggregate`),
cte_2 AS (  SELECT `starrocks_stations`.country_code `starrocks_weather__country`, CAST(DATE_FORMAT(CONVERT_TZ(`starrocks_weather_daily`.date, @@session.time_zone, '+00:00'), '%Y-%m-01T00:00:00.000') AS DATETIME) `starrocks_weather__date_month`, avg(CAST(`starrocks_weather_daily`.tmax AS DOUBLE)) `starrocks_weather_daily__avg_tmax` 
  FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
  LEFT JOIN  lakehouse.trino_gold.dim_station  AS `starrocks_stations` ON `starrocks_weather_daily`.station_id = `starrocks_stations`.station_id
  WHERE (`starrocks_weather_daily`.date >= TIMESTAMP(convert_tz('2025-01-01T00:00:00.000', '+00:00', @@session.time_zone)) AND `starrocks_weather_daily`.date <= TIMESTAMP(convert_tz('2025-12-31T23:59:59.999', '+00:00', @@session.time_zone)))
  GROUP BY 1, 2
  ORDER BY  2  ASC),
cte_3 AS (  SELECT `fk_aggregate_keys`.`starrocks_weather__country` `starrocks_weather__country`, `fk_aggregate_keys`.`starrocks_weather__date_month` `starrocks_weather__date_month`, `q_0`.`starrocks_weather_daily__avg_tmax` - `q_1`.`starrocks_weather_daily__avg_tmax_prior_year` `starrocks_weather_daily__tmax_yoy_delta` 
  FROM (SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country`, `starrocks_weather__date_month` `starrocks_weather__date_month` 
  FROM (SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country`, `starrocks_weather__date_month` `starrocks_weather__date_month` 
  FROM  cte_2  AS `cte_2`
   UNION ALL 
  SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country`, `starrocks_weather__date_month` `starrocks_weather__date_month` 
  FROM  cte_1  AS `cte_1`) AS `fk_aggregate_keys_source`) AS `fk_aggregate_keys`
  LEFT JOIN  cte_2  AS `q_0` ON ((`fk_aggregate_keys`.`starrocks_weather__country` = `q_0`.`starrocks_weather__country` OR ((`fk_aggregate_keys`.`starrocks_weather__country` IS NULL) AND (`q_0`.`starrocks_weather__country` IS NULL)))) AND ((`fk_aggregate_keys`.`starrocks_weather__date_month` = `q_0`.`starrocks_weather__date_month` OR ((`fk_aggregate_keys`.`starrocks_weather__date_month` IS NULL) AND (`q_0`.`starrocks_weather__date_month` IS NULL))))
  LEFT JOIN  cte_1  AS `q_1` ON ((`fk_aggregate_keys`.`starrocks_weather__country` = `q_1`.`starrocks_weather__country` OR ((`fk_aggregate_keys`.`starrocks_weather__country` IS NULL) AND (`q_1`.`starrocks_weather__country` IS NULL)))) AND ((`fk_aggregate_keys`.`starrocks_weather__date_month` = `q_1`.`starrocks_weather__date_month` OR ((`fk_aggregate_keys`.`starrocks_weather__date_month` IS NULL) AND (`q_1`.`starrocks_weather__date_month` IS NULL))))),
cte_4 AS (  SELECT `starrocks_stations`.country_code `starrocks_weather__country`, CAST(DATE_FORMAT(CONVERT_TZ(`starrocks_weather_daily`.date, @@session.time_zone, '+00:00'), '%Y-%m-01T00:00:00.000') AS DATETIME) `starrocks_weather__date_month`, avg(CAST(`starrocks_weather_daily`.tmax AS DOUBLE)) `starrocks_weather_daily__avg_tmax` 
  FROM  lakehouse.trino_gold.fct_weather_daily  AS `starrocks_weather_daily`
  LEFT JOIN  lakehouse.trino_gold.dim_station  AS `starrocks_stations` ON `starrocks_weather_daily`.station_id = `starrocks_stations`.station_id
  WHERE (`starrocks_weather_daily`.date >= TIMESTAMP(convert_tz('2025-01-01T00:00:00.000', '+00:00', @@session.time_zone)) AND `starrocks_weather_daily`.date <= TIMESTAMP(convert_tz('2025-12-31T23:59:59.999', '+00:00', @@session.time_zone)))
  GROUP BY 1, 2)
SELECT `fk_aggregate_keys`.`starrocks_weather__country` `starrocks_weather__country`, `fk_aggregate_keys`.`starrocks_weather__date_month` `starrocks_weather__date_month`, `q_2`.`starrocks_weather_daily__avg_tmax` `starrocks_weather__avg_tmax`, `q_0`.`starrocks_weather_daily__avg_tmax_prior_year` `starrocks_weather__avg_tmax_prior_year`, `q_1`.`starrocks_weather_daily__tmax_yoy_delta` `starrocks_weather__tmax_yoy_delta` 
FROM (SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country`, `starrocks_weather__date_month` `starrocks_weather__date_month` 
FROM (SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country`, `starrocks_weather__date_month` `starrocks_weather__date_month` 
FROM  cte_1  AS `cte_1`
 UNION ALL 
SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country`, `starrocks_weather__date_month` `starrocks_weather__date_month` 
FROM  cte_3  AS `cte_3`
 UNION ALL 
SELECT DISTINCT `starrocks_weather__country` `starrocks_weather__country`, `starrocks_weather__date_month` `starrocks_weather__date_month` 
FROM  cte_4  AS `cte_4`) AS `fk_aggregate_keys_source`) AS `fk_aggregate_keys`
LEFT JOIN  cte_1  AS `q_0` ON ((`fk_aggregate_keys`.`starrocks_weather__country` = `q_0`.`starrocks_weather__country` OR ((`fk_aggregate_keys`.`starrocks_weather__country` IS NULL) AND (`q_0`.`starrocks_weather__country` IS NULL)))) AND ((`fk_aggregate_keys`.`starrocks_weather__date_month` = `q_0`.`starrocks_weather__date_month` OR ((`fk_aggregate_keys`.`starrocks_weather__date_month` IS NULL) AND (`q_0`.`starrocks_weather__date_month` IS NULL))))
LEFT JOIN  cte_3  AS `q_1` ON ((`fk_aggregate_keys`.`starrocks_weather__country` = `q_1`.`starrocks_weather__country` OR ((`fk_aggregate_keys`.`starrocks_weather__country` IS NULL) AND (`q_1`.`starrocks_weather__country` IS NULL)))) AND ((`fk_aggregate_keys`.`starrocks_weather__date_month` = `q_1`.`starrocks_weather__date_month` OR ((`fk_aggregate_keys`.`starrocks_weather__date_month` IS NULL) AND (`q_1`.`starrocks_weather__date_month` IS NULL))))
LEFT JOIN  cte_4  AS `q_2` ON ((`fk_aggregate_keys`.`starrocks_weather__country` = `q_2`.`starrocks_weather__country` OR ((`fk_aggregate_keys`.`starrocks_weather__country` IS NULL) AND (`q_2`.`starrocks_weather__country` IS NULL)))) AND ((`fk_aggregate_keys`.`starrocks_weather__date_month` = `q_2`.`starrocks_weather__date_month` OR ((`fk_aggregate_keys`.`starrocks_weather__date_month` IS NULL) AND (`q_2`.`starrocks_weather__date_month` IS NULL))))
ORDER BY  1  ASC,  2  ASC
LIMIT 50000
;


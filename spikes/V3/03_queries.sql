-- Cube-like queries, one block per "-- @name" marker (run.sh runs EXPLAIN on each).
-- Each EXPLAIN must contain "mv_weather_wide" in the scan TABLE line (except the Q4 control).

-- @Q1_two_tables
-- Observation count per year: fact + dim_date, a SUBSET of the MV's tables (View Delta Join).
SELECT d.year, count(*) AS observation_count
FROM lakehouse.trino_gold.fct_weather_daily AS f
LEFT JOIN lakehouse.trino_gold.dim_date AS d ON f.date = d.date
GROUP BY d.year;

-- @Q1_three_tables
-- Same question with all three tables joined (exact SPJG match with the MV).
SELECT d.year, count(*) AS observation_count
FROM lakehouse.trino_gold.fct_weather_daily AS f
LEFT JOIN lakehouse.trino_gold.dim_station AS s ON f.station_id = s.station_id
LEFT JOIN lakehouse.trino_gold.dim_date AS d ON f.date = d.date
GROUP BY d.year;

-- @Q2
-- Average tmax per country and month, one year.
SELECT s.country_code, date_trunc('month', f.date) AS month_start, avg(CAST(f.tmax AS DOUBLE)) AS avg_tmax
FROM lakehouse.trino_gold.fct_weather_daily AS f
LEFT JOIN lakehouse.trino_gold.dim_station AS s ON f.station_id = s.station_id
LEFT JOIN lakehouse.trino_gold.dim_date AS d ON f.date = d.date
WHERE f.date >= '2024-01-01' AND f.date < '2025-01-01'
GROUP BY s.country_code, date_trunc('month', f.date);

-- @Q3_with_station
-- Top 20 stations by total precipitation, one year (fact + station).
SELECT f.station_id, sum(CAST(f.prcp AS DOUBLE)) AS total_prcp
FROM lakehouse.trino_gold.fct_weather_daily AS f
LEFT JOIN lakehouse.trino_gold.dim_station AS s ON f.station_id = s.station_id
WHERE f.date >= '2024-01-01' AND f.date < '2025-01-01'
GROUP BY f.station_id
ORDER BY total_prcp DESC
LIMIT 20;

-- @Q3_fact_only
-- Single-table form (what Cube emits when no station/date dimension is requested).
SELECT f.station_id, sum(CAST(f.prcp AS DOUBLE)) AS total_prcp
FROM lakehouse.trino_gold.fct_weather_daily AS f
WHERE f.date >= '2024-01-01' AND f.date < '2025-01-01'
GROUP BY f.station_id
ORDER BY total_prcp DESC
LIMIT 20;

-- @Q4_control
-- Bounding-box join, non-aggregate; informational.
SELECT f.station_id, f.date, f.tmax
FROM lakehouse.trino_gold.fct_weather_daily AS f
JOIN lakehouse.trino_gold.dim_station AS s ON f.station_id = s.station_id
WHERE s.latitude BETWEEN 38 AND 42 AND s.longitude BETWEEN -80 AND -70;

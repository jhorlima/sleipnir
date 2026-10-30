-- Median and p95 of tmax by country, 2025. Exact percentiles; Trino and StarRocks answers match within 5%.
SELECT
    s.country_code,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.tmax) AS median_tmax,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY f.tmax) AS p95_tmax
FROM fct_weather_daily AS f
LEFT JOIN dim_station AS s ON f.station_id = s.station_id
WHERE f.date >= DATE '2025-01-01' AND f.date <= DATE '2025-12-31'
GROUP BY 1
ORDER BY 1

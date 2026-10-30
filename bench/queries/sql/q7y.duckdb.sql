-- Q7 with granularity year (the shape a Cube rollup can serve): one extra date column.
SELECT
    s.country_code,
    CAST(date_trunc('year', f.date) AS DATE) AS year_start,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.tmax) AS median_tmax,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY f.tmax) AS p95_tmax
FROM fct_weather_daily AS f
LEFT JOIN dim_station AS s ON f.station_id = s.station_id
WHERE f.date >= DATE '2025-01-01' AND f.date <= DATE '2025-12-31'
GROUP BY 1, 2
ORDER BY 1

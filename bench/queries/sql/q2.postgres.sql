SELECT
    s.country_code,
    CAST(date_trunc('month', f.date) AS DATE) AS month_start,
    avg(CAST(f.tmax AS DOUBLE PRECISION)) AS avg_tmax
FROM fct_weather_daily AS f
LEFT JOIN dim_station AS s ON f.station_id = s.station_id
WHERE f.date >= DATE '2025-01-01' AND f.date <= DATE '2025-12-31'
GROUP BY 1, 2
ORDER BY 1, 2

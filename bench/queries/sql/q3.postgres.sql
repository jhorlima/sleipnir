SELECT
    f.station_id,
    sum(CAST(f.prcp AS DOUBLE PRECISION)) AS total_prcp
FROM fct_weather_daily AS f
WHERE f.date >= DATE '2025-01-01' AND f.date <= DATE '2025-12-31'
GROUP BY 1
HAVING sum(CAST(f.prcp AS DOUBLE PRECISION)) IS NOT NULL
ORDER BY total_prcp DESC, f.station_id ASC
LIMIT 20

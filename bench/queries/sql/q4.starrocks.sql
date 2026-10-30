SELECT
    s.country_code,
    count(*) AS observation_count,
    avg(CAST(f.tmax AS DOUBLE)) AS avg_tmax
FROM fct_weather_daily AS f
JOIN dim_station AS s ON f.station_id = s.station_id
WHERE f.date >= '2025-01-01' AND f.date <= '2025-12-31'
  AND s.latitude BETWEEN 36 AND 44
  AND s.longitude BETWEEN -10 AND 4
GROUP BY 1
ORDER BY 1

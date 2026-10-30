SELECT
    f.station_id,
    f.date,
    CAST(f.tmax AS DOUBLE) AS tmax,
    CAST(f.tmin AS DOUBLE) AS tmin,
    CAST(f.prcp AS DOUBLE) AS prcp
FROM fct_weather_daily AS f
WHERE f.station_id = 'USW00094728'
  AND f.date BETWEEN DATE '2025-06-01' AND DATE '2025-06-30'
ORDER BY f.date

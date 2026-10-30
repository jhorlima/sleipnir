-- Trailing 7 calendar days (the day and the 6 before it), for the days that have an observation.
SELECT
    f.station_id,
    f.date,
    avg(CAST(w.tmax AS DOUBLE)) AS avg_tmax_7d
FROM fct_weather_daily AS f
JOIN fct_weather_daily AS w
    ON w.station_id = f.station_id
    AND w.date BETWEEN date_sub(f.date, INTERVAL 6 DAY) AND f.date
WHERE f.station_id IN ('USW00094728', 'USW00023174', 'GME00127786', 'SPE00120278')
  AND w.station_id IN ('USW00094728', 'USW00023174', 'GME00127786', 'SPE00120278')
  AND f.date BETWEEN '2025-01-01' AND '2025-03-31'
GROUP BY 1, 2
ORDER BY 1, 2

SELECT
    CAST(date_trunc('year', f.date) AS DATE) AS year_start,
    count(*) AS observation_count
FROM fct_weather_daily AS f
GROUP BY 1
ORDER BY 1

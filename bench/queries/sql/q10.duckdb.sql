-- Average tmax by country and month in 2025, the same month a year earlier, and the change.
-- A month present only a year earlier is also a row (the shifted stage of Cube's time_shift), with an empty avg_tmax.
WITH monthly_avg_tmax AS (
    SELECT
        s.country_code,
        CAST(date_trunc('month', f.date) AS DATE) AS month_start,
        avg(CAST(f.tmax AS DOUBLE)) AS avg_tmax
    FROM fct_weather_daily AS f
    LEFT JOIN dim_station AS s ON f.station_id = s.station_id
    WHERE f.date >= DATE '2024-01-01' AND f.date <= DATE '2025-12-31'
    GROUP BY 1, 2
),
current_year AS (
    SELECT country_code, month_start, avg_tmax
    FROM monthly_avg_tmax
    WHERE month_start >= DATE '2025-01-01'
),
prior_year AS (
    SELECT country_code, month_start + INTERVAL 1 YEAR AS month_start, avg_tmax
    FROM monthly_avg_tmax
    WHERE month_start < DATE '2025-01-01'
)
SELECT
    coalesce(current_year.country_code, prior_year.country_code) AS country_code,
    CAST(coalesce(current_year.month_start, prior_year.month_start) AS DATE) AS month_start,
    current_year.avg_tmax,
    prior_year.avg_tmax AS avg_tmax_prior_year,
    current_year.avg_tmax - prior_year.avg_tmax AS tmax_yoy_delta
FROM current_year
FULL OUTER JOIN prior_year
    ON prior_year.country_code IS NOT DISTINCT FROM current_year.country_code
    AND prior_year.month_start = current_year.month_start
ORDER BY 1, 2

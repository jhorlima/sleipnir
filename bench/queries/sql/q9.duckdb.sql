-- Precipitation by country and its share of the total, 2025.
WITH country_totals AS (
    SELECT
        s.country_code,
        sum(CAST(f.prcp AS DOUBLE)) AS total_prcp
    FROM fct_weather_daily AS f
    LEFT JOIN dim_station AS s ON f.station_id = s.station_id
    WHERE f.date >= DATE '2025-01-01' AND f.date <= DATE '2025-12-31'
    GROUP BY 1
)
SELECT
    country_code,
    total_prcp,
    total_prcp / NULLIF(sum(total_prcp) OVER (), 0) AS prcp_share_of_total
FROM country_totals
ORDER BY prcp_share_of_total DESC, country_code

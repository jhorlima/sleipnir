-- Median across stations of the annual precipitation, per year. Stations without precipitation in a year are skipped.
WITH station_years AS (
    SELECT station.station_id, years.year
    FROM dim_station AS station
    CROSS JOIN (SELECT DISTINCT year FROM dim_date) AS years
),
annual_precipitation AS (
    SELECT
        station_years.year,
        sum(CAST(f.prcp AS DOUBLE)) AS annual_prcp
    FROM station_years
    LEFT JOIN fct_weather_daily AS f
        ON f.station_id = station_years.station_id
        AND station_years.year = EXTRACT(YEAR FROM f.date)
    GROUP BY station_years.station_id, station_years.year
)
SELECT
    year,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY annual_prcp) AS median_station_annual_prcp
FROM annual_precipitation
GROUP BY year
ORDER BY year

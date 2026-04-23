-- Model: temp_anomaly
-- Description: Calculates the temperature anomaly for each city and date.
--              Anomaly = actual TEMP_MAX minus the city's overall average TEMP_MAX.
--              Positive values = hotter than normal. Negative = cooler than normal.

{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT
        CITY,
        DATE,
        TEMP_MAX,
        TEMP_MIN,
        TEMP_MEAN
    FROM {{ source('raw', 'city_weather') }}
    WHERE TEMP_MAX IS NOT NULL
),

city_averages AS (
    SELECT
        CITY,
        ROUND(AVG(TEMP_MAX), 2)  AS AVG_TEMP_MAX,
        ROUND(AVG(TEMP_MIN), 2)  AS AVG_TEMP_MIN,
        ROUND(AVG(TEMP_MEAN), 2) AS AVG_TEMP_MEAN
    FROM source
    GROUP BY CITY
)

SELECT
    s.CITY,
    s.DATE,
    s.TEMP_MAX,
    s.TEMP_MIN,
    s.TEMP_MEAN,
    ca.AVG_TEMP_MAX,
    ca.AVG_TEMP_MIN,
    ca.AVG_TEMP_MEAN,

    -- Anomaly: how much warmer/cooler than the city's historical average
    ROUND(s.TEMP_MAX  - ca.AVG_TEMP_MAX,  2) AS TEMP_MAX_ANOMALY,
    ROUND(s.TEMP_MIN  - ca.AVG_TEMP_MIN,  2) AS TEMP_MIN_ANOMALY,
    ROUND(s.TEMP_MEAN - ca.AVG_TEMP_MEAN, 2) AS TEMP_MEAN_ANOMALY,

    -- Label for easy dashboard filtering
    CASE
        WHEN (s.TEMP_MAX - ca.AVG_TEMP_MAX) > 2  THEN 'Above Normal'
        WHEN (s.TEMP_MAX - ca.AVG_TEMP_MAX) < -2 THEN 'Below Normal'
        ELSE 'Near Normal'
    END AS ANOMALY_CATEGORY

FROM source s
JOIN city_averages ca
  ON s.CITY = ca.CITY
ORDER BY s.CITY, s.DATE

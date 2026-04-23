-- Model: moving_avg
-- Description: Calculates 7-day rolling averages of TEMP_MAX, TEMP_MIN, and TEMP_MEAN
--              for each city, ordered by date. This smooths out daily fluctuations
--              and reveals underlying temperature trends.

{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT
        CITY,
        DATE,
        TEMP_MAX,
        TEMP_MIN,
        TEMP_MEAN,
        PRECIPITATION_MM,
        WIND_SPEED_MAX_KMH
    FROM {{ source('raw', 'city_weather') }}
    WHERE TEMP_MAX IS NOT NULL
      AND TEMP_MIN IS NOT NULL
      AND TEMP_MEAN IS NOT NULL
)

SELECT
    CITY,
    DATE,
    TEMP_MAX,
    TEMP_MIN,
    TEMP_MEAN,
    PRECIPITATION_MM,
    WIND_SPEED_MAX_KMH,

    -- 7-day rolling average of max temperature
    ROUND(
        AVG(TEMP_MAX) OVER (
            PARTITION BY CITY
            ORDER BY DATE
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) AS TEMP_MAX_7DAY_AVG,

    -- 7-day rolling average of min temperature
    ROUND(
        AVG(TEMP_MIN) OVER (
            PARTITION BY CITY
            ORDER BY DATE
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) AS TEMP_MIN_7DAY_AVG,

    -- 7-day rolling average of mean temperature
    ROUND(
        AVG(TEMP_MEAN) OVER (
            PARTITION BY CITY
            ORDER BY DATE
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) AS TEMP_MEAN_7DAY_AVG,

    -- Number of days included in the rolling window (may be < 7 at the start)
    COUNT(*) OVER (
        PARTITION BY CITY
        ORDER BY DATE
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS ROLLING_WINDOW_DAYS

FROM source
ORDER BY CITY, DATE

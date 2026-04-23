-- Model: rolling_precip
-- Description: Calculates a 7-day rolling sum of precipitation for each city.
--              Also includes a daily rain indicator and cumulative rain count
--              to help identify wet vs dry periods.

{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT
        CITY,
        DATE,
        PRECIPITATION_MM,
        TEMP_MAX,
        TEMP_MIN,
        WEATHER_CODE
    FROM {{ source('raw', 'city_weather') }}
    WHERE PRECIPITATION_MM IS NOT NULL
)

SELECT
    CITY,
    DATE,
    PRECIPITATION_MM,
    TEMP_MAX,
    TEMP_MIN,
    WEATHER_CODE,

    -- 1 if it rained that day, 0 otherwise
    CASE WHEN PRECIPITATION_MM > 0 THEN 1 ELSE 0 END AS IS_RAIN_DAY,

    -- 7-day rolling total precipitation
    ROUND(
        SUM(PRECIPITATION_MM) OVER (
            PARTITION BY CITY
            ORDER BY DATE
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) AS PRECIP_7DAY_ROLLING_SUM,

    -- 7-day rolling count of rainy days
    SUM(CASE WHEN PRECIPITATION_MM > 0 THEN 1 ELSE 0 END) OVER (
        PARTITION BY CITY
        ORDER BY DATE
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS RAIN_DAYS_LAST_7,

    -- 30-day rolling total precipitation
    ROUND(
        SUM(PRECIPITATION_MM) OVER (
            PARTITION BY CITY
            ORDER BY DATE
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ), 2
    ) AS PRECIP_30DAY_ROLLING_SUM,

    -- Wet/dry period label based on 7-day rolling sum
    CASE
        WHEN SUM(PRECIPITATION_MM) OVER (
            PARTITION BY CITY
            ORDER BY DATE
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) > 25 THEN 'Wet Period'
        WHEN SUM(PRECIPITATION_MM) OVER (
            PARTITION BY CITY
            ORDER BY DATE
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) = 0 THEN 'Dry Period'
        ELSE 'Normal Period'
    END AS PERIOD_LABEL

FROM source
ORDER BY CITY, DATE

-- Model: dry_spell
-- Description: Calculates consecutive dry days (precipitation = 0) for each city.
--              The counter resets to 0 on any day with precipitation > 0.
--              Uses Snowflake's CONDITIONAL_TRUE_EVENT to group dry streaks,
--              then counts days within each streak group.

{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT
        CITY,
        DATE,
        PRECIPITATION_MM,
        TEMP_MAX,
        WEATHER_CODE
    FROM {{ source('raw', 'city_weather') }}
    WHERE PRECIPITATION_MM IS NOT NULL
),

-- Flag each row: 1 = rain day (streak break), 0 = dry day
rain_flags AS (
    SELECT
        CITY,
        DATE,
        PRECIPITATION_MM,
        TEMP_MAX,
        WEATHER_CODE,
        CASE WHEN PRECIPITATION_MM > 0 THEN 1 ELSE 0 END AS IS_RAIN_DAY
    FROM source
),

-- Assign a streak group number: increments each time a rain day occurs
streak_groups AS (
    SELECT
        CITY,
        DATE,
        PRECIPITATION_MM,
        TEMP_MAX,
        WEATHER_CODE,
        IS_RAIN_DAY,
        -- Each rain day starts a new group; dry days stay in the same group
        SUM(IS_RAIN_DAY) OVER (
            PARTITION BY CITY
            ORDER BY DATE
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS STREAK_GROUP
    FROM rain_flags
),

-- Count consecutive dry days within each streak group
dry_spell_counts AS (
    SELECT
        CITY,
        DATE,
        PRECIPITATION_MM,
        TEMP_MAX,
        WEATHER_CODE,
        IS_RAIN_DAY,
        STREAK_GROUP,
        -- Count dry days within this streak group; rain days get 0
        CASE
            WHEN IS_RAIN_DAY = 1 THEN 0
            ELSE ROW_NUMBER() OVER (
                PARTITION BY CITY, STREAK_GROUP
                ORDER BY DATE
            )
        END AS DRY_SPELL_DAYS
    FROM streak_groups
)

SELECT
    CITY,
    DATE,
    PRECIPITATION_MM,
    TEMP_MAX,
    WEATHER_CODE,
    IS_RAIN_DAY,
    DRY_SPELL_DAYS,

    -- Human-readable label
    CASE
        WHEN IS_RAIN_DAY = 1        THEN 'Rain Day'
        WHEN DRY_SPELL_DAYS >= 7   THEN 'Extended Dry Spell (7+ days)'
        WHEN DRY_SPELL_DAYS >= 3   THEN 'Short Dry Spell (3-6 days)'
        WHEN DRY_SPELL_DAYS >= 1   THEN 'Dry (1-2 days)'
        ELSE 'Rain Day'
    END AS DRY_SPELL_LABEL,

    -- Maximum dry spell length achieved so far for each city (running max)
    MAX(DRY_SPELL_DAYS) OVER (
        PARTITION BY CITY
        ORDER BY DATE
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS MAX_DRY_SPELL_SO_FAR

FROM dry_spell_counts
ORDER BY CITY, DATE

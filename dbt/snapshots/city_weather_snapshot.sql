-- Snapshot: city_weather_snapshot
-- Description: Captures the state of RAW.CITY_WEATHER daily.
--              Uses the 'timestamp' strategy — if a row's TEMP_MAX changes
--              (e.g., the API corrects a historical value), the snapshot records
--              both the old and new value with valid_from / valid_to timestamps.
--              This enables historical auditing of data corrections.

{% snapshot city_weather_snapshot %}

{{
    config(
        target_schema='DBT',
        unique_key='CITY || \'_\' || DATE',
        strategy='timestamp',
        updated_at='DATE',
        invalidate_hard_deletes=True
    )
}}

SELECT
    CITY,
    DATE,
    LATITUDE,
    LONGITUDE,
    TEMP_MAX,
    TEMP_MIN,
    TEMP_MEAN,
    PRECIPITATION_MM,
    WIND_SPEED_MAX_KMH,
    WEATHER_CODE
FROM {{ source('raw', 'city_weather') }}

{% endsnapshot %}

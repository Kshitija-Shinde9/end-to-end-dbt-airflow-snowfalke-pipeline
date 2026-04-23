# Weather Analytics Lab 2 — End-to-End ELT Pipeline
### Powered by Snowflake · Apache Airflow · dbt · Preset · Open-Meteo API

---

## Table of Contents
- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Cities Tracked](#cities-tracked)
- [Project Structure](#project-structure)
- [Pipeline 1 — Weather ETL DAG](#pipeline-1----weather-etl-dag)
- [Pipeline 2 — TrainPredict DAG](#pipeline-2----trainpredict-dag)
- [Pipeline 3 — WeatherData DBT DAG](#pipeline-3----weatherdata-dbt-dag)
- [dbt Models](#dbt-models)
- [dbt Tests & Snapshot](#dbt-tests--snapshot)
- [Snowflake Schema & Tables](#snowflake-schema--tables)
- [Airflow Setup](#airflow-setup)
- [Preset Dashboard](#preset-dashboard)
- [Lessons Learned](#lessons-learned)

---

## Overview

This project builds a **fully automated end-to-end weather analytics pipeline** using the ELT pattern:

It ingests 60 days of real historical weather data from four US cities into Snowflake, uses **dbt** to run analytical transformations on the raw data (moving averages, temperature anomalies, rolling precipitation, and dry spell tracking), schedules all dbt work through **Apache Airflow**, and visualises the insights in a live **Preset dashboard** — all running on a fully automated daily schedule.

A bonus **ML forecasting pipeline** also runs daily, training a native Snowflake ML model and generating a 7-day temperature forecast per city.

Three DAGs handle the three stages of work in sequence:
- **02:30 UTC** — ETL: fetch and load raw weather data into Snowflake
- **03:30 UTC** — TrainPredict: train Snowflake ML model and generate 7-day forecast
- **04:30 UTC** — WeatherData_DBT: run dbt models, tests, and snapshots on the raw data

---

## System Architecture

<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/4492b0ab-6128-4f8f-bfcc-c2bf3c122180" />

> **Architecture Overview:**
> Open-Meteo API → Airflow ETL (4 parallel city pipelines) → Snowflake RAW.CITY_WEATHER → Airflow ML Forecast (TrainPredict) → Snowflake ANALYTICS (FINAL + METRICS) → Airflow dbt ELT (models, tests, snapshot) → Snowflake DBT Schema → Preset Dashboard
---

## Cities Tracked

| City | Latitude | Longitude | State |
|------|----------|-----------|-------|
| Miami | 25.7617 | -80.1918 | Florida |
| Newport Beach | 33.6189 | -117.9289 | California |
| Seattle | 47.6062 | -122.3321 | Washington |
| Boston | 42.3601 | -71.0589 | Massachusetts |

---

## Project Structure

```
weather-forecasting-airflow-snowflake/
│
├── README.md
│
├── dags/
│   ├── weather_etl_pipeline.py     # DAG 1 — ETL: extract, transform, load
│   ├── weather_prediction.py       # DAG 2 — ML: train model, generate forecast
│   └── weather_dbt_dag.py          # DAG 3 — ELT: dbt run, test, snapshot
│
└── dbt/
    ├── dbt_project.yml             # dbt project config
    ├── profiles.yml                # Snowflake connection via env vars
    ├── models/
    │   ├── sources.yml             # Source table definition (RAW.CITY_WEATHER)
    │   ├── schema.yml              # All model tests (30 tests total)
    │   ├── moving_avg.sql          # 7-day rolling temperature averages
    │   ├── temp_anomaly.sql        # Deviation from city historical average
    │   ├── rolling_precip.sql      # 7-day and 30-day rolling precipitation
    │   └── dry_spell.sql           # Consecutive dry day counter
    └── snapshots/
        └── city_weather_snapshot.sql  # SCD snapshot of RAW.CITY_WEATHER
```

---

## Pipeline 1 — Weather ETL DAG

**DAG ID:** `WeatherData_ETL`
**Schedule:** `30 2 * * *` (Daily at 02:30 UTC)
**File:** `dags/weather_etl_pipeline.py`

<img width="1246" height="372" alt="image" src="https://github.com/user-attachments/assets/9397b0cc-c5ff-4dd4-bf44-9857c2d0cb99" />

### How It Works

The ETL pipeline runs **4 parallel city pipelines**, each consisting of 3 tasks:

```
extract  →  transform  →  load
```
<img width="1248" height="690" alt="image" src="https://github.com/user-attachments/assets/b187b6ce-3d8f-4290-b4eb-4eda9ee7830f" />

### Task Breakdown

#### 1. `extract(latitude, longitude)`
- Calls the **Open-Meteo Forecast API**
- Fetches **past 60 days** of daily weather data per city
- Collects: `temp_max`, `temp_min`, `temp_mean`, `precipitation_sum`, `wind_speed_max`, `weather_code`

```python
params = {
    "latitude": latitude,
    "longitude": longitude,
    "past_days": 60,
    "forecast_days": 0,
    "daily": ["temperature_2m_max", "temperature_2m_min", "temperature_2m_mean",
              "precipitation_sum", "windspeed_10m_max", "weathercode"],
    "timezone": "America/Los_Angeles"
}
```

#### 2. `transform(raw_data, latitude, longitude, city)`
- Flattens the nested API JSON response
- Converts data into a list of tuples, one row per day
- Returns clean records ready for loading

#### 3. `load(records, target_table)`
- Creates a **temp staging table** and inserts records into it
- Runs a **MERGE (UPSERT)** against `RAW.CITY_WEATHER` — prevents duplicates on re-runs
- Wrapped in **SQL transaction** with `BEGIN / COMMIT / ROLLBACK` inside `try/except` for full idempotency

```sql
MERGE INTO RAW.CITY_WEATHER t
USING CITY_WEATHER_STAGE s
ON t.CITY = s.CITY AND t.DATE = s.DATE
WHEN MATCHED THEN UPDATE SET
    TEMP_MAX = s.TEMP_MAX,
    TEMP_MIN = s.TEMP_MIN,
WHEN NOT MATCHED THEN INSERT (
    CITY, LATITUDE, LONGITUDE, DATE, TEMP_MAX, TEMP_MIN, TEMP_MEAN,
    PRECIPITATION_MM, WIND_SPEED_MAX_KMH, WEATHER_CODE
)
VALUES (s.CITY, s.LATITUDE)
```

### Airflow Connections & Variables Used

Snowflake credentials are stored in an **Airflow Connection** (`snowflake_conn`) — no hardcoded passwords.


City configurations are stored as an **Airflow Variable** (JSON):

```json
[
  {"city": "Miami",         "lat": 25.7617,  "lon": -80.1918},
  {"city": "Newport Beach", "lat": 33.6189,  "lon": -117.9289},
  {"city": "Seattle",       "lat": 47.6062,  "lon": -122.3321},
  {"city": "Boston",        "lat": 42.3601,  "lon": -71.0589}
]
```

> Set via **Admin → Variables → `weather_cities`** in the Airflow UI

---

## Pipeline 2 — TrainPredict DAG

**DAG ID:** `TrainPredict`
**Schedule:** `30 3 * * *` (Daily at 03:30 UTC — runs after ETL)
**File:** `dags/weather_prediction.py`

<!-- Screenshot: TrainPredict DAG graph — train > predict both success -->
<!-- <img width="1710" height="953" alt="TrainPredict DAG graph" src="YOUR_SCREENSHOT_URL" /> -->

### How It Works

```
RAW.CITY_WEATHER  →  [train]  →  [predict]  →  ANALYTICS.CITY_WEATHER_FINAL
```

#### Task 1: `train()`
1. Creates a clean training view (`ADHOC.CITY_WEATHER_TRAIN_VIEW`) filtering out null `TEMP_MAX` rows
2. Trains a native **Snowflake ML Forecast model** using `SNOWFLAKE.ML.FORECAST`
3. Saves evaluation metrics to `ANALYTICS.CITY_WEATHER_MODEL_METRICS`

```sql
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST ANALYTICS.CITY_WEATHER_FORECAST_MODEL (
    INPUT_DATA    => SYSTEM$REFERENCE('VIEW', 'ADHOC.CITY_WEATHER_TRAIN_VIEW'),
    SERIES_COLNAME    => 'CITY',
    TIMESTAMP_COLNAME => 'DATE',
    TARGET_COLNAME    => 'TEMP_MAX',
    CONFIG_OBJECT     => {'ON_ERROR': 'SKIP'}
);
```

#### Task 2: `predict()`
1. Runs the trained model to generate **7-day forecasts** with **95% prediction intervals**
2. Captures results via `RESULT_SCAN(LAST_QUERY_ID())`
3. Stores raw forecast in `ADHOC.CITY_WEATHER_FORECAST`
4. Builds the **final union table** joining historical actuals and forecast side by side:

```sql
-- Historical actuals
SELECT CITY, DATE, TEMP_MAX AS ACTUAL, NULL AS FORECAST, NULL AS LOWER_BOUND, NULL AS UPPER_BOUND
FROM RAW.CITY_WEATHER

UNION ALL

-- 7-day ML forecast
SELECT REPLACE(SERIES, '"', '') AS CITY, TS AS DATE,
       NULL AS ACTUAL, FORECAST, LOWER_BOUND, UPPER_BOUND
FROM ADHOC.CITY_WEATHER_FORECAST
```

---

## Pipeline 3 — WeatherData DBT DAG

**DAG ID:** `WeatherData_DBT`
**Schedule:** `30 4 * * *` (Daily at 04:30 UTC — runs after TrainPredict)
**File:** `dags/weather_dbt_dag.py`

<!-- Screenshot: WeatherData_DBT DAG graph — dbt_run > dbt_test > dbt_snapshot all green -->
<!-- <img width="1710" height="953" alt="WeatherData_DBT DAG graph" src="YOUR_SCREENSHOT_URL" /> -->

### How It Works

```
dbt_run  →  dbt_test  →  dbt_snapshot
```

The DAG reads Snowflake credentials from the `snowflake_conn` Airflow connection via `BaseHook.get_connection()` and passes them as environment variables to each `BashOperator` task. The dbt project folder is mounted into the Airflow Docker container at `/opt/airflow/dbt`.

```python
conn = BaseHook.get_connection('snowflake_conn')

dbt_run = BashOperator(
    task_id="dbt_run",
    bash_command=f"/home/airflow/.local/bin/dbt run "
                 f"--profiles-dir {DBT_PROJECT_DIR} --project-dir {DBT_PROJECT_DIR}",
)
```

**Environment variables passed to dbt:**

| Variable | Source |
|----------|--------|
| `DBT_USER` | `conn.login` |
| `DBT_PASSWORD` | `conn.password` |
| `DBT_ACCOUNT` | `conn.extra_dejson.get("account")` |
| `DBT_DATABASE` | `conn.extra_dejson.get("database")` |
| `DBT_ROLE` | `conn.extra_dejson.get("role")` |
| `DBT_WAREHOUSE` | `conn.extra_dejson.get("warehouse")` |
| `DBT_TYPE` | `"snowflake"` |

---

## dbt Models

The dbt project (`weather_analytics`) contains **4 analytical models**, all materialized as tables in the `DBT` schema of `USER_DB_FERRET`.

<!-- Screenshot: dbt run output — 4 models SUCCESS in Docker terminal -->
<!-- <img width="1710" height="600" alt="dbt run output" src="YOUR_SCREENSHOT_URL" /> -->

### `moving_avg` — 7-Day Rolling Temperature Averages

**Source:** `RAW.CITY_WEATHER`
**Output table:** `DBT.MOVING_AVG` (436 rows)

Calculates 7-day rolling averages of `TEMP_MAX`, `TEMP_MIN`, and `TEMP_MEAN` per city using Snowflake window functions. Smooths out daily fluctuations to reveal underlying temperature trends. Also tracks `ROLLING_WINDOW_DAYS` so the first 6 days (where the window is smaller than 7) are correctly reflected.

```sql
AVG(TEMP_MAX) OVER (
    PARTITION BY CITY
    ORDER BY DATE
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
) AS TEMP_MAX_7DAY_AVG
```

| Column | Type | Description |
|--------|------|-------------|
| `CITY` | VARCHAR | City name |
| `DATE` | DATE | Observation date |
| `TEMP_MAX` | FLOAT | Daily max temperature (°C) |
| `TEMP_MIN` | FLOAT | Daily min temperature (°C) |
| `TEMP_MEAN` | FLOAT | Daily mean temperature (°C) |
| `PRECIPITATION_MM` | FLOAT | Daily precipitation (mm) |
| `WIND_SPEED_MAX_KMH` | FLOAT | Max wind speed (km/h) |
| `TEMP_MAX_7DAY_AVG` | FLOAT | 7-day rolling avg of TEMP_MAX |
| `TEMP_MIN_7DAY_AVG` | FLOAT | 7-day rolling avg of TEMP_MIN |
| `TEMP_MEAN_7DAY_AVG` | FLOAT | 7-day rolling avg of TEMP_MEAN |
| `ROLLING_WINDOW_DAYS` | DECIMAL | Days included in the rolling window |

<!-- Screenshot: Preset — moving_avg dataset columns confirmed -->
<!-- <img width="1710" height="800" alt="moving_avg dataset in Preset" src="YOUR_SCREENSHOT_URL" /> -->

---

### `temp_anomaly` — Temperature Anomaly vs City Historical Average

**Source:** `RAW.CITY_WEATHER`
**Output table:** `DBT.TEMP_ANOMALY` (436 rows)

Uses a CTE to first compute each city's overall historical average for `TEMP_MAX`, `TEMP_MIN`, and `TEMP_MEAN`, then joins back to calculate the daily deviation from that average. Labels each day as `Above Normal` (>+2°C), `Below Normal` (<-2°C), or `Near Normal`.

```sql
city_averages AS (
    SELECT CITY,
           ROUND(AVG(TEMP_MAX), 2)  AS AVG_TEMP_MAX,
           ROUND(AVG(TEMP_MIN), 2)  AS AVG_TEMP_MIN,
           ROUND(AVG(TEMP_MEAN), 2) AS AVG_TEMP_MEAN
    FROM source
    GROUP BY CITY
)
```

| Column | Type | Description |
|--------|------|-------------|
| `CITY` | VARCHAR | City name |
| `DATE` | DATE | Observation date |
| `TEMP_MAX` | FLOAT | Daily max temperature (°C) |
| `TEMP_MIN` | FLOAT | Daily min temperature (°C) |
| `TEMP_MEAN` | FLOAT | Daily mean temperature (°C) |
| `AVG_TEMP_MAX` | FLOAT | City's overall historical avg TEMP_MAX |
| `AVG_TEMP_MIN` | FLOAT | City's overall historical avg TEMP_MIN |
| `AVG_TEMP_MEAN` | FLOAT | City's overall historical avg TEMP_MEAN |
| `TEMP_MAX_ANOMALY` | FLOAT | Deviation of TEMP_MAX from city average |
| `TEMP_MIN_ANOMALY` | FLOAT | Deviation of TEMP_MIN from city average |
| `TEMP_MEAN_ANOMALY` | FLOAT | Deviation of TEMP_MEAN from city average |
| `ANOMALY_CATEGORY` | VARCHAR | Above Normal / Below Normal / Near Normal |

<!-- Screenshot: Preset — temp_anomaly dataset columns confirmed -->
<!-- <img width="1710" height="800" alt="temp_anomaly dataset in Preset" src="YOUR_SCREENSHOT_URL" /> -->

---

### `rolling_precip` — 7-Day and 30-Day Rolling Precipitation

**Source:** `RAW.CITY_WEATHER`
**Output table:** `DBT.ROLLING_PRECIP` (432 rows)

Calculates both a 7-day and 30-day rolling sum of precipitation per city, plus a count of rainy days in the past 7 days. Labels each 7-day window as `Wet Period` (>25mm), `Dry Period` (0mm), or `Normal Period`.

| Column | Type | Description |
|--------|------|-------------|
| `CITY` | VARCHAR | City name |
| `DATE` | DATE | Observation date |
| `PRECIPITATION_MM` | FLOAT | Daily precipitation (mm) |
| `TEMP_MAX` | FLOAT | Daily max temperature (°C) |
| `TEMP_MIN` | FLOAT | Daily min temperature (°C) |
| `WEATHER_CODE` | DECIMAL | WMO weather code |
| `IS_RAIN_DAY` | DECIMAL | 1 if precipitation > 0, else 0 |
| `PRECIP_7DAY_ROLLING_SUM` | FLOAT | 7-day rolling total precipitation |
| `RAIN_DAYS_LAST_7` | DECIMAL | Count of rainy days in the last 7 |
| `PRECIP_30DAY_ROLLING_SUM` | FLOAT | 30-day rolling total precipitation |
| `PERIOD_LABEL` | VARCHAR | Wet Period / Normal Period / Dry Period |

<!-- Screenshot: Preset — rolling_precip dataset columns confirmed -->
<!-- <img width="1710" height="800" alt="rolling_precip dataset in Preset" src="YOUR_SCREENSHOT_URL" /> -->

---

### `dry_spell` — Consecutive Dry Day Counter

**Source:** `RAW.CITY_WEATHER`
**Output table:** `DBT.DRY_SPELL` (432 rows)

Tracks consecutive dry days (precipitation = 0) per city. Uses a running `SUM(IS_RAIN_DAY)` window to assign a streak group number that increments each time it rains, then counts days within each group using `ROW_NUMBER`. The counter resets to 0 on any rain day. Also computes a running maximum dry spell so far per city.

| Column | Type | Description |
|--------|------|-------------|
| `CITY` | VARCHAR | City name |
| `DATE` | DATE | Observation date |
| `PRECIPITATION_MM` | FLOAT | Daily precipitation (mm) |
| `TEMP_MAX` | FLOAT | Daily max temperature (°C) |
| `WEATHER_CODE` | DECIMAL | WMO weather code |
| `IS_RAIN_DAY` | DECIMAL | 1 if precipitation > 0, else 0 |
| `DRY_SPELL_DAYS` | DECIMAL | Consecutive dry days up to this date |
| `DRY_SPELL_LABEL` | VARCHAR | Rain Day / Dry (1-2 days) / Short Dry Spell (3-6 days) / Extended Dry Spell (7+ days) |
| `MAX_DRY_SPELL_SO_FAR` | DECIMAL | Running maximum dry spell days for this city |

<!-- Screenshot: Preset — dry_spell dataset columns confirmed -->
<!-- <img width="1710" height="800" alt="dry_spell dataset in Preset" src="YOUR_SCREENSHOT_URL" /> -->

---

## dbt Tests & Snapshot

### dbt Tests — 30 Tests, All Pass

Tests are defined in `models/schema.yml` and cover every model. Each model has:
- `not_null` tests on all key columns
- `accepted_values` tests on categorical columns (e.g. `ANOMALY_CATEGORY`, `PERIOD_LABEL`, `DRY_SPELL_LABEL`)
- `accepted_values` tests on `CITY` confirming only the 4 expected cities are present
- Source-level `not_null` tests on `RAW.CITY_WEATHER`

<!-- Screenshot: dbt test output — all 30 PASS in terminal -->
<!-- <img width="1710" height="860" alt="dbt test 30/30 pass" src="YOUR_SCREENSHOT_URL" /> -->

### dbt Snapshot — SCD Type 2 History

The snapshot `city_weather_snapshot` uses the `timestamp` strategy with `DATE` as the `updated_at` field, writing to `DBT.CITY_WEATHER_SNAPSHOT`. If source data is ever corrected retroactively (e.g. the API revises a historical temperature), the snapshot records both old and new values with `dbt_valid_from` and `dbt_valid_to` timestamps — enabling full historical auditing.

```sql
{% snapshot city_weather_snapshot %}
{{
    config(
        target_schema='DBT',
        unique_key="CITY || '_' || DATE",
        strategy='timestamp',
        updated_at='DATE',
        invalidate_hard_deletes=True
    )
}}
SELECT CITY, DATE, LATITUDE, LONGITUDE, TEMP_MAX, TEMP_MIN, TEMP_MEAN,
       PRECIPITATION_MM, WIND_SPEED_MAX_KMH, WEATHER_CODE
FROM {{ source('raw', 'city_weather') }}
{% endsnapshot %}
```

<!-- Screenshot: dbt snapshot output — 1 snapshot SUCCESS in terminal -->
<!-- <img width="1710" height="400" alt="dbt snapshot success" src="YOUR_SCREENSHOT_URL" /> -->

---

## Snowflake Schema & Tables

### Database & Schema Layout

```
USER_DB_FERRET
├── RAW
│   └── CITY_WEATHER                    ← Raw daily weather (ETL target)
├── DBT
│   ├── MOVING_AVG                      ← 7-day rolling temperature averages
│   ├── TEMP_ANOMALY                    ← Daily temperature anomaly per city
│   ├── ROLLING_PRECIP                  ← 7-day / 30-day rolling precipitation
│   ├── DRY_SPELL                       ← Consecutive dry day tracker
│   └── CITY_WEATHER_SNAPSHOT           ← SCD Type 2 history of raw table
├── ADHOC
│   ├── CITY_WEATHER_TRAIN_VIEW         ← Clean view for ML training
│   └── CITY_WEATHER_FORECAST           ← Raw ML forecast output
└── ANALYTICS
    ├── CITY_WEATHER_FINAL              ← Historical actuals + 7-day forecast
    └── CITY_WEATHER_MODEL_METRICS      ← Snowflake ML evaluation metrics
```

<!-- Screenshot: Snowflake — SHOW TABLES in DBT schema showing all 5 tables -->
<!-- <img width="1710" height="500" alt="Snowflake DBT schema tables" src="YOUR_SCREENSHOT_URL" /> -->

### `RAW.CITY_WEATHER` — Source Table

| Column | Type | Description |
|--------|------|-------------|
| `CITY` | STRING | City name (part of composite PK) |
| `LATITUDE` | FLOAT | Geographic latitude |
| `LONGITUDE` | FLOAT | Geographic longitude |
| `DATE` | DATE | Observation date (part of composite PK) |
| `TEMP_MAX` | FLOAT | Daily max temperature (°C) |
| `TEMP_MIN` | FLOAT | Daily min temperature (°C) |
| `TEMP_MEAN` | FLOAT | Daily mean temperature (°C) |
| `PRECIPITATION_MM` | FLOAT | Total daily precipitation (mm) |
| `WIND_SPEED_MAX_KMH` | FLOAT | Max daily wind speed (km/h) |
| `WEATHER_CODE` | INTEGER | WMO weather interpretation code |

> **Composite Primary Key:** `(CITY, DATE)` — one record per city per day, enforced via MERGE

### `DBT.MOVING_AVG` — Verified in Snowflake (436 rows)

<!-- Screenshot: Snowflake — SELECT * FROM USER_DB_FERRET.DBT.MOVING_AVG showing data -->
<!-- <img width="1710" height="800" alt="MOVING_AVG data in Snowflake" src="YOUR_SCREENSHOT_URL" /> -->

### `DBT.TEMP_ANOMALY` — Verified in Snowflake (436 rows)

<!-- Screenshot: Snowflake — SELECT * FROM USER_DB_FERRET.DBT.TEMP_ANOMALY showing data -->
<!-- <img width="1710" height="800" alt="TEMP_ANOMALY data in Snowflake" src="YOUR_SCREENSHOT_URL" /> -->

### `DBT.ROLLING_PRECIP` — Verified in Snowflake (432 rows)

<!-- Screenshot: Snowflake — SELECT * FROM USER_DB_FERRET.DBT.ROLLING_PRECIP showing data -->
<!-- <img width="1710" height="800" alt="ROLLING_PRECIP data in Snowflake" src="YOUR_SCREENSHOT_URL" /> -->

### `DBT.DRY_SPELL` — Verified in Snowflake (432 rows)

<!-- Screenshot: Snowflake — SELECT * FROM USER_DB_FERRET.DBT.DRY_SPELL showing data -->
<!-- <img width="1710" height="800" alt="DRY_SPELL data in Snowflake" src="YOUR_SCREENSHOT_URL" /> -->

---

## Airflow Setup

### Prerequisites

- Docker Desktop with at least 4GB memory
- Apache Airflow 2.10.1 (via `apache/airflow:2.10.1` image)
- `apache-airflow-providers-snowflake==5.7.0`
- `snowflake-connector-python`
- `dbt-snowflake==1.8.0`

All Python dependencies are declared in `docker-compose.yaml` under `_PIP_ADDITIONAL_REQUIREMENTS`.

### Docker Compose — dbt Volume Mount

The dbt project folder is mirrored into the Airflow container so dbt commands can run inside it:

```yaml
volumes:
  - ${AIRFLOW_PROJ_DIR:-.}/dbt:/opt/airflow/dbt
```

This is the key step that allows `BashOperator` tasks to call `/home/airflow/.local/bin/dbt run --project-dir /opt/airflow/dbt`.

### Connections

Configure in **Admin → Connections:**

| Conn ID | Type | Description |
|---------|------|-------------|
| `snowflake_conn` | Snowflake | Account: `SFEDU02-EAB27764`, Database: `USER_DB_FERRET`, Schema: `RAW`, Role: `TRAINING_ROLE`, Warehouse: `FERRET_QUERY_WH` |

### Variables

Configure in **Admin → Variables:**

| Key | Type | Description |
|-----|------|-------------|
| `weather_cities` | JSON | List of city objects with `city`, `lat`, `lon` |

### DAG Execution Order

```
02:30 UTC  →  WeatherData_ETL     (fetches + loads 60-day weather for 4 cities)
03:30 UTC  →  TrainPredict        (trains Snowflake ML model + generates 7-day forecast)
04:30 UTC  →  WeatherData_DBT     (dbt run → dbt test → dbt snapshot)
```

<!-- Screenshot: Airflow DAGs list — all 3 DAGs active with correct schedules -->
<!-- <img width="1710" height="470" alt="All 3 DAGs in Airflow" src="YOUR_SCREENSHOT_URL" /> -->

---

## Preset Dashboard

**Dashboard name:** Weather Analytics Dashboard: City Climate Insights
**BI tool:** Preset (Apache Superset-based)
**Connected to:** Snowflake `USER_DB_FERRET` → `DBT` schema

### Connecting Preset to Snowflake

Preset was connected to Snowflake in 3 steps: select Snowflake as the database type, enter credentials (database: `USER_DB_FERRET`, account: `SFEDU02-EAB27764`, warehouse: `FERRET_QUERY_WH`, role: `TRAINING_ROLE`), and confirm the connection.

<!-- Screenshot: Preset — Step 1 select Snowflake -->
<!-- <img width="1710" height="800" alt="Preset connect database step 1" src="YOUR_SCREENSHOT_URL" /> -->

<!-- Screenshot: Preset — Step 2 enter Snowflake credentials -->
<!-- <img width="1710" height="800" alt="Preset enter Snowflake credentials" src="YOUR_SCREENSHOT_URL" /> -->

<!-- Screenshot: Preset — Step 3 database connected successfully -->
<!-- <img width="1710" height="800" alt="Preset database connected" src="YOUR_SCREENSHOT_URL" /> -->

### Datasets Registered

All four dbt output tables were registered as datasets in Preset:

| Dataset | Source Table | Rows |
|---------|-------------|------|
| `moving_avg` | `DBT.MOVING_AVG` | 436 |
| `temp_anomaly` | `DBT.TEMP_ANOMALY` | 436 |
| `rolling_precip` | `DBT.ROLLING_PRECIP` | 432 |
| `dry_spell` | `DBT.DRY_SPELL` | 432 |

### Dashboard — Page 1: Temperature & Dry Spell Insights

<!-- Screenshot: Full dashboard page 1 — showing all 4 charts with City Filter and Date Filter active -->
<!-- <img width="1710" height="900" alt="Dashboard page 1 full view" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 1 — 7-Day Rolling Temperature Trends by City
**Type:** Line chart | **Source:** `moving_avg`

Shows the 7-day rolling average of `TEMP_MAX` over time for all four cities from February to April 2026. Miami stays consistently warm (25–28°C), Newport Beach holds steady in the low 20s, while Boston climbs from below -5°C in February to 15°C by April. Seattle shows mild progression through spring. The rolling average removes day-to-day noise and makes the seasonal warming trend clearly visible.

<!-- Screenshot: 7-Day Rolling Temperature Trends by City chart -->
<!-- <img width="1710" height="700" alt="7-Day Rolling Temperature Trends" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 2 — Maximum Dry Spell Achieved Over Time by City
**Type:** Line chart | **Source:** `dry_spell`

Tracks the running maximum consecutive dry days per city over the observation period. Newport Beach climbs all the way to **41 consecutive dry days** by early April 2026, reflecting its Southern California climate. Boston, Miami, and Seattle all stay under 15 days. This chart captures drought risk building over time in a way a simple daily counter cannot.

<!-- Screenshot: Maximum Dry Spell Achieved Over Time chart -->
<!-- <img width="1710" height="700" alt="Maximum Dry Spell chart" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 3 — City Climate Profile Comparison (Temperature, Rainfall, Wind)
**Type:** Radar / spider chart | **Source:** `temp_anomaly`

Plots `AVG_TEMP_MAX`, `AVG_TEMP_MIN`, `AVG_PRECIPITATION_MM`, and `AVG_WIND_SPEED_MAX_KMH` for all four cities on a single radar chart. Miami clearly dominates on temperature. Newport Beach has the highest wind values. Boston and Seattle cluster inward. This chart lets you compare the full climate fingerprint of all four cities in one glance.

<!-- Screenshot: City Climate Profile Comparison radar chart -->
<!-- <img width="1710" height="700" alt="City Climate Profile radar chart" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 4 — City Climate Profile: Avg Max vs Min Temperature with Wind Intensity
**Type:** Bubble chart | **Source:** `temp_anomaly`

X-axis is average max temperature, Y-axis is average min temperature, and bubble size encodes wind speed. Miami forms a tight warm cluster in the top-right. Newport Beach spreads across the middle-right. Boston and Seattle cluster in the lower-left. This chart shows both the temperature range experienced by each city and how wind intensity varies across that range.

<!-- Screenshot: City Climate Profile bubble chart -->
<!-- <img width="1710" height="700" alt="City Climate Profile bubble chart" src="YOUR_SCREENSHOT_URL" /> -->

---

### Dashboard — Page 2: Precipitation & Anomaly Insights

<!-- Screenshot: Full dashboard page 2 — showing all 4 charts with date filter applied -->
<!-- <img width="1710" height="900" alt="Dashboard page 2 full view" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 5 — Avg Temp Comparison by City Current Month
**Type:** Bar chart (grouped) | **Source:** `moving_avg`

Shows the 7-day rolling average temperature per city grouped by date for the most recent month (April 2026). Miami consistently sits 5–10°C above all other cities. The date-range slider at the bottom allows filtering to any time window, demonstrating the interactive filter capability of the dashboard.

<!-- Screenshot: Avg Temp Comparison by City Current Month bar chart -->
<!-- <img width="1710" height="700" alt="Avg Temp bar chart" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 6 — Average Rainy Days by City
**Type:** Bar chart | **Source:** `rolling_precip`

Shows the average number of rainy days in the last 7 days per city. Boston (3.31) and Seattle (3.24) lead, confirming their wetter climates, while Newport Beach (0.56) confirms its dry Southern California character. Simple but immediately readable.

<!-- Screenshot: Average Rainy Days by City bar chart -->
<!-- <img width="1710" height="700" alt="Average Rainy Days bar chart" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 7 — Temperature Anomaly Heatmap by City
**Type:** Heatmap | **Source:** `temp_anomaly`

Displays `TEMP_MAX_ANOMALY` per city across the most recent dates. Red cells indicate days warmer than the city's historical average; blue cells indicate cooler days. Boston shows large positive anomalies in early April (20.48°C above average) reflecting a warm spell. Newport Beach stays close to zero — consistent with its mild, stable climate. Filtered by the same date range slider.

<!-- Screenshot: Temperature Anomaly Heatmap by City -->
<!-- <img width="1710" height="700" alt="Temperature Anomaly Heatmap" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 8 — Precipitation vs Temperature Correlation
**Type:** Scatter chart | **Source:** `rolling_precip`

X-axis is 7-day rolling precipitation, Y-axis is daily max temperature. Each point is a city-day observation. Miami stays high on the Y-axis regardless of precipitation. Boston and Seattle show a slight negative slope — more rain tends to coincide with cooler temperatures. Newport Beach dots cluster near zero precipitation across a wide temperature range.

<!-- Screenshot: Precipitation vs Temperature Correlation scatter chart -->
<!-- <img width="1710" height="700" alt="Precipitation vs Temperature Correlation" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 9 — Distribution of Maximum Temperature by City
**Type:** Box plot | **Source:** `temp_anomaly`

Shows the full temperature distribution (median, IQR, whiskers, outliers) of `TEMP_MAX` for each city. Boston has the widest spread (-13°C to +27°C), reflecting its seasonal variation. Miami is tightly clustered around 24–26°C. Newport Beach shows one high outlier around 32°C. Seattle is narrow and mild.

<!-- Screenshot: Distribution of Maximum Temperature box plot -->
<!-- <img width="1710" height="700" alt="Distribution of Maximum Temperature box plot" src="YOUR_SCREENSHOT_URL" /> -->

#### Chart 10 — Monthly Rainfall & Temperature Comparison by City
**Type:** Pivot table with heatmap coloring | **Source:** `rolling_precip`

A pivot table showing `AVG(PRECIPITATION_MM)` and `AVG(TEMP_MAX)` per city per month (Jan–Apr 2026). Green shading highlights high precipitation; red shading highlights high temperature. Newport Beach records near-zero precipitation every month (0.03–0.98mm average) while Boston and Seattle are consistently greener. Temperatures warm visibly from January through April for Boston and Seattle.

<!-- Screenshot: Monthly Rainfall & Temperature Comparison pivot table -->
<!-- <img width="1710" height="700" alt="Monthly Rainfall & Temperature pivot table" src="YOUR_SCREENSHOT_URL" /> -->

---

## Lessons Learned

1. **dbt in Airflow needs a volume mount** — The single most important setup step is adding `${AIRFLOW_PROJ_DIR:-.}/dbt:/opt/airflow/dbt` to the Docker Compose volumes. Without it, `BashOperator` tasks cannot find the dbt project and fail silently.

2. **Credentials belong in Airflow Connections, not code** — Using `BaseHook.get_connection('snowflake_conn')` and passing credentials as environment variables to dbt keeps the DAG code clean and secrets out of version control entirely.

3. **MERGE over INSERT for idempotency** — The ETL pipeline uses a temp staging table + MERGE so daily re-runs never create duplicate records. The whole load is wrapped in `BEGIN / COMMIT / ROLLBACK` so a partial failure leaves no dirty data.

4. **Window functions belong in dbt, not in raw SQL** — Moving the `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` window logic, streak-group calculations, and anomaly joins into dbt models makes them version-controlled, testable, and reusable by any BI tool — not buried in a one-off query.

5. **DAG scheduling order matters** — `WeatherData_ETL` at 02:30 → `TrainPredict` at 03:30 → `WeatherData_DBT` at 04:30 ensures fresh raw data is always available before ML training and dbt transformations run.

6. **dbt tests catch problems before Preset does** — Running 30 `not_null` and `accepted_values` tests in the pipeline means data quality issues surface in the Airflow UI as task failures, not as confusing blank charts in the dashboard.

7. **Snapshots enable audit trails for free** — The `city_weather_snapshot` SCD Type 2 snapshot means that if the Open-Meteo API ever corrects a past temperature, both the old and new values are preserved with timestamps — no manual audit table needed.

---

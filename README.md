# Weather Analytics Lab 2 — End-to-End ELT Pipeline

### Powered by · Snowflake · Apache Airflow · dbt · Preset · Open-Meteo API · ML Forecasting

---

## Table of Contents
- [Overview](#overview)
- [Problem Statement](#problem-statement)
- [Solution Requirements](#solution-requirements)
- [Functional Analysis](#functional-analysis)
- [Tech Stack](#tech-stack)
- [System Architecture](#system-architecture)
- [Table Structures](#table-structures)
- [Cities Tracked](#cities-tracked)
- [Project Structure](#project-structure)
- [Pipeline Details](#pipeline-details)
- [Pipeline 1 — Weather ETL DAG](#pipeline-1--weather-etl-dag)
- [Pipeline 2 — TrainPredict DAG](#pipeline-2--trainpredict-dag)
- [Pipeline 3 — WeatherData DBT DAG](#pipeline-3--weatherdata-dbt-dag)
- [dbt Models](#dbt-models)
- [dbt Tests & Snapshot](#dbt-tests--snapshot)
- [Snowflake Schema & Tables](#snowflake-schema--tables)
- [How to Run](#how-to-run)
- [Airflow Setup](#airflow-setup)
- [Preset Dashboard](#preset-dashboard)
- [Conclusion](#conclusion)
- [Future Work](#future-work)
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

## Problem Statement

This project builds an automated weather analytics system to ingest, process, and analyze historical and forecast weather data.

Manual data collection and fragmented analysis limit scalability and consistency. A centralized data warehouse (Snowflake) is required to store structured data, while automated data pipelines (Airflow + dbt) ensure reliable ingestion, transformation, and analytics.

This system enables repeatable, scalable, and production-ready data workflows.

---

## Solution Requirements

### Functional Requirements
- Ingest 60 days of weather data from Open-Meteo API
- Store structured data in Snowflake
- Run ML forecasting for future predictions
- Transform data using dbt models
- Visualize insights using dashboards

### System Usage
- Data engineers monitor pipelines via Airflow UI
- Users access insights through Preset dashboards

### Limitations
- Limited to selected cities
- Batch processing (not real-time)
- Forecast accuracy depends on historical data quality

---  

## Functional Analysis

The system consists of three main pipelines:

1. ETL Pipeline (WeatherData_ETL)
   - Extracts data from Open-Meteo API
   - Loads into Snowflake RAW schema

2. ML Forecast Pipeline (TrainPredict)
   - Trains Snowflake ML Forecast model
   - Generates 7-day predictions

3. dbt ELT Pipeline (WeatherData_DBT)
   - Transforms raw data into analytical models
   - Applies tests and snapshots

### Pipeline Flow
ETL → ML → dbt → Dashboard

Forecast and historical data are combined using UNION ALL to create the final analytics table.

---

## Tech Stack

- Orchestration: Apache Airflow
- Data Warehouse: Snowflake
- Transformation: dbt
- Machine Learning: Snowflake ML Forecast
- Visualization: Preset (Apache Superset)
- Programming: Python, SQL
- Infrastructure: Docker

## System Architecture


<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/4492b0ab-6128-4f8f-bfcc-c2bf3c122180" />

> **Architecture Overview:**
> Open-Meteo API → Airflow ETL (4 parallel city pipelines) → Snowflake RAW.CITY_WEATHER → Airflow ML Forecast (TrainPredict) → Snowflake ANALYTICS (FINAL + METRICS) → Airflow dbt ELT (models, tests, snapshot) → Snowflake DBT Schema → Preset Dashboard

---

## Table Structures

### RAW.CITY_WEATHER

| Column | Type | Description |
|--------|------|------------|
| CITY | STRING | City name |
| DATE | DATE | Observation date |
| TEMP_MAX | FLOAT | Max temperature |
| TEMP_MIN | FLOAT | Min temperature |
| PRECIPITATION | FLOAT | Rainfall |
| WIND_SPEED | FLOAT | Wind speed |
| WEATHER_CODE | INT | Weather condition |

Primary Key: (CITY, DATE)

---

### ANALYTICS.CITY_WEATHER_FINAL

| Column | Type | Description |
|--------|------|------------|
| CITY | STRING |
| DATE | DATE |
| ACTUAL | FLOAT |
| FORECAST | FLOAT |
| LOWER_BOUND | FLOAT |
| UPPER_BOUND | FLOAT |

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

## Pipeline Details

| Pipeline | DAG Name | Schedule | Description |
|----------|----------|----------|------------|
| Pipeline 1 | WeatherData_ETL | 02:30 UTC (Daily) | Extracts 60-day weather data from Open-Meteo API, transforms JSON, and loads into Snowflake RAW schema using MERGE (idempotent). |
| Pipeline 2 | TrainPredict | 03:30 UTC (Daily) | Trains Snowflake ML Forecast model and generates 7-day temperature predictions with confidence intervals. |
| Pipeline 3 | WeatherData_DBT | 04:30 UTC (Daily) | Runs dbt models, tests, and snapshots to transform raw data into analytics-ready tables. |

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

### Connections

Configure in **Admin → Connections:**

| Conn ID | Type | Description |
|---------|------|-------------|
| `snowflake_conn` | Snowflake | Points to `USER_DB_FERRET`, schema `RAW` |

<img width="1710" height="949" alt="image" src="https://github.com/user-attachments/assets/47ce4c20-2706-4336-9fa2-e6556adc48d4" />


### Variables

Configure in **Admin → Variables:**

| Key | Type | Description |
|-----|------|-------------|
| `weather_cities` | JSON | List of city objects with `city`, `lat`, `lon` |

<img width="1710" height="949" alt="image" src="https://github.com/user-attachments/assets/9f98c63a-f52f-40d4-947d-d55415d8dba1" />

---

## Pipeline 2 — TrainPredict DAG

**DAG ID:** `TrainPredict`
**Schedule:** `30 3 * * *` (Daily at 03:30 UTC — runs after ETL)
**File:** `dags/weather_prediction.py`

<img width="1246" height="662" alt="image" src="https://github.com/user-attachments/assets/87b6a705-214b-4b8c-8282-e6402605d098" />


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

<img width="1242" height="748" alt="image" src="https://github.com/user-attachments/assets/548827e2-7368-4515-a1a1-6601f6deeaaa" />

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

dbt run:

<img width="1260" height="310" alt="image" src="https://github.com/user-attachments/assets/da725070-da20-44fb-ab3c-bc8652f82a88" />

dbt test:

<img width="1246" height="776" alt="image" src="https://github.com/user-attachments/assets/ca1b44e6-bd76-43a6-aea0-1c4d6de3b8fe" />

dbt snapshots:

<img width="1246" height="646" alt="image" src="https://github.com/user-attachments/assets/29ca685d-f028-41fd-af5e-d7d398ddec7b" />


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

<img width="1248" height="690" alt="image" src="https://github.com/user-attachments/assets/59613b07-b031-4244-9212-a7970f1ef5ee" />

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

<img width="1234" height="686" alt="image" src="https://github.com/user-attachments/assets/ef64e46c-99b1-4639-9645-db7b998a24c1" />

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

<img width="1238" height="690" alt="image" src="https://github.com/user-attachments/assets/6dd7e58c-8c22-46b1-97fa-3f4307211986" />

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

<img width="1236" height="690" alt="image" src="https://github.com/user-attachments/assets/00cc1170-bbf6-492a-a88a-c3da4fe37031" />

---

## dbt Tests & Snapshot

### dbt Tests — 30 Tests, All Pass

Tests are defined in `models/schema.yml` and cover every model. Each model has:
- `not_null` tests on all key columns
- `accepted_values` tests on categorical columns (e.g. `ANOMALY_CATEGORY`, `PERIOD_LABEL`, `DRY_SPELL_LABEL`)
- `accepted_values` tests on `CITY` confirming only the 4 expected cities are present
- Source-level `not_null` tests on `RAW.CITY_WEATHER`

<img width="1244" height="780" alt="image" src="https://github.com/user-attachments/assets/05534086-ab46-4649-b47b-91c36163f9eb" />


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

<img width="1258" height="192" alt="image" src="https://github.com/user-attachments/assets/6514ea99-1b62-4b88-bb5d-ac1b33216c04" />

<img width="1252" height="650" alt="image" src="https://github.com/user-attachments/assets/69d899e3-094a-4e25-b85c-86c12b83729a" />


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

<img width="3418" height="1016" alt="image" src="https://github.com/user-attachments/assets/6d61dd27-6f51-4a86-b022-16b901765474" />

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

<img width="2650" height="1634" alt="image" src="https://github.com/user-attachments/assets/2c3f11c3-2a4d-4c81-b92d-7d39b7290d0c" />

### `DBT.TEMP_ANOMALY` — Verified in Snowflake (436 rows)

<img width="2646" height="1662" alt="image" src="https://github.com/user-attachments/assets/b4897f93-59fb-4622-aeb6-427028458730" />

### `DBT.ROLLING_PRECIP` — Verified in Snowflake 

<img width="2648" height="1646" alt="image" src="https://github.com/user-attachments/assets/35a85e46-86b1-43ba-a9a5-30916a0ec61d" />

### `DBT.DRY_SPELL` — Verified in Snowflake 

<img width="2640" height="1648" alt="image" src="https://github.com/user-attachments/assets/c3eb7072-28a5-408f-906c-8a7977f30784" />

---

## How to Run

### Start System

docker-compose up airflow-init

docker-compose up -d

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

<img width="1250" height="428" alt="image" src="https://github.com/user-attachments/assets/a9ca59e8-142a-4696-a108-74ef4ac1da52" />

---

## Preset Dashboard

**Dashboard name:** Weather Analytics Dashboard: City Climate Insights
**BI tool:** Preset (Apache Superset-based)
**Connected to:** Snowflake `USER_DB_FERRET` → `DBT` schema

### Connecting Preset to Snowflake

Preset was connected to Snowflake in 3 steps: select Snowflake as the database type, enter credentials (database: `USER_DB_FERRET`, account: `SFEDU02-EAB27764`, warehouse: `FERRET_QUERY_WH`, role: `TRAINING_ROLE`), and confirm the connection.


<img width="1236" height="690" alt="image" src="https://github.com/user-attachments/assets/78a52bc0-975d-427d-85cc-893575ce9272" />


<img width="1236" height="690" alt="image" src="https://github.com/user-attachments/assets/084184ef-cfb0-4160-9198-be75aad0bcb8" />


<img width="1236" height="684" alt="image" src="https://github.com/user-attachments/assets/1a58a1e2-0c3d-41fd-9819-7b6c8edb5c33" />



### Datasets Registered

All four dbt output tables were registered as datasets in Preset:

| Dataset | Source Table |
|---------|-------------|
| `moving_avg` | `DBT.MOVING_AVG` | 
| `temp_anomaly` | `DBT.TEMP_ANOMALY` | 
| `rolling_precip` | `DBT.ROLLING_PRECIP` | 
| `dry_spell` | `DBT.DRY_SPELL` | 

### Dashboard — Page 1: Temperature & Dry Spell Insights

<img width="1090" height="596" alt="image" src="https://github.com/user-attachments/assets/84a703c4-7587-470a-b74a-f2367a7e70e0" />


#### Chart 1 — City Climate Profile Comparison (Temperature, Rainfall, Wind)
**Type:** Radar / spider chart | **Source:** `temp_anomaly`

Plots `AVG_TEMP_MAX`, `AVG_TEMP_MIN`, `AVG_PRECIPITATION_MM`, and `AVG_WIND_SPEED_MAX_KMH` for all four cities on a single radar chart. Miami clearly dominates on temperature. Newport Beach has the highest wind values. Boston and Seattle cluster inward. This chart lets you compare the full climate fingerprint of all four cities in one glance.

<img width="1338" height="800" alt="image" src="https://github.com/user-attachments/assets/6feef695-e8e5-474d-9756-a8163d047dc7" />

#### Chart 2 — 7-Day Rolling Temperature Trends by City
**Type:** Line chart | **Source:** `moving_avg`

Shows the 7-day rolling average of `TEMP_MAX` over time for all four cities from February to April 2026. Miami stays consistently warm (25–28°C), Newport Beach holds steady in the low 20s, while Boston climbs from below -5°C in February to 15°C by April. Seattle shows mild progression through spring. The rolling average removes day-to-day noise and makes the seasonal warming trend clearly visible.

<img width="1334" height="766" alt="image" src="https://github.com/user-attachments/assets/8acf3790-39f7-4f14-b073-6139496f5cbd" />

#### Chart 3 — City Climate Profile: Avg Max vs Min Temperature with Wind Intensity
**Type:** Bubble chart | **Source:** `temp_anomaly`

X-axis is average max temperature, Y-axis is average min temperature, and bubble size encodes wind speed. Miami forms a tight warm cluster in the top-right. Newport Beach spreads across the middle-right. Boston and Seattle cluster in the lower-left. This chart shows both the temperature range experienced by each city and how wind intensity varies across that range.

<img width="1326" height="790" alt="image" src="https://github.com/user-attachments/assets/f7393be8-4756-437f-aeea-3bfd25eca314" />

#### Chart 4 — Maximum Dry Spell Achieved Over Time by City
**Type:** Line chart | **Source:** `dry_spell`

Tracks the running maximum consecutive dry days per city over the observation period. Newport Beach climbs all the way to **41 consecutive dry days** by early April 2026, reflecting its Southern California climate. Boston, Miami, and Seattle all stay under 15 days. This chart captures drought risk building over time in a way a simple daily counter cannot.

<img width="1230" height="702" alt="image" src="https://github.com/user-attachments/assets/2d5fed87-74bf-4725-917d-3943f7b2ed12" />

---

### Dashboard — Page 2: Precipitation & Anomaly Insights

<img width="1100" height="598" alt="image" src="https://github.com/user-attachments/assets/32b1c6cd-b428-44e7-833f-c0f911a4c839" />


#### Chart 5 — Avg Temp Comparison by City Current Month
**Type:** Bar chart (grouped) | **Source:** `moving_avg`

Shows the 7-day rolling average temperature per city grouped by date for the most recent month (April 2026). Miami consistently sits 5–10°C above all other cities. The date-range slider at the bottom allows filtering to any time window, demonstrating the interactive filter capability of the dashboard.

<img width="1230" height="696" alt="image" src="https://github.com/user-attachments/assets/720810bf-9560-4b7c-a923-c8b484738711" />

#### Chart 6 — Temperature Anomaly Heatmap by City
**Type:** Heatmap | **Source:** `temp_anomaly`

Displays `TEMP_MAX_ANOMALY` per city across the most recent dates. Red cells indicate days warmer than the city's historical average; blue cells indicate cooler days. Boston shows large positive anomalies in early April (20.48°C above average) reflecting a warm spell. Newport Beach stays close to zero — consistent with its mild, stable climate. Filtered by the same date range slider.

<img width="1238" height="672" alt="image" src="https://github.com/user-attachments/assets/81f705b9-5b36-4aa3-b28f-fc9e26e5b7a8" />

#### Chart 7 — Average Rainy Days by City
**Type:** Bar chart | **Source:** `rolling_precip`

Shows the average number of rainy days in the last 7 days per city. Boston (3.31) and Seattle (3.24) lead, confirming their wetter climates, while Newport Beach (0.56) confirms its dry Southern California character. Simple but immediately readable.

<img width="1326" height="780" alt="image" src="https://github.com/user-attachments/assets/d3314357-9bee-40e9-94bc-e11cd343041c" />

#### Chart 8 — Precipitation vs Temperature Correlation
**Type:** Scatter chart | **Source:** `rolling_precip`

X-axis is 7-day rolling precipitation, Y-axis is daily max temperature. Each point is a city-day observation. Miami stays high on the Y-axis regardless of precipitation. Boston and Seattle show a slight negative slope — more rain tends to coincide with cooler temperatures. Newport Beach dots cluster near zero precipitation across a wide temperature range.

<img width="1328" height="774" alt="image" src="https://github.com/user-attachments/assets/3ad5b6c9-1dc3-4b35-b970-0227fd07ce4f" />

#### Chart 9 — Distribution of Maximum Temperature by City
**Type:** Box plot | **Source:** `temp_anomaly`

Shows the full temperature distribution (median, IQR, whiskers, outliers) of `TEMP_MAX` for each city. Boston has the widest spread (-13°C to +27°C), reflecting its seasonal variation. Miami is tightly clustered around 24–26°C. Newport Beach shows one high outlier around 32°C. Seattle is narrow and mild.

<img width="1234" height="680" alt="image" src="https://github.com/user-attachments/assets/7c547ce3-4fab-40a1-acf2-a22bb0842cbd" />

#### Chart 10 — Monthly Rainfall & Temperature Comparison by City
**Type:** Pivot table with heatmap coloring | **Source:** `rolling_precip`

A pivot table showing `AVG(PRECIPITATION_MM)` and `AVG(TEMP_MAX)` per city per month (Jan–Apr 2026). Green shading highlights high precipitation; red shading highlights high temperature. Newport Beach records near-zero precipitation every month (0.03–0.98mm average) while Boston and Seattle are consistently greener. Temperatures warm visibly from January through April for Boston and Seattle.

<img width="1232" height="672" alt="image" src="https://github.com/user-attachments/assets/4e7411d7-1c46-42f0-a669-df87ab2f2d5a" />

---

## Conclusion

This project demonstrates the successful implementation of a fully automated end-to-end weather analytics pipeline using modern data engineering tools. The system integrates data ingestion, transformation, machine learning, and visualization into a unified workflow.

Apache Airflow is used to orchestrate multiple pipelines, ensuring a structured and reliable flow of data from source to analytics. The ETL pipeline ingests historical weather data into Snowflake, while dbt enables modular and scalable transformations with built-in testing and validation. In addition, the ML forecasting pipeline leverages Snowflake ML capabilities to generate future temperature predictions, enhancing the analytical value of the system.

The integration of Preset dashboards provides an interactive interface for visualizing insights such as temperature trends, anomalies, and precipitation patterns. Overall, the system ensures data consistency, automation, and reproducibility, making it suitable for real-world analytical applications.

This project highlights how combining data engineering, analytics, and machine learning in a single pipeline can deliver meaningful and actionable insights efficiently.

---

## Future Work

While the current system meets its core objectives, there are several opportunities for improvement and extension.

One potential enhancement is to expand data sources beyond the Open-Meteo API by integrating additional providers or real-time streaming data. This would improve data reliability and scalability. The system can also be extended to include more cities or global-level analytics.

The machine learning pipeline can be further improved by incorporating advanced time-series forecasting models such as LSTM or Prophet to increase prediction accuracy. Additionally, implementing model monitoring and tracking evaluation metrics over time would strengthen the reliability of predictions.

From a system design perspective, introducing CI/CD pipelines for dbt and Airflow would improve deployment efficiency and maintainability. Adding alerting and monitoring mechanisms, such as failure notifications and data quality checks, would make the system more production-ready.

Finally, the visualization layer can be enhanced by adding more interactive dashboards, user-driven filters, and business-focused KPIs to provide deeper and more actionable insights.

These improvements would help evolve the current system into a more scalable, robust, and production-grade data platform.

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

# Weather Analytics Pipeline — Lab 2
### Powered by Snowflake · Apache Airflow · dbt · Preset Dashboard · Open-Meteo API

---

## Table of Contents
- [Overview](#overview)
- [What's New in Lab 2](#whats-new-in-lab-2)
- [System Architecture](#system-architecture)
- [Cities Tracked](#cities-tracked)
- [Project Structure](#project-structure)
- [Pipeline 1 — Weather ETL DAG](#pipeline-1--weather-etl-dag)
- [Pipeline 2 — TrainPredict DAG](#pipeline-2--trainpredict-dag)
- [Pipeline 3 — WeatherData DBT DAG](#pipeline-3--weatherdata-dbt-dag)
- [dbt Project — ELT Transformations](#dbt-project--elt-transformations)
- [Snowflake Schema & Tables](#snowflake-schema--tables)
- [Airflow Setup](#airflow-setup)
- [Preset Dashboard](#preset-dashboard)
- [GitHub Repository Contents](#github-repository-contents)
- [Lessons Learned](#lessons-learned)

---

## Overview

This project is a fully automated end-to-end weather analytics system built using Apache Airflow, Snowflake, dbt, and Preset. It ingests 60 days of real historical weather observations for four US cities from the Open-Meteo API, stores the raw data in Snowflake, transforms it into analytics-ready tables using dbt, trains a 7-day ML forecast using Snowflake's native ML engine, and visualizes everything through an interactive Preset dashboard.

Three Airflow DAGs run automatically every day on a staggered schedule. The ETL pipeline loads raw data at 2:30 AM UTC. The ML pipeline trains and forecasts at 3:30 AM UTC. The dbt ELT pipeline runs transformations at 4:30 AM UTC. No manual steps are required after the initial setup.

---

## What's New in Lab 2

Lab 1 built the ETL and ML forecasting layers. Lab 2 adds two new layers on top of that:

**ELT Layer (dbt):** Four transformation models were built on top of the raw weather data in Snowflake. These models calculate moving averages, temperature anomalies, rolling precipitation, and dry spell streaks — all materialized as tables in a dedicated `DBT` schema. A snapshot tracks historical changes to the raw data over time. All models are covered by 30 schema tests.

**Visualization Layer (Preset):** An 8-chart interactive dashboard was built in Preset, connected directly to the dbt tables in Snowflake. The dashboard includes line charts, heatmaps, bar charts, scatter plots, area charts, and bubble charts — covering temperature trends, anomalies, precipitation patterns, and multi-variable weather correlations.

---

## System Architecture

```
Open-Meteo API
      │
      ▼
┌─────────────────────────────────────────────┐
│           Apache Airflow (Docker)            │
│                                             │
│  WeatherData_ETL DAG  (2:30 AM UTC)         │
│  Extract → Transform → Load (MERGE)         │
│                                             │
│  TrainPredict DAG     (3:30 AM UTC)         │
│  Train ML Model → Generate 7-Day Forecast  │
│                                             │
│  WeatherData_DBT DAG  (4:30 AM UTC)         │
│  dbt run → dbt test → dbt snapshot         │
└─────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────┐
│              Snowflake                       │
│                                             │
│  RAW Schema                                 │
│  └── CITY_WEATHER (raw observations)       │
│                                             │
│  ADHOC Schema                               │
│  ├── CITY_WEATHER_TRAIN_VIEW               │
│  └── CITY_WEATHER_FORECAST                 │
│                                             │
│  ANALYTICS Schema                           │
│  ├── CITY_WEATHER_FINAL                    │
│  └── CITY_WEATHER_MODEL_METRICS            │
│                                             │
│  DBT Schema  ← New in Lab 2                │
│  ├── MOVING_AVG                            │
│  ├── TEMP_ANOMALY                          │
│  ├── ROLLING_PRECIP                        │
│  ├── DRY_SPELL                             │
│  └── CITY_WEATHER_SNAPSHOT                │
└─────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────┐
│         Preset Dashboard  ← New in Lab 2    │
│  8 Charts: Trends · Heatmap · Scatter       │
│  Anomalies · Precipitation · Dry Spells    │
└─────────────────────────────────────────────┘
```

---

## Cities Tracked

| City | Latitude | Longitude | State |
|------|----------|-----------|-------|
| Miami | 25.7743 | -80.1937 | Florida |
| Newport Beach | 33.6189 | -117.9289 | California |
| Seattle | 47.6062 | -122.3321 | Washington |
| Boston | 42.3584 | -71.0598 | Massachusetts |

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
**Schedule:** `30 2 * * *` — Daily at 2:30 AM UTC
**File:** `dags/weather_etl_pipeline.py`

This pipeline runs four parallel task chains, one per city. Each chain has three steps: extract, transform, and load. All twelve tasks run concurrently across the four cities.

```
extract_1 → transform_1 → load_1
extract_2 → transform_2 → load_2
extract_3 → transform_3 → load_3
extract_4 → transform_4 → load_4
```

**extract:** Calls the Open-Meteo Forecast API and fetches the past 60 days of daily weather data. Collects temperature (max, min, mean), precipitation, wind speed, and weather code.

**transform:** Flattens the nested JSON response into a list of structured tuples aligned with the Snowflake schema.

**load:** Creates a temporary staging table, bulk-inserts the records, and runs a MERGE statement to upsert into `RAW.CITY_WEATHER`. The MERGE is keyed on `CITY + DATE`, so re-running the pipeline never creates duplicate rows. All Snowflake operations are wrapped in a SQL transaction with `try/except/rollback` to ensure atomicity.

```sql
MERGE INTO CITY_WEATHER t
USING CITY_WEATHER_STAGE s
ON t.CITY = s.CITY AND t.DATE = s.DATE
WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT ...
```

City configurations (name, latitude, longitude) are stored as an Airflow Variable (`weather_cities`) in JSON format. Snowflake credentials are stored as an Airflow Connection (`snowflake_conn`). Nothing is hardcoded in the pipeline code.

---

## Pipeline 2 — TrainPredict DAG

**DAG ID:** `TrainPredict`
**Schedule:** `30 3 * * *` — Daily at 3:30 AM UTC (one hour after ETL)
**File:** `dags/weather_prediction.py`

```
train() → predict()
```

**train:** Creates a clean training view from `RAW.CITY_WEATHER` containing only rows where `TEMP_MAX` is not null. Trains a `SNOWFLAKE.ML.FORECAST` model using CITY as the series identifier and DATE as the timestamp. Evaluation metrics (MAE, SMAPE, MDA, MSE) are appended to `ANALYTICS.CITY_WEATHER_MODEL_METRICS` after each run.

**predict:** Calls the trained model to generate a 7-day forecast with 95% prediction intervals. Captures the output using `RESULT_SCAN(LAST_QUERY_ID())` and stores it in `ADHOC.CITY_WEATHER_FORECAST`. Creates the final analytics table by combining historical actuals and forecast values using UNION ALL.

```sql
SELECT CITY, DATE, TEMP_MAX AS ACTUAL, NULL AS FORECAST, NULL AS LOWER_BOUND, NULL AS UPPER_BOUND
FROM RAW.CITY_WEATHER
UNION ALL
SELECT REPLACE(SERIES, '"', '') AS CITY, TS AS DATE, NULL, FORECAST, LOWER_BOUND, UPPER_BOUND
FROM ADHOC.CITY_WEATHER_FORECAST
```

---

## Pipeline 3 — WeatherData DBT DAG

**DAG ID:** `WeatherData_DBT`
**Schedule:** `30 4 * * *` — Daily at 4:30 AM UTC (after ETL and ML pipelines)
**File:** `dags/weather_dbt_dag.py`

```
dbt_run → dbt_test → dbt_snapshot
```

This DAG runs the dbt project using `BashOperator`. Credentials are injected at runtime from the Airflow `snowflake_conn` connection using `BaseHook.get_connection()` and passed as environment variables — no credentials are stored in the DAG code.

```python
conn = BaseHook.get_connection('snowflake_conn')

default_args={
    "env": {
        "DBT_USER": conn.login,
        "DBT_PASSWORD": conn.password,
        "DBT_ACCOUNT": conn.extra_dejson.get("account"),
        "DBT_DATABASE": conn.extra_dejson.get("database"),
        "DBT_ROLE": conn.extra_dejson.get("role"),
        "DBT_WAREHOUSE": conn.extra_dejson.get("warehouse"),
        "DBT_TYPE": "snowflake"
    }
}
```

**dbt_run** builds all four transformation models into the `DBT` schema.
**dbt_test** runs all 30 schema tests across the four models.
**dbt_snapshot** captures the current state of `RAW.CITY_WEATHER` for historical auditing.

All three tasks completed successfully with zero errors.

---

## dbt Project — ELT Transformations

The dbt project is named `weather_analytics`. It connects to Snowflake using environment variables defined in `profiles.yml` and materializes all models as tables in the `DBT` schema of `USER_DB_FERRET`.

### Model 1 — moving_avg

Reads from `RAW.CITY_WEATHER` and calculates 7-day rolling averages of TEMP_MAX, TEMP_MIN, and TEMP_MEAN for each city, ordered by date. Rolling averages smooth out daily noise and reveal the underlying temperature trend across weeks.

```sql
AVG(TEMP_MAX) OVER (
    PARTITION BY CITY
    ORDER BY DATE
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
) AS TEMP_MAX_7DAY_AVG
```

**dbt run result:** `1 of 4 OK — DBT.MOVING_AVG` ✅

### Model 2 — temp_anomaly

For each city and date, calculates how much warmer or cooler that day was compared to the city's overall average temperature across the full dataset. Positive values mean hotter than normal, negative values mean cooler. Each row is categorized as Above Normal (>+2°C), Below Normal (<-2°C), or Near Normal.

```sql
ROUND(s.TEMP_MAX - ca.AVG_TEMP_MAX, 2) AS TEMP_MAX_ANOMALY,
CASE
    WHEN (s.TEMP_MAX - ca.AVG_TEMP_MAX) > 2  THEN 'Above Normal'
    WHEN (s.TEMP_MAX - ca.AVG_TEMP_MAX) < -2 THEN 'Below Normal'
    ELSE 'Near Normal'
END AS ANOMALY_CATEGORY
```

**dbt run result:** `2 of 4 OK — DBT.TEMP_ANOMALY` ✅

### Model 3 — rolling_precip

Calculates 7-day and 30-day rolling precipitation totals for each city. Flags each day as a rain day or dry day. Counts how many of the last 7 days had rain. Labels each period as Wet (7-day sum > 25mm), Dry (7-day sum = 0), or Normal.

```sql
SUM(PRECIPITATION_MM) OVER (
    PARTITION BY CITY
    ORDER BY DATE
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
) AS PRECIP_7DAY_ROLLING_SUM
```

**dbt run result:** `3 of 4 OK — DBT.ROLLING_PRECIP` ✅

### Model 4 — dry_spell

Counts consecutive days with zero precipitation for each city. The counter resets to zero whenever it rains. Also tracks the running maximum dry streak seen so far for each city, and categorizes streak length: Rain Day, Dry (1-2 days), Short Dry Spell (3-6 days), Extended Dry Spell (7+ days).

**dbt run result:** `4 of 4 OK — DBT.DRY_SPELL` ✅

### dbt Tests

Tests are defined in `models/schema.yml` and cover all four models:

- `not_null` on CITY, DATE, and all key metric columns
- `accepted_values` on CITY (only the 4 expected cities)
- `accepted_values` on categorical columns (ANOMALY_CATEGORY, PERIOD_LABEL, DRY_SPELL_LABEL)

**dbt test result:** `PASS=30, WARN=0, ERROR=0` ✅

### dbt Snapshot

A snapshot on `RAW.CITY_WEATHER` tracks historical changes to the raw data over time. If the API ever corrects a past observation, the snapshot captures both the old and new version with `dbt_valid_from` and `dbt_valid_to` timestamps.

**dbt snapshot result:** `PASS=1, WARN=0, ERROR=0` ✅

---

## Snowflake Schema & Tables

### Full Database Layout

```
USER_DB_FERRET
│
├── RAW
│   └── CITY_WEATHER
│
├── ADHOC
│   ├── CITY_WEATHER_TRAIN_VIEW
│   └── CITY_WEATHER_FORECAST
│
├── ANALYTICS
│   ├── CITY_WEATHER_FINAL
│   └── CITY_WEATHER_MODEL_METRICS
│
└── DBT  ← New in Lab 2
    ├── MOVING_AVG
    ├── TEMP_ANOMALY
    ├── ROLLING_PRECIP
    ├── DRY_SPELL
    └── CITY_WEATHER_SNAPSHOT
```

### RAW.CITY_WEATHER — Primary Raw Table

| Column | Type | Description |
|--------|------|-------------|
| CITY | STRING | City name — part of composite PK |
| LATITUDE | FLOAT | Geographic latitude |
| LONGITUDE | FLOAT | Geographic longitude |
| DATE | DATE | Observation date — part of composite PK |
| TEMP_MAX | FLOAT | Daily maximum temperature (°C) |
| TEMP_MIN | FLOAT | Daily minimum temperature (°C) |
| TEMP_MEAN | FLOAT | Daily mean temperature (°C) |
| PRECIPITATION_MM | FLOAT | Total daily precipitation (mm) |
| WIND_SPEED_MAX_KMH | FLOAT | Maximum daily wind speed (km/h) |
| WEATHER_CODE | INTEGER | WMO weather interpretation code |

> Composite Primary Key: `(CITY, DATE)` — enforced via MERGE upsert strategy

### DBT.MOVING_AVG

| Column | Type | Description |
|--------|------|-------------|
| CITY | STRING | City name |
| DATE | DATE | Observation date |
| TEMP_MAX | FLOAT | Raw daily max temperature (°C) |
| TEMP_MIN | FLOAT | Raw daily min temperature (°C) |
| TEMP_MEAN | FLOAT | Raw daily mean temperature (°C) |
| TEMP_MAX_7DAY_AVG | FLOAT | 7-day rolling average of TEMP_MAX |
| TEMP_MIN_7DAY_AVG | FLOAT | 7-day rolling average of TEMP_MIN |
| TEMP_MEAN_7DAY_AVG | FLOAT | 7-day rolling average of TEMP_MEAN |
| ROLLING_WINDOW_DAYS | INTEGER | Actual days in rolling window (< 7 at start) |

### DBT.TEMP_ANOMALY

| Column | Type | Description |
|--------|------|-------------|
| CITY | STRING | City name |
| DATE | DATE | Observation date |
| TEMP_MAX | FLOAT | Observed daily max temperature (°C) |
| AVG_TEMP_MAX | FLOAT | City's historical average TEMP_MAX |
| TEMP_MAX_ANOMALY | FLOAT | Difference: observed minus city average |
| TEMP_MIN_ANOMALY | FLOAT | Min temperature anomaly |
| TEMP_MEAN_ANOMALY | FLOAT | Mean temperature anomaly |
| ANOMALY_CATEGORY | STRING | Above Normal / Below Normal / Near Normal |

### DBT.ROLLING_PRECIP

| Column | Type | Description |
|--------|------|-------------|
| CITY | STRING | City name |
| DATE | DATE | Observation date |
| PRECIPITATION_MM | FLOAT | Daily precipitation (mm) |
| IS_RAIN_DAY | INTEGER | 1 = rain, 0 = dry |
| PRECIP_7DAY_ROLLING_SUM | FLOAT | 7-day rolling total precipitation (mm) |
| RAIN_DAYS_LAST_7 | INTEGER | Number of rainy days in last 7 days |
| PRECIP_30DAY_ROLLING_SUM | FLOAT | 30-day rolling total precipitation (mm) |
| PERIOD_LABEL | STRING | Wet Period / Dry Period / Normal Period |

### DBT.DRY_SPELL

| Column | Type | Description |
|--------|------|-------------|
| CITY | STRING | City name |
| DATE | DATE | Observation date |
| PRECIPITATION_MM | FLOAT | Daily precipitation (mm) |
| IS_RAIN_DAY | INTEGER | 1 = rain, 0 = dry |
| DRY_SPELL_DAYS | INTEGER | Consecutive dry days up to this date |
| DRY_SPELL_LABEL | STRING | Rain Day / Dry 1-2 days / Short / Extended |
| MAX_DRY_SPELL_SO_FAR | INTEGER | Running maximum dry streak for this city |

### DBT.CITY_WEATHER_SNAPSHOT

All columns from `RAW.CITY_WEATHER` plus dbt SCD columns: `dbt_scd_id`, `dbt_updated_at`, `dbt_valid_from`, `dbt_valid_to`, `dbt_is_current_record`.

### ANALYTICS.CITY_WEATHER_FINAL

| Column | Type | Description |
|--------|------|-------------|
| CITY | STRING | City name |
| DATE | DATE | Historical or forecast date |
| ACTUAL | FLOAT | Observed TEMP_MAX — NULL for forecast rows |
| FORECAST | FLOAT | ML-predicted TEMP_MAX — NULL for historical rows |
| LOWER_BOUND | FLOAT | Lower bound of 95% prediction interval |
| UPPER_BOUND | FLOAT | Upper bound of 95% prediction interval |

---

## Airflow Setup

### Prerequisites

- Docker Desktop
- Apache Airflow 2.10+
- `apache-airflow-providers-snowflake==5.7.0`
- `snowflake-connector-python`
- `dbt-snowflake` (installed via `_PIP_ADDITIONAL_REQUIREMENTS` in docker-compose)

### docker-compose.yaml — Key Settings

```yaml
_PIP_ADDITIONAL_REQUIREMENTS: "yfinance apache-airflow-providers-snowflake==5.7.0 snowflake-connector-python dbt-snowflake==1.8.0"

volumes:
  - ${AIRFLOW_PROJ_DIR:-.}/dags:/opt/airflow/dags
  - ${AIRFLOW_PROJ_DIR:-.}/dbt:/opt/airflow/dbt
```

### Airflow Connection — snowflake_conn

Configure under **Admin → Connections:**

| Field | Value |
|-------|-------|
| Connection Id | `snowflake_conn` |
| Connection Type | Snowflake |
| Schema | `RAW` |
| Login | your Snowflake username |
| Password | your Snowflake password |
| Account | your Snowflake account identifier |
| Warehouse | your warehouse name |
| Database | `USER_DB_FERRET` |
| Role | `TRAINING_ROLE` |

### Airflow Variables

Configure under **Admin → Variables:**

| Key | Value |
|-----|-------|
| `weather_cities` | `[{"city": "Newport Beach", "lat": 33.6189, "lon": -117.9289}, {"city": "Boston", "lat": 42.3584, "lon": -71.0598}, {"city": "Seattle", "lat": 47.6062, "lon": -122.3321}, {"city": "Miami", "lat": 25.7743, "lon": -80.1937}]` |
| `weather_days_back` | `60` |
| `weather_timezone` | `America/Los_Angeles` |

### DAG Execution Order

```
02:30 UTC → WeatherData_ETL   — loads 60-day weather for 4 cities into RAW schema
03:30 UTC → TrainPredict      — trains ML model + generates 7-day forecast
04:30 UTC → WeatherData_DBT   — runs dbt models, tests, snapshot
```

### Running dbt Manually (for testing)

```bash
# Enter the Docker container
docker exec -it lab2-airflow-1 bash

# Navigate to dbt project
cd /opt/airflow/dbt

# Run with credentials
DBT_ACCOUNT=YOUR_ACCOUNT DBT_USER=YOUR_USER DBT_PASSWORD=YOUR_PASSWORD \
DBT_DATABASE=USER_DB_FERRET DBT_ROLE=TRAINING_ROLE \
DBT_WAREHOUSE=YOUR_WAREHOUSE DBT_TYPE=snowflake DBT_SCHEMA=RAW \
/home/airflow/.local/bin/dbt run --profiles-dir . --project-dir .
```

---

## Preset Dashboard

The dashboard was built in Preset (https://preset.io), connected directly to the `DBT` schema in Snowflake. It contains 8 charts covering every aspect of the weather data.

### Chart 1 — 7-Day Rolling Temperature Trends by City
**Type:** Line Chart | **Dataset:** `moving_avg`
Shows the smoothed 7-day rolling average of TEMP_MAX for all four cities from January through April 2026. Miami stays consistently the warmest (25-30°C). Boston shows the widest seasonal swing, starting near -7°C in winter and climbing to 15°C by April. This chart is the baseline view of how temperatures evolved across cities.

### Chart 2 — Temperature Anomaly Heatmap by City
**Type:** Heatmap | **Dataset:** `temp_anomaly`
Each cell represents one day for one city, colored on a Blue-Red scale. Blue = colder than the city's historical average. Red = warmer than normal. Boston shows strong blue clusters in January-February and red clusters in March-April. This makes unusual weather patterns immediately visible without reading individual numbers.

### Chart 3 — Avg Temp Comparison by City Current Month
**Type:** Bar Chart | **Dataset:** `moving_avg` | **Filter:** April 2026
Shows all four cities side by side for each day in April. Makes it very easy to compare cities on the exact same date. Miami consistently leads, followed by Newport Beach, Seattle, and Boston.

### Chart 4 — Precipitation vs Temperature Correlation
**Type:** Scatter Plot | **Dataset:** `rolling_precip`
X-axis is 7-day rolling precipitation, Y-axis is max temperature, color is city. Each dot is one observation. Reveals whether wetter periods tend to be warmer or cooler for each city. Boston and Seattle cluster at lower temperatures with higher rainfall. Miami spreads across higher temperatures with variable precipitation.

### Chart 5 — Dry Spell Streak by City
**Type:** Line Chart | **Dataset:** `dry_spell`
Tracks consecutive dry days for each city over time. Newport Beach regularly reaches 15+ consecutive dry days, consistent with its Mediterranean climate. Boston and Seattle reset frequently. This chart makes drought and dry period patterns visible at a glance.

### Chart 6 — Rainy Days Last 7 Days by City
**Type:** Line Chart | **Dataset:** `rolling_precip`
Tracks how many of the past 7 days had rainfall for each city. Values range from 0 (fully dry week) to 7 (rained every day). Seattle consistently shows higher counts. Newport Beach frequently drops to 0. Complements the dry spell chart by showing frequency rather than streak length.

### Chart 7 — Temperature Anomaly Category Distribution
**Type:** Pie Chart | **Dataset:** `temp_anomaly`
Shows the percentage of days that fell into each anomaly category (Above Normal, Below Normal, Near Normal) across all cities and the full time period. Gives a quick summary of whether the overall period was warm, cold, or typical.

### Chart 8 — Temperature vs Precipitation vs Wind Speed
**Type:** Bubble Chart | **Dataset:** `rolling_precip`
Three variables at once — temperature on X, precipitation on Y, wind speed as bubble size. Larger bubbles at high precipitation indicate stormy, windy, wet conditions. Smaller bubbles at high temperature indicate warm, calm, dry days. The most analytically complex chart on the dashboard.

---

## GitHub Repository Contents

```
weather-forecasting-airflow-snowflake/
│
├── README.md                          ← this file
│
├── dags/
│   ├── weather_etl_pipeline.py        ← ETL DAG (Lab 1 + Lab 2)
│   ├── weather_prediction.py          ← ML Forecast DAG (Lab 1 + Lab 2)
│   └── weather_dbt_dag.py             ← dbt ELT DAG (Lab 2)
│
└── dbt/
    ├── dbt_project.yml
    ├── profiles.yml
    ├── models/
    │   ├── sources.yml
    │   ├── schema.yml
    │   ├── moving_avg.sql
    │   ├── temp_anomaly.sql
    │   ├── rolling_precip.sql
    │   └── dry_spell.sql
    └── snapshots/
        └── city_weather_snapshot.sql
```

---

## Lessons Learned

**dbt schema naming:** When `profiles.yml` sets `schema: DBT` and `dbt_project.yml` also sets `+schema: DBT`, dbt combines them into `DBT_DBT`. The fix is to only set the schema in `profiles.yml` and remove the override from `dbt_project.yml`.

**dbt in Airflow needs the full binary path:** Using just `dbt` in a `BashOperator` fails because Airflow's PATH does not include the user local bin. The correct command uses `/home/airflow/.local/bin/dbt`.

**Environment variable injection:** Rather than hardcoding Snowflake credentials in `profiles.yml`, the Airflow DAG reads from `snowflake_conn` using `BaseHook.get_connection()` and passes values as environment variables. This keeps credentials secure and out of the codebase.

**pip install inside Docker is temporary:** Installing packages with `pip install` inside a running container works but resets when the container restarts. The permanent fix is adding the package to `_PIP_ADDITIONAL_REQUIREMENTS` in `docker-compose.yaml` so it installs automatically on every restart.

**MERGE over INSERT:** Using a MERGE/upsert strategy with a staging table makes the pipeline fully idempotent. Running the ETL multiple times on the same day never creates duplicates.

**Rolling window edge cases:** At the start of each city's date range, the rolling window contains fewer than 7 days. The `ROLLING_WINDOW_DAYS` column in `moving_avg` tracks how many days are actually included so consumers of the table know when to trust the averages.

---

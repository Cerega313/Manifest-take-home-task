# Raw Layer Modeling Notes

The packet does not include physical raw exports, so this project models a realistic raw shape for Amplitude-style event data: one event row with text timestamps and a JSONB `event_properties` payload. In production, this is where badly typed data usually appears.

For the Postgres workflow source, the replication path is assumed to preserve database-native operational types from Postgres. Those staging models therefore focus on column naming, soft-delete filtering, and lineage fields, not heavy type repair.

## Realistic Raw Values

| Raw field | Example clean values | Example dirty values | Staging treatment |
| --- | --- | --- | --- |
| `event_time` | `"2026-05-29T12:31:45Z"`, `"2026-05-29 12:31:45+00"` | `""`, `"unknown"`, `"not-a-date"` | `safe_timestamp` into `event_time`, then `event_date` |
| `ingestion_timestamp` | `"2026-05-29T12:35:00Z"`, `"1716986100000"` | `"null"`, `"undefined"` | `safe_timestamp` into `ingestion_timestamp` |
| `event_properties.file_count` | `"3"`, `3`, `"3.0"` | `""`, `"unknown"`, `"1,200"`, `"null"` | `safe_int64` into `file_count` |
| `event_properties.success_count` | `"2"`, `2` | `"NaN"`, `"n/a"` | `safe_int64` into `success_count` |
| `event_properties.error_count` | `"0"`, `0` | `"undefined"` | `safe_int64` into `error_count` |
| `event_properties.duration_ms` | `"1520"`, `"1520.0"` | `"1,520"`, `"unknown"` | `safe_int64` into `duration_ms`, `safe_float64 / 1000` into `duration_seconds` |
| `event_properties.user_can_act` | `"true"`, `"false"` | `"yes"`, `"0"`, `""` | `safe_boolean` into `user_can_act` |
| `event_properties.task_plugin_type` | `"file_upload"`, `"questionnaire"` | `" File_Upload "` | trim plus lowercase |

## Why Keep Raw And Typed Columns

The staging model keeps raw values such as `raw_file_count` next to typed values such as `file_count`.

This gives analysts and data engineers two useful behaviors:

- metric queries can safely use typed columns without crashing on bad casts;
- data-quality checks can still inspect the original raw values when parsing fails.

The `has_numeric_parse_error` and `has_timestamp_parse_error` flags in `stg_amp__cw_events` are intentionally blunt. They are triage signals that say, "a business-critical raw field was present but could not be parsed into the expected warehouse type."

The YAML contract expects these flags to be `false` with `severity: error`. That means any parsed staging row with a critical numeric or timestamp parse failure blocks the downstream layer instead of letting metrics silently consume malformed values.

## Warehouse Types

- `safe_int64` maps to Postgres `bigint`, equivalent to the usual warehouse `INT64` concept.
- `safe_float64` maps to Postgres `double precision`, equivalent to the usual warehouse `FLOAT64` concept.
- `safe_boolean` normalizes common boolean spellings into `boolean`.
- `safe_timestamp` maps text timestamps and epoch seconds/milliseconds into Postgres `timestamptz`.

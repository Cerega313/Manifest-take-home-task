# Materialization Strategy

## Assumption

This is an internal legal-workflow platform, not a high-volume consumer event stream. The expected number of active users, cases, tasks, and plugin events is modest.

Because of that, Postgres-backed models use table materializations instead of incremental models. Amplitude-backed models are the exception: event streams are append-heavy, so they use incremental materialization keyed by ingestion timestamps and stable business keys.

## Why Not Incremental For Postgres

Incremental models add operational complexity:

- merge keys and late-arriving data rules;
- backfill and reprocessing strategy;
- invalidation logic when raw parser rules change;
- extra tests around duplicate or missed records.

For Postgres workflow tables, that complexity is not justified until observed data volume or runtime proves otherwise.

## Why Incremental For Amplitude

Amplitude-style events are naturally append-oriented. Even with modest volume, incremental materialization is a cleaner fit because:

- new rows arrive by ingestion time;
- late-arriving events can be handled with a short lookback window;
- event parsing and JSON extraction are the most expensive staging operations in this project;
- downstream upload and questionnaire models can update only affected assignments or date/product groups.

This project uses a 2-day incremental lookback for Amplitude-derived models to tolerate late arrivals and minor ingestion delays.

## Staging Layer

Postgres staging models are materialized as tables.

This keeps type-normalized and soft-delete-filtered data stable for downstream models.

`stg_amp__cw_events` is materialized incrementally because raw text timestamps and dirty JSON values are converted into typed fields there. The model uses `event_natural_key` as its unique key and `ingestion_timestamp` as its processing watermark.

For the Postgres workflow source, the assumption is that the raw extract already preserves database-native types. The staging layer therefore focuses on naming, filtering, lineage, and a consistent contract rather than heavy type repair.

## Intermediate Layer

Intermediate models are persisted because they are business-grain entities that can support more than the four take-home marts. Persisting them makes downstream metric logic simpler, more inspectable, and less repetitive.

Postgres-only intermediate models are materialized as tables:

- `int_case_workflow__custom_tasks`
- `int_case_workflow__case_durations`

Amplitude-derived intermediate models are incremental:

- `int_case_workflow__file_upload_attempts` reprocesses assignments with newly ingested upload events.
- `int_case_workflow__questionnaire_assignments` reprocesses assignments touched by either Postgres assignment updates or newly ingested questionnaire events.

Amplitude-derived daily marts are also incremental:

- `marts_metrics__file_upload_daily` recomputes full `metric_date + catalog_product_id` groups affected by newly ingested upload events.
- `marts_metrics__questionnaire_daily` recomputes full `metric_date + catalog_product_id` groups affected by updated questionnaire assignments.

## When To Revisit This

Incremental materialization should broaden if:

- Postgres workflow volume grows enough that full refresh becomes expensive;
- source freshness SLA requires faster rebuilds;
- intermediate joins become a bottleneck;
- the warehouse cost profile makes full refresh materially wasteful.

Until then, full table rebuilds remain the cleaner default for Postgres-backed models, while Amplitude-backed models use incremental processing because it better matches event-stream behavior.

# Observability And Alerting

## What Runs

Raw source health is monitored with three layers:

- dbt source freshness checks using `ingestion_timestamp`.
- Elementary schema-change tests on every raw source table.
- Elementary daily volume-anomaly tests with 28 days of training data, 1 day of detection, and `day_of_week` seasonality.

The key principle is that raw health checks use ingestion time, not business timestamps such as `created_at` or `event_time`. This makes the tests answer "did the pipeline load normally?" instead of "did the product have normal activity?"

## Airflow Orchestration

The project assumes an Airflow DAG runs the warehouse layers sequentially:

- raw ingestion completes first;
- source freshness and raw Elementary tests run before transformations;
- staging models build after raw checks pass;
- staging tests run before intermediate models;
- intermediate models and tests run before mart builds;
- mart tests run before downstream dashboards, AI agents, or reports consume the data.

Each test stage acts as a quality gate. Failed tests or freshness checks stop the downstream layer from being promoted and trigger Slack notifications so the data team can react quickly, inspect stored failures, and fix the upstream issue before incorrect metrics reach consumers.

## Failure Storage

All Elementary source tests use `store_failures: true`.

In production, failed rows and anomaly metadata should land in the Elementary results schema so the team can inspect the actual table, detection window, observed row count, expected range, and failing run.

## Notification Routing

Failures route by severity and source domain:

- `severity: warn` for schema drift and volume anomalies on raw landing tables.
- Warnings post to a data-observability Slack channel such as `#data-alerts`.
- Repeated warnings or freshness failures older than the SLA escalate to the owning pipeline channel.
- Pager-style alerts should be reserved for production marts or raw feeds that block executive dashboards, customer-facing workflows, or AI-agent answers.

## Metric Threshold Alerts

Some marts have business thresholds, not only data-quality thresholds. Those thresholds should produce owner-facing notifications after the mart layer finishes successfully.

For `marts_metrics__custom_tasks_daily`, the PM target is:

```text
manually_added_task_rate <= 20%
```

A daily Airflow task can evaluate yesterday's rows and post to the responsible workflow/product channel when any product exceeds the target. The notification should include:

- product / visa key: `catalog_product_id`;
- metric date;
- actual manually added task rate;
- target rate, `20%`;
- absolute excess over target, for example `actual_rate - 0.20`;
- total tasks and manually added tasks, so the team can separate real template issues from small-denominator noise.

The same notification can include rolling context:

- number of exceeded days in the last 7 days;
- number of exceeded days in the last 30 days;
- median daily excess over target for the last 7 days;
- median daily excess over target for the last 30 days.

This alert is intentionally separate from raw pipeline alerts. A raw volume anomaly says the data feed may be unhealthy. A PM-threshold alert says the data is healthy enough to measure, and the measured business process is outside the agreed target.

## Example Job Shape

The scheduled job would run after raw ingestion:

```bash
dbt source freshness --select source:postgres_workflow source:amplitude
dbt test --select source:postgres_workflow source:amplitude
edr monitor --slack-webhook-url "$ELEMENTARY_SLACK_WEBHOOK_URL"
```

For a managed orchestrator, the same shape applies:

- raw ingestion task
- dbt source freshness task
- dbt source tests task
- dbt staging build and test task
- dbt intermediate build and test task
- dbt mart build and test task
- Elementary monitor/report task
- Slack/email notification on failed or warning state

## Why This Matters For AI Agents

The AI layer should not answer from a metric mart if a required raw source is stale, has a schema change, or has a severe volume anomaly. The agent should return a degraded-data warning with the failing source and the last successful load timestamp.

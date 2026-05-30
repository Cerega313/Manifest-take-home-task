# Agent Metric Contract

## Purpose

Internal agents should answer from the governed metrics layer, not by inventing joins over raw tables or by re-aggregating already aggregated values.

The metric contract defines what the agent is allowed to do when a user asks for a different time grain, such as week, month, or quarter.

## Required Metadata

Every AI-facing metric should expose:

- metric name;
- metric version;
- business definition;
- source mart or base model;
- base grain;
- default time dimension;
- other allowed time dimensions;
- allowed time grains;
- allowed dimensions;
- numerator and denominator for ratio metrics;
- aggregation behavior;
- owner;
- freshness SLA;
- caveats and unsupported breakdowns.

The project stores this metadata in dbt YAML `meta` fields on mart models and columns.

The agent should use this contract for query planning and answer formatting. It should not use the contract as optional documentation that can be ignored when a question is inconvenient.

## Aggregation Behavior

Additive counts can be summed across time:

```text
monthly_total_tasks = sum(daily_total_tasks)
```

Ratio metrics must be recomputed from components:

```text
monthly_questionnaire_submission_rate =
sum(submitted_assignments) / sum(activated_assignments)
```

The agent must not calculate:

```text
avg(daily_assignment_submission_rate)
```

Averages should be recomputed from base rows or from explicit sum/count components. Averaging daily averages is unsafe unless daily cohort sizes are identical.

Medians and percentiles must be recomputed from base-grain rows:

```text
median(kickoff_to_filing_days)
from int_case_workflow__case_durations
where filing_date is in the requested period
```

The agent must not calculate:

```text
avg(daily_median_kickoff_to_filing_days)
median(monthly_median_kickoff_to_filing_days)
```

Funnel rates must be recomputed from assignment-grain step counts:

```text
monthly_open_to_start_rate =
sum(started_upload_count) / sum(opened_upload_plugin_count)
```

The agent must not compute upload conversion from raw event counts because repeated opens and retries can distort the funnel.

## Behavior By Metric

### Questionnaire Completion

- Type: ratio
- Base grain: `task_assignment`
- Default time dimension: `metric_date`, activation date
- Safe rollup: `sum(submitted_assignments) / sum(activated_assignments)`
- Unsafe rollup: average of daily or weekly submission rates

### Custom Tasks

- Type: ratio
- Base grain: `task`
- Default time dimension: `metric_date`, task creation date
- Safe rollup: `sum(manually_added_tasks) / sum(total_tasks)`
- Unsafe rollup: average of daily custom-task rates

### Case Duration

- Type: average / percentile over case-level duration
- Base grain: `case`
- Default time dimension: `metric_date`, filing date
- Safe average rollup: recompute from base rows or explicit sum/count components
- Safe median/p75/p90 rollup: recompute from `int_case_workflow__case_durations`
- Unsafe rollup: average of daily medians, median of weekly medians, or average of daily p90 values

### File Upload Funnel

- Type: funnel ratios
- Base grain: `task_assignment`
- Default time dimension: `metric_date`, first plugin-open date
- Safe rollup: sum step counts, then divide
- Unsafe rollup: average of daily conversion rates or event-count conversion

## Unsupported Requests

If a requested dimension or time grain is not declared in the metric contract, the agent should return a controlled limitation message or ask a clarification question.

Example:

```text
This metric is not defined by attorney in the current metrics layer. It is available by catalog_product_id and metric_date.
```

This behavior is safer than building an unreviewed join path over operational tables.

## Answer Context

Agent answers should include enough context to make the number auditable:

- metric name and version;
- period;
- time dimension;
- numerator and denominator for ratio metrics;
- source mart or base model;
- caveats or data-quality warnings when relevant.

## Quality And Freshness

If relevant freshness, schema, volume, or model tests fail, the agent should include a degraded-data warning instead of returning the metric as fully reliable.

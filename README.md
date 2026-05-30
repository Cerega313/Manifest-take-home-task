# Manifest Case Workflow Take-Home

## Submission Summary

This repository answers the four launch metrics from the brief and adds a small dbt-style analytics skeleton showing how the work can be operationalized in a warehouse.

The brief only requires four metric queries plus written decisions/design notes. This project includes that minimum plus a lightweight modeling layer because the problem is fundamentally about metric definitions, source-of-truth discipline, and production readiness.

The repository is organized in two parts:

- **Take-home answer:** the files required to answer the prompt directly.
- **Production extension:** additional dbt models, tests, observability notes, and AI-agent guardrails that show how the same metric logic could be made reliable in a warehouse.

## Repository Layout

- `sql/`: the four analyst-facing metric queries requested in the brief.
- `models/staging/`: typed cleanup over the raw Postgres and Amplitude sources.
- `models/intermediate/`: business-grain models at case, task, assignment, and upload-attempt level.
- `models/marts/`: daily metric marts for dashboarding and trend analysis.
- `tests/`: reusable generic dbt tests invoked from YAML model/source contracts.
- `docs/raw_layer_modeling.md`: realistic raw-field examples and safe-casting rules.
- `docs/observability.md`: Airflow orchestration, freshness, Elementary anomaly checks, failure storage, and Slack alert routing.
- `docs/materialization_strategy.md`: materialization choices for Postgres tables and Amplitude incremental models.
- `docs/agent_metric_contract.md`: AI-agent aggregation rules for ratios, averages, percentiles, and funnel metrics.
- `docs/ai_agent_consumption_and_guardrails.md`: practical AI-agent guardrails for consuming these four metrics safely.
- `decisions.md`: metric-by-metric definitions, edge cases, and debatable choices.
- `design.md`: one-page design for an AI-safe analytics layer.
- `dbt_project.yml`: minimal dbt project configuration to show how the layers fit together.

## How To Read This Submission

### Required Take-Home Answer

1. Read [decisions.md](decisions.md) for the metric definitions, source choices, numerator/denominator logic, edge cases, and debatable decisions.
2. Read the four root metric queries in [sql](sql/) to see the direct SQL deliverables requested in the brief.
3. Read [design.md](design.md) for the system-design answer about dashboards, semantic definitions, and AI-safe metric consumption.

### Extra Production Extension

The remaining files show how the answer could be operationalized beyond the brief:

1. Inspect [models](models/) for a dbt-style staging, intermediate, and mart structure.
2. Inspect [tests](tests/) and the model YAML files for reusable data-quality checks.
3. Read [docs/observability.md](docs/observability.md) for freshness, Elementary anomaly checks, and Slack alert routing.
4. Read [docs/agent_metric_contract.md](docs/agent_metric_contract.md) and [docs/ai_agent_consumption_and_guardrails.md](docs/ai_agent_consumption_and_guardrails.md) for the lightweight AI-agent metric contract.

These additions are included because the metrics are likely to be consumed by dashboards and internal agents. The extra layer demonstrates how to prevent common production failures: ambiguous definitions, unsafe rollups, stale data, schema drift, and inconsistent metric answers across tools.

## Optional dbt Validation

The four requested deliverables are the SQL files and documentation. The dbt layer is included to show how the logic would be operationalized.

Without a configured warehouse profile and source tables, the safest structural checks are:

```bash
dbt deps
dbt parse
```

If a reviewer also configures `profiles.yml` and provides compatible raw source tables, the model tests can be run with:

```bash
dbt test
```

`packages.yml` includes Elementary because the raw source contracts demonstrate freshness, schema-change, and volume-anomaly monitoring.

## Overall Approach

The approach prioritizes authoritative source selection first, then transparent metric definitions.

- Metric 1, questionnaire completion:
  Postgres is the source of truth for assignment lifecycle timestamps. Amplitude is used as a supporting signal because the provided backend schema does not expose an explicit plugin type on tasks or assignments.
- Metric 2, custom tasks per visa:
  Postgres only. This is a structural workflow-coverage metric, so task inventory and task provenance belong in the operational model.
- Metric 3, end-to-end case duration:
  Postgres only. Duration should be computed from case lifecycle dates, not UI events.
- Metric 4, file upload funnel:
  Amplitude primary. This is a behavioral plugin funnel, and the subtle trap lives in the event payload semantics.

## Biggest Judgment Calls

1. Questionnaire metric title vs. body:
   the metric title says "% of beneficiaries", but the clarified definition uses activated questionnaire assignments as the denominator. Assignment-level submission is treated as the primary take-home KPI; beneficiary-level variants remain available only in the daily mart as diagnostic context, not as the core take-home SQL.
2. Manual task vs. custom task:
   the PM target explicitly says "manually added", which is narrower than "all non-template tasks". The model exposes a strict manual classification and a broader fallback classification so the ambiguity is visible rather than hidden.
3. Case duration definition:
   `kickoff_date -> filing_date_actual` is used as the primary operational KPI, with `created`, `initialized`, and `classification` alternatives kept side by side because they answer different business questions and have different missingness patterns.

## Required Take-Home Answer Delivered

- All four requested metric SQL files.
- A separate [decisions.md](decisions.md).
- A separate [design.md](design.md).
- Non-obvious SQL logic commented in the core models and metric files.

## Extra Production Extension Delivered

The extension is intentionally secondary to the required answer. Its purpose is to demonstrate how the metric definitions could survive real production use.

- dbt-style layered model structure instead of only standalone queries.
- Daily metric marts so the same logic can power trend charts, not only one-off answers.
- YAML-declared dbt tests for raw daily volume, rate bounds, duration sanity, and funnel monotonicity.
- Elementary-style raw source observability: source freshness, schema-change checks, daily volume anomalies, and alert routing.
- Realistic raw-to-staging handling for dirty JSON event fields, including safe INT64/FLOAT64/boolean parsing.
- Table materializations for Postgres-backed models and incremental materializations for Amplitude-backed event models.
- AI-agent metric contracts that prevent unsafe rollups such as averaging rates or aggregating medians from daily medians.
- Practical AI-agent consumption guardrails focused on safe rollups, approved dimensions, default dates, freshness context, and aggregate-first answers.
- Explicit support for alternate metric definitions where the brief is intentionally ambiguous.

## Important Assumptions

- The Amplitude landing table is modeled as `amplitude.events`, with one row per event and a JSONB `event_properties` payload. The brief explicitly allows reasonable SQL assumptions.
- `catalog_product_id` is used as the visa/product key because the provided schema does not include the human-readable product dimension.
- Exact enum values for `cw_task.creation_source` and `cw_task_assignment.action` are not present in the packet, so those assumptions are explicit in both SQL and `decisions.md`.

## Open Questions Before Production

1. What are the exact enum values for `cw_task.creation_source`, `cw_task_assignment.action`, and any backend plugin mapping field?
2. What is the canonical dimension for "visa type": `catalog_product_id`, `catalog_product_name`, or another product table not included in the prompt?
3. For questionnaire completion, should the primary beneficiary KPI mean "beneficiary submitted any activated questionnaire" or "beneficiary submitted all activated questionnaires"?
4. Is there an authoritative backend mapping from task template or assignment template to plugin type so the current heuristic for questionnaire identification can be removed?

## Notes On Productionization

- The daily marts are the layer intended for BI and internal AI agents.
- The root `sql/metric_*.sql` files use dbt `ref()` to point at the prepared intermediate models. The dbt model files show how those intermediate relations are built.
- The provided packet mentions 14 Amplitude events, but the attached event dictionary enumerates 13. That mismatch should be clarified before production hardening.

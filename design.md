# AI-Safe Analytics Layer Design

## Goal

Give dashboards and internal AI agents access to the same trusted business metrics without letting the agent invent definitions, ignore permissions, or silently answer from raw tables.

## Proposed shape

- Raw layer:
  replicated Postgres workflow tables, legacy CM tables, and raw Amplitude events
- Staging layer:
  typed cleanup, canonical IDs, deleted-row handling, JSON extraction, naming normalization
- Intermediate layer:
  business-grain entities such as `questionnaire_assignments`, `custom_tasks`, `case_durations`, and `file_upload_attempts`
- Metric marts:
  curated daily metric tables with explicit numerators, denominators, grain, owner, freshness SLA, and caveats
- Semantic contract for agents:
  a metric catalog that exposes only curated marts plus machine-readable metadata about definitions, filters, allowed dimensions, and known caveats

## Preventing Agent Hallucination

- Do not let the agent query raw tables by default.
- Publish a metric registry where every metric has:
  - business definition
  - SQL owner
  - numerator
  - denominator
  - grain
  - allowed dimensions
  - freshness SLA
  - caveats and known failure modes
- Expose column-level descriptions from dbt docs or the semantic layer directly to the agent at query-planning time.
- Require the agent to cite the metric object or mart it used, not just return a number.
- Prefer "approved query templates" for sensitive or high-ambiguity KPIs such as conversion funnels and legal workflow SLAs.

## Agent Aggregation Rules

Internal agents should not be treated as authors of metric logic. They should be consumers of a governed metrics layer.

When a user changes time grain from day to week, month, or quarter, the agent should inspect the metric contract and choose the correct aggregation path:

- Additive counts can be summed across time, such as `activated_assignments`, `total_tasks`, or `opened_upload_plugin_count`.
- Ratio metrics must be recomputed from components, not averaged from daily rates. For example, monthly questionnaire submission is `sum(submitted_assignments) / sum(activated_assignments)`, not `avg(assignment_submission_rate)`.
- Average metrics should be recomputed from `sum(value)` and `count(rows)` components where those components are available. Averaging precomputed daily averages is not safe unless all daily cohorts have equal weight.
- Median and percentile metrics must be recomputed from base-grain rows, not from daily medians or percentiles. For case duration, monthly `median_kickoff_to_filing_days` should be calculated from `int_case_workflow__case_durations`, where one row represents one case.
- Funnel metrics should be recomputed from assignment-grain step flags, not event counts and not averaged conversion rates.

If the requested dimension, time grain, or aggregation behavior is not declared in the metric contract, the agent should ask a clarification question or return a controlled limitation message. It should not infer a new definition from raw tables.

The mart YAML includes `meta` fields for AI-facing metrics to make this behavior machine-readable: metric type, base grain, numerator, denominator, default time dimension, allowed time grains, and aggregation behavior.

## AI Agent Consumption Guardrails

The agent-facing design is intentionally scoped to this take-home: internal employees should be able to ask questions about the four launch metrics without letting the agent invent joins or definitions.

Practical guardrails:

- Expose curated metric marts and approved intermediate models, not raw `cw_*` tables or raw Amplitude events.
- Require every agent-facing metric to declare grain, default time dimension, allowed dimensions, numerator, denominator, and aggregation behavior.
- Recompute ratios from numerator and denominator; recompute medians and percentiles from case-level rows.
- Return a controlled limitation message when a requested breakdown is not declared, such as questionnaire completion by attorney.
- Include calculation context in answers: source model, time dimension, numerator, denominator, and data freshness when available.
- Default to aggregate answers. Row-level case/task details should require a separate access-controlled workflow.
- Treat free-text case/questionnaire/document fields as data, not instructions, if they are ever exposed to an agent.
- Keep the analytics agent read-only; operational actions such as changing task status or sending messages are out of scope for this metrics layer.

This is a production extension, not a replacement for the core deliverable. The core deliverable remains the governed SQL definitions and marts for the four metrics.

## Where dbt fits

- dbt is the right place for source contracts, staging cleanup, business-grain intermediate models, metric marts, tests, and documentation.
- Materialization choices:
  - Postgres staging/intermediate: tables, because the internal platform is expected to generate modest operational volume and full refresh is simpler to reason about
  - Amplitude staging/intermediate: incremental tables, because event streams are append-heavy and JSON parsing should be bounded by ingestion watermarks
  - marts: tables by default, with Amplitude-derived daily marts incremental by date/product groups
- The project leans on:
  - source tests for freshness and schema drift
  - model tests for uniqueness, relationships, and accepted values
  - singular tests for domain logic like monotonic funnels and non-negative durations
  - exposures or metadata tags to identify AI-facing marts vs. BI-only marts

## Freshness, drift, and metric breakage

- Freshness:
  source freshness on ingestion timestamps, not business timestamps like `updated_at`
- Drift:
  detect new enum values, new event names, null spikes, and volume anomalies
- Metric breakage:
  protect rate bounds, denominator cliffs, and cross-source reconciliations with automated tests
- Surfacing:
  a failing freshness or semantic test should mark the downstream metric as degraded so both dashboards and agents can warn users instead of returning confident nonsense

## Access control

- Agent-facing access should default to aggregated metric marts.
- Sensitive case artifacts, uploaded documents, and free-text questionnaire answers should not be exposed through these metric endpoints.
- Row-level case/task details require a separate permission model and are outside the core metric layer proposed here.

## Trade-Off To Debate

How much flexibility to give the agent outside the curated metric layer:

- Tight curation improves trust, consistency, and permission safety, but slows down answerability for new questions.
- Looser raw-table access increases coverage, but also sharply increases the risk of wrong definitions and inconsistent answers.

For this workflow launch, curated marts and reviewed semantic definitions are the right default. Raw-table exploration belongs in analyst workflows, not in the employee-facing agent.

# Metric Decisions

## Metric 1: % of beneficiaries who complete the questionnaire

### What The Metric Shows

The metric shows what share of activated questionnaire assignments are completed by the beneficiary each week.

After the clarification from Seva, questionnaire means a task inside an already existing case, not a pre-contract lead questionnaire.

The workflow path is:

```text
cw_case -> cw_task -> cw_task_assignment
```

Only questionnaires inside this case workflow are counted.

### Primary Data Source

Primary source: Postgres.

Required tables:

- `cw_case`
- `cw_task`
- `cw_task_assignment`

Postgres is authoritative because assignment lifecycle state is stored in `cw_task_assignment`: activation, submission, and completion timestamps.

Amplitude can support questionnaire identification and user-behavior validation, but it is not the primary source for questionnaire completion state.

### Calculation Grain

Calculation grain:

- `task_assignment_id`

The metric counts activated questionnaire assignments, not just beneficiaries and not just cases.

### Denominator

Denominator:

- activated questionnaire assignments

Condition:

```sql
activated_ts is not null
```

Soft-deleted records are excluded upstream in staging:

```sql
cw_case.deleted_at is null
cw_task.deleted_at is null
cw_task_assignment.deleted_at is null
```

### Numerator

Primary numerator:

- questionnaire assignments where `submitted_ts is not null`

This means the beneficiary filled out the questionnaire and submitted it for review.

Additional stricter numerator:

- questionnaire assignments where `completed_ts is not null`

This means the assignment was completed after legal-team review.

### Formula

Primary rate:

```text
questionnaire_submission_rate =
submitted_questionnaire_assignments / activated_questionnaire_assignments
```

Additional stricter rate:

```text
questionnaire_reviewer_completion_rate =
reviewer_completed_questionnaire_assignments / activated_questionnaire_assignments
```

### Grouping

The take-home metric groups by activation week:

```sql
date_trunc('week', activated_ts)
```

### Key filters

- New case workflow only: `cw_*` tables
- Questionnaire candidates are identified by one or more of:
  - task name contains `questionnaire`
  - assignment action contains `questionnaire`
  - supporting Amplitude signal shows `task_plugin_type = 'questionnaire'`

### Important Debatable Choice

The documents contain two possible completion signals:

- `submitted_ts`
- `completed_ts`

`submitted_ts` is the primary metric because the business question is completion from the beneficiary side.

`completed_ts` is still included as a stricter secondary metric because the brief mentions reviewer-completed questionnaires.

### SQL Behavior

The SQL:

1. takes questionnaire assignments;
2. keeps only activated assignments;
3. groups by `date_trunc('week', activated_ts)`;
4. counts activated assignments;
5. counts submitted assignments;
6. counts reviewer-completed assignments;
7. calculates submission and reviewer-completion rates.

### Edge Cases

- One beneficiary can have more than one questionnaire assignment.
- One case can contain multiple questionnaire assignments.
- `completed_ts` likely reflects downstream review completion, not just beneficiary action.
- If a questionnaire assignment exists in Postgres but never emits an Amplitude event and has no questionnaire-like naming/action signal, the current heuristic may miss it.
- `iteration_count > 0` suggests rework; those rows remain included because rework is part of the actual workflow burden.

## Metric 2: % custom tasks per visa type, target <= 20%

### What The Metric Shows

The metric shows what share of tasks for each visa type or product was created manually.

The business interpretation is workflow-template coverage: if too many tasks are manual, the standard process does not cover real cases well enough and the template should be improved.

Target from the brief:

```text
custom tasks <= 20%
```

### Primary Data Source

Primary source: Postgres.

Required tables:

- `cw_task`
- `cw_case`

Postgres is authoritative because tasks and task creation provenance are stored in `cw_task`.

### Link Between Task And Visa Type

There is no direct task-to-visa-type field in `cw_task`. The relationship goes through the parent case:

```text
cw_task.case_id -> cw_case.id -> cw_case.catalog_product_id
```

After the clarification from Seva:

- legacy data previously used `visa_type` as a string;
- the new system uses a normalized product catalog;
- the new workflow currently covers EB-1A.

The provided schema does not include the product dimension table, so the metric groups by:

```sql
cw_case.catalog_product_id
```

Even if the current data effectively contains only EB-1A, the query is written to support future products and visa types.

### Calculation Grain

Calculation grain:

- `task_id`

Each row in `cw_task` is treated as one task.

### Denominator

Denominator:

- all non-deleted tasks on non-deleted cases

Conditions:

```sql
cw_task.deleted_at is null
cw_case.deleted_at is null
```

Soft-deleted records are excluded upstream in staging.

### Numerator

Primary numerator:

- manually created / custom tasks

Primary field:

```sql
cw_task.creation_source
```

The provided schema does not include exact enum values for `creation_source`. The SQL therefore uses an explicit assumed manual set:

```sql
creation_source in ('manual', 'custom', 'user_added')
```

The exact values must be confirmed before production use.

Additional diagnostic signal:

```sql
task_template_id is null
```

This signal is not used as the only primary custom-task definition because a task without a template is not necessarily manually created.

### Formula

Primary rate:

```text
custom_task_rate =
custom_tasks / total_tasks
```

In the SQL output this is named:

```text
manually_added_task_rate =
manually_added_tasks / total_tasks
```

Target flag:

```text
is_above_pm_target =
manually_added_task_rate > 0.20
```

### Grouping

The take-home metric groups lifetime counts by:

```sql
catalog_product_id
```

The dbt mart also exposes daily task-created cohorts for trend monitoring.

### Key Filters

- `cw_task.deleted_at is null`
- `cw_case.deleted_at is null`
- Tasks must join to a case
- `catalog_product_id` is used as the available product / visa key

### Important Debatable Choice

Not every task outside the base template is necessarily a "bad" custom task.

The brief references several creation paths:

- generated from workflow template
- added from shared library
- AI-suggested
- manually added by paralegal or attorney

The primary numerator should include manually created tasks, not library tasks and not automatically suggested tasks.

Another engineer might define custom tasks as every task where `task_template_id is null`. That definition is too broad for the PM target because it can overstate template failure by mixing manually created work with other expected non-template work.

### SQL Behavior

The SQL:

1. takes all tasks from `cw_task`;
2. joins tasks to `cw_case`;
3. derives product / visa type through `catalog_product_id`;
4. counts all tasks;
5. separately counts manually created tasks;
6. calculates the manual-task rate;
7. compares the rate to the 20% PM target with `is_above_pm_target`.

### Operational Alerting

Because this metric has a hard PM target, the daily mart can drive a product-team notification after the Airflow mart job finishes.

If yesterday's `manually_added_task_rate` is greater than `20%` for any `catalog_product_id`, the alert should include:

- product / visa key;
- metric date;
- actual manually added task rate;
- target rate;
- excess over target;
- total tasks and manually added tasks.

The alert can also include rolling context for the last 7 and 30 days:

- number of days above target;
- median daily excess over the 20% target.

This separates business-threshold monitoring from data-quality monitoring: raw freshness and volume alerts indicate pipeline health, while the custom-task threshold alert indicates that the workflow template may need product or operations attention.

### Edge Cases

- Exact enum values for `creation_source` are not provided in the packet.
- `task_template_id is null` remains a diagnostic signal, not the primary target definition.
- Current data may contain only EB-1A, but the metric is grouped by product key so that future products do not require a rewrite.
- Different workflow template versions can have different baseline task coverage; version-level diagnostics may be useful if the product-level rate moves above target.

## Metric 3: End-to-end case duration

### What The Metric Shows

The metric shows how long case preparation takes from the start of active work to actual filing.

The brief explicitly asks for a proposed definition and defense because "case duration" can reasonably mean several different intervals.

### Primary Data Source

Primary source: Postgres.

Required table:

- `cw_case`

Postgres is authoritative because case lifecycle dates are backend workflow state, not front-end behavior.

### Primary Definition

Primary definition:

```text
kickoff_date -> filing_date_actual
```

Meaning:

```text
actual start of active case work -> actual filing date
```

Why this is the primary KPI:

- `kickoff_date` represents the start of active case work;
- `filing_date_actual` represents the actual case filing;
- the metric measures case preparation duration, not post-filing waiting time.

### Why `decision_date` Is Not Used

`decision_date` is after filing. If it is used as the end date, the metric includes USCIS response time in addition to team preparation work.

That is not the best endpoint for measuring how quickly the team prepares a case for filing.

### Additional Definitions

Several durations are exposed side by side to make the definition transparent:

- `created_at::date -> filing_date_actual`
- `initialized_at::date -> filing_date_actual`
- `kickoff_date -> filing_date_actual`
- `classification_date -> filing_date_actual`

The primary definition remains:

```text
kickoff_date -> filing_date_actual
```

### Calculation Grain

Calculation grain:

- `case_id`

Each row in `cw_case` is treated as one case.

### Filters

Deleted cases are excluded upstream in staging:

```sql
deleted_at is null
```

The primary completed-duration population requires:

```sql
kickoff_date is not null
filing_date_actual is not null
filing_date_actual >= kickoff_date
```

Rows with invalid date order are not silently converted into negative duration values. The duration field becomes `null`, and the row is excluded from the primary completed-duration aggregation.

### Metrics Calculated

Primary duration formula:

```text
case_duration_days =
filing_date_actual - kickoff_date
```

The take-home SQL outputs:

- `case_count`
- `avg_kickoff_to_filing_days`
- `median_kickoff_to_filing_days`
- `p75_kickoff_to_filing_days`
- `p90_kickoff_to_filing_days`

Median and percentiles are included because case durations are likely skewed. A few very long cases can distort the average.

### Grouping

The take-home metric groups by:

```sql
catalog_product_id
```

This keeps the metric ready for future products and visa types even if the current workflow data only contains EB-1A.

### SQL Behavior

The SQL:

1. takes non-deleted cases from `cw_case` through the staging model;
2. keeps cases with valid `kickoff_date` and `filing_date_actual`;
3. requires `filing_date_actual >= kickoff_date`;
4. calculates days between `kickoff_date` and `filing_date_actual`;
5. groups by `catalog_product_id`;
6. outputs average, median, p75, and p90.

### Edge Cases

- Missing dates will shrink the valid population differently across definitions.
- Invalid date order indicates bad backfill, timezone, or data-entry issues; those rows are excluded from duration aggregates by nulling the affected duration field.
- `case_matter_case_id` indicates a legacy linkage; that count is exposed because migrated/hybrid cases can distort launch metrics.
- `decision_date` can be useful for a separate post-filing lifecycle metric, but it is not part of the case-preparation duration.

### Important Debatable Choice

Another engineer might choose `initialized_at -> filing_date_actual` to stay purely inside the new workflow system. `kickoff_date -> filing_date_actual` maps more directly to the business question: how long active case preparation takes before filing.

## Metric 4: File-upload conversion funnel

### What The Metric Shows

The metric shows where beneficiaries encounter problems while uploading documents.

After the clarification from Seva, the goal is to evaluate whether document upload works reliably and without friction, especially when a user uploads multiple files or folders.

### Primary Data Source

Primary source: Amplitude.

Required events:

- `cw_task_plugin_opened`
- `cw_doc_upload_started`
- `cw_doc_upload_completed`

After the clarification from Seva, all events with the `cw_` prefix belong to the new workflow functionality.

Amplitude is the primary source because this is a front-end plugin funnel and the relevant behavior is captured in event instrumentation.

### Funnel

The funnel is:

1. beneficiary opened the upload plugin;
2. beneficiary started an upload;
3. files were successfully uploaded.

Event sequence:

```text
cw_task_plugin_opened -> cw_doc_upload_started -> cw_doc_upload_completed
```

### Calculation Grain

Best calculation grain:

- `task_assignment_id`

File upload happens in the context of a specific task assignment. Event-count grain is not used because one user can open the plugin multiple times or retry uploads multiple times.

If `task_assignment_id` is missing in part of the instrumentation, the fallback grain should be:

```text
case_id + task_id
```

### Key Filters

- `actor_role = 'beneficiary'`
- `task_plugin_type = 'file_upload'`
- `task_assignment_id is not null`

### Main Data Trap

`cw_doc_upload_completed` does not automatically mean a successful upload.

The event payload contains:

- `file_count`: number of files selected for upload;
- `success_count`: number of files uploaded successfully;
- `error_count`: number of files that failed to upload.

Any-success upload is defined as:

```sql
success_count > 0
```

Full-success upload is defined as:

```sql
success_count = file_count
```

The full-success definition also requires `file_count > 0`.

### Metrics Calculated

The take-home SQL outputs:

- `opened_upload_plugin_count`
- `started_upload_count`
- `completed_upload_with_any_success_count`
- `completed_upload_with_full_success_count`
- `open_to_start_rate`
- `start_to_any_success_rate`
- `start_to_full_success_rate`
- `overall_any_success_rate`
- `overall_full_success_rate`

### Formula

```text
open_to_start_rate =
started_upload_count / opened_upload_plugin_count

start_to_any_success_rate =
completed_upload_with_any_success_count / started_upload_count

start_to_full_success_rate =
completed_upload_with_full_success_count / started_upload_count

overall_any_success_rate =
completed_upload_with_any_success_count / opened_upload_plugin_count

overall_full_success_rate =
completed_upload_with_full_success_count / opened_upload_plugin_count
```

### SQL Behavior

The SQL:

1. takes Amplitude events for the upload plugin;
2. keeps only `actor_role = 'beneficiary'`;
3. groups events by `task_assignment_id`;
4. determines whether the plugin was opened;
5. determines whether upload was started;
6. determines whether at least one file uploaded successfully;
7. determines whether the completed upload was fully successful;
8. calculates funnel step counts and transition rates.

### Edge Cases

- Multiple attempts can exist for one assignment.
- `file_count` on `cw_doc_upload_started` reflects selected files, not necessarily uploaded files.
- Without a session identifier, full success is evaluated from completed upload events rather than by trying to match every start event to a completion event.
- Attorney/paralegal uploads would distort a beneficiary conversion funnel, so the metric filters to beneficiary actor role.

### Important Debatable Choice

Another engineer might compute the funnel on event counts. Assignment grain is more defensible because repeated opens and repeated retries would inflate the denominator and numerator asymmetrically.

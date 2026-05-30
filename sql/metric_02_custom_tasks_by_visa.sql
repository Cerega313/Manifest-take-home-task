/*
Metric: % custom tasks per visa type, target <= 20% -- lifetime, per visa

What the metric shows:
- The share of tasks for each product / visa type that were created manually.
- A high rate suggests the workflow template is not covering real case work well enough.

Primary source:
- Postgres only

Required tables, via dbt model:
- `cw_task`
- `cw_case`

Grain:
- task

Task-to-product relationship:
- `cw_task.case_id -> cw_case.id -> cw_case.catalog_product_id`

Denominator:
- all non-deleted tasks on non-deleted cases

Primary numerator:
- manually created tasks based on `cw_task.creation_source`

Assumption:
- Exact `creation_source` enum values are not present in the packet. The
  intermediate model assumes `manual`, `custom`, and `user_added` are manual.

Diagnostic signal:
- `task_template_id is null` is exposed separately, but not used as the only
  primary custom-task definition because non-template does not always mean manual.

Target:
- manually added task rate should be <= 20%.
*/

with task_base as (
    select
        catalog_product_id,
        task_id,
        is_manually_added_task,
        is_non_template_task,
        is_custom_task_broad
    from {{ ref('int_case_workflow__custom_tasks') }}
)

select
    catalog_product_id as visa_type_key,
    count(*) as total_tasks,
    count(*) filter (
        where is_manually_added_task = 1
    ) as manually_added_tasks,
    count(*) filter (
        where is_non_template_task = 1
    ) as non_template_tasks,
    count(*) filter (
        where is_custom_task_broad = 1
    ) as broad_custom_tasks,
    0.20::numeric as manual_task_rate_target,
    round(
        count(*) filter (where is_manually_added_task = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as manually_added_task_rate,
    round(
        count(*) filter (where is_non_template_task = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as non_template_task_rate,
    round(
        count(*) filter (where is_custom_task_broad = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as broad_custom_task_rate,
    case
        when count(*) filter (where is_manually_added_task = 1)::numeric
             / nullif(count(*), 0) > 0.20
        then true
        else false
    end as is_above_pm_target
from task_base
group by 1
order by manually_added_task_rate desc, visa_type_key

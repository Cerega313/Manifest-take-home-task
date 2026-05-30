{{ config(materialized='table') }}

select
    task_created_date as metric_date,
    catalog_product_id,
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
from {{ ref('int_case_workflow__custom_tasks') }}
group by 1, 2

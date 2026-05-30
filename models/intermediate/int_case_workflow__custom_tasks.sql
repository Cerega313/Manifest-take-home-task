{{ config(materialized='table') }}

with manual_creation_sources as (
    select 'manual' as creation_source
    union all select 'custom'
    union all select 'user_added'
),

library_creation_sources as (
    select 'library' as creation_source
    union all select 'shared_library'
),

ai_creation_sources as (
    select 'ai_suggested' as creation_source
    union all select 'ai_generated'
),

task_base as (
    select
        t.task_id,
        t.case_id,
        c.beneficiary_id,
        c.catalog_product_id,
        c.flow_template_id,
        c.flow_template_version_id,
        t.task_name,
        t.task_template_id,
        lower(coalesce(t.task_creation_source, '')) as task_creation_source,
        t.task_sub_stage,
        t.task_status,
        t.task_created_at,
        t.task_created_at::date as task_created_date
    from {{ ref('stg_pg__cw_task') }} t
    inner join {{ ref('stg_pg__cw_case') }} c
        on t.case_id = c.case_id
)

select
    task_id,
    case_id,
    beneficiary_id,
    catalog_product_id,
    flow_template_id,
    flow_template_version_id,
    task_name,
    task_template_id,
    task_creation_source,
    task_sub_stage,
    task_status,
    task_created_at,
    task_created_date,
    case
        when task_creation_source in (select creation_source from manual_creation_sources) then 1
        else 0
    end as is_manually_added_task,
    case
        when task_template_id is null then 1
        else 0
    end as is_non_template_task,
    case
        when task_creation_source in (select creation_source from manual_creation_sources) then 1
        when task_template_id is null
             and task_creation_source not in (select creation_source from library_creation_sources)
             and task_creation_source not in (select creation_source from ai_creation_sources)
        then 1
        else 0
    end as is_custom_task_broad
from task_base

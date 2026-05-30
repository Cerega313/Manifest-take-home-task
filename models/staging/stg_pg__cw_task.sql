{{ config(materialized='table') }}

select
    id as task_id,
    case_id,
    name as task_name,
    description as task_description,
    task_template_id,
    creation_source::text as task_creation_source,
    case_stage_scope::text as case_stage_scope,
    sub_stage as task_sub_stage,
    status::text as task_status,
    blocked_reason::text as blocked_reason,
    force_unblocked,
    activation_ts as task_activated_ts,
    completion_ts as task_completed_ts,
    created_at as task_created_at,
    updated_at as task_updated_at,
    deleted_at as task_deleted_at,
    ingestion_timestamp
from {{ source('postgres_workflow', 'cw_task') }}
where deleted_at is null

{{ config(materialized='table') }}

select
    id as task_assignment_id,
    task_id,
    role_binding::text as assignment_role_binding,
    role as assignee_role,
    action::text as assignment_action,
    status::text as assignment_status,
    iteration_count,
    active_time_ms,
    auto_activate,
    activated_ts,
    submitted_ts,
    completed_ts,
    created_at as assignment_created_at,
    updated_at as assignment_updated_at,
    deleted_at as assignment_deleted_at,
    ingestion_timestamp
from {{ source('postgres_workflow', 'cw_task_assignment') }}
where deleted_at is null

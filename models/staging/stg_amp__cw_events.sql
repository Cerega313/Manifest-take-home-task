{{ config(
    materialized='incremental',
    unique_key='event_natural_key'
) }}

with raw_events as (
    select
        nullif(btrim(event_time::text), '') as raw_event_time,
        nullif(btrim(ingestion_timestamp::text), '') as raw_ingestion_timestamp,
        event_type,
        event_properties,
        nullif(btrim(event_properties ->> 'case_id'), '') as raw_case_id,
        nullif(btrim(event_properties ->> 'task_id'), '') as raw_task_id,
        nullif(btrim(event_properties ->> 'task_assignment_id'), '') as raw_task_assignment_id,
        nullif(btrim(event_properties ->> 'task_assignee_role'), '') as raw_task_assignee_role,
        nullif(btrim(event_properties ->> 'task_active_assignment_action'), '') as raw_task_active_assignment_action,
        nullif(btrim(event_properties ->> 'task_plugin_type'), '') as raw_task_plugin_type,
        nullif(btrim(event_properties ->> 'task_sub_stage'), '') as raw_task_sub_stage,
        nullif(btrim(event_properties ->> 'task_workflow_status'), '') as raw_task_workflow_status,
        nullif(btrim(event_properties ->> 'catalog_product_id'), '') as raw_catalog_product_id,
        nullif(btrim(event_properties ->> 'catalog_product_name'), '') as raw_catalog_product_name,
        nullif(btrim(event_properties ->> 'catalog_product_service_name'), '') as raw_catalog_product_service_name,
        nullif(btrim(event_properties ->> 'flow_template_id'), '') as raw_flow_template_id,
        nullif(btrim(event_properties ->> 'actor_role'), '') as raw_actor_role,
        event_properties ->> 'user_can_act' as raw_user_can_act,
        event_properties ->> 'user_can_claim' as raw_user_can_claim,
        event_properties ->> 'file_count' as raw_file_count,
        event_properties ->> 'success_count' as raw_success_count,
        event_properties ->> 'error_count' as raw_error_count,
        event_properties ->> 'session_number' as raw_session_number,
        event_properties ->> 'instance_count' as raw_instance_count,
        event_properties ->> 'duration_ms' as raw_duration_ms
    from {{ source('amplitude', 'events') }}
    where event_type like 'cw\_%' escape '\'
),

parsed_events as (
    select
        md5(concat_ws(
            '|',
            coalesce(raw_event_time, ''),
            coalesce(raw_ingestion_timestamp, ''),
            coalesce(event_type, ''),
            coalesce(raw_case_id, ''),
            coalesce(raw_task_id, ''),
            coalesce(raw_task_assignment_id, ''),
            coalesce(event_properties::text, '')
        )) as event_natural_key,
        {{ safe_timestamp('raw_event_time') }} as event_time,
        {{ safe_timestamp('raw_event_time') }}::date as event_date,
        {{ safe_timestamp('raw_ingestion_timestamp') }} as ingestion_timestamp,
        event_type as event_name,
        event_properties,
        raw_case_id as case_id,
        raw_task_id as task_id,
        raw_task_assignment_id as task_assignment_id,
        raw_task_assignee_role as task_assignee_role,
        raw_task_active_assignment_action as task_active_assignment_action,
        lower(raw_task_plugin_type) as task_plugin_type,
        raw_task_sub_stage as task_sub_stage,
        raw_task_workflow_status as task_workflow_status,
        raw_catalog_product_id as catalog_product_id,
        raw_catalog_product_name as catalog_product_name,
        raw_catalog_product_service_name as catalog_product_service_name,
        raw_flow_template_id as flow_template_id,
        lower(raw_actor_role) as actor_role,
        {{ safe_boolean('raw_user_can_act') }} as user_can_act,
        {{ safe_boolean('raw_user_can_claim') }} as user_can_claim,
        {{ safe_int64('raw_file_count') }} as file_count,
        {{ safe_int64('raw_success_count') }} as success_count,
        {{ safe_int64('raw_error_count') }} as error_count,
        {{ safe_int64('raw_session_number') }} as session_number,
        {{ safe_int64('raw_instance_count') }} as instance_count,
        {{ safe_int64('raw_duration_ms') }} as duration_ms,
        {{ safe_float64('raw_duration_ms') }} / 1000.0 as duration_seconds,
        raw_user_can_act,
        raw_user_can_claim,
        raw_event_time,
        raw_ingestion_timestamp,
        raw_file_count,
        raw_success_count,
        raw_error_count,
        raw_session_number,
        raw_instance_count,
        raw_duration_ms,
        case
            when raw_file_count is not null and {{ safe_int64('raw_file_count') }} is null then true
            when raw_success_count is not null and {{ safe_int64('raw_success_count') }} is null then true
            when raw_error_count is not null and {{ safe_int64('raw_error_count') }} is null then true
            when raw_session_number is not null and {{ safe_int64('raw_session_number') }} is null then true
            when raw_instance_count is not null and {{ safe_int64('raw_instance_count') }} is null then true
            when raw_duration_ms is not null and {{ safe_int64('raw_duration_ms') }} is null then true
            else false
        end as has_numeric_parse_error,
        case
            when raw_event_time is not null and {{ safe_timestamp('raw_event_time') }} is null then true
            when raw_ingestion_timestamp is not null and {{ safe_timestamp('raw_ingestion_timestamp') }} is null then true
            else false
        end as has_timestamp_parse_error
    from raw_events
)

select
    event_natural_key,
    event_time,
    event_date,
    ingestion_timestamp,
    event_name,
    event_properties,
    case_id,
    task_id,
    task_assignment_id,
    task_assignee_role,
    task_active_assignment_action,
    task_plugin_type,
    task_sub_stage,
    task_workflow_status,
    catalog_product_id,
    catalog_product_name,
    catalog_product_service_name,
    flow_template_id,
    actor_role,
    user_can_act,
    user_can_claim,
    file_count,
    success_count,
    error_count,
    session_number,
    instance_count,
    duration_ms,
    duration_seconds,
    raw_user_can_act,
    raw_user_can_claim,
    raw_event_time,
    raw_ingestion_timestamp,
    raw_file_count,
    raw_success_count,
    raw_error_count,
    raw_session_number,
    raw_instance_count,
    raw_duration_ms,
    has_numeric_parse_error,
    has_timestamp_parse_error
from parsed_events
{% if is_incremental() %}
where ingestion_timestamp >= (
    select coalesce(
        max(ingestion_timestamp),
        '1900-01-01'::timestamptz
    ) - interval '2 day'
    from {{ this }}
)
   or ingestion_timestamp is null
{% endif %}

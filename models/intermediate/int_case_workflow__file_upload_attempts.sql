{{ config(
    materialized='incremental',
    unique_key='task_assignment_id'
) }}

with changed_assignments as (
    select distinct task_assignment_id
    from {{ ref('stg_amp__cw_events') }}
    where actor_role = 'beneficiary'
      and task_plugin_type = 'file_upload'
      and task_assignment_id is not null
      and event_name in (
          'cw_task_plugin_opened',
          'cw_doc_upload_started',
          'cw_doc_upload_completed'
      )
      {% if is_incremental() %}
      and ingestion_timestamp >= (
          select coalesce(
              max(max_ingestion_timestamp),
              '1900-01-01'::timestamptz
          ) - interval '2 day'
          from {{ this }}
      )
      {% endif %}
),

beneficiary_upload_events as (
    select
        task_assignment_id,
        task_id,
        case_id,
        catalog_product_id,
        event_name,
        event_time,
        ingestion_timestamp,
        file_count,
        success_count,
        error_count
    from {{ ref('stg_amp__cw_events') }}
    where actor_role = 'beneficiary'
      and task_plugin_type = 'file_upload'
      and task_assignment_id is not null
      and event_name in (
          'cw_task_plugin_opened',
          'cw_doc_upload_started',
          'cw_doc_upload_completed'
      )
      {% if is_incremental() %}
      and task_assignment_id in (
          select task_assignment_id
          from changed_assignments
      )
      {% endif %}
),

rollup as (
    select
        task_assignment_id,
        min(case_id) as case_id,
        min(task_id) as task_id,
        min(catalog_product_id) as catalog_product_id,
        min(event_time) filter (
            where event_name = 'cw_task_plugin_opened'
        ) as first_plugin_opened_at,
        min(event_time) filter (
            where event_name = 'cw_doc_upload_started'
        ) as first_upload_started_at,
        min(event_time) filter (
            where event_name = 'cw_doc_upload_completed'
              and coalesce(success_count, 0) > 0
        ) as first_successful_upload_at,
        min(event_time) filter (
            where event_name = 'cw_doc_upload_completed'
              and coalesce(file_count, 0) > 0
              and coalesce(success_count, 0) = coalesce(file_count, 0)
        ) as first_full_success_upload_at,
        max(ingestion_timestamp) as max_ingestion_timestamp,
        count(*) filter (
            where event_name = 'cw_task_plugin_opened'
        ) as plugin_open_event_count,
        count(*) filter (
            where event_name = 'cw_doc_upload_started'
        ) as upload_started_event_count,
        count(*) filter (
            where event_name = 'cw_doc_upload_completed'
        ) as upload_completed_event_count,
        coalesce(sum(file_count) filter (
            where event_name = 'cw_doc_upload_started'
        ), 0) as total_files_selected_across_attempts,
        coalesce(max(file_count) filter (
            where event_name = 'cw_doc_upload_started'
        ), 0) as max_files_selected_in_single_attempt,
        coalesce(sum(success_count) filter (
            where event_name = 'cw_doc_upload_completed'
        ), 0) as total_successful_files_uploaded,
        coalesce(sum(error_count) filter (
            where event_name = 'cw_doc_upload_completed'
        ), 0) as total_failed_files_uploaded
    from beneficiary_upload_events
    group by 1
)

select
    task_assignment_id,
    case_id,
    task_id,
    catalog_product_id,
    first_plugin_opened_at,
    first_upload_started_at,
    first_successful_upload_at,
    first_full_success_upload_at,
    max_ingestion_timestamp,
    plugin_open_event_count,
    upload_started_event_count,
    upload_completed_event_count,
    total_files_selected_across_attempts,
    max_files_selected_in_single_attempt,
    total_successful_files_uploaded,
    total_failed_files_uploaded,
    first_plugin_opened_at::date as plugin_opened_date,
    case
        when first_plugin_opened_at is not null then 1
        else 0
    end as opened_plugin,
    case
        when first_upload_started_at is not null then 1
        else 0
    end as started_upload,
    case
        when first_successful_upload_at is not null then 1
        else 0
    end as has_successful_upload,
    case
        when first_full_success_upload_at is not null
        then 1
        else 0
    end as uploaded_all_selected_files
from rollup
where first_plugin_opened_at is not null

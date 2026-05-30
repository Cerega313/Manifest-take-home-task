{{ config(
    materialized='incremental',
    unique_key='task_assignment_id'
) }}

with amplitude_questionnaire_signal as (
    select
        task_assignment_id,
        min(event_time) as first_questionnaire_event_at,
        max(ingestion_timestamp) as max_questionnaire_event_ingestion_timestamp,
        count(*) as questionnaire_event_count
    from {{ ref('stg_amp__cw_events') }}
    where task_assignment_id is not null
      and task_plugin_type = 'questionnaire'
    group by 1
),

assignment_base as (
    select
        a.task_assignment_id,
        a.task_id,
        t.case_id,
        c.beneficiary_id,
        c.catalog_product_id,
        c.flow_template_id,
        c.flow_template_version_id,
        t.task_name,
        t.task_sub_stage,
        t.task_creation_source,
        a.assignment_action,
        a.assignment_status,
        a.assignment_role_binding,
        a.assignee_role,
        a.iteration_count,
        a.activated_ts,
        a.submitted_ts,
        a.completed_ts,
        a.assignment_created_at,
        a.assignment_updated_at
    from {{ ref('stg_pg__cw_task_assignment') }} a
    inner join {{ ref('stg_pg__cw_task') }} t
        on a.task_id = t.task_id
    inner join {{ ref('stg_pg__cw_case') }} c
        on t.case_id = c.case_id
),

candidate_assignments as (
    select
        base.*,
        amp.first_questionnaire_event_at,
        amp.max_questionnaire_event_ingestion_timestamp,
        amp.questionnaire_event_count,
        case
            when lower(coalesce(base.task_name, '')) like '%questionnaire%' then 1
            else 0
        end as matched_task_name_signal,
        case
            when lower(coalesce(base.assignment_action, '')) like '%questionnaire%' then 1
            else 0
        end as matched_action_signal,
        case
            when amp.task_assignment_id is not null then 1
            else 0
        end as matched_amplitude_signal
    from assignment_base base
    left join amplitude_questionnaire_signal amp
        on base.task_assignment_id::text = amp.task_assignment_id
)

select
    task_assignment_id,
    task_id,
    case_id,
    beneficiary_id,
    catalog_product_id,
    flow_template_id,
    flow_template_version_id,
    task_name,
    task_sub_stage,
    task_creation_source,
    assignment_action,
    assignment_status,
    assignment_role_binding,
    assignee_role,
    iteration_count,
    activated_ts,
    submitted_ts,
    completed_ts,
    assignment_created_at,
    assignment_updated_at,
    first_questionnaire_event_at,
    max_questionnaire_event_ingestion_timestamp,
    questionnaire_event_count,
    matched_task_name_signal,
    matched_action_signal,
    matched_amplitude_signal,
    case
        when activated_ts is not null then activated_ts::date
        else null
    end as activation_date,
    case
        when activated_ts is not null then date_trunc('week', activated_ts)::date
        else null
    end as activation_week,
    case
        when activated_ts is not null then 1
        else 0
    end as is_activated,
    case
        when submitted_ts is not null then 1
        else 0
    end as is_submitted,
    case
        when completed_ts is not null then 1
        else 0
    end as is_reviewer_completed,
    greatest(
        coalesce(assignment_updated_at, '1900-01-01'::timestamptz),
        coalesce(max_questionnaire_event_ingestion_timestamp, '1900-01-01'::timestamptz)
    ) as source_updated_at
from candidate_assignments
where (
    matched_task_name_signal = 1
    or matched_action_signal = 1
    or matched_amplitude_signal = 1
)
{% if is_incremental() %}
   and greatest(
       coalesce(assignment_updated_at, '1900-01-01'::timestamptz),
       coalesce(max_questionnaire_event_ingestion_timestamp, '1900-01-01'::timestamptz)
   ) >= (
       select coalesce(
           max(source_updated_at),
           '1900-01-01'::timestamptz
       ) - interval '2 day'
       from {{ this }}
   )
{% endif %}

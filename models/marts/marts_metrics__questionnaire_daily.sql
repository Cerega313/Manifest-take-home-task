{{ config(
    materialized='incremental',
    unique_key='metric_day_product_key'
) }}

with questionnaire_assignments as (
    select *
    from {{ ref('int_case_workflow__questionnaire_assignments') }}
    where is_activated = 1
      and activation_date is not null
),

changed_groups as (
    select distinct
        activation_date,
        catalog_product_id
    from questionnaire_assignments
    {% if is_incremental() %}
    where source_updated_at >= (
        select coalesce(
            max(max_source_updated_at),
            '1900-01-01'::timestamptz
        ) - interval '2 day'
        from {{ this }}
    )
    {% endif %}
),

filtered_assignments as (
    select questionnaire_assignments.*
    from questionnaire_assignments
    {% if is_incremental() %}
    inner join changed_groups
        on questionnaire_assignments.activation_date = changed_groups.activation_date
       and coalesce(questionnaire_assignments.catalog_product_id::text, '') = coalesce(changed_groups.catalog_product_id::text, '')
    {% endif %}
)

select
    md5(concat_ws(
        '|',
        coalesce(activation_date::text, ''),
        coalesce(catalog_product_id::text, '')
    )) as metric_day_product_key,
    activation_date as metric_date,
    catalog_product_id,
    count(*) as activated_assignments,
    count(*) filter (
        where is_submitted = 1
    ) as submitted_assignments,
    count(*) filter (
        where is_reviewer_completed = 1
    ) as reviewer_completed_assignments,
    count(distinct beneficiary_id) as activated_beneficiaries,
    count(distinct beneficiary_id) filter (
        where is_submitted = 1
    ) as beneficiaries_with_any_submitted_assignment,
    count(distinct beneficiary_id) filter (
        where is_reviewer_completed = 1
    ) as beneficiaries_with_any_reviewer_completed_assignment,
    round(
        count(*) filter (where is_submitted = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as assignment_submission_rate,
    round(
        count(*) filter (where is_reviewer_completed = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as assignment_reviewer_completion_rate,
    round(
        count(distinct beneficiary_id) filter (where is_submitted = 1)::numeric
        / nullif(count(distinct beneficiary_id), 0),
        4
    ) as beneficiary_any_submission_rate,
    round(
        count(distinct beneficiary_id) filter (
            where is_reviewer_completed = 1
        )::numeric
        / nullif(count(distinct beneficiary_id), 0),
        4
    ) as beneficiary_any_reviewer_completion_rate,
    max(source_updated_at) as max_source_updated_at
from filtered_assignments
group by 1, 2, 3

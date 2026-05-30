{{ config(
    materialized='incremental',
    unique_key='metric_day_product_key'
) }}

with upload_attempts as (
    select *
    from {{ ref('int_case_workflow__file_upload_attempts') }}
),

changed_groups as (
    select distinct
        plugin_opened_date,
        catalog_product_id
    from upload_attempts
    {% if is_incremental() %}
    where max_ingestion_timestamp >= (
        select coalesce(
            max(max_ingestion_timestamp),
            '1900-01-01'::timestamptz
        ) - interval '2 day'
        from {{ this }}
    )
    {% endif %}
),

filtered_attempts as (
    select upload_attempts.*
    from upload_attempts
    {% if is_incremental() %}
    inner join changed_groups
        on upload_attempts.plugin_opened_date = changed_groups.plugin_opened_date
       and coalesce(upload_attempts.catalog_product_id, '') = coalesce(changed_groups.catalog_product_id, '')
    {% endif %}
)

select
    md5(concat_ws(
        '|',
        coalesce(plugin_opened_date::text, ''),
        coalesce(catalog_product_id::text, '')
    )) as metric_day_product_key,
    plugin_opened_date as metric_date,
    catalog_product_id,
    count(*) as opened_upload_plugin_count,
    count(*) filter (
        where started_upload = 1
    ) as started_upload_count,
    count(*) filter (
        where has_successful_upload = 1
    ) as completed_upload_with_any_success_count,
    count(*) filter (
        where uploaded_all_selected_files = 1
    ) as completed_upload_with_full_success_count,
    round(
        count(*) filter (where started_upload = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as open_to_start_rate,
    round(
        count(*) filter (where has_successful_upload = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as overall_any_success_rate,
    round(
        count(*) filter (where has_successful_upload = 1)::numeric
        / nullif(count(*) filter (where started_upload = 1), 0),
        4
    ) as start_to_any_success_rate,
    round(
        count(*) filter (where uploaded_all_selected_files = 1)::numeric
        / nullif(count(*) filter (where started_upload = 1), 0),
        4
    ) as start_to_full_success_rate,
    round(
        count(*) filter (where uploaded_all_selected_files = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as overall_full_success_rate,
    sum(total_files_selected_across_attempts) as total_files_selected_across_attempts,
    sum(total_successful_files_uploaded) as total_successful_files_uploaded,
    sum(total_failed_files_uploaded) as total_failed_files_uploaded,
    max(max_ingestion_timestamp) as max_ingestion_timestamp
from filtered_attempts
group by 1, 2, 3

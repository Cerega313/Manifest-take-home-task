/*
Metric: File-upload conversion funnel -- from beneficiary opens upload plugin
to files actually uploaded

Primary source:
- Amplitude

Required events:
- `cw_task_plugin_opened`
- `cw_doc_upload_started`
- `cw_doc_upload_completed`

Primary judgment call:
- The funnel is computed at assignment grain, not event-count grain, to avoid
  inflating the funnel with repeated opens and repeated retries.

Data-quality trap handled here:
- `cw_doc_upload_completed` is not treated as success unless `success_count > 0`.
- Full success is stricter: `success_count = file_count`.
*/

with attempts as (
    select
        plugin_opened_date,
        catalog_product_id,
        started_upload,
        has_successful_upload,
        uploaded_all_selected_files,
        total_files_selected_across_attempts,
        total_successful_files_uploaded,
        total_failed_files_uploaded
    from {{ ref('int_case_workflow__file_upload_attempts') }}
)

select
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
    sum(total_failed_files_uploaded) as total_failed_files_uploaded
from attempts
group by 1, 2
order by 1, 2

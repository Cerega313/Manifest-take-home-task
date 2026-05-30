{{ config(materialized='table') }}

select
    filing_date as metric_date,
    catalog_product_id,
    count(*) as filed_cases,
    count(*) filter (
        where is_valid_primary_duration = 1
    ) as kickoff_population_cases,
    round(avg(kickoff_to_filing_days)::numeric, 2) as avg_kickoff_to_filing_days,
    percentile_cont(0.5) within group (
        order by kickoff_to_filing_days
    ) as median_kickoff_to_filing_days,
    percentile_cont(0.75) within group (
        order by kickoff_to_filing_days
    ) as p75_kickoff_to_filing_days,
    percentile_cont(0.9) within group (
        order by kickoff_to_filing_days
    ) as p90_kickoff_to_filing_days,
    count(*) filter (
        where initialized_to_filing_days is not null
    ) as initialized_population_cases,
    percentile_cont(0.5) within group (
        order by initialized_to_filing_days
    ) as median_initialized_to_filing_days,
    count(*) filter (
        where created_to_filing_days is not null
    ) as created_population_cases,
    percentile_cont(0.5) within group (
        order by created_to_filing_days
    ) as median_created_to_filing_days,
    count(*) filter (
        where has_legacy_case_link = 1
    ) as cases_with_legacy_link
from {{ ref('int_case_workflow__case_durations') }}
group by 1, 2

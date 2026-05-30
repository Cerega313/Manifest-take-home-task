/*
Metric: End-to-end case duration

What the metric shows:
- How long case preparation takes from the start of active work to actual filing.

Primary source:
- Postgres only

Required table:
- `cw_case`

Grain:
- case

Primary definition:
- kickoff_date -> filing_date_actual

Why:
- `kickoff_date` is the closest field in the packet to meaningful case work starting.
- `filing_date_actual` is the cleanest operational endpoint for pre-filing throughput.
- `decision_date` is not used because it includes post-filing USCIS response time,
  not just preparation work controlled by the team.

Primary cohort:
- non-deleted filed cases with `kickoff_date is not null`
- `filing_date_actual >= kickoff_date`

Alternate definitions are included side by side because the start date is not
uniquely determined by the brief and different stakeholders may care about
workflow initialization, case creation, or classification timing instead.
*/

with durations as (
    select
        catalog_product_id,
        created_to_filing_days,
        initialized_to_filing_days,
        kickoff_to_filing_days,
        classification_to_filing_days,
        has_legacy_case_link
    from {{ ref('int_case_workflow__case_durations') }}
    where is_valid_primary_duration = 1
)

select
    catalog_product_id,
    count(*) as case_count,
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
        where classification_to_filing_days is not null
    ) as classification_population_cases,
    percentile_cont(0.5) within group (
        order by classification_to_filing_days
    ) as median_classification_to_filing_days,
    count(*) filter (
        where has_legacy_case_link = 1
    ) as cases_with_legacy_link
from durations
group by 1
order by 1

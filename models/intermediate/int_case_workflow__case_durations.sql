{{ config(materialized='table') }}

select
    case_id,
    beneficiary_id,
    catalog_product_id,
    flow_template_id,
    flow_template_version_id,
    case_stage,
    case_status,
    case_matter_case_id,
    case_created_at,
    case_created_at::date as case_created_date,
    initialized_at,
    initialized_at::date as initialized_date,
    kickoff_date,
    classification_date,
    filing_date_actual as filing_date,
    receipt_date,
    decision_date,
    case
        when filing_date_actual is not null
             and case_created_at is not null
             and filing_date_actual >= case_created_at::date
        then filing_date_actual - case_created_at::date
        else null
    end as created_to_filing_days,
    case
        when filing_date_actual is not null
             and initialized_at is not null
             and filing_date_actual >= initialized_at::date
        then filing_date_actual - initialized_at::date
        else null
    end as initialized_to_filing_days,
    case
        when filing_date_actual is not null
             and kickoff_date is not null
             and filing_date_actual >= kickoff_date
        then filing_date_actual - kickoff_date
        else null
    end as kickoff_to_filing_days,
    case
        when filing_date_actual is not null
             and classification_date is not null
             and filing_date_actual >= classification_date
        then filing_date_actual - classification_date
        else null
    end as classification_to_filing_days,
    case
        when filing_date_actual is not null
             and kickoff_date is not null
             and filing_date_actual >= kickoff_date
        then 1
        else 0
    end as is_valid_primary_duration,
    case
        when case_matter_case_id is not null then 1
        else 0
    end as has_legacy_case_link
from {{ ref('stg_pg__cw_case') }}
where filing_date_actual is not null

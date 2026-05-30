{{ config(materialized='table') }}

select
    id as case_id,
    beneficiary_id,
    catalog_product_id,
    flow_template_id,
    flow_template_version_id,
    stage::text as case_stage,
    status::text as case_status,
    stage_instance_id,
    kickoff_date,
    classification_date,
    filing_date_actual,
    receipt_date,
    decision_date,
    initialized_at,
    case_matter_case_id,
    created_at as case_created_at,
    updated_at as case_updated_at,
    deleted_at as case_deleted_at,
    ingestion_timestamp
from {{ source('postgres_workflow', 'cw_case') }}
where deleted_at is null

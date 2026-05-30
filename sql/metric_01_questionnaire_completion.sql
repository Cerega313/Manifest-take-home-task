/*
Metric: % of beneficiaries who complete the questionnaire -- per week

Primary source:
- Postgres for authoritative lifecycle timestamps
- Amplitude only as a supporting questionnaire-identification signal

Grain:
- task assignment

Denominator:
- activated questionnaire assignments where `activated_ts is not null`

Numerator:
- submitted questionnaire assignments where `submitted_ts is not null`

Strict additional numerator:
- reviewer-completed questionnaire assignments where `completed_ts is not null`

Cohort:
- activation week: `date_trunc('week', activated_ts)`
*/

select
    activation_week as metric_week,
    catalog_product_id,
    count(*) as activated_questionnaire_assignments,
    count(*) filter (
        where is_submitted = 1
    ) as submitted_questionnaire_assignments,
    count(*) filter (
        where is_reviewer_completed = 1
    ) as reviewer_completed_questionnaire_assignments,
    round(
        count(*) filter (where is_submitted = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as questionnaire_submission_rate,
    round(
        count(*) filter (where is_reviewer_completed = 1)::numeric
        / nullif(count(*), 0),
        4
    ) as questionnaire_reviewer_completion_rate
from int_case_workflow__questionnaire_assignments
where is_activated = 1
  and activation_week is not null
group by 1, 2
order by 1, 2

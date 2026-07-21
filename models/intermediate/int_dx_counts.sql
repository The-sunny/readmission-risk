-- Per-encounter diagnosis count and the set of diagnosis codes, used by
-- int_readmission_flags for the any-overlap match on the null-discharge path.

select
    encounter_id,
    count(*) as dx_count,
    array_agg(diagnosis_code) as diagnosis_codes
from {{ ref('stg_diagnoses') }}
group by encounter_id

-- The index-encounter set: every encounter except Elective admissions.
-- Both Inpatient and Outpatient encounter_type qualify.

select
    encounter_id,
    patient_key,
    encounter_type,
    admission_type,
    admission_date,
    discharge_date
from {{ ref('stg_encounters') }}
where admission_type <> 'Elective'

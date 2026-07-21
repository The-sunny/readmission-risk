select
    encounter_id,
    patient_key,
    encounter_type,
    admission_type,
    admission_date,
    discharge_date
from {{ source('raw', 'tbl_common_encounters') }}

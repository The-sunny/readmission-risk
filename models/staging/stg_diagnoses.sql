select
    diagnosis_id,
    encounter_id,
    patient_key,
    diagnosis_code,
    diagnosis_seq,
    diagnosis_date
from {{ source('raw', 'tbl_common_diagnoses') }}

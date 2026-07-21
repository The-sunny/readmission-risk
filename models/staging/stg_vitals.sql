select
    vital_id,
    encounter_id,
    patient_key,
    recorded_at,
    heart_rate,
    sp_02
from {{ source('raw', 'tbl_common_vitals') }}

-- Self-joins index encounters to later encounters of the same patient to
-- find qualifying 30-day returns, then collapses to one row per index
-- encounter (BUILD_SPEC.md section 7, decision 2: no fan-out, ever).
--
-- The return side is all encounters (not just the index set) -- the index
-- filter (excluding Elective) only defines what can be flagged, not what
-- counts as a return visit.
--
-- Standard path (index discharge_date NOT NULL): return admission_date is
-- after the index discharge_date and within 30 days of it.
--
-- Null-discharge path (index discharge_date IS NULL): return admission_date
-- is within 30 days of the index admission_date AND at least one
-- diagnosis_code overlaps between the index and return encounters
-- (any-overlap tie-break, section 7 decision 1).

with index_encounters as (
    select encounter_id, patient_key, admission_date, discharge_date
    from {{ ref('int_index_encounters') }}
),

all_encounters as (
    select encounter_id, patient_key, admission_date, discharge_date
    from {{ ref('stg_encounters') }}
),

dx_sets as (
    select encounter_id, diagnosis_codes
    from {{ ref('int_dx_counts') }}
),

standard_path as (
    select
        idx.encounter_id as index_encounter_id,
        datediff('day', idx.discharge_date, ret.admission_date) as days_to_readmission
    from index_encounters idx
    inner join all_encounters ret
        on ret.patient_key = idx.patient_key
        and ret.encounter_id <> idx.encounter_id
    where idx.discharge_date is not null
        and ret.admission_date > idx.discharge_date
        and ret.admission_date <= dateadd('day', 30, idx.discharge_date)
),

null_discharge_path as (
    select
        idx.encounter_id as index_encounter_id,
        datediff('day', idx.admission_date, ret.admission_date) as days_to_readmission
    from index_encounters idx
    inner join all_encounters ret
        on ret.patient_key = idx.patient_key
        and ret.encounter_id <> idx.encounter_id
    left join dx_sets idx_dx
        on idx_dx.encounter_id = idx.encounter_id
    left join dx_sets ret_dx
        on ret_dx.encounter_id = ret.encounter_id
    where idx.discharge_date is null
        and ret.admission_date > idx.admission_date
        and ret.admission_date <= dateadd('day', 30, idx.admission_date)
        and arrays_overlap(idx_dx.diagnosis_codes, ret_dx.diagnosis_codes)
),

qualifying_returns as (
    select * from standard_path
    union all
    select * from null_discharge_path
),

collapsed as (
    select
        index_encounter_id,
        min(days_to_readmission) as days_to_readmission
    from qualifying_returns
    group by index_encounter_id
)

select
    idx.encounter_id,
    (c.index_encounter_id is not null) as is_readmitted,
    c.days_to_readmission
from index_encounters idx
left join collapsed c
    on c.index_encounter_id = idx.encounter_id

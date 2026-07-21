-- Pre-aggregates vitals to one row per index encounter *before* any join to
-- encounter-level data, so the high-volume vitals table never fans out
-- against the mart's one-row-per-encounter grain.
--
-- end_of_encounter = discharge_date, or MAX(recorded_at) when discharge_date
-- is NULL (see BUILD_SPEC.md section 7, decision 3). The window is the 24h
-- leading up to end_of_encounter, inclusive of both ends. Encounters with no
-- vitals at all (or no computable end_of_encounter) simply produce no row
-- here -- the mart's left join turns that into NULL features while keeping
-- the encounter row.

with vitals_max_recorded as (
    select
        encounter_id,
        max(recorded_at) as max_recorded_at
    from {{ ref('stg_vitals') }}
    group by encounter_id
),

encounter_end as (
    select
        idx.encounter_id,
        coalesce(idx.discharge_date, vmr.max_recorded_at) as end_of_encounter
    from {{ ref('int_index_encounters') }} idx
    left join vitals_max_recorded vmr
        on vmr.encounter_id = idx.encounter_id
),

vitals_in_window as (
    select
        ee.encounter_id,
        sv.heart_rate,
        sv.sp_02
    from encounter_end ee
    inner join {{ ref('stg_vitals') }} sv
        on sv.encounter_id = ee.encounter_id
    where ee.end_of_encounter is not null
        and sv.recorded_at between dateadd('hour', -24, ee.end_of_encounter) and ee.end_of_encounter
)

select
    encounter_id,
    avg(heart_rate) as avg_heart_rate_final_24h,
    var_samp(heart_rate) as var_heart_rate_final_24h,
    avg(sp_02) as avg_spo2_final_24h,
    var_samp(sp_02) as var_spo2_final_24h,
    min(sp_02) as min_spo2_final_24h
from vitals_in_window
group by encounter_id

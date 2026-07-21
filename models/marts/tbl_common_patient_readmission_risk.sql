-- Denormalized, one-row-per-index-encounter analyst mart: readmission risk
-- flag plus supporting diagnosis and vitals features. See BUILD_SPEC.md
-- section 8 for the column-to-source mapping.

select
    idx.patient_key,
    idx.encounter_id,
    idx.admission_date,
    idx.discharge_date,
    idx.admission_type,
    coalesce(dx.dx_count, 0) as dx_count,
    vit.avg_heart_rate_final_24h,
    vit.var_heart_rate_final_24h,
    vit.avg_spo2_final_24h,
    vit.var_spo2_final_24h,
    vit.min_spo2_final_24h,
    rf.is_readmitted,
    rf.days_to_readmission,
    current_timestamp() as _loaded_at
from {{ ref('int_index_encounters') }} idx
left join {{ ref('int_dx_counts') }} dx
    on dx.encounter_id = idx.encounter_id
left join {{ ref('int_vitals_24h_agg') }} vit
    on vit.encounter_id = idx.encounter_id
left join {{ ref('int_readmission_flags') }} rf
    on rf.encounter_id = idx.encounter_id

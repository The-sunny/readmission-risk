-- Demo Snowflake Task: scheduled refresh of the analytical mart.
--
-- Snowflake Tasks can only execute SQL (or a stored procedure), not an
-- external CLI -- dbt Core runs outside Snowflake, so a Task cannot invoke
-- `dbt run` directly. This task instead re-runs the mart's transformation
-- SQL directly (kept in sync by hand with
-- models/marts/tbl_common_patient_readmission_risk.sql), which is enough
-- to demonstrate a scheduled refresh and keep _loaded_at current for the
-- SODA freshness check. See README.md "Technical Decisions" for the fuller
-- discussion of why this is a bounded demo and not real orchestration.
--
-- This script defines the task but does not activate it: CREATE TASK
-- always creates a task in the SUSPENDED state, and the RESUME step below
-- is commented out. Run it manually only when you actually want a
-- recurring hourly warehouse spin-up on your account; day-to-day, the
-- pipeline is refreshed by running `dbt run` by hand.

CREATE OR REPLACE TASK READMISSION_RISK.PUBLIC.refresh_readmission_risk_mart
    WAREHOUSE = READMISSION_WH
    SCHEDULE = 'USING CRON 0 * * * * UTC'  -- hourly, on the hour
AS
    CREATE OR REPLACE TABLE READMISSION_RISK.PUBLIC.tbl_common_patient_readmission_risk AS
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
    from READMISSION_RISK.PUBLIC.int_index_encounters idx
    left join READMISSION_RISK.PUBLIC.int_dx_counts dx
        on dx.encounter_id = idx.encounter_id
    left join READMISSION_RISK.PUBLIC.int_vitals_24h_agg vit
        on vit.encounter_id = idx.encounter_id
    left join READMISSION_RISK.PUBLIC.int_readmission_flags rf
        on rf.encounter_id = idx.encounter_id;

-- Tasks are created suspended. Uncomment to activate the schedule:
-- ALTER TASK READMISSION_RISK.PUBLIC.refresh_readmission_risk_mart RESUME;

-- Source table DDL for the Patient 30-Day Readmission Risk Model.
-- These are raw source tables (loaded via stage + COPY INTO, see 02_load_source_data.sql).
-- They are NOT dbt seeds; dbt only ever reads them as declared sources.

CREATE TABLE IF NOT EXISTS tbl_common_encounters (
    encounter_id    VARCHAR PRIMARY KEY,
    patient_key     VARCHAR NOT NULL,
    encounter_type  VARCHAR NOT NULL,   -- 'Inpatient' / 'Outpatient'
    admission_type  VARCHAR NOT NULL,   -- e.g. 'Emergency', 'Urgent', 'Elective'
    admission_date  TIMESTAMP_NTZ NOT NULL,
    discharge_date  TIMESTAMP_NTZ        -- nullable: drives the null-discharge path
);

CREATE TABLE IF NOT EXISTS tbl_common_diagnoses (
    diagnosis_id    VARCHAR PRIMARY KEY,
    encounter_id    VARCHAR NOT NULL,   -- FK -> tbl_common_encounters
    patient_key     VARCHAR NOT NULL,
    diagnosis_code  VARCHAR NOT NULL,   -- ICD-10-style code
    diagnosis_seq   NUMBER NOT NULL,    -- 1 = primary, 2+ = secondary (not used in matching logic)
    diagnosis_date  TIMESTAMP_NTZ NOT NULL -- realism/future-proofing only; not used to anchor timing
);

CREATE TABLE IF NOT EXISTS tbl_common_vitals (
    vital_id        VARCHAR PRIMARY KEY,
    encounter_id    VARCHAR NOT NULL,   -- FK -> tbl_common_encounters
    patient_key     VARCHAR NOT NULL,
    recorded_at     TIMESTAMP_NTZ NOT NULL,
    heart_rate      NUMBER,
    sp_02           NUMBER
);

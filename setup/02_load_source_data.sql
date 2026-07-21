-- Loads the hand-crafted source-data CSVs into the raw source tables via
-- internal stage + COPY INTO. This is NOT a dbt seed — dbt only ever reads
-- these tables as declared sources.
--
-- Run this whole file with a client that can execute PUT against your local
-- filesystem, e.g. the Snowflake CLI or SnowSQL, from the repo root:
--   snow sql -f setup/02_load_source_data.sql
--   -- or --
--   snowsql -f setup/02_load_source_data.sql
-- (Pasting into a Snowsight worksheet will not work for the PUT steps,
-- since Snowsight has no access to your local disk.)

-- 1. File format shared by all three loads.
CREATE OR REPLACE FILE FORMAT csv_source_format
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL')
    EMPTY_FIELD_AS_NULL = TRUE
    DATE_FORMAT = 'AUTO'
    TIMESTAMP_FORMAT = 'AUTO';

-- 2. Internal named stage for the raw CSVs.
CREATE OR REPLACE STAGE source_data_stage
    FILE_FORMAT = csv_source_format;

-- 3. Upload the local CSVs to the stage (overwrite so reruns pick up edits).
PUT file://source_data/tbl_common_encounters.csv @source_data_stage AUTO_COMPRESS=TRUE OVERWRITE=TRUE;
PUT file://source_data/tbl_common_diagnoses.csv  @source_data_stage AUTO_COMPRESS=TRUE OVERWRITE=TRUE;
PUT file://source_data/tbl_common_vitals.csv     @source_data_stage AUTO_COMPRESS=TRUE OVERWRITE=TRUE;

-- 4. Load each source table. Truncate first so this script is safely
--    re-runnable while iterating on the sample data (these are our own
--    raw tables, not an external system of record).
TRUNCATE TABLE tbl_common_encounters;
COPY INTO tbl_common_encounters
    FROM @source_data_stage
    FILES = ('tbl_common_encounters.csv.gz')
    FILE_FORMAT = (FORMAT_NAME = csv_source_format)
    ON_ERROR = 'ABORT_STATEMENT';

TRUNCATE TABLE tbl_common_diagnoses;
COPY INTO tbl_common_diagnoses
    FROM @source_data_stage
    FILES = ('tbl_common_diagnoses.csv.gz')
    FILE_FORMAT = (FORMAT_NAME = csv_source_format)
    ON_ERROR = 'ABORT_STATEMENT';

TRUNCATE TABLE tbl_common_vitals;
COPY INTO tbl_common_vitals
    FROM @source_data_stage
    FILES = ('tbl_common_vitals.csv.gz')
    FILE_FORMAT = (FORMAT_NAME = csv_source_format)
    ON_ERROR = 'ABORT_STATEMENT';

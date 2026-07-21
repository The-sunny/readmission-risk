-- One-time environment setup: dedicated compute + storage for this project,
-- matching the locked tech-stack decision in BUILD_SPEC.md section 3
-- (XS warehouse, 60s auto-suspend). Run once before 01_ddl_source_tables.sql.

CREATE WAREHOUSE IF NOT EXISTS READMISSION_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 240
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS READMISSION_RISK;
-- The PUBLIC schema is created automatically with the database and is
-- used for both the raw source tables and the dbt-built models.

USE WAREHOUSE READMISSION_WH;
USE DATABASE READMISSION_RISK;
USE SCHEMA PUBLIC;

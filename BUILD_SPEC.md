# Build Spec — Patient 30-Day Readmission Risk Model

> **Purpose of this document:** This is the authoritative brief for building the project. Every architectural decision has already been made and is recorded here. **Do not re-decide, re-scope, or add anything not listed.** If something is genuinely ambiguous or missing, stop and ask — do not improvise a larger scope.

---

## 1. Goal

Build a single denormalized, analyst-ready table, `tbl_common_patient_readmission_risk`, that flags which hospital encounters are at risk of a 30-day readmission and attaches supporting risk features. One row per index encounter. Downstream consumers (research analysts) query this one table — no joins required on their side.

This is a **greenfield** build: we own and define the three source tables ourselves. There is no external source system.

---

## 2. Scope Guardrails (read first)

### IN scope
- Three source tables (DDL + hand-crafted source-data CSVs), defined below.
- dbt Core (local) transformation pipeline: staging → intermediate → marts.
- The one target table, exactly as specified.
- SodaCL checks file (Soda Core, local/CLI).
- README.md with the three required sections.
- One Snowflake Task to demonstrate scheduled refresh (feeds the freshness check).
- `dbt docs generate` as a final step.

### OUT of scope — do NOT build these
- ❌ No Synthea, Faker, or any external/random data generator. Source data is hand-crafted CSVs (see §6).
- ❌ **Do NOT use dbt seeds / `dbt seed`.** The three `tbl_common_*` tables are *raw sources*, loaded into Snowflake via stage + `COPY INTO`, and dbt reads them as declared `sources` only. dbt seeds are for small static lookup/reference data, which this is not — using them here would be semantically wrong and make dbt "own" its own raw sources.
- ❌ No dbt Cloud and no "dbt Projects on Snowflake" build. **Local dbt Core only.**
- ❌ No Soda Cloud during the build. Structure config so a key can be added later, but do not sign up or wire it in.
- ❌ No orchestration beyond one demo Snowflake Task + a conceptual paragraph in the README. Do not build Airflow/Argo.
- ❌ No extra tables, dimensions, or "helper" marts beyond what is listed. Three sources, one target.
- ❌ No de-identification / masking / PHI handling. Not required by this assignment.
- ❌ No ML model, scoring model, or prediction algorithm. We compute features + a rule-based flag only.
- ❌ No BI dashboards, no Streamlit, no visualization app.
- ❌ Do not add columns beyond the defined schemas without asking first.

If a "nice to have" idea comes up, note it in the README as a future enhancement — do not build it.

---

## 3. Tech Stack (locked)

| Concern | Choice |
|---|---|
| Warehouse / compute | Snowflake (XS warehouse, 60s auto-suspend) |
| Transformation | **dbt Core, run locally** (`dbt-snowflake` adapter), connected to Snowflake |
| Source data | Hand-crafted source-data **CSVs** loaded via stage + `COPY INTO` (NOT dbt seeds) |
| Data quality | **SodaCL / Soda Core** (local, CLI) + dbt tests as a secondary layer |
| Orchestration | One Snowflake **Task** (demo) + conceptual note in README |
| Version control | git / GitHub |
| Docs / lineage | `dbt docs generate` (local) — README references it |

Rationale to capture in the README's Technical Decisions section:
- **SQL/dbt over Spark:** the core logic is a self-join with a date-range condition plus window-function aggregation over structured, tabular clinical data — a natural fit for SQL. Spark's distributed engine is unnecessary at this volume and would add operational overhead.
- **dbt Core local:** simplest, fully file-based, transferable, keeps lineage/docs available via `dbt docs`. (Note in README: in a production Snowflake shop, dbt Projects on Snowflake would be a reasonable native alternative that removes the external runner.)

---

## 4. Repo Structure

```
readmission-risk/
├── README.md                             # required deliverable (see §10)
├── CLAUDE.md                             # repo instructions (incl. no-attribution rule, §11)
├── .gitignore                            # MUST ignore profiles.yml, configuration.yml, secrets
├── dbt_project.yml
├── profiles.yml.example                  # template only; real creds are user-supplied, git-ignored
├── setup/
│   ├── 01_ddl_source_tables.sql          # CREATE the 3 tbl_common_* tables
│   └── 02_load_source_data.sql          # stage (PUT) + COPY INTO from the CSVs
├── source_data/                          # raw-source CSVs — NOT dbt seeds, never run `dbt seed`
│   ├── tbl_common_encounters.csv
│   ├── tbl_common_diagnoses.csv
│   └── tbl_common_vitals.csv
├── models/
│   ├── staging/
│   │   ├── _sources.yml                  # declare the 3 source tables to dbt
│   │   ├── stg_encounters.sql
│   │   ├── stg_diagnoses.sql
│   │   └── stg_vitals.sql
│   ├── intermediate/
│   │   ├── int_index_encounters.sql      # exclude Elective; the index set
│   │   ├── int_dx_counts.sql             # dx_count + dx-code set per encounter
│   │   ├── int_vitals_24h_agg.sql        # pre-aggregate vitals per encounter (24h window)
│   │   └── int_readmission_flags.sql     # 30-day self-join + null-discharge path
│   └── marts/
│       ├── _marts.yml                    # dbt tests: not_null, relationships
│       └── tbl_common_patient_readmission_risk.sql
├── soda/
│   ├── configuration.yml                 # Snowflake conn; leave room for optional Soda Cloud key
│   └── checks.yml                        # the required SODA checks (§9)
└── orchestration/
    └── snowflake_task.sql                # scheduled refresh demo (feeds freshness check)
```

---

## 5. Source Table Schemas (DDL)

### `tbl_common_encounters` — grain: one row per encounter
| Column | Type | Notes |
|---|---|---|
| encounter_id | STRING / VARCHAR | Primary key. Readable prefixed values, e.g. `E001`, `E002` |
| patient_key | STRING / VARCHAR | Patient identifier. Readable prefixed values, e.g. `P001`, `P002` |
| encounter_type | STRING | 'Inpatient' / 'Outpatient' (both are valid index encounters) |
| admission_type | STRING | e.g. 'Emergency','Urgent','Elective' — used to exclude 'Elective' |
| admission_date | TIMESTAMP | Always present |
| discharge_date | TIMESTAMP | **Nullable** — drives the null-discharge path |

### `tbl_common_diagnoses` — grain: one row per diagnosis per encounter
| Column | Type | Notes |
|---|---|---|
| diagnosis_id | STRING / VARCHAR | Primary key. Readable prefixed values, e.g. `D001` |
| encounter_id | STRING / VARCHAR | FK → encounters |
| patient_key | STRING / VARCHAR | |
| diagnosis_code | STRING | ICD-10-style code |
| diagnosis_seq | NUMBER | 1 = primary, 2+ = secondary. Included for realism + to support the README note that primary-dx matching was considered. **Not used in the matching logic.** |
| diagnosis_date | TIMESTAMP | When the diagnosis was recorded. Realism/future-proofing only. **Must NOT be used to anchor the 30-day clock or vitals window** — all timing anchors on encounter dates. |

### `tbl_common_vitals` — grain: one row per reading (high volume)
| Column | Type | Notes |
|---|---|---|
| vital_id | STRING / VARCHAR | Primary key. Readable prefixed values, e.g. `V0001` |
| encounter_id | STRING / VARCHAR | FK → encounters |
| patient_key | STRING / VARCHAR | |
| recorded_at | TIMESTAMP | Drives the 24h window and the null-discharge vitals fallback |
| heart_rate | NUMBER | |
| sp_02 | NUMBER | |

---

## 6. Source Data Requirements (hand-crafted CSVs)

These CSVs populate the raw source tables via stage + `COPY INTO` (see §11 checkpoint 2). **They are not dbt seeds — do not place them in a `seeds/` folder and do not run `dbt seed`.**

**Phase 1 (this build): a minimal, hand-verifiable sample.** Keep it as small as possible — roughly **10–20 rows per source table**, only as many as are needed to cover every logic branch below. The whole point is that the user can trace every row by eye and manually confirm the output is correct. Data must be **clean enough that all SODA checks pass** on a normal run.

- Encounters and diagnoses sit comfortably in the 10–20 row range.
- **Vitals is reading-level** (many readings per encounter), so testing the 24h window needs a few readings per encounter. Keep this minimal too: attach vitals **only to the handful of encounters that test vitals behavior** (windowing + the no-vitals case), not to every encounter. It's fine if vitals ends up slightly above 20 rows because of this — but keep it as lean as possible.
- Reuse encounters across scenarios where possible (recall: a return visit is also its own index encounter), so you don't need a fresh set of rows per scenario.

**Phase 2 (later, not now): a larger dataset** for volume/stress testing and to exercise the high-volume vitals join strategy at scale. Do NOT build this now. The architecture is built and validated against the small sample first; the larger dataset is swapped in afterward by replacing the CSVs — no model changes required.

Deliberately plant rows that exercise every logic branch:

1. **Standard readmission:** discharge_date present; patient returns within 30 days → should flag `is_readmitted = true`.
2. **Non-readmission:** patient returns *after* 30 days → should NOT flag.
3. **Null-discharge, matching dx:** discharge_date NULL; return within 30 days of admission_date; at least one overlapping diagnosis_code → should flag.
4. **Null-discharge, no matching dx:** discharge_date NULL; return within 30 days but no overlapping code → should NOT flag.
5. **Elective encounter:** `admission_type = 'Elective'` → must be excluded from the index set entirely.
6. **Multiple readmissions in window:** one index encounter with 2–3 qualifying returns → verify output stays **one row**, `days_to_readmission` = the earliest (MIN), no fan-out.
7. **Multiple diagnoses:** an encounter with several dx codes → verify `dx_count` and any-overlap matching.
8. **Vitals windowing:** an encounter with some readings inside the final 24h and some outside → verify only in-window readings are aggregated.
9. **Null-discharge with no vitals at all:** verify vitals features come out NULL and the **row is still kept**.

> **Do NOT plant out-of-range vitals in the main source-data set** (it would break the passing SODA run). Instead, document in the README how a bad value *would* be caught, and optionally include a separate, clearly-labeled "bad data" scenario file that is not loaded by default.

Both inpatient and outpatient encounters are valid index encounters. Every `encounter_id` referenced in diagnoses/vitals must exist in encounters (so referential integrity holds by construction).

---

## 7. Locked Design Decisions

1. **Diagnosis tie-breaking (null-discharge path):** match on **ANY overlapping diagnosis_code** between the index encounter and the return encounter. Rationale for README: the source has no reliable principal-diagnosis flag, and any-overlap is sufficient to establish clinical relatedness; primary-dx matching was considered and rejected.
2. **Final grain:** **one row per index encounter.** `is_readmitted` is a boolean; `days_to_readmission` is the **earliest** qualifying return (via `MIN`), NULL when not readmitted. No fan-out under any circumstances.
3. **Vitals "end of encounter" anchor:** `end_of_encounter = COALESCE(discharge_date, MAX(recorded_at) for that encounter)`. The 24h window is `[end_of_encounter - 24h, end_of_encounter]`. If discharge_date is NULL **and** there are no vitals, set all vitals features to NULL and **keep the row** (it can still be a valid index encounter for readmission via the admission_date + dx path).

---

## 8. Transformation Logic (layer by layer)

**staging/** — light cleaning and renaming only; one model per source, selecting from the declared dbt sources. No business logic.

**intermediate/**
- `int_index_encounters`: from encounters, **exclude `admission_type = 'Elective'`**. This is the set of index encounters (both Inpatient and Outpatient qualify).
- `int_dx_counts`: per `encounter_id`, compute `dx_count = count of diagnosis rows`, and also expose the set/array of `diagnosis_code`s per encounter for use in the any-overlap match.
- `int_vitals_24h_agg`: per `encounter_id`, compute `end_of_encounter` per §7, then over readings within the 24h window compute: `avg_heart_rate_final_24h`, `var_heart_rate_final_24h`, `avg_spo2_final_24h`, `var_spo2_final_24h`, `min_spo2_final_24h`. **Pre-aggregate here, before any join to encounter-level data**, to avoid vitals fan-out at scale (this is the "high-volume join strategy" the README must justify).
- `int_readmission_flags`: self-join index encounters to later encounters of the **same patient_key**.
  - *Standard path* (index `discharge_date` NOT NULL): a return qualifies if its `admission_date` is after the index `discharge_date` and within 30 days of it. `days_to_readmission = datediff(day, index.discharge_date, return.admission_date)`.
  - *Null-discharge path* (index `discharge_date` IS NULL): a return qualifies if its `admission_date` is within 30 days of the index `admission_date` **and** there is at least one overlapping `diagnosis_code` between index and return encounters. `days_to_readmission = datediff(day, index.admission_date, return.admission_date)`.
  - Collapse to one row per index encounter: `is_readmitted = (any qualifying return exists)`, `days_to_readmission = MIN(days_to_readmission)` (NULL if none).

**marts/**
- `tbl_common_patient_readmission_risk`: join `int_index_encounters` + `int_dx_counts` + `int_vitals_24h_agg` + `int_readmission_flags` on `encounter_id`. Add `_loaded_at = current_timestamp()` (feeds freshness check). Final columns:

| Column | Source |
|---|---|
| patient_key, encounter_id | index encounter |
| admission_date, discharge_date, admission_type | index encounter |
| dx_count | int_dx_counts |
| avg_heart_rate_final_24h, var_heart_rate_final_24h | int_vitals_24h_agg |
| avg_spo2_final_24h, var_spo2_final_24h, min_spo2_final_24h | int_vitals_24h_agg |
| is_readmitted | int_readmission_flags |
| days_to_readmission | int_readmission_flags (earliest) |
| _loaded_at | current_timestamp() |

> **Note on `min_spo2_final_24h`:** the feature list names mean/variance only, but the SODA numeric-sanity check references a `min_spo2_final_24h`. It is included to satisfy the observability requirement. Call this out in the README.

---

## 9. SODA Checks (`soda/checks.yml`)

On `tbl_common_patient_readmission_risk` unless noted:
- **Freshness:** `_loaded_at` within the last 24 hours.
- **Not null:** `patient_key` and `encounter_id` must never be NULL.
- **Numeric sanity:** `avg_heart_rate_final_24h` between 30 and 250; `min_spo2_final_24h` between 50 and 100. (These may legitimately be NULL for the no-vitals edge case — configure the check so NULLs are allowed but present values must be in range.)
- **Referential integrity:** every `encounter_id` in the output exists in source `tbl_common_encounters`.

`soda/configuration.yml` holds the Snowflake connection and should be structured so a Soda Cloud API key can be added later without restructuring — but do not add one now.

---

## 10. README.md (required deliverable)

Must contain exactly these three sections:
1. **Data Lineage:** description + simple diagram of flow: three `tbl_common_*` sources → staging → intermediate → `tbl_common_patient_readmission_risk`. Reference the `dbt docs` DAG.
2. **Technical Decisions:** tool justification (SQL/dbt over Spark; dbt Core local; Snowflake) and the **join strategy for high-volume vitals** (pre-aggregate vitals per encounter before joining; explain the fan-out risk avoided). Note the native dbt-on-Snowflake alternative as a production option.
3. **Handling Edge Cases:** the null-discharge logic (both readmission and vitals fallbacks), the any-overlap dx tie-breaking decision (and why primary-dx was rejected), the one-row grain / no fan-out, and the `min_spo2` note from §8.

Keep it concise and factual. Also state clearly that this is a **denormalized single-table analytical model** in the gold/mart layer, and why that grain was chosen.

---

## 11. Workflow Rules

**Build one layer at a time. After each layer, commit with a clear message and STOP for the user to verify on GitHub before continuing.** Checkpoint order:
1. `setup/` DDL for the three source tables
2. Source-data CSVs + stage/`COPY INTO` load script (no `dbt seed`)
3. `staging/` models
4. `intermediate/` models
5. `marts/` target table
6. `soda/` checks
7. README + `dbt docs generate` + Snowflake Task

**Commit attribution:** Do **not** add `Co-Authored-By` trailers or any Claude/Anthropic attribution to commit messages or code. Record this rule in `CLAUDE.md`. Commits should show the user as sole author.

**Final step:** run `dbt docs generate` so the lineage/docs site is ready to serve, and confirm the repo is clean.

---

## 12. Environment & Credentials

Tools to install locally (Claude Code may walk the user through this): Python, `dbt-snowflake`, `soda-core-snowflake`, optionally the Snowflake CLI/SnowSQL for the CSV load, and git.

**The only account required is the user's Snowflake trial.** dbt Core and Soda Core are free local tools; no dbt Cloud or Soda Cloud account is needed for the build.

**Credentials are user-supplied and must never appear in chat or in git.** The user places their Snowflake connection details into `profiles.yml` (dbt) and `soda/configuration.yml` themselves. Provide a `profiles.yml.example` template. Ensure `.gitignore` excludes `profiles.yml`, `soda/configuration.yml`, and any secrets. When a value is needed, instruct the user to add it to the config file rather than typing it into the conversation.

---

## 13. Definition of Done

- [ ] Three source tables created and loaded from the **minimal sample** CSVs (~10–20 rows each) via stage + `COPY INTO` (no `dbt seed`); all edge-case rows from §6 present and hand-verifiable.
- [ ] Full dbt pipeline runs clean (`dbt run`, `dbt test`) with the target table populated at one-row-per-index-encounter grain.
- [ ] All SODA checks pass on the clean data.
- [ ] README complete with all three sections.
- [ ] `dbt docs generate` runs; lineage DAG viewable locally.
- [ ] One Snowflake Task defined for scheduled refresh.
- [ ] Committed in layered checkpoints; no Claude attribution in history; secrets git-ignored.
- [ ] Nothing built outside the scope in §2.

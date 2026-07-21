# Patient 30-Day Readmission Risk Model

A single denormalized, analyst-ready table — `tbl_common_patient_readmission_risk`
— that flags hospital encounters at risk of a 30-day readmission and attaches
supporting risk features. This is a **gold/mart-layer, one-row-per-index-encounter**
analytical model: downstream research analysts query one table with no joins
on their side. That grain was chosen because it matches the analytical
question exactly ("was *this* encounter followed by a readmission?"), while
letting multi-diagnosis and multi-reading detail (which don't share that
grain) get pre-aggregated up to it before ever reaching the analyst.

## 1. Data Lineage

Three raw sources feed the pipeline, each hand-crafted and loaded via
internal stage + `COPY INTO` (not dbt seeds — see `setup/`):
`tbl_common_encounters`, `tbl_common_diagnoses`, `tbl_common_vitals`.

```
┌────────────────────────┐     ┌───────────┐     ┌──────────────┐     ┌─────────────────────────────────────┐
│ tbl_common_encounters  │     │           │     │              │     │                                     │
│ tbl_common_diagnoses   │ ──▶ │  staging  │ ──▶ │ intermediate │ ──▶ │ tbl_common_patient_readmission_risk  │
│ tbl_common_vitals      │     │           │     │              │     │         (marts / gold layer)         │
└────────────────────────┘     └───────────┘     └──────────────┘     └─────────────────────────────────────┘
```

- **staging/**: one light pass-through model per source (`stg_encounters`,
  `stg_diagnoses`, `stg_vitals`) — renaming/selecting only, no business logic.
- **intermediate/**: `int_index_encounters` (excludes Elective admissions),
  `int_dx_counts` (diagnosis count + code set per encounter),
  `int_vitals_24h_agg` (vitals pre-aggregated to the final-24h window),
  `int_readmission_flags` (the 30-day self-join, collapsed to one row).
- **marts/**: `tbl_common_patient_readmission_risk` joins all four
  intermediate models on `encounter_id`.

For the full column-level DAG (including exactly how `int_index_encounters`
feeds three different downstream models), run `dbt docs generate` and
`dbt docs serve` and browse the lineage graph locally.

## 2. Technical Decisions

**SQL/dbt over Spark:** the core logic is a self-join with a date-range
condition plus window-function aggregation over structured, tabular clinical
data — a natural fit for SQL. Spark's distributed engine is unnecessary at
this volume and would add operational overhead.

**dbt Core, run locally:** simplest, fully file-based, transferable, and
keeps lineage/docs available via `dbt docs`. In a production Snowflake shop,
[dbt Projects on Snowflake](https://docs.snowflake.com/) would be a
reasonable native alternative that removes the external runner — out of
scope here per the build spec.

**Join strategy for high-volume vitals:** `tbl_common_vitals` is
reading-level (many rows per encounter), while the mart is one row per
index encounter. Joining raw vitals straight into the mart would fan out
every encounter row by however many readings it has, breaking the grain.
`int_vitals_24h_agg` pre-aggregates vitals down to one row per
`encounter_id` — computing `end_of_encounter` and the final-24h window
stats — *before* it is ever joined to encounter-level data. The mart then
does a simple one-to-one `LEFT JOIN` against that pre-aggregated result, so
grain is preserved no matter how many vitals readings exist per encounter.

**Orchestration:** one demo Snowflake Task (`orchestration/snowflake_task.sql`)
demonstrates what a scheduled refresh would look like, re-running the
mart's transformation SQL directly and advancing `_loaded_at` (which feeds
the SODA freshness check). The script is defined but intentionally *not*
deployed against the live warehouse — it creates the task in Snowflake's
default `SUSPENDED` state and leaves the `RESUME` step commented out, so
day-to-day the pipeline is refreshed by running `dbt run` by hand instead
of an unattended hourly job. Snowflake Tasks can only execute SQL or stored
procedures — they cannot invoke an external CLI like `dbt run` — so even if
activated, this would be a bounded demonstration, not a substitute for real
orchestration. A production setup would instead have something like
Airflow, dbt Cloud, or a CI job trigger the actual external `dbt run`;
building that orchestrator is explicitly out of scope for this assignment.

## 3. Handling Edge Cases

**Null-discharge logic.** When an index encounter's `discharge_date` is
NULL, two things change:
- *Readmission:* the 30-day window anchors on `admission_date` instead of
  `discharge_date`, and a return only qualifies if it additionally shares
  at least one `diagnosis_code` with the index encounter (see below).
- *Vitals:* `end_of_encounter` falls back to `MAX(recorded_at)` for that
  encounter instead of `discharge_date`. If there are no vitals readings at
  all, all vitals features come out NULL and the row is still kept — a
  missing `discharge_date` and missing vitals don't disqualify an encounter
  from being a valid index encounter via the admission-date + diagnosis path.

**Any-overlap diagnosis tie-break.** The null-discharge readmission match
uses *any* overlapping `diagnosis_code` between the index and return
encounter, rather than matching on a principal/primary diagnosis. The
source has no reliable principal-diagnosis flag (`diagnosis_seq` in
`tbl_common_diagnoses` is included for realism but explicitly not used for
matching), and any-overlap is sufficient to establish clinical relatedness.
Primary-dx matching was considered and rejected on that basis.

**One-row grain, no fan-out.** Every intermediate model that could
otherwise multiply rows collapses back to one row per index encounter
before it reaches the mart: `int_vitals_24h_agg` pre-aggregates readings
(see Technical Decisions), and `int_readmission_flags` collapses however
many qualifying returns exist into a single `is_readmitted` boolean and
`days_to_readmission = MIN(...)` (the earliest qualifying return). Both
sides of the readmission self-join draw from `int_index_encounters`, so an
Elective admission is excluded as a return visit exactly as it is as an
index encounter.

**`min_spo2_final_24h`.** The feature list in the build spec names mean and
variance only, but the SODA numeric-sanity check (section 9) references
`min_spo2_final_24h`. It's included in the mart specifically to satisfy
that observability requirement.

**Bad vitals data (not planted in the main sample).** Out-of-range vitals
(e.g. `heart_rate` outside 30–250, `sp_02` outside 50–100) were deliberately
excluded from the main `source_data/` CSVs, since planting one would break
the passing SODA run this build is meant to demonstrate. The
`invalid_count(...)` checks in `soda/checks.yml` would catch such a value
immediately (NULLs are allowed; only present out-of-range values fail).

**Future enhancements (not built in this phase, per the build spec's scope
guardrails):** a larger, high-volume sample dataset to stress-test the
vitals join strategy at scale (the architecture already supports this by
just swapping the CSVs); Soda Cloud integration once a key is available;
a principal-diagnosis flag if the source system ever provides one reliably;
and full orchestration (e.g. Airflow) triggering the external dbt job on a
schedule, rather than the single demo Snowflake Task.

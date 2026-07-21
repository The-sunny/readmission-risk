# Repo Instructions

This repo is built to the spec in `BUILD_SPEC.md`. That file is authoritative — do not re-decide,
re-scope, or add anything not listed there. If something is ambiguous or missing, stop and ask.

## Commit attribution

Do **not** add `Co-Authored-By` trailers or any Claude/Anthropic attribution to commit messages
or code comments. Commits must show the user as sole author.

## Workflow

Build one layer at a time per BUILD_SPEC.md §11. After each layer, commit with a clear message
and stop for the user to verify on GitHub before continuing.

## Credentials

Never place real Snowflake credentials in chat, in git-tracked files, or in code. Real credentials
go only in `profiles.yml` and `soda/configuration.yml`, both of which are git-ignored. Use
`profiles.yml.example` as the template for the former.

## Environment

- dbt Core runs from the `.venv-dbt` virtualenv (`source .venv-dbt/bin/activate`).
- Soda Core runs from the `.venv-soda` virtualenv (`source .venv-soda/bin/activate`).
- These are separate because `dbt-snowflake` requires `snowflake-connector-python>=4.2,<5.0`
  while `soda-core-snowflake` requires `snowflake-connector-python~=3.0` — the two cannot
  coexist in one environment.

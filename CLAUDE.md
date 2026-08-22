# CLAUDE.md

## Project

This repository is the PSA Statistical Classifications Search application.

The authoritative implementation specification for the current build is:

`PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`

Read that file before planning or modifying the project.

## Current Implementation Phase

The current objective is the functionality-first four-hour MVP described in the implementation specification.

Build the functional classification application first.

Do NOT perform the final visual/UI redesign during this phase.

The working application will be passed to Claude Design after functionality, tests, and deployment readiness are verified.

## Engineering Method

Use graph engineering with parallel workstreams where dependencies allow.

Use bounded implementation loops:

1. Inspect.
2. Implement the smallest correct change.
3. Test.
4. Diagnose failures.
5. Patch narrowly.
6. Re-test.
7. Stop modifying a workstream when its acceptance tests pass.

Parallelize independent workstreams where supported.

Do not have multiple agents modify the same files concurrently.

Use tests as persistent verification rather than repeatedly re-reading or re-reasoning about completed behavior.

## Context and Token Efficiency

Do not repeatedly read the entire repository.

Before each workstream:

- inspect only relevant files;
- use targeted searches;
- inspect existing tests and contracts first;
- consume subagent summaries before opening all changed files.

Each parallel workstream should report:

- files changed;
- tests run;
- test results;
- public contracts changed;
- unresolved issues.

Do not duplicate work across agents.

## Architecture Rules

Maintain strict separation between:

1. classification data sources/adapters;
2. canonical classification repository;
3. search/version services;
4. Shiny reactive/controller layer;
5. presentation/UI layer.

Classification and search logic must be testable without running Shiny.

Do not place classification-specific data transformation logic directly inside Shiny reactives.

The UI should depend on stable service contracts.

## PSIC Revision 5

PSIC Revision 5 / 2026 PSIC must be supported in the first implementation.

Do not assume the installed `phscs` package already contains Revision 5.

If it does not, use the official PSA Revision 5 workbook and the normalization pipeline specified in:

`PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`

Runtime search must use a local normalized artifact and must not require PSA website availability.

PSIC Revision 5 (2026) must be presented as current.

PSIC 2019 must remain available as an archived reference.

## Scope Restrictions

For this MVP, do not introduce unless required by the implementation specification:

- PostgreSQL
- SQLite
- Redis
- REST APIs
- Plumber
- React
- Next.js
- Vue
- authentication
- user accounts
- admin CMS
- PSA API runtime dependency
- complex caching infrastructure
- final branding or decorative UI work

Prefer the smallest dependency surface that satisfies requirements.

## UI

Use Shiny + bslib for the functional UI.

Keep styling intentionally minimal and semantic.

Create and maintain:

`docs/UI_CONTRACT.md`

The future Claude Design pass should be able to redesign the presentation layer without modifying classification adapters, repository logic, search semantics, version handling, or PSIC Revision 5 ingestion.

## Testing

Use `testthat`.

Run targeted tests after each workstream.

Before declaring implementation complete, run the complete relevant test suite and perform the UAT cases defined in the implementation specification.

Do not claim a test passed unless it was actually executed.

Do not claim deployment succeeded unless deployment was actually performed.

## Safety and Data Integrity

Never:

- fabricate classification codes or labels;
- silently substitute another classification edition;
- convert classification codes to numeric values when leading zeros matter;
- label archived editions as current;
- expose credentials or tokens in frontend code;
- silently suppress source/version metadata.

PSA is the authoritative classification source.

`phscs` and `psgc` are software/data access mechanisms, not the issuing authority.

## Completion

Maintain:

`IMPLEMENTATION_STATUS.md`

It must accurately identify:

- completed work;
- tests executed and results;
- PSIC Revision 5 status;
- deployment status;
- known limitations;
- deferred work;
- Claude Design handoff readiness.

Stop the current implementation phase once the MVP acceptance criteria in the authoritative specification are satisfied.
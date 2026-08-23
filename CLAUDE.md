# CLAUDE.md

## Project

This repository is the PSA Statistical Classifications Search application.

The original MVP implementation specification is:

`PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`

It remains the architectural and historical baseline for the project.

The current implementation milestone is defined separately under **Current Functional Extension** below.

## Current Implementation Phase

The functionality-first MVP is complete and preserved as the known-good baseline.

The current phase is the post-MVP functional extension defined in:

`PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md`

The current work must:

- add PSOC 2022 as the current/default PSOC;
- retain PSOC 2012 as archived;
- implement dual PSOC + PSIC search;
- implement PSIC 2019 ↔ 2026 correspondence;
- preserve existing MVP behavior and tests;
- update the UI contract for the next Claude Design pass.

Do NOT perform the final visual/UI redesign during this phase.

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

PSIC Revision 5 / 2026 PSIC is part of the verified project baseline and must remain supported.

Do not replace or bypass the existing supplemental PSIC Revision 5 ingestion merely because the installed `phscs` package changes in the future. Any migration to a package-provided Revision 5 source must preserve the existing canonical contracts, provenance, archive behavior, and tests.

If it does not, use the official PSA Revision 5 workbook and the normalization pipeline specified in:

`PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`

Runtime search must use a local normalized artifact and must not require PSA website availability.

PSIC Revision 5 (2026) must be presented as current.

PSIC 2019 must remain available as an archived reference.

## Scope Restrictions

For the current functional extension, do not introduce unless required by the current implementation specification:

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

- recovery state from any interrupted implementation;
- completed work;
- tests executed and results;
- PSOC 2022 status;
- PSOC 2012 archive status;
- PSIC Revision 5 status;
- dual-search status;
- PSIC correspondence status;
- deployment status;
- known limitations;
- deferred work;
- Claude Design handoff readiness.

Stop the current implementation phase once the acceptance criteria in:

`PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md`

are satisfied.

## Current Functional Extension

The authoritative specification for the current implementation milestone is:

`PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md`

Read that file before modifying the application for this milestone.

This specification supersedes the earlier dual-search / PSIC-correspondence specification wherever they conflict.

Current required outcomes are:

1. Add PSOC 2022 as the current/default PSOC using an official PSA source and a local normalized runtime artifact.
2. Retain PSOC 2012 as an archived reference.
3. Implement parallel PSOC + PSIC search, defaulting to:
   - PSOC 2022
   - PSIC Revision 5 (2026)
4. Implement bidirectional PSIC 2019 ↔ 2026 correspondence with explicit official / derived / suggested provenance.
5. Preserve all valid existing MVP behavior and regression tests.
6. Implement only minimal functional UI for these additions.
7. Final visual design remains a separate Claude Design phase.

Because a previous Claude Code session was interrupted by a usage limit, always inspect the current Git/worktree/test state before assuming which parts of this milestone are complete.
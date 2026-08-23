# Pre-Staging Parallel Execution Master Plan

## PSA Statistical Classifications Search

**Objective:** Complete all remaining statistical-correctness, classification-ingestion, metadata, and bounded UI/UAT repairs efficiently before Posit Connect Cloud staging.  
**Execution style:** Graph engineering + non-overlapping parallel workstreams + bounded repair loops + one convergence regression/UAT pass.  
**Do not deploy or commit automatically.**

---

# 0. Authoritative Pre-Staging Specifications

Execute these three specifications as coordinated work:

```text
1. PSIC_2019_2026_STRUCTURAL_CORRESPONDENCE_REPAIR.md
2. ADDITIONAL_CLASSIFICATION_SYSTEMS_INGESTION.md
3. PRE_STAGING_UI_UAT_REPAIR.md
```

If a filename differs, locate the corresponding specification rather than duplicating it.

The existing `CLAUDE.md`, `IMPLEMENTATION_STATUS.md`, `docs/UI_CONTRACT.md`, and `docs/ASSISTANT_CONTRACT.md` remain governing project contracts.

---

# 1. Why These Should Run as a Graph

The remaining work touches mostly separate areas:

```text
PSIC correspondence
→ R/correspondence/*
→ correspondence builder/artifacts/tests

New classification systems
→ new build scripts/adapters/artifacts/tests

UI/UAT repairs
→ R/ui/*
→ app.R where necessary
→ www/app.css

Shared convergence
→ registry/metadata
→ shared UI wiring
→ documentation
```

Do not serialize everything unnecessarily.

Do not allow parallel agents to edit shared registry/UI files at the same time.

---

# 2. Starting Gate

Before dispatch:

1. inspect current branch;
2. inspect Git status/diff;
3. do not discard uncommitted unified-UI work;
4. run:

```text
Rscript scripts/run_tests.R
```

The last known verified application baseline was 1103 passing tests before subsequent pre-staging work.

Use the actual current result.

Record:

```text
branch
starting commit
working tree state
starting test count
known uncommitted files
```

If working tree is not clean, classify changes:

```text
expected current milestone
unexpected/stray
```

Never reset valid work merely to obtain a clean tree.

---

# 3. Dependency Graph

```text
                                W0. Baseline / Contract Freeze
                                             │
             ┌───────────────────────────────┼───────────────────────────────┐
             ▼                               ▼                               ▼
   W1. PSIC Correspondence        W2. New Classification Sources       W3. UI Audit/Shared Layout
             │                               │                               │
     ┌───────┼────────┐             ┌────────┼─────────┐             ┌───────┼────────┐
     ▼       ▼        ▼             ▼        ▼         ▼             ▼       ▼        ▼
   Struct  Detail   Provenance     PSCC     PTSCS    PSCrCS        Footer  Search   Sources
     │       │        │             │        │         │             │       │        │
     └───────┼────────┘             └────────┼─────────┘             └───────┼────────┘
             ▼                               ▼                               │
   W4. Correspondence Build         W5. Metadata/Registry Convergence        │
             │                               │                               │
             ▼                               ├───────────────┐               │
   W6. Reverse/Service                       ▼               ▼               │
             │                         Repository/Search    PSCCS fix        │
             └──────────────┐                │               │               │
                            └────────────────┼───────────────┴───────────────┘
                                             ▼
                                  W7. Shared UI Convergence
                                             │
                         ┌───────────────────┼───────────────────┐
                         ▼                   ▼                   ▼
                    Composite filters   Sources new cards   Compare verification
                         │                   │                   │
                         └───────────────────┼───────────────────┘
                                             ▼
                                  W8. Targeted Regression
                                             │
                                             ▼
                                  W9. Full Regression/UAT
                                             │
                                             ▼
                                POSIT CONNECT STAGING GATE
```

---

# 4. Wave 0 — Contract Freeze

One main agent only.

Read:

```text
CLAUDE.md
IMPLEMENTATION_STATUS.md
docs/UI_CONTRACT.md
docs/ASSISTANT_CONTRACT.md
R/registry.R
R/repository.R
R/search.R
relevant correspondence contracts
current app navigation/UI IDs
```

Do not inspect every dataset.

Freeze:

```text
canonical classification schema
adapter contract
version/status contract
search contract
correspondence schema
main_nav values
Search input IDs
Level input ID
RM module/session contract
```

Return a compact shared-contract memo to all workstreams.

---

# 5. Wave 1 — Maximum Safe Parallelism

Run these concurrently where agent support exists.

## 5.1 Correspondence subgraph

Follow:

`PSIC_2019_2026_STRUCTURAL_CORRESPONDENCE_REPAIR.md`

Parallel ownership:

```text
structural graph
detailed mapping
provenance/docs
```

Do not edit registry/UI during this wave.

## 5.2 Classification source subgraph

Follow:

`ADDITIONAL_CLASSIFICATION_SYSTEMS_INGESTION.md`

Parallel ownership:

```text
PSCC new files only
PTSCS new files only
PSCrCS new files only
```

Do not edit `R/registry.R`, shared Search UI, or Sources UI during source-specific work.

## 5.3 UI subgraph

Follow:

`PRE_STAGING_UI_UAT_REPAIR.md`

Safe early parallel ownership:

```text
global footer/layout CSS
Search DT/All-levels audit and local module changes
Sources card implementation using existing registry only
```

Do not yet add new-system cards or composite controls until registry convergence is complete.

---

# 6. Wave 2 — Shared Metadata/Registry Convergence

Single owner.

Inputs:

```text
validated PSCC adapter
validated PTSCS adapter
validated PSCrCS adapter
canonical PSCCS correction
Wave 0 contracts
```

Own shared files such as:

```text
R/registry.R
R/repository.R only if needed
R/metadata.R if present
shared adapter metadata tests
```

Tasks:

1. register PSCC 2022;
2. register PTSCS 2025 Version 2.1;
3. register PSCrCS 2025;
4. correct PSCCS name;
5. preserve current/archive semantics;
6. expose optional `component` metadata;
7. preserve all existing systems.

Freeze registry after targeted tests pass.

---

# 7. Wave 3 — Correspondence Convergence

Single owner.

Integrate:

```text
structural graph
detailed mapping precedence
provenance evidence
artifact rebuild
reverse/service graph
```

Rebuild:

```text
data/psic_2019_to_2026_correspondence.rds
metadata artifact
```

Run P0 correspondence tests.

Freeze when:

- G→G/T correct;
- J→J/K correct;
- K onward shifts correct;
- reverse symmetry passes;
- provenance honest.

---

# 8. Wave 4 — Shared UI Convergence

Single owner after registry + correspondence freeze.

Tasks:

## Search

- include validated PSCC/PTSCS/PSCrCS systems;
- remove redundant native DT search;
- make `All levels` explicit default;
- preserve blank-query browse;
- conditionally expose `Component` for PTSCS/PSCrCS.

## Sources

- render cards from final registry;
- include new systems only if registered;
- correct PSCCS name;
- no nested public scroll panels;
- supplemental edition cards;
- correspondence methodology card;
- technical details collapsed.

## Compare Editions

Verify repaired correspondence; modify presentation only if needed to show correct multi-target relationships.

## Global

Ensure source/footer does not overlay content.

Preserve RM mobile composer fix.

---

# 9. Wave 5 — RM Generic Integration Check

Do not build new RM architecture.

Confirm the existing generic tools expose:

```text
PSCC
PTSCS
PSCrCS
correct PSCCS metadata
```

through:

```text
assistant_classification_registry()
assistant_search_classification()
assistant_get_classification_entry()
```

Update intent routing only if necessary.

No live provider evaluation is required for this code-convergence wave if credentials are absent.

Deterministic RM tests must still pass.

---

# 10. Wave 6 — Targeted Test Bundles

Run in this order:

```text
new-source build/adapter tests
registry/metadata tests
correspondence structural/detailed/reverse tests
Search/reactive UI tests
Sources UI tests
RM deterministic tests
```

Do not run the full 1100+ suite after every tiny CSS patch.

Use targeted tests during loops.

Run full suite only at major convergence gates.

---

# 11. Wave 7 — Full Regression

Run:

```text
Rscript scripts/run_tests.R
```

Required:

```text
0 failures
0 unexpected warnings
0 regressions
```

Final count may increase materially.

Do not optimize for an exact count.

---

# 12. Wave 8 — Browser/Human UAT

Test all five destinations:

```text
Search
PSOC + PSIC
Compare Editions
RM Assistant
Sources
```

## Search cases

- PSGC `negros`, All levels;
- blank-query browse;
- archived edition;
- PSCC exact/punctuated code;
- PTSCS component switching;
- PSCrCS component switching;
- correct PSCCS label;
- no secondary native DT Search field.

## Compare Editions

- G trade/repair case;
- J→J/K split;
- K→L shift;
- 2026→2019 reverse;
- multi-target relationship;
- provenance;
- statistical warning.

## Sources

- responsive card deck;
- current/archive disclosures;
- new systems;
- PSCC/PSCCS distinction;
- supplemental cards;
- correspondence methodology;
- no nested scroll traps;
- no footer overlap.

## RM

With RM disabled:

- calm unavailable state;
- other tabs unaffected.

With RM enabled only if credentials are available:

- generic registry sees new systems;
- no-code-without-retrieval remains enforced.

## Viewports

```text
1440 desktop
1366×768
768 tablet
375 mobile
320 mobile
```

Preserve RM Send visibility at 375/320.

---

# 13. Token Optimization Policy

## Main agent

Read only:

- shared contracts;
- workstream summaries;
- failed test output;
- final changed shared files.

Do not reopen every source-specific implementation after targeted tests pass.

## Source workstreams

Inspect workbooks with:

```text
sheet names
headers
metadata
counts
distinct components
small samples
duplicates
```

Never dump full workbook contents.

## Correspondence workstreams

Inspect:

```text
targeted section/division chains
specific repair/trade cases
specific J/K examples
counts
```

Do not print whole PSIC tables.

## UI workstreams

Do not load classification datasets to fix layout.

---

# 14. Bounded Repair Loops

Every criterion:

```text
inspect
→ smallest complete patch
→ targeted test
→ evaluate
→ max 3 repair iterations
→ escalate genuine contract blocker
```

Do not use repeated speculative refactoring.

Freeze passing workstreams.

---

# 15. Shared File Locking

Do not permit simultaneous edits to:

```text
R/registry.R
R/repository.R
app.R
docs/UI_CONTRACT.md
IMPLEMENTATION_STATUS.md
```

Assign them only during explicit convergence waves.

Similarly, `www/app.css` should have one owner during any given wave.

---

# 16. Documentation Convergence

At the end, update once:

```text
IMPLEMENTATION_STATUS.md
docs/UI_CONTRACT.md
docs/DATA_SOURCES.md
docs/CORRESPONDENCE_SOURCES.md
docs/ASSISTANT_CONTRACT.md only if assistant contract changed
README.md only where public feature list/deployment notes need correction
```

Avoid multiple workstreams editing `IMPLEMENTATION_STATUS.md`.

Each workstream should return a summary; the final integrator writes the status document once.

---

# 17. Pre-Staging Definition of Done

## Statistical correctness

- [ ] repaired PSIC structural correspondence;
- [ ] forward/reverse symmetry;
- [ ] honest provenance.

## Additional classifications

- [ ] PSCC 2022;
- [ ] PTSCS 2025 Version 2.1;
- [ ] PSCrCS 2025;
- [ ] canonical PSCCS correction.

## Search/UI

- [ ] All levels real default;
- [ ] redundant table Search removed;
- [ ] component controls;
- [ ] Sources cards;
- [ ] no footer overlap;
- [ ] no mobile regressions.

## Tests

- [ ] targeted suites pass;
- [ ] full regression passes.

## UAT

- [ ] all five destinations pass;
- [ ] 375px and 320px pass.

Only then:

```text
READY FOR POSIT CONNECT CLOUD STAGING
```

---

# 18. Final Claude Code Report

Report:

1. starting branch/status/test count;
2. workstream graph execution;
3. files changed by workstream;
4. new classification validation counts;
5. PSCCS correction;
6. correspondence root cause/fix;
7. artifact before/after statistics;
8. UI fixes;
9. targeted test results;
10. full regression final count;
11. browser UAT;
12. remaining known limitations;
13. staging decision.

Return exactly one:

```text
READY FOR POSIT CONNECT CLOUD STAGING
```

or:

```text
NOT READY FOR STAGING
```

with blockers.

Do not commit automatically.

Do not deploy.

---

# 19. Direct Claude Code Orchestration Prompt

Execute the pre-staging graph defined in:

```text
PRE_STAGING_PARALLEL_EXECUTION_MASTER.md
```

and the three underlying specifications:

```text
PSIC_2019_2026_STRUCTURAL_CORRESPONDENCE_REPAIR.md
ADDITIONAL_CLASSIFICATION_SYSTEMS_INGESTION.md
PRE_STAGING_UI_UAT_REPAIR.md
```

Start by verifying branch, Git state, and current full regression baseline.

Freeze shared contracts once.

Then maximize safe parallelism:

- correspondence structural/detailed/provenance work;
- PSCC/PTSCS/PSCrCS source-specific ingestion;
- non-conflicting UI footer/Search/Sources preparation.

Do not let agents concurrently edit shared registry, app, status, contract, or CSS files.

Converge in this order:

1. metadata/registry;
2. correspondence artifact/service;
3. shared UI;
4. RM generic integration check;
5. targeted tests;
6. full regression;
7. browser UAT;
8. documentation;
9. staging gate.

Optimize token use by reading only relevant files and consuming workstream summaries rather than reopening complete implementations.

Do not deploy.

Do not commit automatically.

Proceed until the staging gate can be answered accurately.

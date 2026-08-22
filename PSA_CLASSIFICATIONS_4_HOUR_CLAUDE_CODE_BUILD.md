# PSA Statistical Classifications Search — 4-Hour Claude Code Build Handoff

**Target:** Functional, public-facing MVP in approximately four focused hours  
**Primary implementation agent:** Claude Code  
**UI strategy:** Functionality-first; deliberately minimal visual styling so the completed functional app can be handed to Claude Design for the final UI/UX pass  
**Primary stack:** R Shiny + `bslib` + `phscs` + `psgc` + `DT` + `dplyr` + `stringr`  
**Deployment target:** Posit Connect Cloud or equivalent Shiny-compatible public hosting  
**Scope:** Read-only statistical classification search, browse, version/edition selection, archived references, source/provenance display, and PSIC Revision 5 inclusion

---

## 0. EXECUTIVE IMPLEMENTATION DIRECTIVE

Build a **functionally complete, design-ready MVP** for external stakeholders to search Philippine Statistics Authority (PSA) statistical classifications.

The application must:

1. Use `phscs` as the primary packaged classification source.
2. Use `psgc` for PSGC releases and historical mapping capabilities.
3. Include **PSIC Revision 5 / 2026 PSIC from the first implementation**, even if the installed `phscs` version does not yet contain it.
4. Preserve archived classifications and expose their edition/version explicitly.
5. Search by both code and descriptive text.
6. Keep all business/data/search logic independent from Shiny UI code.
7. Use only a **minimal semantic `bslib` UI** in this phase.
8. Do **not** spend implementation time on final branding, animation, decorative styling, or a final visual system.
9. Produce a stable UI/data contract that can be handed to **Claude Design** after functionality is verified.
10. Remain stateless and read-only for the MVP: **no authentication, no user database, no admin CMS, no PostgreSQL, no PSA API token requirement**.
11. Be deployable from the repository with reproducible dependencies.

The success criterion is not visual polish. The success criterion is:

> A user can select a classification and edition, search a code or keyword, inspect results, distinguish current from archived references, see provenance/source metadata, and use PSIC Revision 5 immediately.

---

# 1. NON-NEGOTIABLE ARCHITECTURAL RULES

## 1.1 Functional core, imperative shell

The Shiny server must not contain classification-specific transformation logic.

Use:

```text
UI
  ↓
Shiny reactives/controllers
  ↓
Application service
  ↓
Classification repository
  ↓
Adapters/data sources
  ├── phscs
  ├── psgc
  └── PSA PSIC Revision 5 normalized snapshot
```

The following should be callable and testable without launching Shiny:

```r
classification_registry()
classification_versions(system)
classification_levels(system, version)
get_classification(system, version, level)
search_classification(system, version, query, level = NULL)
get_classification_entry(system, version, code)
classification_metadata(system, version)
```

Do not tie these functions to `input`, `output`, `session`, HTML tags, or Shiny reactive objects.

---

## 1.2 Do not over-engineer the four-hour MVP

Explicitly **do not implement**:

- PostgreSQL
- SQLite unless required for an unexpected hosting limitation
- Redis
- Elasticsearch
- Typesense
- Meilisearch
- Plumber API
- REST API
- GraphQL
- React
- Next.js
- Vue
- authentication
- admin accounts
- editable classifications
- runtime PSA synchronization
- scheduled jobs
- analytics dashboards
- complex caching infrastructure
- custom JavaScript search engines
- final branding/design system

Classification datasets are sufficiently small for in-memory use.

---

# 2. PSIC REVISION 5 REQUIREMENT

## 2.1 Current-source reality

As of August 2026:

- PSA officially released **Philippine Standard Industrial Classification Revision 5**, also referred to as the **2026 PSIC**.
- PSA announced its release on **5 August 2026**.
- It was approved/adopted by the PSA Board on **21 May 2026** through PSA Board Resolution No. 09, Series of 2026.
- PSA's official Revision 5 structure contains:
  - 22 sections
  - 88 divisions
  - 260 groups
  - 493 classes
  - 1,338 sub-classes
- The current `phscs` public documentation still identifies `"2019"` as the latest/default PSIC version.
- PSA's published PSIC API documentation currently lists `2019` as the available API version.
- Therefore **do not make PSIC Revision 5 dependent on a PSA API call or a future `phscs` release**.

Official PSA source page:

```text
https://psa.gov.ph/classification/psic
```

Official Revision 5 detailed structure workbook:

```text
https://psa.gov.ph/sites/default/files/scd/PSIC_Revision_5_Detailed_Structure_30July2026.xlsx
```

PSA release announcement:

```text
https://psa.gov.ph/content/psa-releases-philippine-standard-industrial-classification-revision-5
```

PSA PSIC API documentation:

```text
https://psa.gov.ph/classifications-api/psic
```

PSA states that website data/content is licensed under **CC BY 4.0 unless otherwise stated**. Preserve PSA attribution and source URLs in metadata.

---

## 2.2 Required PSIC Revision 5 implementation

Implement a build-time normalization pipeline.

Preferred structure:

```text
data-raw/
  PSIC_Revision_5_Detailed_Structure_30July2026.xlsx   # optional raw snapshot
data/
  psic_2026.rds                                       # normalized runtime artifact
scripts/
  build_psic_2026.R
R/
  sources/
    source_psic_2026.R
```

If repository policy avoids committing the raw XLSX, then:

```text
scripts/build_psic_2026.R
```

must:

1. download the workbook from the official PSA URL;
2. validate that the workbook is readable and structurally plausible;
3. parse all PSIC hierarchy levels;
4. normalize it into the application's canonical classification schema;
5. validate row counts where possible;
6. save a deterministic local runtime artifact such as `data/psic_2026.rds`;
7. record source URL, retrieval date, and optional SHA-256 hash in metadata.

**Runtime searches must not depend on PSA website availability.**

The deployed app should read the normalized local artifact.

---

## 2.3 Canonical PSIC 2026 version identifier

Internally use a stable machine identifier:

```text
2026
```

Display label:

```text
PSIC Revision 5 (2026)
```

Also retain:

```text
2019
```

as an archived PSIC edition through `phscs`.

If older PSIC editions are exposed by the installed package, include them dynamically rather than hard-coding only two versions.

---

# 3. CANONICAL CLASSIFICATION SCHEMA

All adapters should return a canonical structure.

Minimum required fields:

```r
tibble(
  system       = character(),
  version      = character(),
  level        = character(),
  code         = character(),
  label        = character(),
  description  = character(),
  parent_code  = character(),
  status       = character(),
  source       = character(),
  source_url   = character()
)
```

Definitions:

| Field | Meaning |
|---|---|
| `system` | `psic`, `psoc`, `psced`, `pcoicop`, `pcpc`, `psccs`, `psgc` |
| `version` | edition/release identifier |
| `level` | section/division/group/class/sub-class/etc. |
| `code` | official classification code |
| `label` | human-readable classification title |
| `description` | detailed explanatory text if available |
| `parent_code` | immediate parent where derivable |
| `status` | `current`, `archived`, or other explicit state |
| `source` | normally `Philippine Statistics Authority` |
| `source_url` | official source page |

Do not force source-specific column names into UI logic.

---

# 4. CLASSIFICATION REGISTRY

Create one registry as the single source of truth.

Example conceptual contract:

```r
classification_registry()
```

returns rows/objects describing:

```text
psgc
psic
psoc
psced
pcoicop
pcpc
psccs
```

Metadata should include:

```text
id
display_name
short_name
category
adapter
available_versions
current_version
available_levels
supports_history
source
source_url
```

The UI must derive selectors from this registry rather than duplicate classification knowledge.

---

# 5. SEARCH CONTRACT

Implement:

```r
search_classification(
  system,
  version,
  query,
  level = NULL,
  limit = 100
)
```

## 5.1 MVP ranking

Use deterministic ranking:

1. exact code match;
2. code starts with query;
3. exact normalized label match;
4. label starts with query;
5. label contains query;
6. description contains query.

Case-insensitive for textual searches.

Do not add fuzzy matching in the first four-hour build unless all P0 work is complete.

Normalize whitespace.

Do not convert classification codes to numeric values; preserve leading zeros.

---

## 5.2 Empty query behavior

A blank search may return:

- the selected level's first N entries; or
- no results until the user enters a search.

Choose one behavior consistently.

Preferred MVP behavior:

> Blank query shows a browsable/paginated classification table for the selected system/version/level.

This combines Search and Browse without additional complexity.

---

# 6. ARCHIVE AND VERSION BEHAVIOR

Every result must visibly preserve:

```text
classification system
edition/release
classification level
code
title
current/archive status
source
```

Example:

```text
System: PSIC
Edition: Revision 5 (2026)
Code: 62010
Level: Sub-class
Status: Current
Source: Philippine Statistics Authority
```

Archived result:

```text
System: PSIC
Edition: 2019
Status: Archived reference
```

Never label an old edition as incorrect. It is an archived reference that may be valid for historical datasets.

---

# 7. PSGC REQUIREMENTS

Use `psgc` for PSGC data where possible.

MVP requirements:

- release selector;
- geographic level selector;
- code/name search;
- current versus archived release label;
- metadata/source.

Do not spend the four-hour build implementing a graphical history timeline.

However, preserve a service seam for later:

```r
trace_psgc_code(code, from = NULL, to = NULL)
```

which can later wrap `psgc::map_psgc()`.

No UI is required for this function in MVP unless all P0 items are done early.

---

# 8. MINIMAL DESIGN-READY SHINY UI

## 8.1 UI objective

The first implementation must be **usable but intentionally visually neutral**.

Use `bslib` and semantic layout primitives.

Recommended structure:

```text
Header / application title

[Classification system]
[Edition / release]
[Classification level]

[Search field]

Results table

Selected result details
  Code
  Label
  Description
  Version
  Level
  Status
  Source

Footer/source note
```

Recommended `bslib` primitives:

```r
page_navbar()
nav_panel()
layout_sidebar()
sidebar()
card()
card_header()
card_body()
value_box()   # only if genuinely useful; probably unnecessary
```

Do not create decorative dashboard widgets just to fill space.

---

## 8.2 Stable UI contract for Claude Design

Create a document:

```text
docs/UI_CONTRACT.md
```

It must specify:

### Screens/views

1. Search
2. Browse/Archive
3. About/Data Sources

Search and Browse may initially share the same functional screen.

### Stable input IDs

For example:

```text
classification_system
classification_version
classification_level
classification_query
classification_results
selected_entry
```

### Stable conceptual components

```text
AppHeader
ClassificationSelector
VersionSelector
LevelSelector
SearchBox
SearchResults
ClassificationDetail
ArchiveBadge
SourceAttribution
AppFooter
```

These names are conceptual; Shiny does not need a JS component framework.

### Design invariants

Claude Design may later change:

- typography
- color
- spacing
- visual hierarchy
- card treatments
- navigation styling
- responsive layout details
- icons
- microinteractions
- component appearance

Claude Design must **not** need to change:

- classification adapters
- canonical schema
- search ranking
- version logic
- archive logic
- source/provenance logic
- tests
- data ingestion

---

# 9. PROPOSED REPOSITORY STRUCTURE

Use this unless an existing repo structure makes a small adjustment more appropriate.

```text
psa-classifications/
├── app.R
├── R/
│   ├── registry.R
│   ├── repository.R
│   ├── search.R
│   ├── versions.R
│   ├── metadata.R
│   ├── adapters/
│   │   ├── adapter_phscs.R
│   │   ├── adapter_psgc.R
│   │   └── adapter_psic_2026.R
│   └── ui/
│       ├── ui_search.R
│       ├── ui_details.R
│       └── ui_sources.R
├── data/
│   └── psic_2026.rds
├── data-raw/
│   └── PSIC_Revision_5_Detailed_Structure_30July2026.xlsx
├── scripts/
│   └── build_psic_2026.R
├── tests/
│   └── testthat/
│       ├── test-registry.R
│       ├── test-search.R
│       ├── test-versions.R
│       ├── test-psic-2026.R
│       └── test-adapters.R
├── docs/
│   ├── UI_CONTRACT.md
│   ├── DATA_SOURCES.md
│   └── DEPLOYMENT.md
├── www/
│   └── app.css
├── renv.lock
├── .Rprofile
├── README.md
└── .gitignore
```

If using `renv`, initialize and snapshot only the packages actually needed.

---

# 10. DEPENDENCIES

Keep dependency surface small.

Core:

```r
shiny
bslib
phscs
psgc
dplyr
stringr
tibble
purrr
DT
readxl
testthat
```

Potentially:

```r
httr2
digest
```

Use `httr2` only for the build-time Revision 5 downloader if necessary.

Use `digest` if recording SHA-256.

Avoid adding packages for functionality already available in the above set.

---

# 11. FOUR-HOUR ENGINEERING GRAPH

The work must be executed as a dependency graph rather than one monolithic coding loop.

## 11.1 DAG

```text
                         ┌────────────────────┐
                         │ A. Repo/Foundation │
                         └─────────┬──────────┘
                                   │
             ┌─────────────────────┼─────────────────────┐
             ▼                     ▼                     ▼
 ┌─────────────────────┐ ┌───────────────────┐ ┌──────────────────────┐
 │ B. phscs/psgc       │ │ C. PSIC 2026     │ │ D. Search contracts │
 │ adapters + registry │ │ ingest/normalize  │ │ + ranking           │
 └──────────┬──────────┘ └─────────┬─────────┘ └──────────┬───────────┘
            │                      │                      │
            └──────────────┬───────┴──────────────┬───────┘
                           ▼                      ▼
                  ┌─────────────────┐     ┌─────────────────┐
                  │ E. Repository   │     │ F. Unit tests   │
                  │ integration     │     │ per workstream  │
                  └────────┬────────┘     └────────┬────────┘
                           └───────────┬────────────┘
                                       ▼
                            ┌─────────────────────┐
                            │ G. Minimal Shiny UI │
                            └──────────┬──────────┘
                                       ▼
                            ┌─────────────────────┐
                            │ H. Integration/UAT  │
                            └──────────┬──────────┘
                                       ▼
                 ┌─────────────────────┼────────────────────┐
                 ▼                     ▼                    ▼
        ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────┐
        │ I. UI contract  │  │ J. Deployment   │  │ K. Final audit   │
        │ for Design      │  │ packaging/docs  │  │ + handoff        │
        └─────────────────┘  └──────────────────┘  └──────────────────┘
```

---

# 12. PARALLEL WORKSTREAMS

If Claude Code has subagent/parallel-task capability, use it.

## Wave 1 — parallel after foundation

### Workstream B — classification adapters

Allowed focus:

```text
R/registry.R
R/adapters/adapter_phscs.R
R/adapters/adapter_psgc.R
tests/testthat/test-registry.R
tests/testthat/test-adapters.R
```

Goal:

- inspect actual installed `phscs` and `psgc` APIs;
- adapt classification data into canonical schema;
- discover versions dynamically;
- preserve code strings;
- add unit tests.

Do not modify Shiny UI.

---

### Workstream C — PSIC Revision 5

Allowed focus:

```text
scripts/build_psic_2026.R
R/adapters/adapter_psic_2026.R
data/
data-raw/
tests/testthat/test-psic-2026.R
docs/DATA_SOURCES.md
```

Goal:

- ingest official PSA workbook;
- normalize all available levels;
- generate `psic_2026.rds`;
- validate known structure;
- expose through same canonical schema;
- make 2026 current and 2019 archived.

Do not modify Shiny UI.

---

### Workstream D — search engine

Allowed focus:

```text
R/search.R
tests/testthat/test-search.R
```

Goal:

- implement deterministic ranking;
- exact code priority;
- prefix priority;
- textual label and description matching;
- no mutation of source data;
- tests.

Do not modify adapters unless a contract defect is discovered; report the contract issue instead.

---

## Wave 2 — integration

Run after B/C/D converge.

### Workstream E

Integrate:

```text
registry
+
adapters
+
PSIC 2026
+
search
```

into:

```r
get_classification()
classification_versions()
classification_levels()
classification_metadata()
search_classification()
```

Resolve contract mismatches once, centrally.

---

## Wave 3 — parallel

Once the repository/service layer passes tests:

### G1 — minimal Shiny UI

Build functional UI only.

### G2 — UI contract documentation

Write `docs/UI_CONTRACT.md` from actual stable interfaces.

### G3 — deployment packaging

Prepare `renv`, README, and deployment instructions.

These may proceed in parallel because they consume the same stable service contract and should not modify it.

---

# 13. LOOP ENGINEERING RULES

Each workstream must follow a bounded loop.

Use:

```text
INSPECT
  ↓
IMPLEMENT MINIMAL CHANGE
  ↓
TEST
  ↓
EVALUATE
  ├── pass → stop workstream
  └── fail → diagnose smallest cause
                 ↓
             patch once
                 ↓
                test
```

## Loop constraints

1. Maximum **three repair iterations per failing acceptance criterion** before escalating it in the handoff.
2. Do not repeatedly rewrite files that already satisfy tests.
3. Do not refactor unrelated working code.
4. Do not “improve” UI aesthetics during data/search work.
5. Read the smallest relevant file set before editing.
6. Prefer targeted searches over rereading the entire repository.
7. After a workstream passes its tests, freeze its public contract unless integration proves it incorrect.
8. Avoid duplicate reasoning across subagents: give each workstream its exact file ownership and acceptance criteria.
9. At merge/convergence, inspect diffs and contracts rather than rereading every implementation line.
10. Use tests as compressed memory: if a behavior is important, encode it in a test rather than repeatedly restating it in prompts.

---

# 14. TOKEN-EFFICIENCY RULES FOR CLAUDE CODE

Claude Code must optimize context/token usage.

## Required behavior

- Start by reading:
  - `CLAUDE.md` if present;
  - repository tree;
  - dependency files;
  - only the files relevant to the current workstream.
- Do not load all files into context preemptively.
- Use targeted grep/search for:
  - package calls;
  - existing Shiny IDs;
  - source adapters;
  - tests;
  - deployment configuration.
- Delegate independent workstreams with concise contracts.
- Each subagent should return:
  1. files changed;
  2. tests run;
  3. result;
  4. unresolved risks;
  5. public contract changed, if any.
- Main agent should consume those summaries first and inspect code only when integration requires it.
- Never ask a subagent to summarize the whole repository.
- Never ask two subagents to solve the same problem independently unless explicitly performing a review.
- Use one final review agent/pass only after functionality is integrated.

---

# 15. IMPLEMENTATION WAVES AND TIMEBOX

These are prioritization windows, not a reason to stop mid-test.

## 0:00–0:20 — Foundation

- inspect repo/environment;
- scaffold project if empty;
- initialize dependency management;
- establish canonical schema;
- create registry/repository interfaces;
- create tests skeleton;
- confirm `phscs`, `psgc`, and Revision 5 source availability.

### Exit gate

Contracts exist and Wave 1 workstreams can operate independently.

---

## 0:20–1:20 — Parallel data/search work

Run B, C, and D in parallel if possible.

Expected output:

- `phscs` adapter;
- `psgc` adapter;
- Revision 5 normalized source;
- deterministic search engine;
- unit tests.

### Exit gate

Representative adapter and search tests pass.

---

## 1:20–1:50 — Convergence

Integrate repository/service functions.

Must verify:

```text
PSIC 2026 load
PSIC 2019 load
PSOC load
PSCED load
PCOICOP load
PCPC load
PSCCS load
PSGC load
version enumeration
level enumeration
search
metadata
```

### Exit gate

Service layer works without Shiny.

---

## 1:50–2:50 — Minimal Shiny UI

Implement:

- classification selector;
- version/release selector;
- level selector;
- search box;
- results table;
- selected-row details;
- archived/current badge;
- source attribution.

No visual redesign.

### Exit gate

End-to-end interaction works locally.

---

## 2:50–3:25 — UAT and defects

Test representative cases.

Required cases:

1. exact PSIC Revision 5 code;
2. PSIC Revision 5 text search;
3. PSIC 2019 archived search;
4. exact PSOC code;
5. PSOC text search;
6. PSGC current release name search;
7. PSGC old release search;
8. classification level filter;
9. blank query;
10. no result;
11. special characters;
12. leading-zero code preservation;
13. switching classification clears/updates invalid level/version state;
14. selected result retains source/version/status.

Fix only P0/P1 defects.

---

## 3:25–3:45 — Deployment packaging

- snapshot dependencies;
- validate app startup from clean session;
- write deployment notes;
- ensure runtime does not fetch Revision 5 from PSA;
- ensure no secrets are required;
- verify public-safe configuration.

---

## 3:45–4:00 — Claude Design handoff + final audit

Generate:

```text
docs/UI_CONTRACT.md
docs/DATA_SOURCES.md
docs/DEPLOYMENT.md
IMPLEMENTATION_STATUS.md
```

Do not redesign UI in this phase.

---

# 16. ACCEPTANCE TESTS

## P0 — must pass

### Data

- [ ] `phscs` classifications load.
- [ ] `psgc` loads.
- [ ] PSIC Revision 5 loads from local normalized artifact.
- [ ] PSIC 2026 is marked current.
- [ ] PSIC 2019 is available as archived.
- [ ] Codes remain character strings.
- [ ] Available versions are discoverable.
- [ ] Available levels are discoverable.

### Search

- [ ] Exact code is ranked first.
- [ ] Code prefix works.
- [ ] Label search is case-insensitive.
- [ ] Description search works when description exists.
- [ ] Level restriction works.
- [ ] No-result search does not error.
- [ ] Blank query behavior is deterministic.

### UI

- [ ] Classification can be selected.
- [ ] Edition/release can be selected.
- [ ] Level can be selected.
- [ ] Search can be entered.
- [ ] Results render.
- [ ] Selecting a result renders details.
- [ ] Version/status/source are visible.
- [ ] Archived references are distinguishable from current.
- [ ] Layout remains usable on a narrow viewport.

### Reliability

- [ ] No PSA API token is required.
- [ ] No PSA runtime network dependency for PSIC 2026.
- [ ] App starts from a clean R session.
- [ ] Automated tests pass.

---

# 17. PSIC REVISION 5 VALIDATION

At minimum validate the official structure where parsing supports it:

```text
Sections:    22
Divisions:   88
Groups:      260
Classes:     493
Sub-classes: 1,338
```

If workbook parsing makes one of these counts ambiguous due to sheet formatting, do not silently force the expected count.

Instead:

1. inspect the workbook structure;
2. document the interpretation;
3. create a validation test for the parsed canonical records;
4. flag any discrepancy in `IMPLEMENTATION_STATUS.md`.

Never fabricate missing rows to hit an expected total.

---

# 18. SOURCE/PROVENANCE REQUIREMENTS

Every classification edition should have metadata.

Example:

```r
list(
  system = "psic",
  version = "2026",
  display_version = "PSIC Revision 5 (2026)",
  status = "current",
  source = "Philippine Statistics Authority",
  source_url = "https://psa.gov.ph/classification/psic",
  source_artifact_url =
    "https://psa.gov.ph/sites/default/files/scd/PSIC_Revision_5_Detailed_Structure_30July2026.xlsx",
  retrieved_at = "...",
  license = "CC BY 4.0 unless otherwise stated by PSA"
)
```

Do not imply that `phscs` is the official issuing authority. It is the software/data access package; PSA is the classification source.

---

# 19. ERROR HANDLING

The app must fail gracefully.

Examples:

### Missing normalized Revision 5 artifact

Developer-facing startup error:

```text
PSIC Revision 5 runtime artifact is missing.
Run scripts/build_psic_2026.R and redeploy.
```

Do not silently fall back to 2019 while displaying 2026.

### Unsupported version

Return a clear validation error containing available versions.

### Unsupported level

Return a clear validation error containing available levels.

### Search with no matches

Return zero rows and a user-friendly empty state, not an exception.

---

# 20. SECURITY / PUBLIC DEPLOYMENT

This is a public read-only reference app.

Still enforce:

- no embedded secrets;
- no API tokens in client HTML/JavaScript;
- no user-supplied file execution;
- no `eval(parse())`;
- no arbitrary URL fetching from user input;
- HTML escaping/safe rendering for classification text;
- dependencies pinned/reproducible;
- no debug stack traces shown to normal users in production.

No personal data should be collected in this MVP.

---

# 21. PERFORMANCE TARGET

For normal classification sizes:

- initial app load: reasonable for public Shiny hosting;
- common search response: perceived interactive response, preferably under ~300 ms after data is loaded;
- avoid reloading package datasets on every keystroke;
- load/cache immutable classification data once per R process where practical;
- debounce text search approximately 200–300 ms if needed.

Do not optimize prematurely with external search infrastructure.

---

# 22. DESIGN HANDOFF RULE

**This implementation must stop before final visual design.**

At completion, the application should have:

- correct functionality;
- semantic layout;
- neutral Bootstrap/bslib appearance;
- stable IDs;
- stable data contracts;
- responsive basics;
- accessibility-conscious markup.

The next design phase may use Claude Design to visually redesign the UI.

The design phase must be able to work primarily in:

```text
app.R
R/ui/
www/app.css
```

without needing to alter:

```text
R/adapters/
R/repository.R
R/search.R
R/registry.R
scripts/build_psic_2026.R
data/
tests for data/search behavior
```

If the implementation couples presentation to data logic such that redesign requires rewriting backend logic, treat that as an architecture defect and fix it before handoff.

---

# 23. `UI_CONTRACT.md` REQUIRED CONTENT

Claude Code must produce `docs/UI_CONTRACT.md` including:

1. application purpose;
2. user flows;
3. screen/view inventory;
4. stable Shiny input/output IDs;
5. service functions consumed by each view;
6. result object schema;
7. states:
   - initial;
   - loading;
   - results;
   - no results;
   - error;
   - archived;
   - current;
8. responsive requirements;
9. accessibility requirements;
10. elements Claude Design may freely change;
11. elements Claude Design must not change without backend review.

---

# 24. TEST STRATEGY

Use `testthat`.

Prefer many small tests over one giant integration test.

Suggested minimum:

```text
test-registry.R
  - systems registered
  - display names
  - current versions

test-adapters.R
  - canonical columns
  - code character type
  - required metadata

test-psic-2026.R
  - source artifact present
  - hierarchy levels parse
  - expected counts where valid
  - current status

test-search.R
  - exact code rank
  - prefix rank
  - case-insensitive label
  - description
  - no result
  - level filter

test-versions.R
  - PSIC 2026 current
  - PSIC 2019 archived
  - PSGC release enumeration
```

Shiny-specific tests may remain light in the four-hour MVP if service tests are comprehensive.

---

# 25. FINAL IMPLEMENTATION STATUS FILE

Create:

```text
IMPLEMENTATION_STATUS.md
```

with:

```text
## Completed
## Tests Passed
## Deployment Status
## PSIC Revision 5 Status
## Known Limitations
## Deferred V2 Features
## Claude Design Handoff Readiness
## Files Changed
```

Do not claim deployment succeeded unless deployment was actually performed.

---

# 26. DEFERRED FEATURES — DO NOT IMPLEMENT DURING FOUR-HOUR BUILD

Record these as V2+ candidates:

- cross-edition difference viewer;
- full PSIC 2019 ↔ Revision 5 crosswalk;
- PSGC visual history timeline;
- PSGC split/merge/abolition visualization;
- fuzzy search / typo tolerance;
- search across all classification systems simultaneously;
- saved/favorite codes;
- shareable deep links;
- downloadable result citations;
- admin dashboard;
- automatic PSA update synchronization;
- PSA API staging/validation;
- PostgreSQL canonical repository;
- usage analytics;
- feedback system;
- multilingual UI if required;
- WCAG formal audit;
- custom PSA visual branding/design system.

Do not let these delay the MVP.

---

# 27. CLAUDE CODE OPERATING PROMPT

Use the following as the direct implementation instruction.

---

## IMPLEMENTATION PROMPT

You are the primary implementation engineer for a four-hour MVP of a public PSA Statistical Classifications Search application.

Read this entire handoff first.

### Mission

Implement a functional, testable, deployable R Shiny application that allows external stakeholders to search and browse PSA statistical classifications using `phscs` and `psgc`, while also including PSIC Revision 5 (2026) from PSA's official detailed-structure workbook.

The application must be functionality-first and design-ready. Do not spend material time on final visual design because the completed functional application will be passed to Claude Design for a separate UI/UX phase.

### Required engineering method

Use graph/loop engineering.

1. Inspect repository state and `CLAUDE.md`.
2. Establish the canonical schema and public service contracts.
3. Parallelize independent workstreams where your environment supports it:
   - phscs/psgc adapters;
   - PSIC Revision 5 build-time ingestion;
   - search/ranking engine.
4. Give parallel workstreams explicit file ownership and acceptance criteria.
5. Converge only after workstream tests pass.
6. Build the minimal Shiny UI against the stable service layer.
7. Run the UAT cases in this document.
8. Prepare deployment artifacts.
9. Produce the design handoff documents.
10. Stop before final visual redesign.

### Token/context discipline

- Do not read the entire repository repeatedly.
- Use targeted search and smallest-file reads.
- Treat passing tests as compressed context.
- After each workstream, retain a concise summary of files changed, contracts, tests, and unresolved risks.
- Avoid duplicate parallel agents.
- Do not refactor unrelated code.
- Do not keep polishing code that already satisfies acceptance criteria.
- Cap repeated repair loops and report unresolved issues rather than thrashing.

### PSIC Revision 5

Do not assume `phscs::get_psic()` already provides Revision 5.

At implementation time, inspect the installed package.

Regardless, the MVP must expose:

```text
PSIC Revision 5 (2026) — current
2019 PSIC — archived
```

Use the official PSA Revision 5 workbook as the authoritative supplemental source if `phscs` does not yet contain 2026:

```text
https://psa.gov.ph/sites/default/files/scd/PSIC_Revision_5_Detailed_Structure_30July2026.xlsx
```

Build a normalized local runtime artifact. Runtime use must not depend on PSA website availability.

Do not use the PSA API as the source for Revision 5 unless the live official API documentation and endpoint demonstrably support it at implementation time. Current documentation may still expose only the 2019 API version.

### Architecture

Keep all classification/search/version logic outside Shiny.

The UI should consume stable functions such as:

```r
classification_registry()
classification_versions(system)
classification_levels(system, version)
get_classification(system, version, level)
search_classification(system, version, query, level = NULL)
get_classification_entry(system, version, code)
classification_metadata(system, version)
```

### UI

Implement only the minimum functional interface:

```text
classification selector
edition/release selector
level selector
search
results
selected result details
status/current/archive
source/provenance
```

Use `bslib`.

Keep CSS small and neutral.

Do not implement a decorative dashboard.

### Exit condition

Do not consider the task complete until:

- P0 acceptance tests pass;
- PSIC Revision 5 is actually queryable;
- PSIC 2019 remains queryable as archived;
- no PSA API token is required;
- service layer works independently of Shiny;
- app starts from a clean session;
- deployment instructions exist;
- `docs/UI_CONTRACT.md` exists;
- `IMPLEMENTATION_STATUS.md` accurately reports the state.

If deployment credentials/account access are unavailable, complete everything except the actual remote publish and clearly report that limitation.

---

# 28. HANDOFF TO CLAUDE DESIGN AFTER FUNCTIONAL BUILD

After Claude Code reports that the functional implementation and tests pass, do not ask it to redesign the UI.

Instead, provide Claude Design with:

```text
repository
docs/UI_CONTRACT.md
IMPLEMENTATION_STATUS.md
screenshots of the functional UI
desired PSA/public-service visual references
brand/color requirements
mobile/desktop priorities
accessibility target
```

Suggested design brief:

> Redesign the presentation layer of this working PSA statistical classification search app without altering the classification adapters, repository contracts, search semantics, version/archive behavior, or PSIC Revision 5 ingestion. Preserve all stable input/output behaviors defined in `docs/UI_CONTRACT.md`. Focus on an authoritative, modern Philippine public-service information experience with excellent search discoverability, hierarchy readability, archived/current edition clarity, responsive behavior, and WCAG-conscious interaction.

---

# 29. MVP DEFINITION OF DONE

The four-hour first implementation is **DONE** when an external stakeholder can:

1. open the public app;
2. select PSIC;
3. select **PSIC Revision 5 (2026)**;
4. search an industry by code or text;
5. inspect the hierarchy/result description;
6. see that Revision 5 is current;
7. switch to **2019 PSIC**;
8. see that it is an archived reference;
9. search PSOC, PSCED, PSGC, and other supported `phscs` classifications;
10. select an available PSGC release;
11. see clear PSA source/provenance information;
12. use the application without a PSA API token;
13. do all of the above through a functional but intentionally non-final UI.

At this point the implementation is ready for the separate Claude Design phase.

---

# 30. SOURCE REFERENCES FOR IMPLEMENTATION VALIDATION

Claude Code should verify these sources during implementation if internet access is available:

### PSA — PSIC Revision 5
```text
https://psa.gov.ph/classification/psic
```

### PSA release announcement
```text
https://psa.gov.ph/content/psa-releases-philippine-standard-industrial-classification-revision-5
```

### Official Revision 5 workbook
```text
https://psa.gov.ph/sites/default/files/scd/PSIC_Revision_5_Detailed_Structure_30July2026.xlsx
```

### PSA PSIC API documentation
```text
https://psa.gov.ph/classifications-api/psic
```

### phscs documentation
```text
https://yng-me.github.io/phscs/
https://yng-me.github.io/phscs/reference/get_psic.html
```

### psgc documentation
```text
https://yng-me.github.io/psgc/
```

Do not replace official PSA classification provenance with package documentation. Package documentation describes the software interface; PSA remains the authoritative statistical classification source.


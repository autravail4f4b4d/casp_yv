# PSA Classification Search — PSOC 2022 + Dual PSOC/PSIC Search + PSIC 2019↔2026 Correspondence

**Project:** PSA Statistical Classifications Search  
**Implementation phase:** Post-MVP functional extension / interrupted-session recovery  
**Primary implementation agent:** Claude Code  
**Design phase:** Claude Design after functional contracts are stabilized  
**Known-good baseline:** `mvp-functional-v1`  
**Existing MVP:** R Shiny + `bslib` + `phscs` + `psgc`, PSIC Revision 5 local artifact, canonical repository/search layer  
**Runtime principle:** public, read-only, offline-capable classification data; no PSA runtime dependency  
**This file supersedes:** the earlier dual-search/correspondence implementation specification where it conflicts with this document

---

# 0. EXECUTIVE DIRECTIVE

Resume the interrupted post-MVP implementation and deliver three related capabilities:

1. **PSOC 2022 ingestion and version correction**
   - add the official **2022 Updates to the 2012 Philippine Standard Occupational Classification (PSOC)**;
   - make internal version `"2022"` the current PSOC version;
   - retain `2012` from `phscs` as an archived reference;
   - build a local normalized runtime artifact so the application does not depend on PSA at runtime.

2. **Parallel PSOC + PSIC search**
   - one query searches current PSOC and current PSIC side by side;
   - default to **PSOC 2022** and **PSIC Revision 5 (2026)**;
   - preserve the conceptual distinction between occupation and industry.

3. **PSIC 2019 ↔ PSIC Revision 5 (2026) correspondence explorer**
   - provide bidirectional, provenance-aware correspondence;
   - preserve one-to-one, one-to-many, many-to-one, and complex relationships;
   - distinguish official, derived, and suggested mappings;
   - never present algorithmic similarity as an official PSA equivalence.

Do **not** perform the final visual redesign in this phase.

Claude Code should build/test the functional contracts and only enough neutral Shiny UI to exercise all states. Then update `docs/UI_CONTRACT.md` for Claude Design.

---

# 1. RECOVERY FROM THE INTERRUPTED CLAUDE CODE SESSION

The previous implementation attempt stopped because the usage limit was reached.

Do **not** assume:

- no work was done;
- all requested work was completed;
- the repository matches the previous written summary;
- partial files are correct;
- the Git working tree is clean.

Before changing code:

1. Read `CLAUDE.md`.
2. Read `IMPLEMENTATION_STATUS.md`.
3. Read this specification.
4. Run:
   ```bash
   git status
   git branch --show-current
   git log --oneline --decorate -10
   ```
5. Inspect only files changed since the last known-good checkpoint.
6. Search for partial implementations of:
   - PSOC 2022
   - parallel/dual search
   - correspondence/crosswalk
7. Run the existing test suite before deciding what remains.
8. Build a concise recovery matrix: `COMPLETE / PARTIAL / NOT STARTED / BROKEN`.
9. Continue from the verified state instead of rebuilding working code.

Suggested recovery matrix:

| Workstream | State | Evidence | Action |
|---|---|---|---|
| Existing MVP regression suite | ? | test run | preserve/fix |
| PSOC 2022 source ingest | ? | files/tests | resume/build |
| PSOC 2022 adapter | ? | files/tests | resume/build |
| PSOC registry current version | ? | registry/test | correct |
| Dual search service | ? | files/tests | resume/build |
| Dual search UI hooks | ? | files/UAT | resume/build |
| PSIC correspondence source audit | ? | doc/source | resume |
| Correspondence schema | ? | files/tests | resume/build |
| Correspondence artifact | ? | artifact/tests | resume/build |
| Correspondence UI hooks | ? | files/UAT | resume/build |
| UI contract updates | ? | docs | update last |

Do not delete partial work solely because this document is newer. Reuse it if it satisfies the updated contracts and tests.

---

# 2. OFFICIAL PSOC 2022 FACTS TO PRESERVE

PSA identifies the latest PSOC version as:

> **2022 Updates to the 2012 Philippine Standard Occupational Classification (PSOC)**

Recommended display labels:

```text
2022 PSOC
```

or:

```text
2022 Updates to the 2012 PSOC
```

Internal version identifier:

```text
2022
```

Archived predecessor:

```text
2012
```

## 2.1 Official structure

PSA technical notes state that the 2022 PSOC contains four levels:

```text
10 major groups       — 1-digit
43 sub-major groups   — 2-digit
130 minor groups      — 3-digit
456 unit groups       — 4-digit
```

These are validation targets.

Do not fabricate or remove records simply to force a count if the selected source representation yields a discrepancy. Investigate and document discrepancies.

## 2.2 Official change example

PSA documents that Unit Group:

```text
2121 — Mathematicians and Actuaries
```

was split in the 2022 update into:

```text
2121 — Mathematicians
2123 — Actuaries
```

Use such documented cases as useful validation fixtures if the ingested source contains them.

## 2.3 Official sources

Primary PSA references:

```text
https://psa.gov.ph/classification/psoc
https://psa.gov.ph/classification/psoc/technical-notes
https://psa.gov.ph/issip/classification-systems/approved-standard-classification-systems/node/1684079770
https://psa.gov.ph/psa-board/resolutions/year/2022
```

During implementation, inspect the current PSA PSOC page for the best downloadable or structured official source.

---

# 3. PSOC 2022 SOURCE STRATEGY

The application already uses `phscs`, but the current implementation may expose only PSOC 2012.

Do not wait for a future package update.

Use the same architectural pattern already used for PSIC Revision 5:

```text
phscs
  └── PSOC 2012
         │
         └── archived

Official PSA 2022 PSOC source
         │
         ▼
scripts/build_psoc_2022.R
         │
         ▼
normalize + validate
         │
         ▼
data/psoc_2022.rds
data/psoc_2022_metadata.rds
         │
         ▼
adapter_psoc_2022.R
         │
         ▼
classification repository
         │
         ├── 2022 → current
         └── 2012 → archived
```

## 3.1 Source preference order

At build time, prefer:

1. official PSA downloadable structured file, if available;
2. official PSA structured classification endpoint/page suitable for deterministic extraction;
3. official PSA API only if it demonstrably exposes the 2022 PSOC;
4. another PSA-issued official artifact that can be deterministically normalized.

Do not use an unofficial third-party copy as the primary source when PSA has an official source.

## 3.2 Runtime rule

Runtime must use:

```text
data/psoc_2022.rds
```

or equivalent local normalized artifact.

The public application must not fetch PSOC 2022 from PSA on each request.

---

# 4. PSOC 2022 CANONICAL SCHEMA

PSOC 2022 must use the existing application canonical classification schema.

Minimum fields should remain consistent with the MVP:

```r
tibble(
  system       = "psoc",
  version      = "2022",
  level        = character(),
  code         = character(),
  label        = character(),
  description  = character(),
  parent_code  = character(),
  status       = "current",
  source       = "Philippine Statistics Authority",
  source_url   = character()
)
```

Do not create a PSOC-only schema that leaks into UI logic.

Canonical PSOC levels:

```text
major_group
sub_major_group
minor_group
unit_group
```

Display labels may be:

```text
Major Group
Sub-major Group
Minor Group
Unit Group
```

Preserve codes as character values.

---

# 5. REQUIRED PSOC 2022 BUILD FILES

Suggested additions:

```text
R/adapters/
  adapter_psoc_2022.R

scripts/
  build_psoc_2022.R

data/
  psoc_2022.rds
  psoc_2022_metadata.rds

data-raw/
  <official PSA source artifact if appropriate and repository-safe>

tests/testthat/
  test-psoc-2022.R
```

Update:

```text
R/registry.R
R/repository.R   # only if needed by existing extension seam
docs/DATA_SOURCES.md
README.md
IMPLEMENTATION_STATUS.md
```

Do not rewrite `adapter_phscs.R` merely to force 2022 into `phscs`.

Use a supplemental adapter consistent with the existing PSIC 2026 pattern.

---

# 6. PSOC 2022 VALIDATION

Required automated validations:

- [ ] `system == "psoc"`
- [ ] `version == "2022"`
- [ ] `status == "current"`
- [ ] code column is character
- [ ] valid canonical columns
- [ ] source is PSA
- [ ] source metadata exists
- [ ] four hierarchy levels present
- [ ] 10 major groups
- [ ] 43 sub-major groups
- [ ] 130 minor groups
- [ ] 456 unit groups
- [ ] `2121` reflects the updated mathematician concept if represented by the official source
- [ ] `2123` Actuaries is present if represented by the official source
- [ ] artifact loads without network access
- [ ] source/build metadata includes retrieval/source information

If exact counts do not match, do not force them. Diagnose source/extraction semantics and document the discrepancy.

---

# 7. REGISTRY VERSION CORRECTION

After PSOC 2022 is validated, the application registry must return:

```text
PSOC
├── 2022 — CURRENT
└── 2012 — ARCHIVED
```

Expected conceptual contract:

```r
classification_versions("psoc")
```

should identify 2022 and 2012, with 2022 current/default.

`get_classification("psoc", "2022", ...)` must use the supplemental 2022 adapter/artifact.

`get_classification("psoc", "2012", ...)` may continue to use `phscs`.

Do not silently substitute 2012 if the 2022 artifact is missing.

---

# 8. FEATURE A — PARALLEL PSOC + PSIC SEARCH

Build the dual-search feature only after the current versions are correct.

Default pairing:

```text
Occupations — PSOC
2022 PSOC
CURRENT

Industries — PSIC
PSIC Revision 5 (2026)
CURRENT
```

One search query such as:

```text
accountant
nurse
software developer
teacher
farmer
restaurant
construction worker
```

returns two independent result sets.

Semantic rule:

```text
PSOC → occupation / kind of work performed by a person
PSIC → primary economic activity / industry of an establishment or enterprise
```

Never imply PSOC and PSIC codes are equivalents.

Preferred headings:

```text
Occupations — PSOC
Industries — PSIC
```

---

# 9. DUAL SEARCH SERVICE CONTRACT

Add or complete:

```r
search_parallel_classifications <- function(
  query,
  systems = c("psoc", "psic"),
  versions = c(psoc = "2022", psic = "2026"),
  levels = NULL,
  limit_per_system = 20
)
```

Suggested return shape:

```r
list(
  query = "accountant",
  results = list(
    psoc = <canonical search tibble>,
    psic = <canonical search tibble>
  ),
  metadata = list(
    psoc_version = "2022",
    psic_version = "2026"
  )
)
```

Reuse:

```r
search_classification()
```

Do not implement a second ranking engine.

---

# 10. DUAL SEARCH VERSION SELECTORS

Conceptual UI:

```text
Search occupations and industries
[ software developer                         ]

Occupations — PSOC
Edition: [ 2022 PSOC ▼ ]

Industries — PSIC
Edition: [ Revision 5 (2026) ▼ ]
```

Archived choices may include:

```text
PSOC:
2022 — Current
2012 — Archived

PSIC:
2026 Revision 5 — Current
2019 — Archived
```

Do not hard-code display choices if the registry can supply them.

Stable conceptual states:

```text
initial
loading
results_both
results_psoc_only
results_psic_only
no_results
error_psoc
error_psic
```

A failure/no-match on one side must not suppress the other.

---

# 11. FEATURE B — PSIC 2019 ↔ REVISION 5 CORRESPONDENCE

Implement a classification correspondence layer, not a generic text-similarity convenience feature.

Possible relationships:

```text
1 → 1   unchanged
1 → 1   renamed
1 → 1   reclassified
1 → N   split
N → 1   merged
N → M   complex
0 → 1   new
1 → 0   discontinued / absorbed
```

Do not force every source code into one target code.

Preferred terminology:

```text
PSIC edition correspondence
Suggested 2026 correspondence
Previous classification
Related classification in Revision 5
```

Avoid "Equivalent code" unless supported by an official authoritative correspondence relationship.

---

# 12. SOURCE AUDIT FOR AN OFFICIAL PSA PSIC CROSSWALK

Before generating inferred mappings, check whether PSA has published an official:

```text
2019 PSIC ↔ PSIC Revision 5 correspondence / concordance / crosswalk
```

Create/update:

```text
docs/CORRESPONDENCE_SOURCES.md
```

Record:

```text
source searched
URL
retrieval/check date
whether an official crosswalk exists
scope/level of crosswalk
usable format
provenance decision
```

If an official PSA crosswalk exists, use it as primary mapping evidence and mark those mappings `official`.

If none exists, proceed with `derived` and `suggested`; do not block implementation.

---

# 13. CORRESPONDENCE PROVENANCE MODEL

Required values:

```text
official
derived
suggested
```

**official** — only a mapping explicitly published by PSA as a PSIC correspondence.

**derived** — deterministic mapping supported by authoritative revision evidence such as official UN ISIC Rev.4↔Rev.5 correspondence, compatible PSIC hierarchy, or exact code/title continuity.

**suggested** — algorithmically inferred from PSIC structures, labels, descriptions, hierarchy, or similarity.

Never promote a suggested mapping to official.

---

# 14. CORRESPONDENCE SCHEMA

Suggested normalized relationship table:

```r
tibble(
  source_system        = character(),
  source_version       = character(),
  source_code          = character(),
  source_level         = character(),
  source_label         = character(),

  target_system        = character(),
  target_version       = character(),
  target_code          = character(),
  target_level         = character(),
  target_label         = character(),

  relation_type        = character(),
  provenance           = character(),
  confidence           = character(),
  confidence_score     = double(),
  method               = character(),
  evidence             = character(),
  review_status        = character(),
  notes                = character()
)
```

`relation_type`:

```text
unchanged
renamed
split
merged
reclassified
new
discontinued
complex
possible
unknown
```

`confidence`:

```text
high
moderate
low
```

`review_status`:

```text
auto
reviewed
needs_review
```

---

# 15. CORRESPONDENCE OFFLINE ARTIFACT

Create:

```text
data/psic_2019_to_2026_correspondence.rds
```

Prefer one normalized relationship artifact queryable in both directions.

Build script:

```text
scripts/build_psic_correspondence.R
```

Runtime must not depend on PSA or UN website availability.

---

# 16. CORRESPONDENCE BUILD GRAPH

```text
2019 PSIC
    │
    ├────────────────┐
    ▼                ▼
Exact structural   authoritative
continuity         revision bridge
    │                │
    └────────┬───────┘
             ▼
      hierarchy checks
             │
             ▼
   label/description checks
             │
             ▼
       candidate scoring
             │
             ▼
 relationship cardinality
             │
             ▼
 provenance + confidence
             │
             ▼
     offline RDS artifact
```

Use exact/structural continuity first. Where appropriate, use official UN ISIC Rev.4↔Rev.5 correspondence as **derived** evidence. Because PSIC includes national adaptations, UN correspondence is not itself an official PSA PSIC crosswalk.

Algorithmic suggestions should be deterministic first: normalized token/string similarity plus hierarchy restrictions. Do not use a generative LLM as the authoritative mapping engine.

---

# 17. SCORING

Make scoring explicit, centralized, and testable.

Illustrative starting framework only:

```text
same exact code                     +40
authoritative ISIC bridge            +30
near-identical title                 +15
compatible hierarchy                 +10
description similarity                +5
```

These are not statistically calibrated probabilities.

Public UI should use:

```text
High
Moderate
Low
```

Do not display probability percentages unless actually calibrated.

---

# 18. BIDIRECTIONAL SERVICE

Required:

```r
get_psic_correspondence(
  code,
  from_version = "2019",
  to_version = "2026"
)
```

and:

```r
get_psic_correspondence(
  code,
  from_version = "2026",
  to_version = "2019"
)
```

Also useful:

```r
search_psic_correspondence(
  query,
  from_version,
  to_version,
  limit = 20
)
```

Return source entry + target relationship rows + warnings, not a single target code string.

---

# 19. STATISTICAL SAFETY RULE

Classification correspondence is **not statistical redistribution**.

If:

```text
2019 code A = 10,000 establishments
```

and:

```text
A → B
A → C
A → D
```

the app must not allocate 10,000 among B/C/D.

Required public warning for split/complex cases:

> Classification correspondence identifies related categories across editions. It does not provide a basis for automatically reallocating historical statistical values among revised categories.

---

# 20. CORRESPONDENCE UI CONTRACT

Minimal one-to-one state:

```text
Compare PSIC editions

From: 2019 PSIC
To:   PSIC Revision 5 (2026)

2019
[code]
[label]

          ↓

2026
[code]
[label]

Relationship: Likely unchanged
Provenance: Derived
Confidence: High

Evidence:
- ...
```

Split state:

```text
2019 [source]

Relationship: Split

        ↙                ↘

2026 candidate A    2026 candidate B
High                Moderate
```

The UI contract must support:

```text
one-to-one
split
merged
complex
no match
low confidence
official
derived
suggested
reverse lookup
```

---

# 21. UPDATED DEPENDENCY DAG

```text
                      RECOVERY / AUDIT
                            │
                            ▼
                  A. Reconfirm MVP tests
                            │
          ┌─────────────────┴──────────────────┐
          ▼                                    ▼
 B. PSOC 2022 source audit           C. PSIC crosswalk source audit
          │                                    │
          ▼                                    ▼
 D. PSOC 2022 build pipeline         E. Correspondence schema/evidence
          │                                    │
          ▼                                    ▼
 F. PSOC 2022 adapter/tests          G. Correspondence build/tests
          │                                    │
          ▼                                    │
 H. Registry: 2022 current                     │
          │                                    │
          └──────────────┐                     │
                         ▼                     │
                  I. Dual search service        │
                         │                     │
                         └──────────┬──────────┘
                                    ▼
                           J. Service integration
                                    │
                       ┌────────────┴────────────┐
                       ▼                         ▼
                K. Minimal Shiny UI        L. Tests/UAT
                       │                         │
                       └────────────┬────────────┘
                                    ▼
                         M. UI contract/docs
                                    │
                                    ▼
                              CLAUDE DESIGN
```

---

# 22. PARALLEL WORKSTREAMS

Once recovery audit confirms state, parallelize where possible.

## PSOC 2022 workstream

Own:

```text
scripts/build_psoc_2022.R
R/adapters/adapter_psoc_2022.R
data/psoc_2022*.rds
tests/testthat/test-psoc-2022.R
```

## PSIC correspondence workstream

Own:

```text
docs/CORRESPONDENCE_SOURCES.md
R/correspondence/
scripts/build_psic_correspondence.R
data/psic_2019_to_2026_correspondence.rds
tests/testthat/test-correspondence-*.R
```

## Dual-search workstream

Own:

```text
R/parallel_search.R
tests/testthat/test-parallel-search.R
```

Final dual-search validation waits until PSOC 2022 registry integration is available.

---

# 23. LOOP ENGINEERING

For every workstream:

```text
INSPECT CURRENT STATE
        ↓
REUSE VALID PARTIAL WORK
        ↓
IMPLEMENT SMALLEST MISSING CHANGE
        ↓
TARGETED TEST
        ↓
PASS?
├── yes → freeze workstream
└── no
     ↓
  diagnose
     ↓
  narrow patch
     ↓
  retest
```

Rules:

1. Do not restart a workstream merely because the previous Claude session ended.
2. Maximum three repeated repair loops for the same acceptance failure before recording/escalating.
3. Do not refactor unrelated MVP code.
4. Tests serve as persistent behavioral memory.
5. Freeze passing public contracts unless integration proves them defective.
6. Do not beautify UI during backend work.

---

# 24. TOKEN-EFFICIENCY RULES

Because the previous session ended on a usage limit:

- do not reread the entire repository;
- inspect Git diff/status first;
- read the smallest relevant files;
- use targeted code search;
- use existing tests instead of reconstructing behavior verbally;
- assign non-overlapping files to parallel subagents;
- consume subagent summaries before reviewing full diffs;
- do not ask two subagents to solve the same workstream;
- stop modifying a workstream after acceptance tests pass.

Each workstream summary:

```text
status
files changed
tests run
results
contract added/changed
remaining risk
```

---

# 25. TEST PLAN — PSOC 2022

- [ ] official/source metadata documented
- [ ] local `psoc_2022.rds` generated
- [ ] artifact loads offline
- [ ] canonical schema valid
- [ ] codes are strings
- [ ] 10 major groups
- [ ] 43 sub-major groups
- [ ] 130 minor groups
- [ ] 456 unit groups
- [ ] registry identifies 2022 current
- [ ] registry identifies 2012 archived
- [ ] current/default PSOC resolves to 2022
- [ ] explicit PSOC 2012 still works
- [ ] missing 2022 artifact does not silently masquerade as 2022

---

# 26. TEST PLAN — DUAL SEARCH

- [ ] default PSOC version is 2022
- [ ] default PSIC version is 2026
- [ ] one query produces independent PSOC and PSIC sets
- [ ] existing canonical ranking reused
- [ ] exact-code ranking unaffected
- [ ] label ranking unaffected
- [ ] PSOC no-result does not suppress PSIC
- [ ] PSIC no-result does not suppress PSOC
- [ ] version metadata retained
- [ ] archived editions can be explicitly selected if exposed
- [ ] PSOC/PSIC semantic distinction present in UI
- [ ] code string behavior preserved

---

# 27. TEST PLAN — PSIC CORRESPONDENCE

- [ ] source audit documented
- [ ] offline correspondence artifact exists
- [ ] source/target codes strings
- [ ] provenance required
- [ ] relation type validated
- [ ] confidence validated
- [ ] one-to-one lookup works
- [ ] one-to-many split works
- [ ] many-to-one merge works if evidence exists
- [ ] reverse 2026→2019 lookup works
- [ ] algorithmic mapping can never be `official`
- [ ] no-match safe state
- [ ] low-confidence safe state
- [ ] statistical redistribution is never performed

---

# 28. FULL REGRESSION GATE

At the end:

```bash
Rscript scripts/run_tests.R
```

All previously passing MVP tests must remain passing unless a test intentionally asserted the now-obsolete fact that PSOC 2012 was current.

If such a test changes:

1. document why;
2. replace the obsolete expectation with:
   ```text
   PSOC 2022 current
   PSOC 2012 archived
   ```
3. do not weaken unrelated assertions.

Report:

```text
old baseline test count
new total test count
passes
failures
skips
manual browser UAT
```

---

# 29. UAT — PSOC VERSION

1. Open standard classification search.
2. Select PSOC.
3. Confirm default/current version displays `2022`.
4. Search a known 2022 occupation.
5. Confirm result source/version.
6. Switch to PSOC 2012.
7. Confirm it is clearly archived.
8. Use the Mathematicians/Actuaries split as a useful validation case where applicable.

---

# 30. UAT — DUAL SEARCH

1. Search `accountant`.
2. Confirm PSOC panel uses 2022.
3. Confirm PSIC panel uses Revision 5 (2026).
4. Confirm the interface does not imply equivalence.
5. Search `software developer`.
6. Check both sides independently.
7. Trigger a one-sided no-result state.
8. Verify the other side remains usable.

---

# 31. UAT — PSIC CORRESPONDENCE

1. Test an unchanged/high-confidence case.
2. Test a split case.
3. Test reverse lookup.
4. Confirm provenance appears.
5. Confirm derived/suggested is not presented as official.
6. Confirm no-match state.
7. Confirm low-confidence state.
8. Confirm split warning prohibits statistical value redistribution.

---

# 32. MINIMAL SHINY UI ONLY

Add/retain functional navigation for:

```text
Search
Dual Search
Compare PSIC Editions
Browse / Archive
About / Sources
```

Exact navigation may follow the existing MVP structure.

Do not perform final aesthetic design.

Use neutral `bslib` structures sufficient for functionality testing, mobile/desktop state testing, accessibility semantics, and Claude Design handoff.

---

# 33. UI CONTRACT UPDATE

Before returning to Claude Design, update:

```text
docs/UI_CONTRACT.md
```

It must define:

## PSOC version states

```text
2022 current
2012 archived
```

## Dual-search contract

- stable input/output IDs;
- PSOC version selector;
- PSIC version selector;
- independent result sets;
- partial/no-result/error states;
- semantic labels Occupation vs Industry.

## Correspondence contract

- source classification entry;
- target candidates;
- relation type;
- cardinality;
- provenance;
- confidence;
- evidence;
- warnings;
- reverse direction;
- no-match;
- split;
- merge;
- complex.

Claude Design must not have to invent statistical semantics.

---

# 34. DOCUMENTATION UPDATES

Update:

```text
README.md
IMPLEMENTATION_STATUS.md
docs/UI_CONTRACT.md
docs/DATA_SOURCES.md
docs/CORRESPONDENCE_SOURCES.md
```

`IMPLEMENTATION_STATUS.md` should include:

```text
## Recovery from interrupted session
## PSOC 2022 status
## PSOC 2012 archive status
## Dual search status
## PSIC correspondence status
## Data source/provenance status
## Tests
## Manual UAT
## Known limitations
## Claude Design readiness
```

---

# 35. OPTIONAL FUTURE FEATURE — PSOC 2012 ↔ 2022 CORRESPONDENCE

Do not allow this to block the current implementation.

Preserve architecture that could later support:

```text
PSOC 2012 ↔ 2022
```

This is relevant because the 2022 PSOC is explicitly an update to the 2012 classification and PSA documents structural changes such as splits/new unit groups.

Record it as deferred unless all P0 work is complete and an authoritative correspondence source is available.

---

# 36. CLAUDE CODE RESUME PROMPT

Paste this to Claude Code after placing this file in the project folder:

> Resume the interrupted implementation of the PSA Statistical Classifications Search project.
>
> The previous Claude Code session ended because the usage limit was reached. Do not assume the previous feature implementation either completed or failed entirely.
>
> Read, in order:
>
> 1. `CLAUDE.md`
> 2. `IMPLEMENTATION_STATUS.md`
> 3. `docs/UI_CONTRACT.md`
> 4. `PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md`
>
> This specification supersedes the prior dual-search/PSIC-correspondence spec where they conflict.
>
> **First recover state rather than coding immediately:**
>
> - inspect `git status`, current branch, recent commits and diffs;
> - find any partially implemented PSOC 2022, dual-search, or correspondence files;
> - run the existing tests;
> - classify each workstream as COMPLETE, PARTIAL, NOT STARTED, or BROKEN;
> - reuse valid partial work.
>
> Then implement the missing work using the dependency graph in the specification.
>
> The first functional correction is that **PSOC 2022 must be the current/default PSOC**. PSOC 2012 remains archived. Use an official PSA source and a local normalized runtime artifact, following the established PSIC Revision 5 supplemental-source pattern.
>
> After PSOC 2022 is validated and registered, complete the dual PSOC/PSIC search with defaults:
>
> - PSOC 2022
> - PSIC Revision 5 (2026)
>
> The two panels are parallel occupation/industry searches, not equivalent-code mappings.
>
> Complete the PSIC 2019↔2026 correspondence layer with explicit provenance (`official`, `derived`, `suggested`) and cardinality-aware mappings. Check for an official PSA crosswalk before generating derived/suggested relationships.
>
> Do not perform the final visual redesign. Implement only enough neutral Shiny UI to test all new states, then update `docs/UI_CONTRACT.md` for Claude Design.
>
> Use parallel workstreams where file ownership does not overlap. Use bounded repair loops and avoid rereading/refactoring unrelated working code.
>
> Before completion:
>
> 1. run targeted tests for each workstream;
> 2. run `Rscript scripts/run_tests.R`;
> 3. manually verify PSOC 2022, dual search, and correspondence states in the browser;
> 4. update `IMPLEMENTATION_STATUS.md`;
> 5. report the final test count, files changed, source/provenance findings, known limitations, and Claude Design readiness.
>
> Do not stop merely to propose architecture unless a genuine blocker contradicts this approved specification.

---

# 37. CLAUDE DESIGN HANDOFF PROMPT

After Claude Code completes and all functional tests pass, return to Claude Design and use:

> The functional application has been extended since the previous design context.
>
> Read the latest:
>
> - `docs/UI_CONTRACT.md`
> - `IMPLEMENTATION_STATUS.md`
> - `docs/DATA_SOURCES.md`
> - `docs/CORRESPONDENCE_SOURCES.md`
>
> Important functional changes:
>
> 1. **PSOC 2022 is now the current/default occupation classification.**
> 2. **PSOC 2012 remains available as an archived reference.**
> 3. A single query can search **PSOC 2022 occupations and PSIC Revision 5 (2026) industries in parallel**.
> 4. The app now supports **bidirectional PSIC 2019 ↔ 2026 correspondence**, including one-to-one, split, merge/complex, no-match, confidence, and provenance states.
>
> Update the visual design around the new stable contracts without changing their statistical semantics.
>
> For dual search:
>
> - desktop may show occupations and industries side by side;
> - mobile should use a clean tabbed/stacked treatment;
> - make the occupation-vs-industry distinction unmistakable;
> - never visually imply that PSOC and PSIC codes are equivalents.
>
> For PSIC correspondence, design for one-to-one, split, merged, complex, no match, high/moderate/low confidence, official/derived/suggested provenance, and reverse 2026→2019 lookup.
>
> Do not rely on color alone to communicate provenance or confidence.
>
> Preserve all stable IDs and backend result/service contracts defined in `docs/UI_CONTRACT.md`.
>
> Do not rewrite the backend architecture.

---

# 38. DEFINITION OF DONE

## PSOC

- PSOC 2022 local artifact exists;
- 2022 source is PSA and documented;
- official level counts validate or any discrepancy is explicitly documented;
- PSOC 2022 is current/default;
- PSOC 2012 remains archived and searchable;
- runtime is offline-capable.

## Dual search

- one query searches PSOC and PSIC independently;
- defaults are PSOC 2022 and PSIC 2026;
- canonical ranking is reused;
- partial/no-result states work;
- occupation and industry semantics are distinct.

## PSIC correspondence

- bidirectional 2019↔2026 lookup works;
- cardinality is preserved;
- provenance is mandatory;
- non-official mappings are never called official;
- correspondence works offline;
- statistical values are never automatically redistributed.

## Quality

- all valid MVP regressions remain passing;
- new tests pass;
- manual browser UAT is documented;
- UI contract is updated;
- implementation status is accurate;
- repository is ready to return to Claude Design.

---

# 39. PRIMARY SOURCE REFERENCES

## PSOC 2022

PSA PSOC page:

```text
https://psa.gov.ph/classification/psoc
```

PSA PSOC technical notes:

```text
https://psa.gov.ph/classification/psoc/technical-notes
```

PSA Inventory of Statistical Standards — latest version 2022 PSOC:

```text
https://psa.gov.ph/issip/classification-systems/approved-standard-classification-systems/node/1684079770
```

PSA Board Resolutions 2022:

```text
https://psa.gov.ph/psa-board/resolutions/year/2022
```

## PSIC

```text
https://psa.gov.ph/classification/psic
```

## Software interfaces

`phscs`:

```text
https://yng-me.github.io/phscs/
```

`psgc`:

```text
https://yng-me.github.io/psgc/
```

Always treat PSA as the issuing authority. `phscs` and `psgc` are software/data-access mechanisms.

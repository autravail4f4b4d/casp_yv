# Implementation Status — PSA Statistical Classifications Search

This document now covers **two milestones**:

1. The original functionality-first MVP (`PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`)
   — complete, preserved as the known-good baseline. See git commit
   `8269eb3` ("feat: complete functional PSA classifications MVP").
2. The current post-MVP functional extension
   (`PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md`) — the
   subject of this update: PSOC 2022, parallel PSOC/PSIC search, and PSIC
   2019↔Revision 5 correspondence.

## Recovery from interrupted session

The prior Claude Code session for this milestone was interrupted by a
usage limit after producing only documentation: commit `2202a66` ("docs:
define PSOC 2022 and classification extension") added the extension spec
and updated `CLAUDE.md`, but **no implementation code, adapters, tests, or
UI for PSOC 2022, dual search, or PSIC correspondence existed yet**.

Recovery audit performed at the start of this session:
- `git status` — clean working tree, nothing uncommitted.
- `git log --oneline -30` — exactly two commits (`8269eb3` MVP, `2202a66`
  docs-only).
- Targeted grep across the whole repository for
  `psoc_2022|parallel_search|psic_correspondence|CORRESPONDENCE_SOURCES|adapter_psoc_2022|build_psoc_2022|build_psic_correspondence`
  — zero hits outside the spec file itself.
- Full MVP test suite run before any changes: **302/302 passing**,
  confirming the baseline exactly matched the previous session's own
  `IMPLEMENTATION_STATUS.md` claim.

Recovery matrix (final classification):

| Workstream | State at recovery | Action taken |
|---|---|---|
| Existing MVP regression suite | COMPLETE | Re-verified, preserved |
| PSOC 2022 source ingest | NOT STARTED | Built |
| PSOC 2022 adapter | NOT STARTED | Built |
| PSOC registry current version | NOT STARTED | Corrected |
| Dual search service | NOT STARTED | Built |
| Dual search UI hooks | NOT STARTED | Built |
| PSIC correspondence source audit | NOT STARTED | Performed, documented |
| Correspondence schema | NOT STARTED | Built |
| Correspondence artifact | NOT STARTED | Built |
| Correspondence UI hooks | NOT STARTED | Built |
| UI contract updates | NOT STARTED | Updated |

No partial work was discarded — there was none to discard beyond the
already-complete MVP baseline, which was reused as-is.

## PSOC 2022 status

**Current and default.** Source: PSA's official **"2022 Updates to the
2012 PSOC"** workbook (`https://psa.gov.ph/classification/psoc`). PSA's
file host for this specific workbook sits behind a Cloudflare JavaScript
challenge that blocked automated retrieval (`curl`/`httr2` both received
HTTP 403 with `Cf-Mitigated: challenge`); the user manually downloaded the
same official file and supplied it at
`data-raw/2022-Updates-to-the-2012-PSOC.xlsx`. This is recorded honestly
in `docs/DATA_SOURCES.md` and in `data/psoc_2022_metadata.rds$retrieval_method`
— the source is still official PSA data, only the retrieval mechanism
differs from the PSIC Revision 5 precedent (which downloads directly).

Validated structural counts (`scripts/build_psoc_2022.R`, referential
integrity of every parent_code chain hard-enforced as a build failure
condition):

| Level | PSA stated | Parsed |
|---|---|---|
| Major groups | 10 | **10** ✓ |
| Sub-major groups | 43 | **43** ✓ |
| Minor groups | 130 | **130** ✓ |
| Unit groups | 456 | **466** (documented discrepancy — no duplicate/malformed codes found; see `docs/DATA_SOURCES.md`) |

PSA's own documented validation fixture — Unit Group `2121` ("Mathematicians
and Actuaries" in 2012) splitting into `2121` ("Mathematicians") and `2123`
("Actuaries") in 2022 — is confirmed present with the correct shared parent.

Runtime artifact: `data/psoc_2022.rds` (649 canonical rows) +
`data/psoc_2022_metadata.rds`, read offline by
`R/adapters/adapter_psoc_2022.R`. Missing-artifact error:
`"PSOC 2022 runtime artifact is missing. Run scripts/build_psoc_2022.R and redeploy."`
— never silently substitutes 2012 data while claiming to show 2022.

## PSOC 2012 archive status

**Retained, fully queryable, correctly marked archived.** The phscs-sourced
2012 edition's `status` was corrected from `"current"` to `"archived"` in
`R/adapters/adapter_phscs.R` (a deliberate, spec-mandated correction — PSA
no longer treats 2012 as current now that the 2022 update exists). Its
level vocabulary was also renamed from `major`/`sub-major`/`minor`/`unit`
to the canonical `major_group`/`sub_major_group`/`minor_group`/`unit_group`
form so switching between 2012 and 2022 in the UI never leaves a stale,
incompatible level selected. Both changes are covered by updated/added
tests in `tests/testthat/test-adapters.R`.

## Dual search status

**Complete and default-correct.** `search_parallel_classifications()`
(`R/parallel_search.R`) defaults to PSOC 2022 + PSIC Revision 5 (2026),
reuses `search_classification()` verbatim (no second ranking engine),
isolates each system's search in its own `tryCatch` so a failure or
no-match on one side never suppresses the other, and is exposed through a
new "Dual Search" nav panel with independent PSOC ("Occupations") and PSIC
("Industries") result panels, each with their own edition selector.
Manually verified live (see Manual UAT below).

## PSIC correspondence status

**Complete.** Source audit (`docs/CORRESPONDENCE_SOURCES.md`) confirmed no
official PSA PSIC 2019↔Revision 5 crosswalk exists yet (expected — Revision
5 was released only 18 days before this audit). A genuine official **UN
Statistics Division ISIC Rev.4↔Rev.5 correspondence table** was found and
downloaded (`data-raw/ISIC4-5_Correspondence_Table.xlsx`, 603 rows) and
used as **derived** (not official — PSIC has national adaptations UN
evidence doesn't capture) corroborating evidence, gated behind a
conformance check since PSIC doesn't always preserve ISIC's own code
numbering.

Built artifact `data/psic_2019_to_2026_correspondence.rds` — **2,699 rows**,
exhaustive over all 1,360 PSIC 2019 sub-class codes:

| Relation type | Count | | Provenance | Count | | Confidence | Count |
|---|---|---|---|---|---|---|---|
| unchanged | 741 | | derived | 2,510 | | high | 1,985 |
| renamed | 768 | | suggested | 189 | | moderate | 605 |
| split | 507 | | **official** | **0** | | low | 109 |
| merged | 100 | | | | | | |
| complex | 59 | | | | | | |
| possible | 130 | | | | | | |
| discontinued | 143 | | | | | | |
| new | 251 | | | | | | |

`official` provenance is enforced as a hard test guard
(`!("official" %in% correspondence$provenance)`), not just a claim.
Bidirectional lookup (`get_psic_correspondence()`,
`search_psic_correspondence()`) confirmed working both directions live in
the browser, including a real split case (`01179` → `01171`/`01172`) with
the mandated statistical-safety warning rendered inline.

## Data source/provenance status

| Artifact | Source | Retrieval | Provenance recorded in |
|---|---|---|---|
| `data/psic_2026.rds` | PSA official workbook | Automated (direct URL) | `docs/DATA_SOURCES.md`, `data/psic_2026_metadata.rds` |
| `data/psoc_2022.rds` | PSA official workbook | **Manual** (Cloudflare-blocked automation) | `docs/DATA_SOURCES.md`, `data/psoc_2022_metadata.rds` |
| `data/psic_2019_to_2026_correspondence.rds` | Derived from PSIC 2019 (phscs) + PSIC 2026 (local artifact), corroborated by UN ISIC Rev.4↔Rev.5 table | Automated (UN source) + deterministic build-time computation | `docs/CORRESPONDENCE_SOURCES.md`, `data/psic_2019_to_2026_correspondence_metadata.rds` |

All three are read-only at runtime — no network calls anywhere in the
request path for any of them.

## Tests

`Rscript scripts/run_tests.R`:

- **Before this milestone (baseline, re-verified at recovery):** 302/302 passing
- **After this milestone: 485/485 passing, 0 failed, 0 warnings, 0 skipped**
  (+183 new tests, 0 regressions)

| New/changed test file | Covers |
|---|---|
| `test-psoc-2022.R` | Artifact existence/offline load, canonical schema, all 4 levels, structural counts (with honest documented discrepancy), referential integrity, the Mathematicians/Actuaries fixture, level filtering, unsupported-level/missing-artifact errors, registry current/archived resolution, no silent 2012-for-2022 substitution, live search |
| `test-adapters.R` (modified) | PSOC level vocabulary renamed to canonical form; new "psoc 2012 is archived" assertion |
| `test-parallel-search.R` | Defaults, independent result sets, verbatim reuse of `search_classification()` (equality-asserted, not just spot-checked), one-sided no-result/error isolation, archived-edition selection, per-system level filtering, per-system limits, leading-zero preservation, semantic labels |
| `test-correspondence-schema.R`, `test-correspondence-build.R`, `test-correspondence-service.R` | Schema validation, source-audit doc presence, offline artifact load, character-typed codes, provenance/relation_type/confidence enums (including the `official` guard), real unchanged/split cases, reverse lookup, no-match safety, label search, absence of any numeric value/count/allocation column anywhere in the schema |

## Manual UAT

Performed live in a running Shiny session (`shiny::runApp('app.R')` under
the renv-activated environment), verified via the browser automation
tooling's DOM/network inspection rather than screenshots:

- **PSOC version (spec section 29):** selecting PSOC shows edition "2022"
  with all rows `status = current`; switching to "2012" shows all rows
  `status = archived`; level names consistent across both editions.
- **Dual search (spec section 30):** query "accountant" → PSOC panel shows
  exactly `2411 ACCOUNTANTS`, PSIC panel shows "No results." independently
  (proves one-sided no-match doesn't suppress the other); defaults
  confirmed as PSOC "2022" / PSIC "2026" in the UI on load.
- **PSIC correspondence (spec section 31):** browsed 2019→2026 (high-
  confidence "renamed" rows shown correctly); searched a known split source
  (`01179`) and confirmed both target candidates (`01171`, `01172`) render
  with the statistical-safety warning inline; switched direction to
  2026→2019 and confirmed reverse lookup returns the same relationship
  from the other side.

One real bug was found and fixed during this manual testing (see Known
limitations).

## Known limitations

- **A genuine reactive-race bug was found and fixed**: the Search screen's
  level-choice observer could receive a transiently mismatched
  system/version pair (e.g. version `"2022"` arriving while
  `classification_system` still read `"psgc"`) during rapid input
  changes, calling `classification_levels()` with an invalid combination
  and crashing that observer uncaught. Fixed with a defensive guard in
  `app.R` that silently skips the stale combination (the system-change
  observer's own update shortly settles it correctly).
- **A DT-widget-in-hidden-tab rendering bug was found and fixed**: Shiny's
  implicit suspend-when-hidden/resume-on-tab-shown behavior proved
  unreliable in this app for outputs outside the default "Search" tab —
  sometimes never triggering a first render, and for `DT::renderDT`
  outputs specifically, sometimes freezing the widget at a broken
  zero-width layout if it was ever built while its container was hidden.
  Fixed by giving `page_navbar` a real `id = "main_nav"` and explicitly
  gating every secondary-tab output on `req(input$main_nav == "<value>")`
  combined with `outputOptions(suspendWhenHidden = FALSE)` — see the
  detailed note in `docs/UI_CONTRACT.md` section 4. This pattern should be
  followed for any future new tab's outputs.
- **PSOC 2022's unit-group count (466) doesn't match PSA's technical-notes
  figure (456)** — same class of discrepancy as PSIC Revision 5's groups
  count (261 vs. 260, from the original MVP). Investigated (no duplicate
  or malformed codes, full referential integrity holds); recorded as
  honestly unexplained in `docs/DATA_SOURCES.md`, not forced to match.
- **No official PSA PSIC 2019↔Revision 5 crosswalk exists** as of this
  build (confirmed by source audit, not assumed) — every correspondence
  row is `derived` or `suggested`. If PSA publishes one later, only rows
  matching that document's explicit mappings may be relabeled `official`;
  see `docs/CORRESPONDENCE_SOURCES.md`'s reconciliation note.
- **Correspondence coverage above the sub-class level is limited to clean
  exact-code matches** (no split/merge/discontinued/new bookkeeping for
  section/division/group/class) — an explicit, documented scope limit
  since the spec's exhaustiveness requirement is stated only for
  sub-class.
- **PSOC 2012 ↔ 2022 correspondence** (spec section 35) is explicitly
  deferred, as directed by the spec ("Do not allow this to block the
  current implementation... Record it as deferred").
- All MVP-era known limitations (documented in prior versions of this
  file, now superseded by this rewrite) remain: no formal WCAG audit, no
  fuzzy search, `retrieved_at` in phscs/psgc metadata is build-date rather
  than each package's own data vintage, a handful of pcoicop/pcpc rows use
  a documented honest label fallback, and PSIC 2019 division→section
  `parent_code` is `NA` (section codes are letters, not derivable by
  truncation).

## Deferred V2 Features

Unchanged from the MVP baseline, per spec section 26 of the original
build spec — see `docs/UI_CONTRACT.md` and the git history of this file
for the full list (cross-system simultaneous search, fuzzy search,
saved/favorite codes, formal WCAG audit, final visual branding, etc.).
Additionally, per this milestone's own spec section 35: **PSOC 2012 ↔ 2022
correspondence** is deferred pending a future authoritative source.

## Deployment Status

Unchanged from the MVP baseline: **not deployed to a public host** (no
Posit Connect Cloud or equivalent credentials available in this
environment). `renv.lock` remains the reproducible dependency record; no
new dependencies were added for this milestone (correspondence scoring
uses a hand-rolled token-similarity function rather than adding a
`stringdist`-style package, per the project's smallest-dependency-surface
preference).

## Claude Design Handoff Readiness

**Ready.** Everything Claude Design needs to change for the three new
screens (Dual Search, Compare PSIC Editions, plus the unchanged Search/
About screens) lives in `app.R` and `R/ui/*.R`; nothing about the visual
pass requires touching `R/adapters/`, `R/repository.R`, `R/search.R`,
`R/parallel_search.R`, `R/correspondence/`, `R/registry.R`, any
`scripts/build_*.R`, `data/`, or any test. Full stable-ID/component/state
inventory — including the new PSOC version states, dual-search contract,
and correspondence contract — is in `docs/UI_CONTRACT.md` sections 3, 4,
8, 13, 14, and 15. The `input$main_nav` gate pattern (section 4) is
explicitly documented so a future tab addition doesn't repeat the same
rendering bug found and fixed in this milestone.

## Files Changed (this milestone)

New files:
```
R/adapters/adapter_psoc_2022.R
R/correspondence/schema.R
R/correspondence/scoring.R
R/correspondence/isic_bridge.R
R/correspondence/service.R
R/parallel_search.R
R/ui/ui_dual_search.R
R/ui/ui_correspondence.R
scripts/build_psoc_2022.R
scripts/build_psic_correspondence.R
data/psoc_2022.rds
data/psoc_2022_metadata.rds
data/psic_2019_to_2026_correspondence.rds
data/psic_2019_to_2026_correspondence_metadata.rds
data-raw/2022-Updates-to-the-2012-PSOC.xlsx
data-raw/ISIC4-5_Correspondence_Table.xlsx
docs/CORRESPONDENCE_SOURCES.md
tests/testthat/test-psoc-2022.R
tests/testthat/test-parallel-search.R
tests/testthat/test-correspondence-schema.R
tests/testthat/test-correspondence-build.R
tests/testthat/test-correspondence-service.R
```

Modified files:
```
R/registry.R          -- PSOC 2022/2012 version+level+current-version wiring
R/repository.R        -- dispatch to adapter_psoc_2022 for system="psoc", version="2022"
R/adapters/adapter_phscs.R  -- psoc 2012 status corrected to archived; level names renamed to canonical form
app.R                  -- Dual Search + Compare PSIC Editions nav panels and server logic; page_navbar id="main_nav"; defensive version/system race guard
tests/testthat/test-adapters.R  -- updated for renamed psoc levels + archived status
docs/UI_CONTRACT.md    -- new stable IDs, PSOC version states, dual-search contract, correspondence contract, states table, main_nav gate pattern documented
docs/DATA_SOURCES.md   -- new PSOC 2022 provenance section
README.md              -- updated feature summary and rebuild commands
```

No MVP files were destructively rewritten — every change above is either
a new file or a narrow, targeted edit to an existing one, with the
specific reason documented inline at each edit site.

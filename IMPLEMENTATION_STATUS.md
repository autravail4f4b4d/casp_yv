# Implementation Status — PSA Statistical Classifications Search

Build performed per `PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md` and
`CLAUDE.md` using graph/loop engineering: a foundation phase (canonical
schema + contract discovery), three parallel background workstreams
(adapters+registry, PSIC Revision 5 ingestion, search engine), a
convergence/integration phase (`R/repository.R`), a minimal Shiny UI built
and verified live in a browser, dependency pinning via `renv`, and this
documentation pass.

## Completed

- **Canonical schema** (`R/schema.R`): `new_classification_tibble()` /
  `validate_classification_tibble()`, enforcing all-character columns
  (leading zeros preserved), required non-NA fields, and
  `status ∈ {"current","archived"}`.
- **Registry** (`R/registry.R`): `classification_registry()` introspects
  all 7 systems (psgc, psic, psoc, psced, pcoicop, pcpc, psccs) dynamically
  from the adapters — no hardcoded second copy of version/level data.
- **phscs adapter** (`R/adapters/adapter_phscs.R`): psic (2019, archived),
  psoc (2012), psced (2017), pcoicop (2020 current / 2009 archived), pcpc
  (2002), psccs (2018). Levels queried via each system's own documented
  level vocabulary (never inferred from code shape). `parent_code` derived
  by a generic, per-dataset-verified truncation search; left `NA` (never
  fabricated) wherever a parent can't be verified against real data —
  notably psic division→section (section codes are letters, not derivable
  by truncation).
- **psgc adapter** (`R/adapters/adapter_psgc.R`): all releases from
  `psgc::list_releases()`; `parent_code` derived by a generic
  trailing-zero-group scan validated against the real barangay→municipality
  →province→region chain and against an NCR city with no province segment.
- **PSIC Revision 5 ingestion** (`scripts/build_psic_2026.R` +
  `R/adapters/adapter_psic_2026.R`): parses PSA's official detailed-
  structure workbook (downloaded from the official URL, committed at
  `data-raw/`), builds `data/psic_2026.rds` + `data/psic_2026_metadata.rds`
  (source URL, retrieval date, SHA-256, validated counts). Full details in
  `docs/DATA_SOURCES.md`.
- **Search/ranking engine** (`R/search.R`): `search_classification_data()`
  — deterministic 6-tier ranking (exact code → code prefix → exact label →
  label prefix → label contains → description contains), literal (never
  regex) matching, whitespace normalization, blank-query browse mode,
  never errors on no-match, never coerces codes to numbers.
- **Service integration** (`R/repository.R`): the exact public contract
  from spec section 1.1 — `classification_versions()`,
  `classification_levels()`, `get_classification()`,
  `search_classification()`, `get_classification_entry()`,
  `classification_metadata()` — dispatching to the correct adapter per
  system/version (including the psic 2019-vs-2026 split), with clear
  validation errors listing available systems/versions/levels.
- **Minimal Shiny UI** (`app.R`, `R/ui/ui_search.R`, `R/ui/ui_details.R`,
  `R/ui/ui_sources.R`, `www/app.css`): system/edition/level selectors,
  debounced search box, results table (DT), row-click detail card with a
  current/archived badge, and an About/Data Sources tab. Verified live in
  a browser (see below) — one real bug found and fixed during that
  verification (see Known Limitations).
- **Dependency pinning**: `renv` initialized and snapshotted
  (`renv.lock`, `.Rprofile`); verified the full test suite and a fresh
  `Rscript` app launch both work under the renv-activated environment.
- **Docs**: `docs/UI_CONTRACT.md`, `docs/DATA_SOURCES.md`,
  `docs/DEPLOYMENT.md`, `README.md`, this file.

## Tests Passed

`Rscript scripts/run_tests.R` → **302 / 302 passing, 0 failed, 0 warnings,
0 skipped**, across:

| File | Covers |
|---|---|
| `test-schema.R` | Canonical tibble construction/validation |
| `test-registry.R` | Registry completeness and consistency |
| `test-adapters.R` | phscs/psgc canonical output, parent_code correctness, leading-zero preservation, current/archived status |
| `test-psic-2026.R` | PSIC 2026 artifact structure, counts, known-row spot checks, missing-artifact error |
| `test-search.R` | Full ranking algorithm on synthetic fixtures (all 6 tiers, case/whitespace, literal-char matching, level filter, limit, blank/no-match) |
| `test-repository.R` | End-to-end integration over **real** data for every registered system/version, plus the spec's UAT scenarios (exact/text search for PSIC/PSOC/PSGC, old-release search, level filter, literal-dot PCOICOP search, leading zeros, validation errors, edition-switch isolation) |

### UAT scenarios (spec section 15/16) — status

| # | Case | Evidence |
|---|---|---|
| 1 | Exact PSIC Revision 5 code | `test-repository.R` (code `"01111"`) |
| 2 | PSIC Revision 5 text search | Manual browser verification (query "software" against PSIC) + `test-search.R` tier logic |
| 3 | PSIC 2019 archived search | `test-repository.R` + manual browser verification (all rows show `archived`) |
| 4 | Exact PSOC code | `test-repository.R` (code `"1111"`, "Legislators") |
| 5 | PSOC text search | `test-repository.R` (query "legislators") |
| 6 | PSGC current release name search | `test-repository.R` (query "Bukidnon") |
| 7 | PSGC old release search | `test-repository.R` (release `Q1_2023`, query "Ilocos Norte") |
| 8 | Classification level filter | `test-repository.R` + `test-search.R` |
| 9 | Blank query (browse) | `test-repository.R` + manual browser verification |
| 10 | No result | `test-repository.R` (`"zzzzznomatch"`) |
| 11 | Special characters | `test-repository.R` (literal `.` in a real PCOICOP code) + `test-search.R` (dots, parentheses) |
| 12 | Leading-zero code preservation | `test-repository.R`, `test-adapters.R` |
| 13 | Switching classification clears/updates invalid level/version state | **Manual browser verification only** (see Known Limitations) |
| 14 | Selected result retains source/version/status | **Manual browser verification only** (detail card rendered correctly with code/label/description/system/version/level/status badge/source link) |

## PSIC Revision 5 Status

**Fully implemented and current.** `data/psic_2026.rds` (2,202 rows) is
built from PSA's official Revision 5 detailed-structure workbook, parsed
and validated at build time, and read directly by the running app with no
PSA network dependency. Validated structural counts: 22 sections ✓, 88
divisions ✓, **261 groups** (PSA states 260 — documented discrepancy, see
`docs/DATA_SOURCES.md`; no parsing defect found after investigation), 493
classes ✓, 1,338 sub-classes ✓. PSIC 2026 is marked `current`; PSIC 2019
(via `phscs`) remains fully queryable, marked `archived`.

## Deployment Status

**Not deployed to a public host.** No Posit Connect Cloud (or equivalent)
account/credentials were available in this environment. Everything short
of the actual remote publish has been completed and verified:

- `renv.lock` pins the full reproducible dependency set.
- The app was launched via a fresh `Rscript` process (not a pre-warmed
  session) under the renv-activated environment and confirmed serving the
  UI with no startup errors, twice (once before, once after the
  `outputOptions` fix below).
- No PSA API token or any other credential is required anywhere.
- See `docs/DEPLOYMENT.md` for the exact restore/run/test commands a
  deployer needs.

## Known Limitations

- **One real bug found and fixed during live-browser verification**: the
  About/Data Sources tab's `uiOutput` has no reactive inputs, and Shiny
  suspends outputs inside a non-active `nav_panel` by default — it never
  rendered until the tab was clicked, and even then only through a real
  reactive re-trigger, which this static output doesn't have. Fixed with
  `outputOptions(output, "sources_panel", suspendWhenHidden = FALSE)` in
  `app.R`. Re-verified working after the fix.
- **UAT cases 13 and 14 (Shiny reactive-wiring behavior) were verified
  manually in a live browser, not via an automated test.** A
  `shiny::testServer()` test was considered but rejected: `testServer`
  does not simulate the client applying `updateSelectInput()`'s pushed
  choices back into `input$...`, so a naive test would exercise less than
  the real client/server round-trip already verified manually (setting
  `classification_system` via `Shiny.setInputValue` in the live app and
  confirming version reset to the system's current edition, level reset to
  "All levels", and the results table/detail card updating correctly).
  This is a documented gap in automated (not functional) coverage.
- **psic division→section `parent_code` is `NA`** for the phscs-sourced
  2019 edition (section codes are letters, not derivable from a division's
  numeric code without a section/division range table that wasn't
  available/verifiable at implementation time). Never fabricated.
- **A handful of individual rows** across pcoicop/pcpc have
  `label`/`parent_code` filled in via a documented, honest fallback (title
  extracted from a leading ALL-CAPS phrase in `description`, or the code
  itself as a last resort) rather than the packaged data providing a clean
  label directly — see the header comment in `R/adapters/adapter_phscs.R`
  for the exact rows and rationale.
- **`retrieved_at` in phscs/psgc metadata is `Sys.Date()`** (the date this
  build ran), not each package's own internal data-vintage date, since
  that isn't introspectable from the installed packages. PSIC 2026's
  `retrieved_at` (from `scripts/build_psic_2026.R`) is the actual workbook
  download date and is accurate.
- **No formal WCAG audit, no fuzzy search, no cross-system simultaneous
  search, no saved/favorite codes, no shareable deep links** — all
  explicitly deferred per spec section 26 (see below).

## Deferred V2 Features

Per spec section 26 — not implemented, by design:

- Cross-edition difference viewer / full PSIC 2019 ↔ Revision 5 crosswalk
- PSGC visual history timeline / split-merge-abolition visualization
  (the `trace_psgc_code()` service seam mentioned in spec section 7 was
  **not** added in this build — flagging this as a gap against the spec's
  "preserve a service seam for later" suggestion; it can be added without
  touching any other contract)
- Fuzzy search / typo tolerance
- Search across all classification systems simultaneously
- Saved/favorite codes, shareable deep links, downloadable citations
- Admin dashboard, automatic PSA sync, PSA API staging
- PostgreSQL, usage analytics, feedback system, multilingual UI
- Formal WCAG audit
- Final PSA visual branding/design system (explicitly the next phase, not
  this one)

## Claude Design Handoff Readiness

**Ready.** Per spec section 22's requirement, everything Claude Design
needs to change lives in `app.R`, `R/ui/*.R`, and `www/app.css`; nothing
about the visual pass requires touching `R/adapters/`, `R/repository.R`,
`R/search.R`, `R/registry.R`, `scripts/build_psic_2026.R`, `data/`, or any
test. Full stable-ID/component/state inventory is in
`docs/UI_CONTRACT.md`.

## Files Changed

New repository, all files created in this build:

```
.Rprofile
.claude/launch.json
.gitignore
README.md
app.R
renv.lock
renv/ (renv infrastructure)
R/schema.R
R/registry.R
R/repository.R
R/search.R
R/adapters/adapter_phscs.R
R/adapters/adapter_psgc.R
R/adapters/adapter_psic_2026.R
R/ui/ui_search.R
R/ui/ui_details.R
R/ui/ui_sources.R
data/psic_2026.rds
data/psic_2026_metadata.rds
data-raw/PSIC_Revision_5_Detailed_Structure_30July2026.xlsx
scripts/build_psic_2026.R
scripts/run_tests.R
docs/UI_CONTRACT.md
docs/DATA_SOURCES.md
docs/DEPLOYMENT.md
tests/testthat/helper.R
tests/testthat/test-schema.R
tests/testthat/test-registry.R
tests/testthat/test-adapters.R
tests/testthat/test-psic-2026.R
tests/testthat/test-search.R
tests/testthat/test-repository.R
www/app.css
IMPLEMENTATION_STATUS.md
```

No files were destructively modified — this was an empty repository
(only the two spec markdown files) at the start of this build.

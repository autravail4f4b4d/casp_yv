# Data Sources: supplemental PSA classifications

This document covers the supplemental data sources built on one pattern:
PSA's own official workbook, normalized offline into a local runtime
artifact, with **no PSA network dependency at runtime**.

- [PSIC Revision 5 (2026 PSIC)](#psic-revision-5-2026-psic)
- [2022 Updates to the 2012 PSOC](#2022-updates-to-the-2012-psoc)
- [Philippine Standard Commodity Classification (PSCC), 2022](#philippine-standard-commodity-classification-pscc-2022)
- [Philippine Tourism Statistical Classification System (PTSCS), 2025 v2.1](#philippine-tourism-statistical-classification-system-ptscs-2025-v21)
- [Philippine Standard Creative Classification System (PSCrCS), 2025](#philippine-standard-creative-classification-system-pscrcs-2025)

PSA is the issuing authority for every classification listed here. The
`phscs` and `psgc` packages, these normalization pipelines and the RM
assistant are access mechanisms, never the authority.

---

## PSIC Revision 5 (2026 PSIC)

## What this is and why it exists

The Philippine Statistics Authority (PSA) officially released the
**Philippine Standard Industrial Classification Revision 5**, publicly
referred to as the **2026 PSIC**, on **5 August 2026**. It was approved by
the PSA Board on **21 May 2026** through **PSA Board Resolution No. 09,
Series of 2026**.

At the time this app was built, the installed `phscs` R package's PSIC
support tops out at the 2019 edition (its own documentation states the
default/latest available version is `"2019"`), and PSA's published PSIC API
documentation likewise still lists `2019` as its latest available API
version. Neither `phscs` nor the PSA API can currently serve Revision 5.

To present PSIC Revision 5 as the current edition without depending on a
package release or a live PSA API, this app implements a **build-time
normalization pipeline**: PSA's own official detailed-structure workbook is
parsed once, offline, into the application's canonical classification
schema, and the result is committed as a local runtime artifact
(`data/psic_2026.rds`). The running Shiny app only ever reads that local
artifact — it never calls out to PSA at runtime.

`phscs` and `psgc` are software/data access mechanisms, not the issuing
authority. **PSA is the sole authoritative source** for PSIC Revision 5;
this pipeline exists only to make PSA's own published data usable before
downstream tooling catches up.

## Source URLs

- PSA classification landing page: `https://psa.gov.ph/classification/psic`
- PSA release announcement: `https://psa.gov.ph/content/psa-releases-philippine-standard-industrial-classification-revision-5`
- PSA PSIC API documentation (still lists 2019 as latest): `https://psa.gov.ph/classifications-api/psic`
- Official Revision 5 detailed structure workbook (the file this pipeline parses):
  `https://psa.gov.ph/sites/default/files/scd/PSIC_Revision_5_Detailed_Structure_30July2026.xlsx`

## Retrieval record

- Local snapshot: `data-raw/PSIC_Revision_5_Detailed_Structure_30July2026.xlsx`
- Retrieved: 2026-08-23, fetched directly from the PSA URL above
- File size: approximately 98.9 KB
- SHA-256 (recorded automatically in `data/psic_2026_metadata.rds$sha256`
  every time `scripts/build_psic_2026.R` is run): see that metadata file for
  the exact hash of the workbook that produced the currently-committed
  `data/psic_2026.rds`.
- Licensing: PSA states that website data/content is licensed under
  **CC BY 4.0 unless otherwise stated**. PSA attribution and source URLs are
  preserved in every canonical row (`source`, `source_url`) and in the
  metadata sidecar.

## Workbook structure

The workbook has two sheets:

- `"Note"` — a single free-text disclaimer cell, not used by the pipeline.
- `"Detailed Structure"` — the actual hierarchy, with a header row followed
  by 1,791 data rows across 6 columns: `Section`, `Division`, `Group`,
  `Class`, `Sub-Class`, `Description`.

There is no separate "label" vs. "description" column — the single
`Description` cell on each row is the short title for whichever code(s) that
row populates. The canonical schema's `label` field is populated from this
text; `description` is left `NA` for PSIC 2026 since no separate longer-form
text exists in the source.

## Parsing algorithm

Each of the 1,791 data rows populates at least one of the five level columns
(section/division/group/class/sub-class), and sometimes more than one at
once: when a parent level has exactly one child at every level below it, the
workbook collapses that entire chain onto a single row instead of emitting a
row per level. Across the 1,791 rows: 1,463 rows populate exactly 1 level
column, 246 rows populate exactly 2, 81 rows populate exactly 3, and 1 row
populates all 4 of division/group/class/sub-class simultaneously
(`division="75", group="750", class="7500", subclass="75000"`, description
"Veterinary activities").

The pipeline (`scripts/build_psic_2026.R`) processes rows top-to-bottom,
maintaining a "last seen code" for each of the five levels. For each row, for
each populated level column **in hierarchy order** (section → division →
group → class → sub-class):

1. The code's parent is the nearest populated ancestor level, preferring a
   code assigned **earlier on the same row** over the historical "last seen"
   code from a previous row.
2. One canonical record is emitted per populated column, using that row's
   single description-cell text as the record's `label`.
3. The "last seen" tracker for that level is updated to this code before
   moving to the next populated column on the same row.

Section-level records get `parent_code = NA`.

## Validated counts vs. PSA's officially stated structure

PSA states the Revision 5 structure contains:

| Level | PSA stated | Parsed |
|---|---|---|
| Sections | 22 | **22** (match) |
| Divisions | 88 | **88** (match) |
| Groups | 260 | **261** (discrepancy — see below) |
| Classes | 493 | **493** (match) |
| Sub-classes | 1,338 | **1,338** (match) |

Total canonical records produced: 2,202.

### The groups: 261 parsed vs. 260 stated

The parse honestly yields **261** distinct group-level records, not the 260
PSA states in its summary. Per the implementation spec's explicit
instruction, **the pipeline does not fabricate, merge, or drop rows to force
a match to 260** — `scripts/build_psic_2026.R` prints this as a `WARN
(documented discrepancy)` during the build and does not abort.

Investigation performed (a few minutes, not exhaustive):

- All 261 parsed group codes are distinct (no duplicate group code appears
  twice under the same or different divisions).
- Every group's code prefix correctly matches its own parent division code
  (no orphaned or mis-parented groups).
- All 88 divisions have at least one group, and the per-division group
  counts look like a normal, plausible distribution (ranging from 1 group in
  several divisions up to 9 groups in division 47 — wholesale/retail trade,
  which is expected to be group-heavy).

No internal parsing defect (duplicate codes, mis-nesting, orphaned parents)
was found that would explain a spurious extra group. The most likely
explanation is that PSA's own published summary total of 260 undercounts by
one relative to its own detailed-structure workbook — i.e. the discrepancy
appears to originate in PSA's summary figure, not in this pipeline's parse.
This is recorded here as an **honest "not fully explained after a brief
investigation"** rather than a confirmed root cause; if PSA publishes a
corrigendum or a revised summary count, this document and
`data/psic_2026_metadata.rds` should be reconciled against it.

## Spot checks

- **Veterinary activities** (all-4-levels-collapsed case):
  `division="75"`, `group="750"`, `class="7500"`, `subclass="75000"`, all
  sharing the label "Veterinary activities", with the expected parent chain
  (`750`'s parent is `75`, `7500`'s parent is `750`, `75000`'s parent is
  `7500`).
- **Growing of corn** (class+sub-class collapsed case, near the top of the
  file): `class="0113"`, `subclass="01130"`, both labeled "Growing of corn",
  with `0113`'s parent being group `011` and `01130`'s parent being class
  `0113`.

Both are asserted in `tests/testthat/test-psic-2026.R`.

## Why runtime never re-fetches from PSA

`scripts/build_psic_2026.R` is a **build-time-only** ingestion step. It is
run once (by a developer, or as part of a release/build process) to produce
`data/psic_2026.rds` and `data/psic_2026_metadata.rds`, which are committed
to the repository as the deployed runtime artifacts. The running Shiny app
and its adapters (`R/adapters/adapter_psic_2026.R`) only ever `readRDS()`
these local files — there is no PSA network call anywhere in the request
path. This satisfies the requirement that runtime search must not depend on
PSA website availability, and means the app behaves identically whether or
not PSA's site, API, or workbook URL is reachable at the time someone uses
the app. To refresh the data (e.g. if PSA republishes a corrected workbook),
re-run the build script and re-commit the two regenerated artifact files.

---

## 2022 Updates to the 2012 PSOC

### What this is and why it exists

PSA identifies the latest Philippine Standard Occupational Classification
edition as the **"2022 Updates to the 2012 Philippine Standard Occupational
Classification (PSOC)"**. It captures new and emerging occupations formed
since 2012 (new industries, technology, equipment, production patterns).

At the time this app was built, the installed `phscs` R package's PSOC
support tops out at the 2012 edition — following the same pattern already
established for PSIC Revision 5, this app implements a **build-time
normalization pipeline** for the 2022 update, so it can be presented as the
current PSOC edition without depending on a future `phscs` release or a
live PSA API call. The running Shiny app only ever reads the local runtime
artifact (`data/psoc_2022.rds`) — it never calls out to PSA at runtime.

### Source URLs

- PSA classification landing page: `https://psa.gov.ph/classification/psoc`
- PSA PSOC technical notes: `https://psa.gov.ph/classification/psoc/technical-notes`
- Official 2022 update workbook (the file this pipeline parses):
  `https://psa.gov.ph/sites/default/files/kmcd/files/2022-Updates-to-the-2012-PSOC.xlsx`

### Retrieval record — manual download (Cloudflare-blocked automated retrieval)

Unlike the PSIC Revision 5 workbook (which is served directly, no bot
protection), `psa.gov.ph`'s file host for this particular workbook sits
behind a Cloudflare JavaScript challenge. Automated retrieval via `curl`
and `httr2` (with and without a browser-identifying User-Agent header)
consistently received an HTTP 403 response with a `Cf-Mitigated: challenge`
header — the request never reached the actual file. A real browser session
(via this session's browser automation tooling) could load the PSA PSOC
page and pass the challenge when *viewing* it, but the tooling available
had no way to persist the resulting downloaded binary file to disk (it
renders/interacts with pages; it does not capture browser-initiated file
downloads).

Given that, **the user manually downloaded the workbook from the same
official URL above and supplied it directly** at
`data-raw/2022-Updates-to-the-2012-PSOC.xlsx`. This is recorded honestly
here and in `data/psoc_2022_metadata.rds$retrieval_method` — the source is
still the official PSA URL; only the retrieval mechanism (human download
vs. this pipeline's own HTTP client) differs from the PSIC Revision 5
precedent. `scripts/build_psoc_2022.R` does not attempt automated download
for this source and will fail with a clear error naming the expected local
path if the file isn't already present.

- Local snapshot: `data-raw/2022-Updates-to-the-2012-PSOC.xlsx`
- File size: approximately 900.5 KB
- SHA-256 (recorded automatically in `data/psoc_2022_metadata.rds$sha256`
  every time `scripts/build_psoc_2022.R` is run): see that metadata file
  for the exact hash of the workbook that produced the currently-committed
  `data/psoc_2022.rds`.
- Licensing: same as PSIC Revision 5 above — CC BY 4.0 unless otherwise
  stated by PSA.

### Workbook structure

Ten sheets, one per PSOC major group: `"Group 1"` .. `"Group 9"`, `"Group
0"` (major group 0 = Armed Forces Occupations, standard PSOC/ISCO
convention). Each sheet has 6 columns: `SUB-MAJOR GROUP` (2-digit code),
`MINOR GROUP` (3-digit), `UNIT GROUP` (4-digit), `OCCUPATIONAL TITLES AND
DEFINITIONS` (the entity's title on a coded row; free-text definitions/
task lists/example job titles on rows with no code), `1992 PSOC` and `2008
ISCO` cross-reference codes (historical crosswalk columns, not used by this
pipeline).

The major-group level itself has no code column — its code comes from the
sheet name, and its title is the first non-blank, non-"Major Group N."-
marker text in the title column before the first coded row (the "Group 0"
sheet omits that marker line entirely and states its title directly, so
the parser does not assume the marker always exists).

Exactly like the PSIC Revision 5 workbook, when a level has exactly one
child at the level below, the row collapses multiple code columns onto one
row sharing one title (e.g. sub-major `411` + unit `4110` on one row,
titled "GENERAL OFFICE CLERKS"). The same forward-fill/collapse-handling
parsing algorithm used for PSIC Revision 5 (`scripts/build_psic_2026.R`)
is reused here (`scripts/build_psoc_2022.R`).

`description` is left `NA` for PSOC 2022: the workbook's prose (multi-
paragraph definitions, "tasks performed" lists, "examples of the
occupations classified here" job-title lists) is extensive and interleaves
genuine definitional text with bare example titles that are *not* further
classification codes. Reliably separating the two without an explicit
legend risked mislabeling text as a description; the short title alone is
captured, and the full text remains in the source workbook.

### Validated counts vs. PSA's officially stated structure

PSA's technical notes state the 2022 PSOC structure contains:

| Level | PSA stated | Parsed |
|---|---|---|
| Major groups | 10 | **10** (match) |
| Sub-major groups | 43 | **43** (match) |
| Minor groups | 130 | **130** (match) |
| Unit groups | 456 | **466** (discrepancy — see below) |

Total canonical records produced: 649.

#### The unit groups: 466 parsed vs. 456 stated

Same pattern as the PSIC Revision 5 groups discrepancy above. Per the
implementation spec's explicit instruction, **the pipeline does not
fabricate, merge, or drop rows to force a match to 456** —
`scripts/build_psoc_2022.R` prints this as a `WARN (documented
discrepancy)` during the build and does not abort.

Investigation performed:

- All 466 parsed unit-group codes are distinct (zero duplicates).
- All 466 codes are well-formed 4-digit strings (zero malformed codes).
- A referential-integrity check (part of the build script itself, hard-
  failing the build if it doesn't hold) confirms every major/sub-major/
  minor/unit `parent_code` resolves to a real record at the level above —
  the parsed hierarchy is internally consistent.

No internal parsing defect was found. As with PSIC's groups discrepancy,
this is recorded as an **honest "not fully explained after investigation"**
rather than a confirmed root cause — PSA's own technical-notes summary
figure and the actual published workbook disagree by 10 unit groups.

### Spot check: PSA's own documented change example

PSA's technical notes specifically describe unit group `2121`
("Mathematicians and Actuaries" under the 2012 PSOC) being split in the
2022 update into `2121` ("Mathematicians") and `2123` ("Actuaries"). Both
codes are confirmed present in the parsed data, sharing the same parent
minor group, with the expected split titles — asserted in
`tests/testthat/test-psoc-2022.R`.

### Why runtime never re-fetches from PSA

Same principle as PSIC Revision 5: `scripts/build_psoc_2022.R` is a
build-time-only step producing `data/psoc_2022.rds` and
`data/psoc_2022_metadata.rds`, committed as the deployed runtime
artifacts. `R/adapters/adapter_psoc_2022.R` only ever `readRDS()`s these
local files. To refresh the data, place an updated workbook at
`data-raw/2022-Updates-to-the-2012-PSOC.xlsx` (manually, given the
Cloudflare retrieval block) and re-run the build script.

---

## Philippine Standard Commodity Classification (PSCC), 2022

**Not to be confused with PSCCS.** PSCC classifies traded commodities;
PSCCS is the Philippine Standard Classification of Crime for Statistical
Purposes. The two acronyms differ by one letter and name unrelated
classifications. The registry previously carried the commodity name on the
crime classification; that is corrected, and a regression test now asserts
both names independently.

| | |
|---|---|
| Official name | Philippine Standard Commodity Classification |
| Version | 2022 (current) |
| PSA reference | `https://psa.gov.ph/classification/pscc` |
| Raw workbook | `data-raw/pscc.xlsx` |
| Build script | `scripts/build_pscc_2022.R` |
| Runtime artifacts | `data/pscc_2022.rds`, `data/pscc_2022_metadata.rds` |
| Adapter | `R/adapters/adapter_pscc_2022.R` |

Codes are strings and are preserved verbatim, including punctuation and
leading zeros — real examples carried through the whole stack and visible
in Search: `0301.99.49-001` (Ricefield eel) and `10.06` (Rice). Nothing in
the pipeline numeric-coerces a code.

## Philippine Tourism Statistical Classification System (PTSCS), 2025 v2.1

| | |
|---|---|
| Official name | Philippine Tourism Statistical Classification System |
| Version | 2025 Version 2.1 (current), internal id `2025-v2.1` |
| PSA reference | `https://psa.gov.ph/classification/ptscs` |
| Raw workbook | `data-raw/PTSCS-Version-2.1.xlsx` |
| Build script | `scripts/build_ptscs_2025.R` |
| Runtime artifacts | `data/ptscs_2025_v2_1.rds`, `data/ptscs_2025_v2_1_metadata.rds` |
| Adapter | `R/adapters/adapter_ptscs_2025.R` |

**Validated counts match PSA exactly: 176 tourism industries, 214 tourism
characteristic products.** The workbook's own Metadata sheet states those
figures, so they were confirmed from the source rather than taken on faith
from a specification.

The data sheets hold more physical rows than data rows (196 and 236). Every
extra row was accounted for before any parsing decision was made:

```
Industries  176 data + 16 category headings + 1 column header + 2 blanks + 1 title = 196
Products    214 data + 18 category headings + 1 column header + 2 blanks + 1 title = 236
```

The category headings are real PTSCS structure, not junk, so they are
preserved as `major_category` (and `major_category_group` for the
top-level numbered headings) rather than discarded. They are **not** emitted
as classification records: they carry only a presentational ordinal
("1.", "12.3."), no official code, and minting one would be fabrication.

**Component provenance is part of the statistical meaning:**

- Tourism Industries → **2019 Updates to the 2009 PSIC**
- Tourism Characteristic Products → **CPC Version 2.1**

PTSCS mints no codes of its own — it selects codes out of those two
classifications and groups them thematically. The industry component is
therefore deliberately **not** migrated to PSIC Revision 5; doing so
silently would misstate what PSA published. The build script enforces this
with a hard `stop()` if an industry record ever carries a source version
other than 2019, and tests assert it independently.

## Philippine Standard Creative Classification System (PSCrCS), 2025

| | |
|---|---|
| Official name | Philippine Standard Creative Classification System |
| Version | 2025 (current) |
| PSA reference | `https://psa.gov.ph/classification/pscrcs/` |
| Raw workbook | `data-raw/PSCrCS_classification.xlsx` |
| Build script | `scripts/build_pscrcs_2025.R` |
| Runtime artifacts | `data/pscrcs_2025.rds`, `data/pscrcs_2025_metadata.rds` |
| Adapter | `R/adapters/adapter_pscrcs_2025.R` |

**Validated counts match PSA exactly: 317 creative industries, 409 creative
goods and services, 114 creative occupations** (840 records total). The
workbook's Metadata sheet states these counts and their underlying
classifications, independently confirming the specification.

**Component provenance:**

- Creative Industries → **2019 Updates to the 2009 PSIC**
- Creative Goods and Services → **CPC Version 2.1**
- Creative Occupations → **2022 Updates to the 2012 PSOC**

As with PTSCS, the industry component stays on 2019 PSIC and is never
silently converted to Revision 5.

### Known characteristics of both composite systems

- **No code hierarchy.** Neither workbook publishes parent/child code
  relationships, so `parent_code` is `NA` throughout and no hierarchy was
  manufactured. The canonical `level` field carries the component id, and
  the meaningful control for these systems is the **Component** selector,
  not the Level selector.
- **Codes are not globally unique within the system.** Because each
  component indexes a different source classification, the same 5-digit
  string can legitimately appear in two components. PSCrCS has three such
  collisions today (`46510`, `47610`, `47620`, shared between the PSIC and
  CPC components); PTSCS has none at present. Uniqueness is enforced per
  `(component, code)`, not system-wide. Anything keying on
  `system + version + code` alone must account for this.
- **No leading-zero codes exist in either workbook today.** The build
  reports this honestly as a count of zero rather than asserting a fixture
  that does not exist. String handling is enforced end to end regardless
  (`col_types = "text"`, character assertions), so none could be lost if PSA
  adds one.

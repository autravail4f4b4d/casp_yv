# Additional PSA Classification Systems — Pre-Staging Ingestion

## Claude Code Implementation Specification

**Project:** PSA Statistical Classifications Search  
**Priority:** P0/P1 functional expansion before staging  
**New systems:** PSCC 2022, PTSCS 2025 Version 2.1, PSCrCS 2025  
**Related correction:** PSCCS canonical name  
**Method:** Graph engineering + parallel source-specific workstreams + single convergence  
**Do not deploy or commit automatically.**

---

# 0. Mission

Add the three PSA classification systems whose official Excel source files are now present in `data-raw/`:

```text
data-raw/pscc.xlsx
data-raw/PTSCS-Version-2.1.xlsx
data-raw/PSCrCS_classification.xlsx
```

Implement them using the existing canonical repository/search architecture.

Do not create a second search engine or classification repository.

The three systems are not structurally identical:

```text
PSCC
→ ordinary commodity classification / hierarchical code system

PTSCS
→ thematic/composite tourism classification
   built from tourism industries and tourism characteristic products

PSCrCS
→ thematic/composite creative classification
   built from creative industries, goods/services, and occupations
```

Do not force PTSCS or PSCrCS into a fake single hierarchy.

---

# 1. Official PSA Verification Targets

These are current official-source expectations. Verify against the local Excel metadata before build.

## 1.1 PSCC

Canonical name:

```text
Philippine Standard Commodity Classification (PSCC)
```

Expected current version:

```text
2022 PSCC
```

Purpose:

```text
detailed classification of commodities entering/traded in Philippine trade
```

Official PSA reference:

```text
https://psa.gov.ph/classification/pscc
```

PSA identifies the version as 2022 PSCC and describes it as a detailed classification of traded commodities.

Important code rule:

```text
PSCC codes are strings.
Never numeric-coerce them.
Preserve leading zeros, dots, hyphens, and suffixes.
```

The local workbook is the build-time source of truth for its exact levels/columns.

Do not assume hierarchy columns without inspecting the workbook.

Preserve any explicit prior-edition/cross-reference columns present in the workbook as metadata rather than discarding them.

---

## 1.2 PTSCS

Canonical name:

```text
Philippine Tourism Statistical Classification System (PTSCS)
```

Current edition:

```text
2025 PTSCS
Version 2.1
```

Official PSA reference:

```text
https://psa.gov.ph/classification/ptscs
```

Official validation targets:

```text
176 tourism industries
214 tourism characteristic products
```

Alignment:

```text
Tourism Industries
→ 2019 Updates to the 2009 PSIC

Tourism Characteristic Products
→ Central Product Classification (CPC) Version 2.1
```

Do not silently update PTSCS industry codes to PSIC Revision 5.

If the app offers a future 2019→2026 PSIC link, it must be clearly presented as a separate correspondence/derived relationship.

---

## 1.3 PSCrCS

Canonical name:

```text
Philippine Standard Creative Classification System (PSCrCS)
```

Approved/adopted:

```text
2025
```

Official PSA references:

```text
https://psa.gov.ph/classification/pscrcs/
https://psa.gov.ph/content/psa-releases-philippine-standard-creative-classification-system
```

Official validation targets:

```text
317 creative industries
409 creative goods and services
114 creative occupations
```

Underlying classifications:

```text
Creative Industries
→ 2019 Updates to the 2009 PSIC

Creative Goods and Services
→ CPC Version 2.1

Creative Occupations
→ 2022 Updates to the 2012 PSOC
```

Do not silently replace the industry component with PSIC 2026.

Do not present CPC or PSOC codes as newly invented PSCrCS code systems.

The component provenance is part of the statistical meaning.

---

# 2. PSCC vs PSCCS — Mandatory Canonical Metadata Correction

The existing application currently risks conflating these acronyms.

Required canonical distinction:

```text
PSCC
Philippine Standard Commodity Classification
Current edition: 2022
Domain: traded commodities
```

```text
PSCCS
Philippine Standard Classification of Crime for Statistical Purposes
Edition: 2018
Domain: crime statistics
```

Search the canonical registry/adapter metadata for the incorrect PSCCS label:

```text
Philippine Standard Commodity Classification System
```

Patch the single authoritative metadata source.

Do not fix only the dropdown label.

Add regression tests asserting both names independently.

---

# 3. Architecture Contract

Preserve:

```text
source workbook
      ↓
build-time normalization
      ↓
local validated runtime artifact
      ↓
adapter
      ↓
canonical repository
      ↓
existing search/version services
      ↓
Search / Sources / RM generic tools
```

Do not parse raw Excel workbooks on every Shiny request.

Do not add a PSA runtime network dependency.

Do not modify the official source workbook in place.

Keep raw inputs in `data-raw/`.

---

# 4. Canonical Schema Strategy

Audit the existing canonical schema first.

Do not rewrite it if optional metadata can support the new systems.

## 4.1 Ordinary/hierarchical systems

PSCC should use the existing canonical fields where possible:

```text
system
version
level
code
label
description
parent_code
status
source
source_url
```

Add source-specific metadata only where needed.

## 4.2 Composite/thematic systems

PTSCS and PSCrCS need component provenance.

Prefer optional fields/metadata such as:

```text
component
major_category
source_system
source_version
source_code
source_label
```

Exact field names should follow repository conventions.

These may be optional/NA for ordinary classifications.

Do not create a separate repository abstraction just for composite classifications.

---

# 5. PTSCS Modeling Contract

Conceptual canonical records:

```text
system          ptscs
version         2025-v2.1
component       tourism_industry
code            <underlying 2019 PSIC code>
label           <official activity label>
source_system   psic
source_version  2019
source_code     <same/reference PSIC code>
major_category  <PTSCS tourism category>
```

and:

```text
system          ptscs
version         2025-v2.1
component       tourism_product
code            <underlying CPC 2.1 code>
label           <official product label>
source_system   cpc
source_version  2.1
source_code     <CPC code>
major_category  <PTSCS tourism product category>
```

Do not claim an underlying PSIC/CPC code is a unique proprietary PTSCS code if the source workbook identifies it as the source classification code.

Preserve the PTSCS thematic category as first-class metadata.

---

# 6. PSCrCS Modeling Contract

Conceptual records:

```text
component = creative_industry
source_system = psic
source_version = 2019
```

```text
component = creative_good_service
source_system = cpc
source_version = 2.1
```

```text
component = creative_occupation
source_system = psoc
source_version = 2022
```

Preserve creative domain/category information from the workbook where available.

Do not manufacture a hierarchy that the source file does not provide.

---

# 7. PSCC Modeling Contract

Inspect the workbook and derive the actual hierarchy.

Preserve:

- exact code text;
- description;
- unit of quantity where present;
- hierarchy/heading metadata;
- previous-edition/cross-reference fields where present;
- source provenance.

Do not numeric-coerce code columns.

Required fixture examples should include at least one leading-zero code and one punctuated/hyphenated code from the workbook.

---

# 8. Build Artifacts

Recommended additions, adapted to repository naming conventions:

```text
scripts/build_pscc_2022.R
scripts/build_ptscs_2025.R
scripts/build_pscrcs_2025.R

data/pscc_2022.rds
data/pscc_2022_metadata.rds

data/ptscs_2025_v2_1.rds
data/ptscs_2025_v2_1_metadata.rds

data/pscrcs_2025.rds
data/pscrcs_2025_metadata.rds
```

Adapters:

```text
R/adapters/adapter_pscc_2022.R
R/adapters/adapter_ptscs_2025.R
R/adapters/adapter_pscrcs_2025.R
```

Exact filenames may follow existing conventions.

---

# 9. Graph Engineering Plan

```text
                           A. Contract Audit
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        ▼                         ▼                         ▼
 B. PSCC build/adapter     C. PTSCS build/adapter    D. PSCrCS build/adapter
        │                         │                         │
        └─────────────────────────┼─────────────────────────┘
                                  ▼
                    E. Canonical metadata convergence
                                  │
                   ┌──────────────┼──────────────┐
                   ▼              ▼              ▼
             F. Registry      G. Search       H. RM/Source exposure
                   └──────────────┼──────────────┘
                                  ▼
                      I. UI component convergence
                                  │
                                  ▼
                          J. Full regression/UAT
```

---

# 10. Wave A — Contract Audit

Read only:

```text
CLAUDE.md
IMPLEMENTATION_STATUS.md
R/registry.R
R/repository.R
R/search.R
R/adapters/
R/metadata.R if present
tests/testthat/
docs/UI_CONTRACT.md
docs/DATA_SOURCES.md
R/assistant/assistant_tools.R only to confirm generic registry/search wrappers
```

Also inspect only the local workbook metadata/sheets/headers necessary to normalize each source.

Do not dump full workbooks into agent context.

Return:

```text
canonical required fields
optional metadata support
version/status contract
adapter registration contract
search contract
RM generic-tool behavior
files shared at convergence
```

Freeze before parallel work.

---

# 11. Wave B — PSCC Workstream

## File ownership

```text
scripts/build_pscc_2022.R
R/adapters/adapter_pscc_2022.R
data/pscc_2022*.rds
tests/testthat/test-pscc-2022.R
```

Do not touch registry/search/UI concurrently.

## Tests

- exact 2022 version;
- official full name;
- code remains character;
- leading zero preserved;
- punctuation preserved;
- source rows normalize without duplicate canonical keys;
- hierarchy references valid;
- unit/cross-reference metadata preserved where source provides it;
- adapter returns canonical contract.

---

# 12. Wave C — PTSCS Workstream

## File ownership

```text
scripts/build_ptscs_2025.R
R/adapters/adapter_ptscs_2025.R
data/ptscs_2025_v2_1*.rds
tests/testthat/test-ptscs-2025.R
```

## Required validation

```text
176 tourism industries
214 tourism characteristic products
```

If workbook counts differ:

- investigate headers/blank rows/duplicates;
- do not force counts;
- report discrepancy.

## Tests

- exactly two conceptual components unless workbook proves otherwise;
- industry source = 2019 PSIC;
- product source = CPC 2.1;
- codes remain strings;
- source/component/category preserved;
- current status/version correct;
- no silent 2019→2026 PSIC conversion.

---

# 13. Wave D — PSCrCS Workstream

## File ownership

```text
scripts/build_pscrcs_2025.R
R/adapters/adapter_pscrcs_2025.R
data/pscrcs_2025*.rds
tests/testthat/test-pscrcs-2025.R
```

## Required validation

```text
317 creative industries
409 creative goods and services
114 creative occupations
```

If workbook differs, investigate and report; do not force.

## Tests

- three components preserved;
- creative industries source = 2019 PSIC;
- goods/services source = CPC 2.1;
- occupations source = 2022 PSOC;
- categories/domains preserved where present;
- codes remain strings;
- current/adopted metadata correct.

---

# 14. Convergence E — Canonical Metadata and PSCCS Fix

One agent owns shared metadata changes.

Likely shared files:

```text
R/registry.R
R/repository.R
R/metadata.R if present
existing phscs adapter metadata if that is the canonical PSCCS source
tests/testthat/test-registry*.R
tests/testthat/test-adapters.R
```

Tasks:

1. register PSCC;
2. register PTSCS;
3. register PSCrCS;
4. fix PSCCS canonical name;
5. ensure PSCC and PSCCS remain distinct;
6. preserve existing current/archive version logic;
7. expose component metadata without breaking ordinary systems.

Do not touch UI here.

Required registry test:

```text
PSCC  → Philippine Standard Commodity Classification
PSCCS → Philippine Standard Classification of Crime for Statistical Purposes
```

---

# 15. Convergence F/G — Repository and Search

Prefer zero search-engine changes.

The existing deterministic search should accept new registered systems through the canonical adapter contract.

Only patch generic repository/search code if tests demonstrate a contract gap.

Required behaviors:

```text
search_classification(system = "pscc", ...)
search_classification(system = "ptscs", ...)
search_classification(system = "pscrcs", ...)
```

or repository-equivalent canonical calls.

Composite systems must support filtering by `component` through the smallest compatible extension.

Do not duplicate ranking code.

---

# 16. RM Integration

The existing RM tools should remain generic.

Confirm that:

```text
assistant_classification_registry()
assistant_search_classification()
assistant_get_classification_entry()
```

discover the new systems through the canonical repository.

Do not create separate LLM tools for each new system unless the generic contract cannot represent a required component filter.

Update RM intent-routing prompt only if necessary:

```text
trade commodities / imports / exports
→ PSCC

tourism industries / tourism characteristic products
→ PTSCS

creative industries / creative goods and services / creative occupations
→ PSCrCS
```

The absolute RM rule remains:

```text
No retrieved code = no code presented as the answer.
```

Do not run live provider evaluation unless credentials are available.

---

# 17. UI Integration Contract

At convergence, the Search system selector should include validated systems:

```text
PSCC
PTSCS
PSCrCS
```

Sources should show cards for them.

Composite systems should expose a `Component` selector as defined in `PRE_STAGING_UI_UAT_REPAIR.md`.

Do not create new top-level navigation tabs for these classifications.

They belong in the canonical Search/Browse system selector and RM registry.

---

# 18. Sources Documentation

Update:

```text
docs/DATA_SOURCES.md
IMPLEMENTATION_STATUS.md
docs/UI_CONTRACT.md if component UI changes
docs/ASSISTANT_CONTRACT.md only if RM routing contract changes
```

For each source record:

```text
official PSA name
version
local raw workbook filename
PSA URL
build script
runtime artifact
source/underlying classification relationships
known limitations
```

Do not expose absolute local machine paths.

---

# 19. Token-Efficiency Rules

Do not paste whole workbooks into agent context.

For each workbook inspect only:

```text
sheet names
header rows
metadata block
row counts
distinct component/category values
sample first/last records
duplicate code checks
required source columns
```

Parallel subagents return only:

```text
source structure
normalization decisions
files changed
validation counts
tests
unresolved discrepancy
```

Use tests as persistent memory.

Do not ask each workstream to reread the full registry architecture.

---

# 20. Bounded Loop Rules

Each source workstream:

```text
inspect workbook contract
→ minimal build script
→ build artifact
→ targeted validation
→ adapter
→ targeted tests
→ freeze
```

Maximum three repair iterations per acceptance criterion.

Do not rewrite passing search/RM code.

---

# 21. Acceptance Checklist

## PSCC

- [ ] 2022 registered current;
- [ ] official name correct;
- [ ] exact codes preserved as strings;
- [ ] leading zeros/punctuation preserved;
- [ ] source metadata documented;
- [ ] Search works;
- [ ] Sources card works;
- [ ] RM generic lookup can discover it.

## PTSCS

- [ ] 2025 Version 2.1 registered current;
- [ ] 176 industries validated;
- [ ] 214 products validated;
- [ ] industry component retains 2019 PSIC provenance;
- [ ] product component retains CPC 2.1 provenance;
- [ ] component filter works;
- [ ] no silent PSIC 2026 substitution.

## PSCrCS

- [ ] 2025 registered current;
- [ ] 317 industries validated;
- [ ] 409 goods/services validated;
- [ ] 114 occupations validated;
- [ ] correct 2019 PSIC/CPC2.1/2022 PSOC provenance;
- [ ] component filter works.

## PSCCS correction

- [ ] canonical name = Philippine Standard Classification of Crime for Statistical Purposes;
- [ ] edition 2018 preserved;
- [ ] PSCC remains distinct.

## Regression

- [ ] existing systems still search;
- [ ] existing versions/status unaffected;
- [ ] dual search unaffected;
- [ ] correspondence unaffected;
- [ ] RM deterministic tests unaffected.

---

# 22. Final Verification

Run targeted source tests.

Then:

```text
Rscript scripts/run_tests.R
```

Required:

```text
0 failures
0 unexpected warnings
0 regressions
```

Browser UAT:

- Search each new system;
- blank-query browse;
- exact code lookup;
- component switching for PTSCS;
- component switching for PSCrCS;
- Sources cards;
- correct PSCCS name.

Do not deploy.

Do not commit automatically.

---

# 23. Direct Claude Code Prompt

Implement `ADDITIONAL_CLASSIFICATION_SYSTEMS_INGESTION.md`.

The raw official Excel sources already exist in:

```text
data-raw/pscc.xlsx
data-raw/PTSCS-Version-2.1.xlsx
data-raw/PSCrCS_classification.xlsx
```

Verify their metadata/structure first.

Use the graph-engineering plan:

1. freeze canonical contracts;
2. build PSCC, PTSCS, and PSCrCS in parallel with non-overlapping files;
3. converge once for registry/metadata;
4. reuse existing repository/search;
5. expose composite component filtering;
6. verify generic RM integration;
7. fix PSCCS canonical naming;
8. run targeted/full tests and browser UAT.

Do not force official validation counts if the workbook evidence contradicts them; investigate and report.

Do not silently convert PTSCS/PSCrCS industry components from 2019 PSIC to Revision 5.

Do not deploy.

Do not commit automatically.

Proceed.

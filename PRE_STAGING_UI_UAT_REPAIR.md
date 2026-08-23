# Pre-Staging UI/UAT Repair

## Claude Code Implementation Specification

**Project:** PSA Statistical Classifications Search  
**Priority:** P0/P1 pre-staging usability and accessibility repair  
**Target:** Complete human-UAT fixes before Posit Connect Cloud staging  
**Method:** Graph engineering + bounded loops + parallel file ownership  
**Do not deploy or commit automatically.**

---

# 0. Mission

Apply the bounded presentation/UI corrections discovered during human visual UAT without weakening the verified deterministic classification services, RM grounding, PSIC correspondence, or classification adapters.

This specification covers the confirmed pre-staging UI defects:

```text
UI-01  Global PSA attribution/footer overlays content
UI-02  Sources uses nested fixed-height scroll panels; replace with responsive card/deck layout
UI-03  Search page exposes a redundant native DT/table Search control
UI-04  Level selector needs a true explicit "All levels" default
UI-05  Search must accommodate composite classifications (PTSCS/PSCrCS) cleanly after ingestion
```

A related metadata correctness issue is tracked separately but must be verified in this UI pass:

```text
META-01
PSCCS must display:
Philippine Standard Classification of Crime for Statistical Purposes

not:
Philippine Standard Commodity Classification System
```

The canonical metadata fix should occur in the registry/adapter layer, not as a UI-only override.

---

# 1. Preserve the Approved Unified Design

Preserve the approved navigation labels and underlying `main_nav` values:

```text
Search
PSOC + PSIC
Compare Editions
RM Assistant
Sources
```

Do not create another top-level Browse/Archive destination.

Browse/archive behavior remains folded into Search via:

- system selector;
- edition/release selector;
- level/component selectors;
- blank-query browse.

Preserve:

- Nocturne/dark theme;
- 56px hero search;
- current vs archived visual vocabulary;
- existing responsive navigation;
- RM static greeting;
- RM streaming/stop/new-chat;
- RM unavailable state;
- RM per-session behavior;
- the 375px/320px composer fix;
- inert `Ask RM about this` placeholders.

Do not wire the Ask RM placeholders in this milestone.

---

# 2. UI-01 — Remove Global Footer/Source Overlap

## Problem

The global source/provenance note currently overlaps content on Search and Sources.

Observed behavior:

```text
results/content
      ↓
fixed/sticky PSA source line
      ↓
rows and text pass behind the footer
```

This obscures real classification content and creates an accessibility defect.

## Required behavior

Prefer normal document flow:

```text
page content
     ↓
page-level source/provenance note
     ↓
end of scroll
```

Do not use `position: fixed` or `position: absolute` for the global source note unless a genuine design contract requires it.

If any sticky/fixed treatment remains, reserve the full occupied height in every scrolling content container so nothing can pass underneath.

Normal-flow placement is preferred because `Sources` already provides persistent provenance information.

## Acceptance tests/UAT

Verify at:

```text
1440×800 or similar desktop
1366×768 office laptop
768px tablet
375px mobile
320px mobile
```

Required:

- last visible result row never obscured;
- source line fully readable;
- source line does not cover sidebar;
- no focusable control can sit behind the note;
- page can scroll to all content;
- RM composer remains unaffected.

---

# 3. UI-02 — Sources Page: Responsive Card/Deck Architecture

## Problem

The Sources view currently behaves like technical/debug documentation:

- wide tables;
- multiple short fixed-height scroll containers;
- nested vertical scrollbars;
- implementation paths exposed prominently;
- long audit material competing with public-facing provenance.

This is difficult for LGU/public users to scan.

## Required public information architecture

Use one normal page scroll.

```text
Sources
│
├── Classification systems
│      ├── PSGC card
│      ├── PSIC card
│      ├── PSOC card
│      ├── PSCED card
│      ├── PCOICOP card
│      ├── PCPC card
│      ├── PSCCS card
│      ├── PSCC card
│      ├── PTSCS card
│      └── PSCrCS card
│
├── Supplemental/current edition provenance
│      ├── PSIC Revision 5
│      └── PSOC 2022
│
├── PSIC edition correspondence methodology
│
└── Technical implementation details ▾
```

The final card set must reflect whatever systems are actually registered after the additional-classification ingestion milestone.

Do not hard-code a public card for a system that failed ingestion/validation.

---

## 3.1 Classification system cards

Each card should show, where available:

```text
Acronym
Official classification name
Current edition/version
Archived editions summary/count
Scope/purpose
Philippine Statistics Authority as issuing authority
Reference/source link
```

Responsive target:

```text
wide desktop: 3 columns where content permits
tablet/smaller desktop: 2 columns
mobile: 1 column
```

Cards should expand naturally.

Do not add fixed internal vertical scrollbars.

### Archived editions

Do not immediately render long PSGC release lists as dozens of visible badges.

Prefer:

```text
Current: Q2 2026
Archived editions: 11 available
[View archived editions ▾]
```

Expanded content may list the archived editions.

Use semantic disclosure controls.

---

## 3.2 Supplemental edition cards

Present PSIC Revision 5 and PSOC 2022 as separate provenance cards.

Public card content should prioritize:

```text
classification/edition
official PSA source
current/archive status
local/offline runtime artifact
validation status
```

Example conceptual copy:

```text
PSIC Revision 5 (2026)
Current edition
Official PSA source
Validated local runtime snapshot
Runtime does not depend on PSA website availability
```

Implementation-specific paths belong in a collapsed technical section.

---

## 3.3 PSIC correspondence methodology card

Replace the large, always-visible scrolling audit table with a concise public summary:

```text
PSIC 2019 ↔ Revision 5 correspondence

Official crosswalk status
Evidence used
Provenance definitions
Statistical-use warning

[View detailed source audit ▾]
```

Public definitions:

```text
Official
Explicit PSA-published correspondence record

Derived
Supported by authoritative structural evidence

Suggested
Algorithmic candidate requiring caution
```

The detailed audit trail may be expandable beneath the summary.

No nested 200px/300px audit scrollbar unless the final detailed table genuinely cannot be represented with normal page flow.

---

## 3.4 Technical implementation details

Repository/internal paths such as:

```text
scripts/*.R
R/adapters/*.R
data/*.rds
tests/testthat/*
```

must not dominate the public Sources page.

If retained for transparency, place under:

```text
Technical implementation details ▾
```

collapsed by default.

The public page should answer:

- Where did this classification come from?
- Which edition is current?
- Which editions are archived?
- Is PSA the issuing authority?
- How is an offline/supplemental edition sourced?
- What evidence supports correspondence?

---

# 4. UI-03 — Remove Redundant Native Results-Table Search

## Problem

The Search page currently exposes:

```text
Main 56px classification search field
+
native DT/table "Search:" field
```

Human UAT found the smaller native search confusing/nonfunctional for the observed use case.

Even if made functional, the two inputs represent different mental models:

```text
main search
→ queries the classification repository

DT search
→ filters only already returned rows
```

This is not obvious to LGU personnel.

## Required behavior

Remove/hide the native DT/table search control from the primary Search results table.

Preserve:

- sorting;
- pagination;
- row selection;
- result count;
- accessible table semantics.

The 56px hero search remains the sole general classification query input.

Do not introduce another table-only filter in V1.

Apply the same rule to other result grids only if their native search field duplicates a canonical app-level search and the removal does not damage a distinct workflow.

Do not globally disable all DT filtering without targeted inspection.

---

# 5. UI-04 — Explicit "All levels" Default

## Problem

`All levels` must be a real selectable default, not placeholder-only text.

## Required contract

For every hierarchical classification:

```text
display:
All levels

service representation:
existing canonical unrestricted level representation
(prefer NULL / equivalent already used by the application)
```

Do not send literal `"All levels"` to a service expecting a real classification level.

## System-specific choices

Examples:

```text
PSGC
All levels
Region
Province
City / Municipality
Barangay
```

```text
PSIC
All levels
Section
Division
Group
Class
Subclass
```

```text
PSOC
All levels
Major group
Sub-major group
Minor group
Unit group
```

Use actual canonical level labels from the registered adapters.

Do not invent level vocabulary.

## System/version changes

Preferred behavior:

```text
System changes
→ Level resets to All levels

Edition changes
→ Level resets to All levels
```

unless the application already has a tested contract that safely preserves an equivalent valid level.

Predictability is preferred.

## Required UAT fixture

For PSGC:

```text
query = "negros"
level = All levels
```

must be capable of returning matching records at multiple levels, such as:

- region;
- province;
- barangay;

when present in the selected edition.

This is a UI/reactive verification of unrestricted search, not a request to change deterministic ranking.

---

# 6. UI-05 — Composite Classification Controls

This applies only after PTSCS and PSCrCS are successfully registered.

PTSCS and PSCrCS are thematic/composite classifications, not ordinary single-hierarchy systems.

Do not force their component categories into fake hierarchy levels.

## PTSCS

Expose, where practical:

```text
Component
All components
Tourism Industries
Tourism Characteristic Products
```

The underlying source classifications must remain visible in result details:

```text
Tourism Industries
→ 2019 PSIC

Tourism Characteristic Products
→ CPC Version 2.1
```

## PSCrCS

Expose:

```text
Component
All components
Creative Industries
Creative Goods and Services
Creative Occupations
```

Underlying sources:

```text
Creative Industries
→ 2019 PSIC

Creative Goods and Services
→ CPC Version 2.1

Creative Occupations
→ 2022 PSOC
```

## UI strategy

Prefer a conditional `Component` selector for composite systems.

Do not rename the ordinary `Level` control globally to `Component`.

Possible behavior:

```text
ordinary hierarchical system
→ show Level

composite system
→ show Component
→ show Level only if that component actually has a meaningful hierarchy exposed by the adapter
```

Use the smallest implementation consistent with the canonical repository contract.

---

# 7. META-01 Verification — PSCCS Name Correction

The canonical application metadata must display:

```text
PSCCS
Philippine Standard Classification of Crime for Statistical Purposes
2018
```

It must not display:

```text
Philippine Standard Commodity Classification System
```

PSCC and PSCCS are distinct:

```text
PSCC
Philippine Standard Commodity Classification

PSCCS
Philippine Standard Classification of Crime for Statistical Purposes
```

The canonical metadata correction belongs to the metadata/registry convergence workstream in the master pre-staging plan.

This UI workstream must verify the corrected name appears in:

- Search system selector;
- Sources cards;
- detail/provenance displays;
- RM registry output if surfaced.

Do not add a UI-only alias that hides a wrong canonical registry value.

---

# 8. Accessibility Requirements

Preserve/verify:

- visible keyboard focus;
- active tab name/state;
- semantic labels;
- heading hierarchy;
- contrast at WCAG AA where required;
- current/archive status not conveyed by color alone;
- disclosure controls keyboard accessible;
- cards do not create redundant focus stops;
- hidden/inert Ask RM placeholders remain noninteractive;
- table pagination remains keyboard accessible;
- mobile RM send control remains in accessibility tree;
- no nested scrolling traps on Sources.

Do not suppress outline/focus indicators.

---

# 9. Graph Engineering Plan

```text
                     A. UI Contract Audit
                              │
              ┌───────────────┼────────────────┐
              ▼               ▼                ▼
       B. Global layout   C. Search UX    D. Sources deck
       footer/flow        controls/table  public provenance
              │               │                │
              └───────────────┼────────────────┘
                              ▼
                   E. Composite controls
                              │
                              ▼
                       F. Responsive/UAT
                              │
                              ▼
                      G. Full regression
```

---

# 10. Parallel Workstreams

Parallelize after A freezes shared UI IDs/contracts.

## A — Audit

Read only:

```text
app.R
R/ui/*
www/app.css
docs/UI_CONTRACT.md
IMPLEMENTATION_STATUS.md
relevant UI tests
```

Return:

```text
stable IDs
main_nav values
shared layout classes
Search input IDs
Level input ID
DT config location
Sources rendering location
footer/provenance rendering location
RM composer selectors that must not regress
```

## B — Global layout/footer

Own:

```text
www/app.css
shared layout helper only if necessary
```

Do not concurrently edit Sources/Search module files.

## C — Search controls

Own the specific Search UI module/server wiring needed for:

- native DT search removal;
- true All levels default;
- optional component selector convergence hook.

Avoid touching registry/adapters.

## D — Sources deck

Own:

```text
R/ui/ui_sources.R or repository-equivalent Sources UI file
Sources-specific CSS classes after B freezes shared styles
```

Do not alter provenance data contracts.

## E — Composite controls convergence

Start only after additional-classification ingestion exposes stable metadata.

One agent owns the shared UI/reactive modifications required to conditionally show Component vs Level.

---

# 11. Bounded Loop Rules

For each workstream:

```text
inspect
→ minimal change
→ targeted test
→ browser/DOM verification
→ narrow repair
→ retest
→ freeze
```

Maximum three repair iterations per acceptance criterion.

Do not refactor passing backend services.

Do not rewrite the entire CSS again unless the existing stylesheet is demonstrably unsalvageable.

---

# 12. Token Efficiency

Do not reread the entire repository.

Use targeted searches for:

```text
main_nav
source
footer
position: fixed
position: sticky
DT
filter
searching
level
All levels
ui_sources
edition
component
```

Do not load classification data to fix CSS.

Workstream summaries must contain only:

```text
files changed
tests
result
public contract change
remaining risk
```

---

# 13. P0/P1 Acceptance Checklist

## Global

- [ ] source/footer never overlays content;
- [ ] normal page scrolling reaches all content;
- [ ] unified navigation unchanged.

## Search

- [ ] hero search is sole general query field;
- [ ] redundant DT search hidden/removed;
- [ ] sorting/pagination/result count retained;
- [ ] `All levels` is a real default;
- [ ] blank-query browse still works;
- [ ] PSGC `negros` + All levels can show multi-level matches.

## Sources

- [ ] no nested-scroll card deck for ordinary public content;
- [ ] responsive 3/2/1 column behavior where appropriate;
- [ ] archived editions collapsible;
- [ ] supplemental edition provenance readable;
- [ ] correspondence methodology summarized;
- [ ] detailed source audit expandable;
- [ ] technical implementation details collapsed by default.

## New systems

- [ ] PSCC card appears only after validated registration;
- [ ] PTSCS card appears only after validated registration;
- [ ] PSCrCS card appears only after validated registration;
- [ ] composite Component control works where implemented.

## Metadata

- [ ] PSCCS displays the correct crime-classification name;
- [ ] PSCC and PSCCS cannot be confused.

## Mobile

- [ ] 375px passes;
- [ ] 320px passes;
- [ ] RM Send remains visible and accessible;
- [ ] no horizontal overflow caused by Sources cards.

---

# 14. Final Verification

Run targeted UI/reactive tests.

Then:

```text
Rscript scripts/run_tests.R
```

Browser/UAT at:

```text
1440 desktop
1366×768
768 tablet
375 mobile
320 mobile
```

Verify all five destinations.

Do not claim live RM provider/multilingual testing unless credentials are actually available.

Do not deploy.

Do not commit automatically.

---

# 15. Direct Claude Code Prompt

Implement `PRE_STAGING_UI_UAT_REPAIR.md`.

First verify the actual branch, Git status, and current regression baseline.

Treat this as a bounded presentation/accessibility milestone.

Preserve deterministic classification logic, correspondence logic, RM grounding, and registered classification data.

Use the graph/parallel ownership plan in this file.

Required outcomes:

1. eliminate global source/footer overlap;
2. replace Sources nested scrolling with responsive public-facing cards/disclosures;
3. remove the redundant native Search-results DT search field;
4. make `All levels` a real default;
5. integrate conditional composite-system Component controls after PTSCS/PSCrCS registration;
6. verify canonical PSCCS naming appears correctly;
7. preserve RM mobile composer behavior;
8. pass full regression and browser UAT.

Do not deploy.

Do not commit automatically.

Proceed.

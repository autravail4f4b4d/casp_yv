# Post–Connect Cloud Staging UI Refinement Plan
## Graph-Engineered Parallel Implementation Specification

**Project:** Statistical Classifications Search  
**Repository:** `autravail4f4b4d/pcas_yv`  
**Working branch:** `feature/pre-staging-hardening`  
**Deployment target:** Posit Connect Cloud staging  
**Purpose:** Implement the UI/UX and result-count corrections identified during the first hosted staging review, while preserving classification data, correspondence logic, RM grounding, and existing application contracts.

---

# 1. Objective

The first Posit Connect Cloud staging deployment is functional and has exposed a bounded set of UI and interaction issues that should be corrected before formal human visual UAT and final RM acceptance testing.

This work is a **staging refinement pass**, not a redesign of the classification engine.

The implementation must:

1. improve the usability and semantics of Search filters;
2. correct misleading result-count display;
3. make PSOC and PSIC searches independently usable;
4. clarify PSIC correspondence terminology;
5. remove redundant filters in composite classifications;
6. fix narrow-layout dropdown overlap/stacking defects;
7. improve Edition / Release presentation;
8. preserve all existing classification/search/correspondence/RM behavior unless explicitly changed below;
9. remain suitable for manual republishing to the existing Connect Cloud staging deployment.

---

# 2. Frozen Contracts / Non-Negotiable Constraints

The following are **frozen** for this refinement and must not be changed unless a failing test demonstrates that the current contract itself is defective.

## 2.1 Navigation

Keep the existing five top-level destinations:

- Search
- PSOC + PSIC
- Compare Editions
- RM Assistant
- Sources

Do not create a sixth navigation destination.

Do not rename the underlying navigation values unless required by an existing contract.

## 2.2 Classification authority and content

Do not modify canonical classification records merely to solve UI issues.

Do not alter:

- PSGC classification content;
- PSIC classification content;
- PSOC classification content;
- PSCC classification content (source values remain frozen; the PSCC adapter may be enriched with source-form hierarchy/display metadata under UI-POST-07);
- PSCCS classification content;
- PTSCS classification content;
- PSCrCS classification content;
- PSIC 2019 ↔ Revision 5 structural correspondence edges;
- correspondence provenance;
- correspondence confidence;
- curated PSOC overrides.

## 2.3 RM grounding

Preserve:

> **No retrieved code = no code presented as authoritative.**

Do not change RM tool semantics or grounding behavior as part of this UI pass.

PSOC and PSIC remain conceptually distinct:

- **PSOC** = what a person does / occupation.
- **PSIC** = economic activity of the establishment or business.

## 2.4 Deployment

- Work on `feature/pre-staging-hardening`.
- Do not merge to `main`.
- Do not deploy automatically.
- Keep Connect Cloud automatic republishing disabled.
- Do not commit secrets.
- Do not change `OPENAI_API_KEY` handling.
- Do not automatically commit unless explicitly instructed.
- After successful implementation, create a new staging checkpoint/tag only after all tests and UAT gates pass.

---

# 3. Staging Findings to Implement

## UI-POST-01 — Compare Editions: Relationship terminology help

### Problem

The `Relationship` field contains values such as:

- `split`
- `merged`
- `reclassified`
- `continued` / `unchanged` if present

These are meaningful but not self-explanatory to a general user.

`Relationship`, `Provenance`, and `Confidence` are also different concepts and should not be conflated.

### Required change

Add a compact, accessible information tooltip beside the `Relationship` heading.

Minimum wording:

> **Relationship** describes how a classification changed between editions. **Split** = one old category became multiple new categories. **Merged** = multiple old categories became one. **Reclassified** = the activity moved or was recoded to another category. **Continued/unchanged** = the concept remains substantially the same.

Preserve the distinction:

- **Relationship** → what happened to the concept between editions.
- **Provenance** → where the correspondence evidence came from.
- **Confidence** → strength/certainty of the mapping.

### Optional improvement

If low-risk within the same component, add concise tooltips for `Provenance` and `Confidence` as well.

### Acceptance criteria

- Tooltip is keyboard accessible.
- Tooltip has an accessible name/description.
- Tooltip is usable on narrow/mobile layouts.
- No correspondence values or mappings change.
- Table sorting/filtering behavior remains intact.

---

# 4. UI-POST-02 — PSOC + PSIC: Independent Search Fields

## Problem

The current PSOC + PSIC interface does not make the occupational and industrial searches sufficiently independent.

This weakens the conceptual distinction between PSOC and PSIC.

## Required design

Replace the shared search interaction with two independent search areas.

### PSOC panel

Label:

> **PSOC — Occupation**

Helper text:

> Describes what a person does.

Input placeholder:

> `Search an occupation or PSOC code`

Internal state should be independent, e.g.:

- `psoc_query`
- `psoc_results`
- `psoc_selected`

### PSIC panel

Label:

> **PSIC — Industry**

Helper text:

> Describes the economic activity of the establishment or business.

Input placeholder:

> `Search an industry or PSIC code`

Independent state, e.g.:

- `psic_query`
- `psic_results`
- `psic_selected`

## Layout

Desktop:

- PSOC and PSIC panels side by side.

Tablet/mobile:

- panels stack vertically;
- no horizontal overflow;
- each panel retains its own selected result/detail state.

## Behavioral requirements

Typing into PSOC must not change PSIC results.

Typing into PSIC must not change PSOC results.

Do not infer an industry from an occupation.

Do not infer an occupation from an industry.

If there is a future/optional `Ask RM` action, it may use both selections explicitly, but the two search controls must remain independent.

## Acceptance criteria

- Independent queries can exist simultaneously.
- Independent selected records can exist simultaneously.
- Clearing one side does not clear the other.
- Mobile stacking works at 375 px and 320 px.
- Existing canonical search functions are reused rather than duplicated.

---

# 5. UI-POST-03 — Composite Classifications: Component vs Level

## Affected systems

- PTSCS 2025 v2.1
- PSCrCS 2025

## Problem

Both `Component` and `Level` are shown even when `Level` merely repeats the semantic meaning of `Component`.

Examples of machine-like `level` values may include:

- `tourism_product`
- `tourism_industry`
- `creative_industry`
- `creative_product`
- `creative_occupation`

This is confusing and exposes internal field values.

## Required rule

> **Component is the primary public filter for composite classifications. Show Level only when Level adds genuine hierarchical information within the selected Component.**

Do not simply hard-code "hide Level for PTSCS/PSCrCS" without first auditing the artifact.

### Audit first

For PTSCS and PSCrCS, inspect the equivalent of:

```r
distinct(component, level)
```

Determine whether the mapping is effectively one-to-one.

### If Component ↔ Level is one-to-one

Hide `Level` from the public UI.

Keep `level` in the underlying canonical data model.

### If a Component has two or more meaningful internal levels

Show `Level`, but:

- only show levels valid for the selected component;
- use human-readable labels;
- never expose raw values such as `tourism_product`;
- reset stale Level state to `All levels` when Component changes.

## Expected public Component choices

### PTSCS

- All components
- Tourism Industries
- Tourism Characteristic Products

Underlying provenance remains:

- Tourism Industries → 2019 PSIC
- Tourism Characteristic Products → CPC Version 2.1

### PSCrCS

- All components
- Creative Industries
- Creative Goods and Services
- Creative Occupations

Underlying provenance remains:

- Creative Industries → 2019 PSIC
- Creative Goods and Services → CPC Version 2.1
- Creative Occupations → 2022 PSOC

## Acceptance criteria

- No redundant Component + Level combination is shown.
- `level` remains available internally.
- No fake hierarchy is invented.
- Changing Component cannot leave an invalid stale Level selection.
- Machine values are not shown to users.
- Search semantics and record counts remain correct.

---

# 6. UI-POST-04 — Dropdown Overlay / Narrow-Layout Defect

## Problem

On narrow layouts, opening the `System` dropdown can visually cover or collide with controls below it.

This creates the appearance that fields are overwritten or hidden.

## Required change

Audit the current input widget implementation and CSS stacking context.

Fix:

- `z-index`;
- overflow clipping;
- parent `overflow` rules;
- menu max-height;
- sidebar/menu positioning;
- narrow-layout spacing;
- viewport-edge collision behavior.

## Required behavior

The expanded dropdown must:

- remain above surrounding content while open;
- not be clipped by the sidebar container;
- have a bounded, scrollable menu if long;
- not permanently obscure or distort adjacent controls;
- close normally after selection;
- remain keyboard navigable;
- remain usable at 320 px width.

Do not solve this by applying an extreme global z-index to all inputs.

Use a scoped component/container solution.

## Acceptance criteria

Test at:

- 1440 px
- 1366 px
- 768 px
- 375 px
- 320 px

No filter menu may be clipped or rendered behind adjacent controls.

---

# 7. UI-POST-05 — Search Result Count Correctness

## Problem

The Search interface frequently shows exactly:

> `200 results`

across classification systems.

The likely cause is that the displayed/materialized result set is capped at 200 and the UI uses the rendered-row count as though it were the true number of matches.

This is semantically incorrect.

## Required architecture

Separate:

1. **total filtered match count**
2. **materialized/rendered result count**
3. **presentation cap/page size**

Do not solve this by merely increasing the cap.

### Preferred behavior

If there are 3,487 matches and only 200 are materialized:

> `3,487 results · showing first 200`

If fewer than the cap match:

> `87 results`

If true total cannot reasonably be determined:

> `200+ results`

Never display `200 results` when the real meaning is "first 200 returned."

## Performance requirement

Preserve a rendering/materialization cap where useful.

The UI must not attempt to render thousands of result rows merely to show an accurate total.

Where feasible for in-memory RDS-backed data:

```text
filter
  ├── count all matching rows
  └── materialize first N for presentation
```

Avoid performing the same expensive filtering twice if one filtered object or count-aware service result can provide both.

## Contract recommendation

Prefer a result contract equivalent to:

```text
results$data
results$total_matches
results$returned_count
results$is_truncated
results$limit
```

Do not force this exact shape if the repository already has an equivalent contract.

## Required tests

Cover:

- 0 matches
- 1 match
- fewer than 200
- exactly 200
- greater than 200
- browsing/no query
- filtered query
- at least one large classification system

## Acceptance criteria

- True count and rendered count are never conflated.
- Existing search ranking/order is unchanged.
- Existing 200-row performance protection may remain.
- All classification systems use the same count semantics.

---

# 8. UI-POST-06 — Edition / Release Selector Refinement

## Problem

The current Edition / Release selector is visually dense.

Issues observed:

- strong horizontal row lines;
- crowded radio rows;
- Current/Archived badges compete with labels;
- raw release values such as `Q1_2023` look implementation-oriented;
- long PSGC release histories require scrolling and need better visual hierarchy.

## Required visual behavior

Use compact selectable rows with spacing rather than strong table-like separators.

Recommended row properties:

- approximately 36–40 px row height;
- consistent left/right padding;
- subtle or no row separator;
- visible hover state;
- visible keyboard focus state;
- selected-row state;
- Current/Archived badge aligned consistently;
- bounded scrolling only when needed.

## Human-readable labels

Public display should transform identifiers such as:

- `Q1_2023` → `Q1 2023`
- `Q4_2023` → `Q4 2023`
- `April_2024` → `April 2024`

Preserve raw identifiers internally.

Do not change chronological order.

## Acceptance criteria

- Release labels are readable and human-facing.
- Current/Archived status remains textually explicit.
- No status is conveyed by color alone.
- Long release lists remain scrollable.
- Keyboard selection remains functional.
- Narrow layout does not collapse badge/label readability.

---


# 9. UI-POST-07 — PSCC 2022 Commodity Classification: Source-Form Hierarchy and Display

## Problem

The current PSCC display is confusing because a commodity classification is not well represented as a flat `code + label` list.

The uploaded reference workbook, `commodity classification.xlsx`, shows that the **2022 Philippine Standard Commodity Classification (PSCC)** is presented as a structured classification form with hierarchy, descriptor rows, final commodity codes, units, and explicit cross-references.

The public UI should follow that source structure rather than flattening every workbook row into an equivalent-looking result.

## 9.1 Source-form audit from the uploaded workbook

The implementation audit was performed against the actual supplied workbook:

`data-raw/commodity classification.xlsx`

The workbook structure differs slightly from the preliminary counts used when this specification was drafted.

The following are **observed workbook-structure counts from the supplied Excel file**. They are implementation/audit counts describing workbook rows and source-form structures; they are **not official PSA classification totals** and must not be presented as such in the public application.

| Source-form structure | Observed count |
|---|---:|
| Section rows | 21 |
| Chapter rows | 98 |
| Heading rows | 1,245 |
| Six-digit intermediate 2022 PSCC codes | 1,979 |
| Eight-digit intermediate 2022 PSCC codes | 2,350 |
| Detailed 2022 PSCC rows | 16,049 |
| Descriptor-only hierarchy rows | 2,325 |
| Inline caption rows | 80 |
| Sub-chapter rows | 66 |
| Excel-numeric code corruptions detected | 9 |

The audit also identified **9 code cells whose Excel representation had been converted to floating-point-like values**, for example values structurally resembling:

`8701.2099999999991`

These anomalies originate in the supplied workbook rather than the application UI. The build pipeline applies only deterministic repairs that can be independently established from the surrounding source sequence. The original anomalous values must remain auditable in build metadata (for example, `metadata$numeric_cell_repairs`) rather than being silently discarded.

The audit further identified **1,647 descriptions containing U+00A0 non-breaking spaces within leading hierarchy markers**. Base matching based only on `[[:space:]]` did not recognize these correctly, causing hierarchy depth to be understated. The parser must therefore handle ordinary spaces and non-breaking spaces when interpreting source hierarchy markers, while preserving the original raw description.

These figures supersede the preliminary structural counts previously written in this specification.

## 9.2 Source hierarchy example

The workbook expresses commodity structure approximately like:

```text
SECTION I — LIVE ANIMALS; ANIMAL PRODUCTS
  Chapter 1 — Live animals
    Heading 01.01 — Live horses, asses, mules and hinnies
      Horses
        0101.21.00-000 — Pure-bred breeding animals
        0101.29.00     — Other
          0101.29.00-001 — Race horses
          0101.29.00-009 — Other
```

The UI must preserve the meaning of this hierarchy.

Do not display all of the above as visually equivalent flat rows.

## 9.3 Canonical/source-form fields to preserve

The PSCC adapter/repository may be enriched with display metadata, but the source values themselves must remain authoritative.

Preserve at minimum:

```text
section
chapter
heading
pscc_2022_code
raw_description
unit_of_quantity
pscc_2019_code
ahtn_2022_code
source_row
source_order
```

Where derivable without inventing hierarchy, also expose:

```text
node_type
display_depth
display_description
parent_path / breadcrumb metadata
is_selectable_code
is_structural_label
```

Do not remove the original source description after generating a cleaned display description.

## 9.4 Row/node semantics

The implementation must distinguish at least the following concepts where supported by the workbook:

- Section
- Chapter
- Heading
- intermediate coded category/subheading
- descriptor-only hierarchy label
- detailed commodity item
- structural note/sub-chapter if present

Do **not** infer the entire node type from code length alone.

Use the source-form combination of:

- Heading column;
- 2022 PSCC column;
- description hierarchy markers;
- Unit of Quantity;
- 2019 PSCC cross-reference;
- AHTN 2022 cross-reference;
- surrounding structural context.

Important edge case:

Some workbook rows contain both a value in `Heading` and a detailed `2022 PSCC` code. The parser/display model must preserve both fields rather than assuming that Heading rows and commodity-code rows are mutually exclusive.

## 9.5 Public Search result design

For PSCC search results, use a hierarchy-aware presentation.

Recommended result structure:

```text
0101.21.00-000
Pure-bred breeding animals

Section I › Chapter 1 › Heading 01.01 › Horses

Unit: u
2019 PSCC: 0101.21.00-00
AHTN 2022: 0101.21.00
```

The first visual line should prioritize:

1. **2022 PSCC code**, when the row has one;
2. **human-readable commodity description**.

Secondary metadata should contain:

- hierarchy/breadcrumb;
- unit of quantity;
- 2019 PSCC cross-reference;
- AHTN 2022 cross-reference.

Do not concatenate every field into one long result title.

## 9.6 Browse mode

When the Search query is blank and the user is browsing PSCC:

Prefer hierarchical browsing:

```text
Section
  ↓
Chapter
  ↓
Heading
  ↓
Intermediate category / descriptor
  ↓
Commodity item
```

The implementation may use:

- collapsible groups;
- indented rows;
- breadcrumb-driven drill-down;
- a hierarchy-aware result list.

Do not require all 26,000+ source rows to be rendered simultaneously.

The true result-count contract from UI-POST-05 still applies.

## 9.7 Description indentation

The workbook uses leading dash patterns such as:

```text
- Horses :
- - Other
- - - Male cattle :
- - - - Oxen
```

These source markers encode hierarchy.

For the public interface:

- derive indentation/depth from the leading hierarchy markers where valid;
- display the hierarchy visually using indentation/breadcrumbs;
- remove only the **leading structural dash markers** from `display_description`;
- preserve the exact `raw_description` internally;
- do not strip hyphens occurring as legitimate punctuation inside the actual description.

Example:

```text
raw_description:
- - - - Oxen

display_description:
Oxen
```

## 9.8 Code handling is string-only

Every classification/cross-reference code must remain a character string.

Never coerce PSCC, AHTN, or historical PSCC codes to numeric values.

This is required to preserve:

- leading zeroes;
- periods;
- hyphens;
- source-specific suffixes;
- exact code width.

Add a validation check for suspicious floating-point-like expansions or other non-canonical code artifacts.

Do not silently "repair" a suspicious source value unless an explicit deterministic normalization rule is documented and tested.

If a source anomaly exists, preserve the raw value and expose/report the anomaly during the build.

## 9.9 Cross-reference semantics

The columns:

- `2019 PSCC`
- `AHTN 2022`

are **cross-reference fields**, not levels in the 2022 PSCC hierarchy.

Do not show them in the public `Level` selector.

Do not treat AHTN 2022 as the parent of the PSCC record.

In the detail view label them explicitly:

```text
2022 PSCC
2019 PSCC cross-reference
AHTN 2022 cross-reference
Unit of Quantity
```

## 9.10 PSCC Level selector

Audit the current PSCC `Level` values.

The public Level selector must describe genuine hierarchy and must not expose raw parser categories.

If the normalized artifact can reliably support public levels, use human-readable labels such as:

- All levels
- Section
- Chapter
- Heading
- Intermediate category / Subheading
- Commodity item

Only expose a level when its derivation from the official workbook is deterministic.

If intermediate source rows cannot be reliably mapped to a formal named PSCC level, prefer:

```text
Intermediate category
```

rather than inventing an official classification term.

## 9.11 Search behavior

PSCC search should support:

- 2022 PSCC code;
- description text;
- Heading code/title;
- 2019 PSCC code as a clearly identified cross-reference search;
- AHTN 2022 code as a clearly identified cross-reference search.

When a match occurs through a historical/AHTN cross-reference, make that reason visible, for example:

```text
Matched 2019 PSCC cross-reference: 0101.21.00-00
```

or:

```text
Matched AHTN 2022: 0101.21.00
```

Do not present the cross-reference code as though it were the 2022 PSCC code.

## 9.12 Detail panel

For a selected detailed PSCC record, use a structured detail panel rather than a generic flattened label block.

Recommended fields:

| Public label | Source |
|---|---|
| 2022 PSCC | Column B |
| Description | Column C |
| Hierarchy | derived from Section/Chapter/Heading/source descriptors |
| Unit of Quantity | Column D |
| 2019 PSCC | Column E |
| AHTN 2022 | Column F |

Where relevant, also show:

- Section;
- Chapter;
- Heading;
- immediate parent descriptor.

## 9.13 PSCC vs PSCCS safeguard

Keep the two systems independent:

- **PSCC** = Philippine Standard Commodity Classification
- **PSCCS** = Philippine Standard Classification of Crime for Statistical Purposes

No UI refactor may merge, alias, or route one system to the other.

## 9.14 Implementation boundary

This finding may require a **PSCC adapter/display metadata enrichment**, not merely CSS.

Allowed:

- enrich the normalized PSCC artifact with source-form hierarchy metadata;
- add display helpers;
- add breadcrumb/depth fields;
- distinguish structural nodes from detailed commodity items;
- improve search matching metadata.

Not allowed:

- rewrite official source descriptions;
- invent missing official hierarchy;
- change commodity codes;
- overwrite 2019/AHTN cross-reference values;
- change unrelated classification adapters.

## 9.15 Required PSCC tests

Add tests for at least:

1. Section row preservation.
2. Chapter row preservation.
3. Heading row preservation.
4. Descriptor-only row preservation.
5. Six-digit intermediate code preservation.
6. Eight-digit intermediate code preservation.
7. Detailed hyphenated PSCC item preservation.
8. Leading zero preservation.
9. Punctuation/hyphen preservation in codes.
10. Unit of Quantity preservation.
11. 2019 PSCC cross-reference preservation.
12. AHTN 2022 cross-reference preservation.
13. Correct breadcrumb for a representative early-chapter item.
14. Public description does not expose leading hierarchy dashes.
15. Raw description remains unchanged internally.
16. Cross-reference matches are explicitly labeled as such.
17. PSCC and PSCCS remain separate registry systems.
18. A row containing both Heading and 2022 PSCC values preserves both.
19. Suspicious numeric/floating-like code artifacts are detected rather than silently coerced.
20. Browse mode does not render the entire workbook at once.

## 9.16 Acceptance criteria

- PSCC no longer appears as an undifferentiated flat commodity list.
- The visible hierarchy corresponds to the uploaded workbook form.
- Section → Chapter → Heading context is visible for detailed items.
- Descriptor-only hierarchy rows are not mistaken for final commodity codes.
- Final commodity codes remain strings with exact leading zeroes/punctuation.
- Unit, 2019 PSCC, and AHTN 2022 are visible as secondary metadata.
- Cross-references are not mistaken for hierarchy.
- Result-count semantics remain truthful.
- Search performance remains bounded.
- No PSCCS regression occurs.

---

# 10. Graph Engineering Execution Plan

The implementation should use a dependency graph rather than one long serial pass.

## 9.1 Graph

```text
                         ┌─────────────────────────────┐
                         │ W0 — Contract/Audit Freeze  │
                         └──────────────┬──────────────┘
                                        │
        ┌───────────────────────────────┼────────────────────────────────┐
        │                               │                                │
        ▼                               ▼                                ▼
┌────────────────┐             ┌──────────────────┐             ┌───────────────────┐
│ W1-A Counts    │             │ W1-B Composite  │             │ W1-C Dual Search  │
│ Search service │             │ filters/levels  │             │ PSOC + PSIC       │
└───────┬────────┘             └────────┬─────────┘             └─────────┬─────────┘
        │                               │                                 │
        │                 ┌─────────────┴─────────────┐                   │
        │                 │                           │                   │
        ▼                 ▼                           ▼                   ▼
┌────────────────┐ ┌──────────────────┐      ┌──────────────────┐ ┌──────────────────┐
│ W1-D Release   │ │ W1-E Dropdown    │      │ W1-F Compare    │ │ shared UI state  │
│ selector UX    │ │ overlay/CSS      │      │ tooltip/help    │ │ validation       │
└───────┬────────┘ └────────┬─────────┘      └────────┬─────────┘ └────────┬─────────┘
        └───────────────────┴─────────────────────────┴───────────────────┘
                                        │
                                        ▼
                         ┌─────────────────────────────┐
                         │ W2 — Convergence / Contract │
                         │ integration                 │
                         └──────────────┬──────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
             ┌─────────────┐     ┌──────────────┐    ┌──────────────┐
             │ W3-A Tests  │     │ W3-B A11y   │    │ W3-C Visual │
             │ unit/integ. │     │ DOM/focus   │    │ browser UAT │
             └──────┬──────┘     └──────┬───────┘    └──────┬───────┘
                    └────────────────────┴────────────────────┘
                                        │
                                        ▼
                         ┌─────────────────────────────┐
                         │ W4 — Full Regression Gate   │
                         └──────────────┬──────────────┘
                                        │
                                        ▼
                         ┌─────────────────────────────┐
                         │ W5 — Staging Republish      │
                         │ + Formal RM UAT             │
                         └─────────────────────────────┘
```

---

# 11. Workstream Ownership and Parallelization

## W0 — Contract / Audit Freeze

**Serial prerequisite.**

Goals:

1. identify the exact owner files/functions for:
   - Search query filtering;
   - result limit;
   - displayed result count;
   - Edition/Release input;
   - Component/Level input;
   - PSOC + PSIC search state;
   - Compare Editions table header;
   - sidebar/dropdown CSS;
   - PSCC adapter/build path, normalized artifact, and public result/detail rendering;
2. inspect PTSCS/PSCrCS `distinct(component, level)`;
3. audit the supplied PSCC workbook structure against the normalized PSCC artifact;
4. document current input IDs and service contracts before modification.

### Token optimization

Do not read the whole repository.

Use targeted discovery, e.g. conceptually:

```text
rg "200|limit|head\(|slice_head|results" R tests
rg "Edition|release|Archived|Current" R www tests
rg "component|level|tourism_product|creative_" R tests
rg "PSOC.*PSIC|psoc_query|psic_query" R tests
rg "Relationship|Provenance|Confidence" R tests
rg "PSCC|commodity|AHTN|Unit of Quantity|2019 PSCC" R scripts tests
```

Once an owner file is identified, stop broad searching and read only the relevant functions/sections.

### Output

A short implementation map:

```text
issue → owner function/file → tests → shared dependency
```

No code changes in W0 unless required to expose a missing test seam.

---

## W1-A — Result Count Correctness

**Can run in parallel after W0.**

Ownership:

- search/repository count contract;
- count presentation;
- truncation semantics;
- tests for `<200`, `=200`, `>200`.

Avoid editing general CSS except small result-count styling if required.

Must not alter ranking.

---

## W1-B — Composite Classification Filters

**Can run in parallel after W0.**

Ownership:

- PTSCS/PSCrCS component-level audit;
- conditional Level visibility;
- human-readable Level labels;
- stale Level reset behavior;
- related tests.

Must not change artifact schemas unless an existing canonical metadata defect is proven.

Prefer UI adaptation over data mutation.

---

## W1-C — PSOC + PSIC Independent Search

**Can run in parallel after W0.**

Ownership:

- two search inputs;
- two independent reactive states;
- two independent results;
- responsive panel layout;
- dual-search tests.

Must reuse canonical search/repository services.

No RM tool rewrite.

---

## W1-D — Edition / Release UX

**Can run in parallel after W0.**

Ownership:

- public label formatting;
- release-row presentation;
- selected/current/archive states;
- release list scroll behavior.

Do not change raw edition IDs or edition ordering.

---

## W1-E — Dropdown Overlay / Responsive CSS

**Can run in parallel after W0, but coordinate shared CSS ownership.**

Ownership:

- sidebar/input stacking context;
- dropdown clipping;
- menu max-height;
- responsive narrow-width behavior.

### Shared-file rule

If `www/app.css` is also needed by W1-C or W1-D, designate W1-E as the sole CSS convergence owner.

Other workstreams should return proposed class names/required selectors rather than concurrently editing the same CSS blocks.

---

## W1-F — Compare Editions Tooltip

**Can run in parallel after W0.**

Ownership:

- accessible Relationship tooltip;
- optional Provenance/Confidence tooltip;
- tooltip tests.

No correspondence service/data changes.

---


## W1-G — PSCC Source-Form Hierarchy and Display

**Can run in parallel after W0, but must converge with W1-A count semantics and W1-E shared UI/CSS.**

Ownership:

- audit `commodity classification.xlsx` against the normalized PSCC artifact;
- preserve Section / Chapter / Heading / descriptor / coded-item context;
- add hierarchy/breadcrumb metadata where deterministic;
- keep all PSCC/cross-reference codes as strings;
- distinguish structural rows from selectable detailed commodity codes;
- improve PSCC result cards and detail panel;
- add PSCC-specific hierarchy/search tests.

Constraints:

- do not alter official commodity descriptions/codes;
- do not invent hierarchy;
- do not treat 2019 PSCC or AHTN 2022 as hierarchy levels;
- do not modify PSCCS;
- if adapter changes are required, keep them PSCC-scoped.

Token strategy:

1. inspect the PSCC adapter/build script and one normalized artifact sample;
2. compare only representative workbook ranges plus structural-pattern counts;
3. implement a deterministic row classifier/hierarchy builder;
4. target PSCC tests before any full suite;
5. do not repeatedly parse the full Excel workbook during tests—build once or use a bounded fixture that preserves the relevant source forms.

---

# 12. Shared-File Locking Rules

Parallelism is only useful if merge conflict cost remains low.

Before coding, create a simple ownership table.

Example:

| Shared resource | Owner |
|---|---|
| Search result count service | W1-A |
| Composite filter server logic | W1-B |
| PSOC + PSIC server state | W1-C |
| Edition/release rendering | W1-D |
| `www/app.css` convergence | W1-E |
| Compare tooltip | W1-F |
| PSCC adapter / hierarchy metadata | W1-G |
| final shared UI helpers | W2 |

Rules:

1. only one workstream owns a shared file at a time;
2. other workstreams return a patch recommendation or helper contract rather than editing the same region;
3. converge shared helpers in W2;
4. do not allow parallel agents to reformat unrelated code.

---

# 13. Token-Efficient Agent Instructions

Every workstream should receive only:

1. this specification section relevant to that workstream;
2. the W0 owner-file map;
3. exact relevant tests;
4. exact frozen contracts.

Do not give every agent the full repository history.

## Required agent behavior

Each agent must:

- use targeted `rg`/file reads;
- avoid whole-file reads when a function-range read is enough;
- avoid whole-repo test runs until its targeted tests pass;
- report changed files and contracts;
- stop after a maximum of three repair loops for the same failing criterion;
- never silently broaden scope;
- never regenerate unrelated artifacts.

## Bounded loop

For each acceptance criterion:

```text
inspect
  ↓
implement
  ↓
targeted test
  ↓
if fail: diagnose + repair
  ↓
max 3 iterations
  ↓
escalate instead of thrashing
```

---

# 14. Convergence Wave W2

After all W1 workstreams complete:

1. integrate shared reactive/input contracts;
2. resolve CSS ownership in one pass;
3. confirm no duplicate formatting helpers were introduced;
4. confirm Search, PSOC + PSIC, Compare Editions, and composite filter inputs use consistent naming/labeling;
5. confirm responsive breakpoints do not conflict;
6. confirm no workstream changed canonical data unintentionally.

Run a targeted integration set before the full suite.

---

# 15. Testing Requirements

## 14.1 Unit / service tests

Required:

- result count semantics;
- truncation semantics;
- component-level dependency;
- component change resets Level;
- raw machine values are not exposed;
- PSOC/PSIC state independence;
- release display formatting;
- tooltip presence and accessible association.

## 14.2 Regression cases for count semantics

Explicitly test:

```text
0
1
199
200
201
>200
```

At `201`, UI must not simply say `200 results`.

## 14.3 PSOC + PSIC regression

Verify:

```text
PSOC query A + PSIC query B
```

can coexist.

Then:

- clear PSOC → PSIC stays;
- select PSOC result → PSIC stays;
- change PSIC query → PSOC selection stays unless product design explicitly says otherwise.

## 14.4 Composite-system tests

For both PTSCS and PSCrCS:

- `All components`;
- every individual Component;
- hidden Level when redundant;
- valid Level choices when non-redundant;
- no stale invalid Level after Component change.

---

# 16. Browser / Visual UAT Matrix

Test all relevant pages at:

| Width | Purpose |
|---:|---|
| 1440 | large desktop |
| 1366 | common office laptop |
| 768 | tablet/narrow desktop |
| 375 | mobile |
| 320 | minimum narrow target |

## Search

Verify:

- System dropdown does not clip/collide.
- Edition list is visually calm.
- Current/Archived badges remain readable.
- release labels are human-readable.
- result total is truthful.
- Level is contextually correct.
- PTSCS/PSCrCS do not show redundant Level controls.

## PSOC + PSIC

Verify:

- side-by-side desktop;
- stacked mobile;
- independent search fields;
- no state leakage;
- clear occupation vs industry explanation.


## PSCC

Verify:

- Section / Chapter / Heading context is visible;
- detailed commodity rows do not look identical to structural descriptor rows;
- leading hierarchy dashes are not used as the primary visual hierarchy;
- 2022 PSCC code and Description are the primary result content;
- Unit of Quantity, 2019 PSCC, and AHTN 2022 appear as secondary metadata;
- breadcrumb/drill-down is readable on mobile;
- a blank-query browse does not materialize all 26,000+ rows at once;
- result total uses the truthful count contract from W1-A.

## Compare Editions

Verify:

- Relationship tooltip works with mouse, keyboard, and touch.
- table remains usable horizontally/vertically.
- correspondence rows unchanged.

## RM Assistant

Even if RM is disabled during deterministic UAT:

- tab layout remains intact;
- composer does not break at 375/320;
- no CSS changes from W1-C/W1-E damage RM.

---

# 17. RM Testing Sequence

RM testing should be split into two phases.

## Phase A — Engineering smoke test

May be run before or during UI refinement.

Purpose:

- provider configuration works;
- model/client initializes;
- tools execute;
- grounding rule works;
- PSOC vs PSIC distinction is preserved;
- sessions remain isolated.

This is not the formal acceptance gate.

## Phase B — Formal RM UAT

Run **after the refined UI is republished to staging**.

Include:

- existing 12-case evaluation;
- English;
- Filipino;
- Cebuano;
- mixed-language probes;
- PSOC vs PSIC distinction;
- PSCC vs PSCCS routing;
- PTSCS component reasoning;
- PSCrCS component reasoning;
- PSIC correspondence questions;
- no-code-without-retrieval grounding;
- multi-session isolation.

Formal RM UAT is a production gate.

---

# 18. Full Regression Gate

After targeted tests and browser structural checks:

```powershell
Rscript scripts/run_tests.R
```

The previous verified baseline before this refinement was **2151 passing tests**.

The pass count may increase.

Gate:

```text
FAIL 0
WARN 0
SKIP 0
```

Any reduction in test count must be explained.

Then:

```powershell
Rscript -e "renv::status()"
```

Expected:

```text
No issues found -- the project is in a consistent state.
```

If dependencies change, regenerate:

```powershell
Rscript -e "rsconnect::writeManifest()"
```

Do not regenerate the manifest merely because CSS/UI code changed if dependencies did not change, unless the staging workflow explicitly requires a refresh.

---

# 19. Git / Staging Workflow

After implementation and all gates:

```text
feature/pre-staging-hardening
        │
        ├── UI refinement commits
        │
        ├── full test gate
        │
        └── new immutable staging tag
```

Suggested commit separation:

```text
fix: correct search result count semantics
feat: refine composite classification filters
feat: add independent PSOC and PSIC search
fix: improve responsive filter dropdown behavior
feat: clarify correspondence relationship terminology
style: refine edition and release selector
```

Consolidation into fewer commits is acceptable if the changes are tightly coupled.

After the final passing commit:

```powershell
git push
```

Create the next staging tag, e.g.:

```powershell
git tag -a pre-staging-v4 -m "Staging UI refinement candidate: all tests passing"
git push origin pre-staging-v4
```

Do not move older tags.

In Posit Connect Cloud:

- keep repository: `autravail4f4b4d/pcas_yv`;
- keep branch: `feature/pre-staging-hardening`;
- keep automatic publish on push: OFF;
- manually **Republish** after the new branch commit is pushed.

---

# 20. Definition of Done

This refinement is complete only when all of the following are true:

- [ ] Relationship tooltip is implemented and accessible.
- [ ] PSOC and PSIC have independent search fields and state.
- [ ] PTSCS Component/Level semantics are audited.
- [ ] PSCrCS Component/Level semantics are audited.
- [ ] Redundant Level controls are hidden.
- [ ] Non-redundant Level values are human-readable and component-aware.
- [ ] System dropdown no longer collides/clips on narrow widths.
- [ ] Result count reports true matches rather than the 200-row rendering cap.
- [ ] Edition/Release rows are visually simplified.
- [ ] Raw release IDs are humanized in the UI.
- [ ] Current/Archived remains explicit text.
- [ ] PSCC source-form hierarchy is preserved in the normalized/display model.
- [ ] PSCC Search distinguishes structural nodes from detailed commodity items.
- [ ] PSCC result details expose Unit of Quantity, 2019 PSCC, and AHTN 2022 as secondary metadata.
- [ ] PSCC codes remain strings with leading zeroes and punctuation preserved.
- [ ] PSCC cross-references are not treated as hierarchy levels.
- [ ] PSCC and PSCCS remain independent.
- [ ] Full targeted test set passes.
- [ ] Full regression suite has 0 fail / 0 warn / 0 skip.
- [ ] `renv::status()` is clean.
- [ ] Hosted staging is manually republished.
- [ ] Human visual UAT passes at 1440/1366/768/375/320.
- [ ] RM engineering smoke test passes.
- [ ] Formal RM UAT passes before production.
- [ ] No merge to `main` occurs before staging gates pass.

---

# 21. Claude Code Orchestrator Prompt

Use the following as the top-level implementation instruction.

> Implement `POST_CONNECT_STAGING_UI_REFINEMENT_GRAPH.md` on `feature/pre-staging-hardening` using graph engineering.
>
> **Execution model**
>
> 1. Run W0 first as a bounded audit. Produce an owner-file/function map and inspect PTSCS/PSCrCS `component × level` cardinality.
> 2. After W0, execute W1-A through W1-G in parallel where file ownership does not conflict.
> 3. Enforce single-writer ownership for shared files, especially global CSS and shared UI helpers.
> 4. Converge in W2 only after every parallel workstream has passed its targeted tests.
> 5. Run targeted integration tests, accessibility/DOM checks, then the full regression suite.
> 6. Perform browser UAT at 1440, 1366, 768, 375, and 320 px.
> 7. Do not deploy, merge, tag, or commit automatically.
>
> **Token-efficiency rules**
>
> - Search first; read only owner files/functions.
> - Do not repeatedly scan the whole repository.
> - Do not provide full project context to every parallel worker.
> - Give each worker only its scope, owner files, relevant tests, and frozen contracts.
> - Use targeted tests before the full test suite.
> - Maximum three repair loops per failing acceptance criterion.
> - Do not regenerate unrelated data artifacts.
> - Do not reformat unrelated files.
>
> **Frozen behavior**
>
> Do not change canonical classification content, correspondence mappings/provenance/confidence, curated PSOC mappings, RM grounding behavior, five-tab navigation, or Git/deployment configuration unless explicitly required by the specification.
>
> **Final report**
>
> Report:
>
> - W0 owner map;
> - PTSCS and PSCrCS component-level audit results;
> - files changed by workstream;
> - exact result-count contract implemented;
> - PSOC/PSIC independence behavior;
> - responsive dropdown fix;
> - Edition/Release rendering changes;
> - tooltip behavior;
> - targeted test results;
> - full regression result;
> - browser UAT matrix;
> - any remaining staging blockers.
>
> Stop before commit, tag, merge, or deployment.

---

# 22. Recommended Execution Order

The most efficient critical path is:

```text
W0 audit
   ↓
┌──────────────┬──────────────┬──────────────┐
W1-A           W1-B           W1-C
counts         composite      PSOC+PSIC
│              │              │
├──────────────┼──────────────┤
W1-D           W1-E           W1-F           W1-G
release        dropdown       tooltip         PSCC source form
└──────────────┴──────────────┴───────────────┘
   ↓
W2 convergence
   ↓
targeted integration tests
   ↓
full regression
   ↓
browser UAT
   ↓
push + new staging tag
   ↓
manual Connect Cloud republish
   ↓
formal RM UAT
   ↓
production decision
```

This keeps the critical path short, minimizes repeated repository reads, and isolates independent UI changes so they can be implemented concurrently without sacrificing contract control.

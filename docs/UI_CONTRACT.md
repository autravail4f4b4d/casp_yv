# UI Contract — PSA Statistical Classifications Search

This document is the stable interface between the functional application
(this build) and the follow-up Claude Design visual pass. It describes what
Claude Design may change freely and what it must not change without going
back through the classification/search/version service layer.

## 1. Application purpose

A read-only search and browse tool over Philippine Statistics Authority
(PSA) statistical classifications: PSGC, PSIC (including PSIC Revision 5 /
"2026 PSIC"), PSOC, PSCED, PCOICOP, PCPC, and PSCCS. A user picks a
classification system and edition/release, optionally narrows to a
hierarchy level, searches by code or keyword (or leaves the query blank to
browse), inspects a result's full detail, and can always see whether that
edition is PSA's current one or an archived reference.

## 2. User flows

1. **Browse a system/edition.** Pick a classification system → an
   edition/release is pre-selected (PSA's current one where applicable) →
   optionally pick a level → the results table shows that level's entries
   (blank query = browse, per spec section 5.2).
2. **Search within a system/edition.** Type a code or keyword into the
   search box → results re-rank deterministically (exact code, code
   prefix, exact label, label prefix, label contains, description
   contains) → optionally narrow by level.
3. **Inspect a result.** Click a row in the results table → the "Selected
   entry" card shows its code, label, description, system, edition, level,
   current/archived status, and PSA source link.
4. **Compare current vs. archived.** Switch a system's edition selector
   (e.g. PSIC "2026" ↔ "2019") → the same code/label space is re-queried
   under the other edition, with its own status badge — an archived
   edition is never relabeled as current, and switching editions never
   silently mixes rows from two editions in one result set.
5. **Check provenance.** Open "About / Data Sources" → see every system's
   issuing authority/source URL and the full PSIC Revision 5 ingestion
   provenance (source workbook URL, retrieval date, SHA-256, validated
   structural counts).

## 3. Screen/view inventory

| Screen | Status |
|---|---|
| Search | Implemented — also serves as Browse (spec section 5.2 chose to combine them into one screen) |
| Browse/Archive | Combined into the Search screen; edition selector + level selector + blank-query browse together satisfy this |
| Dual Search | Implemented as a separate nav panel — one query, independent PSOC (occupations) + PSIC (industries) result panels |
| Compare PSIC Editions | Implemented as a separate nav panel — bidirectional PSIC 2019 ↔ Revision 5 (2026) correspondence explorer |
| About/Data Sources | Implemented as a separate nav panel |

All four nav panels live under one `bslib::page_navbar(id = "main_nav", ...)`
— `input$main_nav` is a real Shiny input holding the active tab's `value`
(`"search"` / `"dual_search"` / `"correspondence"` / `"about"`). See the
implementation note under section 4 for why this exists and why every
secondary-tab output is gated on it.

## 4. Stable Shiny input/output IDs

Claude Design may restyle any element carrying these IDs, but must not
rename, remove, or repurpose the IDs themselves without updating `app.R`'s
server logic in the same change.

| ID | Type | Meaning |
|---|---|---|
| `classification_system` | input (select) | Selected system id (`psgc`, `psic`, `psoc`, `psced`, `pcoicop`, `pcpc`, `psccs`) |
| `classification_version` | input (select) | Selected edition/release id for the current system |
| `classification_level` | input (select) | Selected hierarchy level id, or `""` (the "All levels" sentinel, `ALL_LEVELS_VALUE` in `app.R`) |
| `classification_query` | input (text) | Free-text search query; blank = browse |
| `classification_results` | output (DT table) | Results table; row selection drives the detail card |
| `selected_entry` | output (uiOutput) | The "Selected entry" detail card body |
| `main_nav` | input (implicit, from `page_navbar(id = "main_nav")`) | The active tab's value: `"search"` / `"dual_search"` / `"correspondence"` / `"about"` |
| `sources_panel` | output (uiOutput) | The About/Data Sources panel body |
| `dual_search_query` | input (text) | Shared query searched against both PSOC and PSIC |
| `dual_search_psoc_version` | input (select) | PSOC edition for the dual-search panel (default: current, "2022") |
| `dual_search_psic_version` | input (select) | PSIC edition for the dual-search panel (default: current, "2026") |
| `dual_search_psoc_results` | output (DT table) | Occupations (PSOC) result panel |
| `dual_search_psic_results` | output (DT table) | Industries (PSIC) result panel |
| `dual_search_psoc_state` | output (uiOutput) | Error / "No results." message for the PSOC panel, independent of the PSIC panel |
| `dual_search_psic_state` | output (uiOutput) | Error / "No results." message for the PSIC panel, independent of the PSOC panel |
| `correspondence_direction` | input (select) | `"2019-2026"` or `"2026-2019"` — which way the correspondence lookup runs |
| `correspondence_query` | input (text) | Code or title fragment to search within the correspondence artifact; blank = browse |
| `correspondence_results` | output (DT table) | One row per relationship (a split/merge appears as multiple rows); row selection drives the detail panel |
| `correspondence_detail` | output (uiOutput) | Full relationship detail: source/target entries, relation type, provenance, confidence, evidence, and the statistical-safety warning when relevant |

**Implementation note for whoever next edits `app.R` — the `input$main_nav`
gate pattern:** every output outside the default "Search" tab (`sources_panel`,
both dual-search result/state pairs, and both correspondence outputs) is
built with two things together, not one or the other:

1. `req(input$main_nav == "<that tab's value>")` as the **first line** of
   the render function.
2. `outputOptions(output, "<id>", suspendWhenHidden = FALSE)`.

Do not drop either half. Relying only on Shiny's own implicit
suspend-when-hidden/resume-on-tab-shown behavior (i.e. leaving outputs at
their default and never touching `outputOptions`) was tested and found
**unreliable** in this app — both a plain `renderUI` with no reactive
inputs (it simply never got a first trigger to resume) and a `DT::renderDT`
table (it sometimes never received the tab-shown resume signal at all,
leaving it permanently blank) failed intermittently depending on exactly
how the tab became visible. Conversely, forcing `suspendWhenHidden = FALSE`
**without** the `req(input$main_nav == ...)` gate is actively harmful for
any `DT::renderDT` output: DataTables initializes its column-width layout
at the moment the widget is built, and if that happens while the
container is still `display:none` (tab hidden), the widget freezes at a
broken zero-width layout that **never recovers**, even after the tab
becomes visible and the underlying data later changes — this was verified
directly via server-side debug logging showing correct, non-empty data
being computed while the client still rendered nothing. The gate-plus-
force-active combination is what makes both halves safe: the gate stops
the DT widget from ever being built while hidden, and forcing the output
active means it still computes (and is ready) the instant `input$main_nav`
switches to that tab's value, without depending on the flaky implicit
mechanism at all.

## 5. Conceptual components

`AppHeader`, `ClassificationSelector`, `VersionSelector`, `LevelSelector`,
`SearchBox`, `SearchResults`, `ClassificationDetail`, `ArchiveBadge`,
`SourceAttribution`, `AppFooter` — these map onto the current markup as
follows (all in `R/ui/*.R`, none of it Shiny-reactive logic):

- `AppHeader` → `page_navbar(title = ...)` in `app.R`
- `ClassificationSelector`/`VersionSelector`/`LevelSelector`/`SearchBox` →
  the `sidebar()` contents in `search_ui()` (`R/ui/ui_search.R`)
- `SearchResults` → the `DT::DTOutput("classification_results")` card
- `ClassificationDetail` → `entry_detail_ui()` (`R/ui/ui_details.R`)
- `ArchiveBadge` → `status_badge()` (`R/ui/ui_details.R`) — a plain
  Bootstrap `badge` span, no custom CSS
- `SourceAttribution` → the source line + link inside `entry_detail_ui()`,
  and the systems table in `sources_ui()` (`R/ui/ui_sources.R`)
- `AppFooter` → the `footer =` argument of `page_navbar()` in `app.R`

## 6. Service functions consumed by each view

Defined in `R/repository.R` (integration layer), `R/registry.R`, and
`R/search.R`. The UI never calls an adapter directly.

- Search screen: `classification_registry()`, `classification_versions()`,
  `classification_levels()`, `search_classification()`,
  `get_classification_entry()`* (*not currently wired to a click-to-fetch
  path — the detail card currently reads the already-fetched row out of
  the results reactive by row index, which is cheaper than a second
  lookup; `get_classification_entry()` exists for any future deep-link/
  direct-code-lookup feature).
- About/Data Sources screen: `classification_registry()`.
- Dual Search screen: `classification_versions()`,
  `search_parallel_classifications()` (`R/parallel_search.R`, which itself
  calls `search_classification()` once per system — no separate ranking
  logic).
- Compare PSIC Editions screen: `search_psic_correspondence()`,
  `get_psic_correspondence()` (`R/correspondence/service.R`).

## 7. Result object schema

Every function above returns (or operates on) the canonical tibble defined
in `R/schema.R`, `CLASSIFICATION_SCHEMA_COLUMNS`:

```
system, version, level, code, label, description, parent_code,
status, source, source_url
```

All columns are character (never numeric — codes keep leading zeros).
`status` is exactly `"current"` or `"archived"`. `description`/`parent_code`
may be `NA`.

## 8. States

| State | How it's shown |
|---|---|
| Initial | First system in the registry pre-selected, its current edition pre-selected, "All levels", blank query → results table shows that edition's browse listing immediately |
| Loading | `validate(need(...))` shows "Loading edition..." in the results table area during the brief window between switching a system and its version-choice update landing (guards against querying a version that hasn't been validated against the new system yet) |
| Results | Results table populated, "Selected entry" shows the placeholder prompt until a row is clicked |
| No results | Results table renders with zero rows (DT's own "No matching records found" — no custom empty-state copy was added; this is a reasonable place for Claude Design to add friendlier empty-state text) |
| Error | Unsupported system/version/level raise an R error with a message that names the available choices (see `R/repository.R`); because every input on this screen is populated *from* the registry/adapters, a user can only reach this by a race during a version/level transition, which `validate(need(...))` already covers for the version case |
| Archived | `status_badge()` renders a grey/secondary "Archived reference" badge |
| Current | `status_badge()` renders a green "Current" badge |

### Dual Search states (per system, independently — see section 14)

| State | How it's shown |
|---|---|
| Initial | Both panels browse their current edition (PSOC 2022 / PSIC 2026) on a blank query, exactly like the Search screen's initial state |
| results_both | Both panels populated |
| results_psoc_only / results_psic_only | One panel has rows, the other shows its own "No results." message (`dual_search_{psoc,psic}_state`) — the populated panel is never affected by the other's emptiness |
| no_results | Both panels show "No results." independently |
| error_psoc / error_psic | That panel's state output shows `"Error: <message>"` in red; the other panel renders normally from its own independent `search_classification()` call |

### Correspondence states (see section 15)

| State | How it's shown |
|---|---|
| one-to-one | One results row; detail panel shows one source + one target with relation_type "unchanged" or "renamed" |
| split / merged / complex | Multiple results rows sharing a `from_code` (split) or `to_code` (merged); each row's detail view includes the statistical-safety warning inline |
| no match | `to_code` is `NA` (relation_type "discontinued") or `from_code` is `NA` (relation_type "new"); detail panel shows an explicit "(no prior counterpart...)" / "(no related category...)" message, never a blank or fabricated code |
| low confidence | `confidence_badge()` renders a red/danger "Low" badge — still shown, never hidden or filtered out by default |
| official / derived / suggested | `provenance_badge()` renders green/blue/yellow respectively; see section 15 for why no row is currently `official` |
| reverse lookup | Switching `correspondence_direction` to `"2026-2019"` re-queries the same artifact in the other direction via the same `get_psic_correspondence()`/`search_psic_correspondence()` functions |

## 9. Responsive requirements

`bslib::page_navbar` + `layout_sidebar` are responsive by default
(Bootstrap 5 grid; the sidebar collapses to a toggleable off-canvas panel
on narrow viewports — the "Toggle sidebar" button is Bootstrap/bslib
default behavior, not custom code). No fixed pixel widths were introduced
outside the sidebar's default width. Verified at a 375px-wide viewport
that the layout remains usable (sidebar collapses behind the toggle,
results table scrolls horizontally within its own container rather than
the page body scrolling horizontally).

## 10. Accessibility requirements

- All form inputs have visible `<label>`s (via `shiny::selectInput`/
  `textInput`'s built-in label rendering) — do not switch to placeholder-
  only labels.
- The detail card uses a semantic `<dl>`/`<dt>`/`<dd>` structure, not
  bare `<div>`s, so screen readers announce field/value pairs correctly.
- External source links carry `rel="noopener"` and open in a new tab
  (`target="_blank"`) — if Claude Design changes link behavior, keep
  `rel="noopener"` for any link that stays `target="_blank"`.
- Status is conveyed through text ("Current" / "Archived reference"), not
  color alone, inside `status_badge()` — preserve the text label if
  restyling the badge.
- No WCAG formal audit was performed (explicitly deferred per spec section
  26); the above are baseline practices only.

## 11. What Claude Design may change freely

- Typography, color, spacing, visual hierarchy, card treatments,
  navigation styling, responsive layout *details* (not the underlying
  sidebar/card structure's existence), icons, microinteractions, component
  appearance.
- `www/app.css` in full.
- The markup inside `R/ui/*.R` and `app.R`'s `ui <- ...` block, as long as
  every ID in section 4 above still exists and is still fed by the same
  server-side reactive (i.e. restyle `search_ui()`'s sidebar freely; do not
  remove `classification_system`/`classification_version`/
  `classification_level`/`classification_query`).

## 12. What Claude Design must not change without backend review

- `R/schema.R`, `R/registry.R`, `R/repository.R`, `R/search.R`,
  `R/parallel_search.R`, `R/correspondence/*.R`, `R/adapters/*.R`,
  `scripts/build_psic_2026.R`, `scripts/build_psoc_2022.R`,
  `scripts/build_psic_correspondence.R`, anything under `data/` or
  `data-raw/`, and every file under `tests/`.
- The ranking order in `R/search.R` (exact code → code prefix → exact
  label → label prefix → label contains → description contains) — this is
  the ONLY ranking engine; dual search reuses it verbatim, it does not
  have its own.
- The archive/current status semantics (`"current"`/`"archived"` are the
  only two legal values; PSIC 2019 and PSOC 2012 are always archived,
  PSIC 2026 and PSOC 2022 are always current, for as long as that reflects
  PSA's actual position).
- The correspondence provenance/confidence vocabulary
  (`official`/`derived`/`suggested`; `high`/`moderate`/`low`) and the rule
  that this codebase's own deterministic matching logic must never label a
  row `official` (see `docs/CORRESPONDENCE_SOURCES.md`).
- The `CORRESPONDENCE_STATISTICAL_WARNING` text (`R/correspondence/schema.R`)
  and the rule that it must always appear alongside any split/merged/
  complex relationship — this is a statistical-safety requirement (spec
  section 19), not decorative copy.

## 13. PSOC version states

```text
2022 — current   ("2022 Updates to the 2012 PSOC")
2012 — archived  (via phscs)
```

Both are fully queryable through the same `classification_versions("psoc")`
/ `get_classification("psoc", version, ...)` contract already used for
every other system — the Search screen requires no special-casing to
support this; switching `classification_version` between `"2022"` and
`"2012"` behaves exactly like switching PSIC between `"2026"` and `"2019"`.

## 14. Dual-search contract

- Stable IDs: see section 4 (`dual_search_query`,
  `dual_search_psoc_version`, `dual_search_psic_version`,
  `dual_search_psoc_results`, `dual_search_psic_results`,
  `dual_search_psoc_state`, `dual_search_psic_state`).
- Service function: `search_parallel_classifications(query, systems,
  versions, levels, limit_per_system)` (`R/parallel_search.R`) — a thin
  orchestrator that calls `search_classification()` once per system inside
  its own `tryCatch`, so one system's failure or empty result never
  affects the other. It adds no ranking logic of its own.
- PSOC version selector and PSIC version selector are independent —
  either can be switched to an archived edition without affecting the
  other.
- States, all independently addressable per system (see
  `res$results[[system]]` / `res$errors[[system]]` in
  `search_parallel_classifications()`'s return shape):
  - **results** — a canonical result tibble, possibly zero rows (a genuine
    no-match, not an error)
  - **error** — that system's `search_classification()` call raised a
    validation error (e.g. an unsupported version); the OTHER system's
    panel is entirely unaffected and still renders normally
- Semantic labels are mandatory, not optional styling: "Occupations —
  PSOC" and "Industries — PSIC" (`PARALLEL_SEARCH_SYSTEM_LABELS` in
  `R/parallel_search.R`) must always appear on their respective panels.
  Claude Design may restyle the presentation of this distinction but must
  never remove it or imply the two codes are interchangeable — a PSOC code
  and a PSIC code describe different things (what a person does vs. what
  an establishment does) and are never equivalents.

## 15. Correspondence contract

- Stable IDs: see section 4 (`correspondence_direction`,
  `correspondence_query`, `correspondence_results`,
  `correspondence_detail`).
- Service functions (`R/correspondence/service.R`):
  `get_psic_correspondence(code, from_version, to_version)` and
  `search_psic_correspondence(query, from_version, to_version, limit)`,
  reading the offline artifact `data/psic_2019_to_2026_correspondence.rds`
  (built by `scripts/build_psic_correspondence.R`). Both directions
  (2019→2026 and 2026→2019) are fully supported by the same functions —
  there is no separate "reverse lookup" function.
- Result shape (`CORRESPONDENCE_SCHEMA_COLUMNS` reshaped to caller-facing
  `from_*`/`to_*` names by the service layer): `from_system`,
  `from_version`, `from_code`, `from_level`, `from_label`, `to_system`,
  `to_version`, `to_code`, `to_level`, `to_label`, `relation_type`,
  `provenance`, `confidence`, `confidence_score`, `method`, `evidence`,
  `review_status`, `notes`.
- Cardinality: one row per relationship edge. A 1→N split or N→1 merge
  appears as multiple rows sharing the same `from_code` (split) or the
  same `to_code` (merge) — never collapsed into one row. A "new" (0→1)
  row has `from_code = NA`; a "discontinued" (1→0) row has `to_code = NA`;
  both are rendered with an explicit "(no prior counterpart...)" /
  "(no related category...)" message by `correspondence_detail_ui()`
  rather than showing a blank or a fabricated code.
- Provenance (`official` / `derived` / `suggested`) and confidence
  (`high` / `moderate` / `low`) are always shown together, never just one.
  As of this build, **no row in the shipped artifact is `official`** — see
  `docs/CORRESPONDENCE_SOURCES.md` for the source audit that determined no
  official PSA PSIC 2019↔Revision 5 crosswalk currently exists; every row
  is `derived` (deterministic code/hierarchy continuity, or a corroborated
  UN ISIC Rev.4↔Rev.5 bridge) or `suggested` (label-similarity only). If a
  future rebuild ever introduces an `official` row, it must be backed by an
  actual cited PSA document in that same source-audit file — never
  promoted from `suggested`/`derived` on confidence alone.
- The statistical-safety warning
  (`CORRESPONDENCE_STATISTICAL_WARNING`, defined once in
  `R/correspondence/schema.R` and reused verbatim by the UI) must appear:
  (a) always, in the footer of the Compare PSIC Editions screen, and
  (b) inline in the relationship detail panel specifically whenever
  `relation_type` is `split`, `merged`, or `complex` — these are exactly
  the cardinalities where a naive reader might otherwise assume a
  statistical value could be divided or summed across the mapped
  categories, which this tool never does and must never appear to endorse.
- Claude Design must not have to invent any of the above statistical or
  provenance semantics — restyle the badges, cards, and arrows freely, but
  the underlying facts they display come entirely from the service layer.

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
| About/Data Sources | Implemented as a separate nav panel |

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
| `sources_panel` | output (uiOutput) | The About/Data Sources panel body (`suspendWhenHidden = FALSE` — see note below) |

**Note for whoever next edits `app.R`:** `sources_panel` has no reactive
inputs of its own, and lives in a nav panel that isn't active on load —
Shiny suspends outputs inside inactive tabs by default and only resumes
them on a tab-shown event with a matching reactive dependency to
re-trigger, so without `outputOptions(output, "sources_panel",
suspendWhenHidden = FALSE)` this panel renders once, immediately at
session start, permanently — never leave `suspendWhenHidden` at its
default for a static `uiOutput` inside a non-default tab.

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
  `R/adapters/*.R`, `scripts/build_psic_2026.R`, anything under `data/` or
  `data-raw/`, and every file under `tests/`.
- The ranking order in `R/search.R` (exact code → code prefix → exact
  label → label prefix → label contains → description contains).
- The archive/current status semantics (`"current"`/`"archived"` are the
  only two legal values; PSIC 2019 is always archived, PSIC 2026 is always
  current, for as long as that reflects PSA's actual position).

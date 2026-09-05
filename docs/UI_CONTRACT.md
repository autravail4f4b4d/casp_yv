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

> **Visual system:** the unified design approved in
> `unified-app-primary.dc.html` / `HANDOFF-CLAUDE-CODE.md` is implemented.
> Visible tab labels changed; `main_nav` values did not. See §16 for the
> label mapping and §17 for the visual system.

| Screen | Status |
|---|---|
| Search | Implemented — also serves as Browse (spec section 5.2 chose to combine them into one screen) |
| Browse/Archive | Combined into the Search screen; edition selector + level selector + blank-query browse together satisfy this |
| Dual Search | Implemented as a separate nav panel — one query, independent PSOC (occupations) + PSIC (industries) result panels |
| Compare PSIC Editions | Implemented as a separate nav panel — bidirectional PSIC 2019 ↔ Revision 5 (2026) correspondence explorer |
| RM Assistant | **No longer a nav panel — superseded by §23.8.** A global contextual panel (sidecar / drawer / sheet) mounted once per page and opened from the header and from record-level launchers. See `docs/ASSISTANT_CONTRACT.md` §16 |
| About/Data Sources | Implemented as a separate nav panel |

**Four** nav panels live under one `bslib::page_navbar(id = "main_nav", ...)`
— `input$main_nav` is a real Shiny input holding the active tab's `value`
(`"search"` / `"dual_search"` / `"correspondence"` / `"about"`). See the
implementation note under section 4 for why this exists and why every
secondary-tab output is gated on it. `"rm_assistant"` is no longer one of
those values.

**The RM panel needs no such gating**, and deliberately so: it declares no
Shiny outputs that drive the chat. The chat is a custom element driven by
custom messages (delivered whether or not the panel is open) and its
greeting is present in the initial HTML rather than pushed from the server,
so it needs neither a `req(input$main_nav == ...)` gate nor
`outputOptions(suspendWhenHidden = FALSE)`. Its two `renderUI` outputs (the
attached-context chips and the Search screen's record-level launcher) are
forced always-on for the same reason every other always-visible output in
this app is.

## 4. Stable Shiny input/output IDs

Claude Design may restyle any element carrying these IDs, but must not
rename, remove, or repurpose the IDs themselves without updating `app.R`'s
server logic in the same change.

| ID | Type | Meaning |
|---|---|---|
| `classification_system` | input (select) | Selected system id. Ten registered: `psgc`, `psic`, `psoc`, `psced`, `pcoicop`, `pcpc`, `psccs`, `pscc`, `ptscs`, `pscrcs`. Choices are built from `classification_registry()`, never hard-coded |
| `classification_version` | input (**radioButtons**) | Selected edition/release id for the current system. Rendered as a radio group so every edition and its Current/Archived status is visible at once — this is where Browse/Archive lives, so archived editions must not be hidden inside a closed dropdown. The ID and the value it yields are unchanged; only the widget type differs, so `app.R` updates it with `updateRadioButtons()` (rich `choiceNames` carrying the status badge, plain `choiceValues`) rather than `updateSelectInput()` |
| `classification_level` | input (select) | Selected hierarchy level id, or `ALL_LEVELS_VALUE` (`"__all_levels__"`) meaning no level restriction. **The sentinel is deliberately non-empty**: an empty-string value makes selectize render the entry as greyed placeholder text rather than a chosen option, which human UAT read as an unfilled control. `app.R` translates it (and any level not valid for the current system+version) back to `NULL` before it reaches a service, so the repository never receives a literal `"All levels"` |
| `classification_component` | input (select) | Component id for composite systems, or `ALL_COMPONENTS_VALUE` (`"__all_components__"`). Wrapped in a `conditionalPanel` on `output.classification_is_composite`, so it appears only for systems the registry marks composite |
| `classification_is_composite` | output (reactive flag) | Drives the Component control's visibility. Derived from `classification_components()`, so a system whose ingestion failed and never registered can never surface the control |
| `classification_query` | input (text) | Free-text search query; blank = browse |
| `classification_results` | output (DT table) | Results table; row selection drives the detail card |
| `selected_entry` | output (uiOutput) | The "Selected entry" detail card body |
| `main_nav` | input (implicit, from `page_navbar(id = "main_nav")`) | The active tab's value: `"search"` / `"dual_search"` / `"correspondence"` / `"about"`. `"rm_assistant"` was removed when RM became a global panel (§23.2) |
| `classification_result_count` | output (uiOutput) | Result count above the results table; reads the same reactive as the table so the two can never disagree |
| `sources_panel` | output (uiOutput) | The About/Data Sources panel body |
| `dual_search_psoc_query` | input (text) | PSOC query. **Independent of PSIC** (UI-POST-02): typing here must never change any PSIC state |
| `dual_search_psic_query` | input (text) | PSIC query. Independent of PSOC in the same way |
| `dual_search_psoc_version` | input (select) | PSOC edition for the dual-search panel (default: current, "2022") |
| `dual_search_psic_version` | input (select) | PSIC edition for the dual-search panel (default: current, "2026") |
| `dual_search_psoc_results` | output (DT table) | Occupations (PSOC) result panel |
| `dual_search_psic_results` | output (DT table) | Industries (PSIC) result panel |
| `dual_search_psoc_count` | output (uiOutput) | PSOC result count for that panel only |
| `dual_search_psic_count` | output (uiOutput) | PSIC result count for that panel only |
| `dual_search_psoc_detail` | output (uiOutput) | PSOC selected-record detail; coexists with the PSIC detail |
| `dual_search_psic_detail` | output (uiOutput) | PSIC selected-record detail; coexists with the PSOC detail |
| `classification_level_is_informative` | output (reactive flag) | Drives the `conditionalPanel` around the Level control. FALSE when `level` merely restates `component` (UI-POST-03), in which case the control is hidden AND the level is forced to `NULL` server-side so a stale value cannot keep filtering |

**Removed in UI-POST-02:** `dual_search_query`, the single shared input that
searched both systems at once. It is gone deliberately — one input driving
both panels is precisely what blurred the PSOC/PSIC distinction. Do not
reintroduce a shared query control.
| `dual_search_psoc_state` | output (uiOutput) | Error / "No results." message for the PSOC panel, independent of the PSIC panel |
| `dual_search_psic_state` | output (uiOutput) | Error / "No results." message for the PSIC panel, independent of the PSOC panel |
| `correspondence_direction` | input (select) | `"2019-2026"` or `"2026-2019"` — which way the correspondence lookup runs |
| `correspondence_query` | input (text) | Code or title fragment to search within the correspondence artifact; blank = browse |
| `correspondence_results` | output (DT table) | One row per relationship (a split/merge appears as multiple rows); row selection drives the detail panel |
| `correspondence_detail` | output (uiOutput) | Full relationship detail: source/target entries, relation type, provenance, confidence, evidence, and the statistical-safety warning when relevant |
| `rm_assistant` | Shiny module id | The RM Assistant module namespace (stable; specified by the assistant spec) |
| `rm_assistant-chat` | shinychat chat element | The chat transcript + composer. Created by `shinychat::chat_mod_ui()`; driven by `shinychat::chat_mod_server()` |
| `rm_assistant-chat_user_input` | input (textarea) | The chat composer's value, set on submit |
| `rm_assistant-new_chat` | input (actionButton) | Clear / new chat. The server calls the module's `clear()`, which resets BOTH the transcript and the ellmer client's turn history |

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
- RM Assistant screen: `rm_assistant_status()`, `create_rm_chat_client()`
  (`R/assistant/assistant_client.R`), `rm_assistant_tools()`
  (`R/assistant/assistant_tools.R`), `RM_GREETING` / `RM_FOOTER_TEXT`
  (`R/assistant/assistant_prompt.R`), and `shinychat::chat_mod_server()`.
  The UI never constructs a chat client itself and never calls a
  classification adapter directly.

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

### RM Assistant states (see `docs/ASSISTANT_CONTRACT.md`)

| State | How it's shown |
|---|---|
| Initial | Static greeting beginning exactly **"Madayaw! I am RM."**, four starter suggestion chips, empty composer. Rendered from the initial HTML — **no model call and no server round-trip** is spent on the greeting |
| Streaming | shinychat streams the reply; the send button becomes a **"Stop generating"** cancel control (provided natively by shinychat, not hand-rolled) |
| Cancelled | User presses "Stop generating"; the partial reply stops |
| New chat | `rm_assistant-new_chat` clears the transcript AND the ellmer client's turn history, then the static greeting reappears — again with no model call |
| Unavailable | `rm_assistant_unavailable_ui(reason)` replaces the whole chat: "RM Assistant is temporarily unavailable" plus "You can still search and browse all classifications using the main application", and optionally a short non-technical reason. Decided once at startup from the deployment's provider configuration. Never renders a stack trace or provider error text |
| Coding answer | **Exactly one assistant message per coding turn**, containing only the deterministic rendering (code, label, level, coding role, edition, status, source, and the clarification question when there is one). No model prose is appended, so no second, contradictory message and no spontaneous language change follows a correct answer. See `docs/ASSISTANT_CONTRACT.md` §15 |
| Clarification with options | The deterministic question is rendered **once**, followed by its bounded option list. Replying `2`, `second`, `option 2`, `the latter`, or the option's own label selects that option; a reply the option set cannot interpret re-asks the same question unchanged |
| Clarification, bare qualifier | A single-word setting (`residential`, `private`, `hospital`, …) answering an open activity question narrows the question instead of producing a code. See `docs/ASSISTANT_CONTRACT.md` §14.4 |
| Explanation | Only when the user explicitly asks (`why?`, `explain this`, `what does this mean?`, `bakit?`). The model's text is appended as an extra message only after passing the response guard; codes, labels, status and clarification state are unchanged |
| Provider fails mid-stream | **Known limitation** — the transcript rolls back and the user's text is restored, but no explanation is shown. Documented in `docs/ASSISTANT_CONTRACT.md` §12 |

Responsive note specific to this panel: `shiny-chat-container` is a CSS
grid, and a grid item's default `min-width: auto` lets a wide child size the
column past its container. At 375px this produced a ~580px column inside a
~325px card, silently clipping the send button off-screen (it disappeared
from the accessibility tree entirely, making RM unusable on a phone). The
fix is a single rule in `www/app.css`:
`.rm-assistant-card shiny-chat-container { grid-template-columns: minmax(0, 1fr); }`.
**Keep it, or re-verify mobile reachability of the send button if you change
the chat layout.**

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
  `R/assistant/*.R`, `prompts/RM_SYSTEM_PROMPT.md`,
  `scripts/build_psic_2026.R`, `scripts/build_psoc_2022.R`,
  `scripts/build_psic_correspondence.R`,
  `scripts/build_assistant_assets.R`, anything under `data/` or
  `data-raw/`, and every file under `tests/`.
- The RM grounding rule and its three enforcement points (prompt, tool
  results, tests); the registered tool list and their result field sets;
  the fail-closed default of `RM_ASSISTANT_ENABLED`; and per-session chat
  client construction. See `docs/ASSISTANT_CONTRACT.md` §13.
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

- Stable IDs: see section 4 (`dual_search_psoc_query`,
  `dual_search_psic_query`, `dual_search_psoc_version`,
  `dual_search_psic_version`, `dual_search_psoc_results`,
  `dual_search_psic_results`, `dual_search_psoc_state`,
  `dual_search_psic_state`, `dual_search_psoc_count`,
  `dual_search_psic_count`, `dual_search_psoc_detail`,
  `dual_search_psic_detail`).
- **The two sides are independent (UI-POST-02).** Each owns its query,
  edition, count, table and selection. No PSIC output may read a PSOC input
  or vice versa. Clearing one side must leave the other intact, and both
  detail panels may be populated simultaneously. An occupation must never be
  used to infer an industry, or the reverse.
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
- Semantic labels are mandatory, not optional styling. As of UI-POST-02 the
  panel headings are **"PSOC — Occupation"** and **"PSIC — Industry"**, each
  with its explanatory line ("Describes what a person does." /
  "Describes the economic activity of the establishment or business."), as
  fixed by the refinement specification. These supersede the earlier
  "Occupations — PSOC" / "Industries — PSIC" wording;
  `PARALLEL_SEARCH_SYSTEM_LABELS` in `R/parallel_search.R` remains the label
  source for the parallel-search service and is unchanged.
  The headings must always appear on their respective panels.
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

## 16. Visible labels vs. `main_nav` values (unified UI milestone)

Presentation labels changed; navigation identities did **not**. Every
`req(input$main_nav == ...)` gate in `app.R` is unchanged, and every
bookmarkable value is stable.

| `main_nav` value | Visible label | Previous label |
|---|---|---|
| `search` | Search | Search |
| `dual_search` | PSOC + PSIC | Dual Search |
| `correspondence` | Compare Editions | Compare PSIC Editions |
| `about` | Sources | About / Data Sources |

`rm_assistant` was a fifth value in this table until the imported design
made RM a global panel rather than a destination (§23.2). The assistant's
own ids — the `rm_assistant` module namespace, `rm_assistant-chat`,
`rm_assistant-new_chat` — are unchanged.

Browse/Archive remains **not** a separate value — it is expressed inside
`search` by the edition control + level select + blank-query browse.

## 17. Visual system (unified UI milestone)

Implemented in `www/app.css` against the approved dark ("nocturne")
direction. Theme colours are set on `bslib::bs_theme()` in `app.R`
(`bg`/`fg`/`primary`/`card-bg`) so every Bootstrap component — form
controls, cards, tables, DT — inherits a coherent dark palette rather than
needing per-component overrides.

**Two colours carry meaning and are never decorative:**

- **accent** (teal) — current edition, verified result, active nav.
- **ochre** (`oklch(0.66 0.125 70)` line / `oklch(0.80 0.10 70)` text) —
  archived edition, caution, statistical-safety warning. Used as line,
  border and text only; **never as a background flood**.

Both always ship with visible text (`Current` / `Archived`), satisfying
§10's "status conveyed through text, not colour alone".

**Icons.** Phosphor, but **vendored locally** at `www/Phosphor.woff2` with
only the eleven glyphs the design uses declared in `app.css` — not loaded
from a CDN. A public government-facing deployment should not make a
third-party request per visitor or disclose visitor IPs to unpkg, and the
app must work on restricted networks. Every icon is paired with a visible
text label, so a failed font load degrades to readable text.

**Key metrics** (from the handoff): Search hero input `min-height: 56px` /
`font-size: 19px` / `padding-left: 46px`, max-width 820px centred; sidebar
260px; results/detail `1fr : 380px`. On mobile the hero drops to 50px/16px
— 16px is the iOS zoom-on-focus floor and must not be reduced.

**Breakpoints** — bslib/Bootstrap 5 defaults plus a 375px floor. No others
were invented. ≥992px desktop; 576–991px tablet (single-column Search body);
≤575px mobile (single column, hero shrinks, correspondence row stacks with
the arrow rotated, reserved Ask RM slots hidden).

**Mobile navigation.** bslib's collapsible top nav, restyled. This is the
fallback the handoff explicitly permits (§5) rather than the bottom tab
bar; it sets the same five `main_nav` values through the same mechanism,
and its links measure ~275×53px. The toggler is floored at 44×44px.

### Reserved "Ask RM" slots — SUPERSEDED, now activated

> **Superseded by §23.9.** This subsection described two inert,
> `aria-hidden` `<span class="psa-askrm-reserved">` placeholders that held
> layout space for controls that had not been wired yet, and set the
> conditions they had to meet when they were: real button semantics and
> AA-clearing text.
>
> Both conditions are now met. The placeholders are gone from the markup
> and their CSS is deleted; the two positions carry real `<button>`
> controls that open the global assistant panel with the record attached.
> See §23.9 for the launcher inventory and §23.12 for what "attached
> context" is and is not.

### Focus visibility

2px accent outline at 2px offset on every interactive element, via
`:focus-visible`. Marked `!important` because Bootstrap ships
`.form-control:focus { outline: 0 }`, which outranks a bare element
selector — a visible focus indicator is an accessibility requirement and
must not be silently removable by a component library's reset.

### Measured contrast (against `#0f1119`)

| Token | Ratio | Verdict |
|---|---|---|
| Body text | 16.29:1 | AAA |
| accent-300 | 11.95:1 | AAA |
| accent | 8.62:1 | AAA |
| Archived ochre text | 9.96:1 | AAA |
| Muted 62% / 55% | 6.74 / 5.51:1 | AA |
| Muted 45% | 4.08:1 | **fails AA — not used for content** |

The design's "~45% opacity" helper text measured 4.08:1, under AA for
normal-size text (13px is not "large"). It was raised to 55% wherever it
carries content — an intentional, documented divergence from the handoff's
exact opacity value, taken because the handoff also requires WCAG-conscious
states and accessibility wins the tie.

## 18. Pre-staging UI repairs (UI-01 … UI-05, META-01)

### UI-01 — global footer no longer overlays content

The footer was never `position: fixed` or `sticky`. The overlap came from
bslib's **fill page mode**: `page_navbar()` emits `body.bslib-page-fill`,
which pins the body to exactly `100vh` and lays its children out as a
column flexbox. `.tab-content` then received a fixed viewport-sized slice
while the active `.tab-pane`'s real content was taller, and because
`.tab-pane` keeps `overflow: visible` the surplus was painted outside its
own box — straight over the footer. The document did scroll, so content was
reachable, but rows, the DT info line and the focusable pagination controls
physically sat behind the footer band. Measured before the fix at 1440×900
on Search: footer 862–900px, last table row 1070–1120px, pagination
1175–1229px.

The fix opts the **page-level chain only** out of viewport-height filling,
so the app is an ordinary flowing document. Nothing is taken out of flow,
so nothing needs a reserved height; `min-height: 100vh` keeps the footer at
the bottom of short pages. The `html-fill-item` / `html-fill-container`
machinery *inside* panels — notably the RM assistant card and its chat
container — is deliberately untouched and still fills normally.

Verified `position: static`, zero overlap and zero horizontal overflow at
1440, 1366, 768, 375 and 320px.

### UI-02 — Sources is a card deck, not a scroll trap

Sources previously used fixed-height (`max-height: 620px; overflow-y:
auto`) prose panels — nested scrollbars inside an already-scrolling page —
with implementation paths dominating a public page. It is now one normal
page scroll: a registry-driven card deck, then supplemental edition
provenance cards, then a correspondence methodology card, then technical
implementation details.

**The deck is registry-driven and must stay that way.** It iterates
`classification_registry()`; there is no hard-coded list of systems. A
system that registers gets a card automatically, and a system whose
ingestion or validation failed never reaches the registry and so silently
gets no card. Long audit and technical material sits behind native
`<details>`/`<summary>` disclosures: keyboard-operable, correctly
represented in the accessibility tree, no JavaScript.

Verified: 13 cards (10 registered systems + PSIC Rev 5 + PSOC 2022 +
correspondence methodology), 8 disclosures all collapsed by default,
**zero nested scroll regions**, no horizontal overflow.

Nothing on this page overrides a registry value. `display_name` renders
verbatim — a UI-only alias papering over a wrong canonical value would hide
a defect rather than fix it.

### UI-03 — redundant results-table search removed

Every results grid now uses `dom = "tip"` rather than `"ftip"`. The `"f"`
is DataTables' own search box, which sat directly beneath the hero search
and filtered only already-returned rows — a different mental model from the
hero field, which queries the whole classification repository. Human UAT
found the pair confusing. Sorting, pagination and the info line are all
retained.

Applied to all three grids (Search, both PSOC + PSIC panels, Compare
Editions) because each sits under its own canonical app-level query field
and therefore duplicates it.

### UI-04 — "All levels" is a real default

See the `classification_level` row in §4. The sentinel is non-empty so the
option renders as genuinely selected, and it is translated to `NULL` before
reaching a service. Switching system or edition resets Level to All levels.

Verified UAT fixture: PSGC + `negros` + All levels returns matches at
**Reg, Prov and Bgy simultaneously** (4 results across three levels).

### UI-05 — Component control for composite systems

PTSCS and PSCrCS mint no codes of their own: they select codes out of
PSIC / CPC / PSOC and group them by component. Presenting those components
as hierarchy levels would misrepresent them, so they get a **separate
Component control**, shown only for systems the registry marks composite.
The ordinary Level control is never globally renamed.

The underlying source classification stays visible in results:
`search_classification_data()` now preserves adapter-supplied extra columns
(`component`, `major_category`, `source_system`, `source_version`,
`source_code`) after the canonical 10, instead of dropping them. Ordinary
systems have no extras and are unaffected.

### META-01 — PSCCS naming corrected canonically

`R/registry.R` now carries:

```
PSCC   Philippine Standard Commodity Classification                      (2022)
PSCCS  Philippine Standard Classification of Crime for Statistical Purposes (2018)
```

Fixed in the single authoritative metadata source, not aliased in the UI,
so the Search selector, Sources cards, detail panes and the RM registry
tool all correct at once. A regression test asserts both names
independently and asserts neither carries the other's wording.

## 19. Canonical schema: extra columns are permitted after the first ten

The contract is that the **first ten columns are exactly
`CLASSIFICATION_SCHEMA_COLUMNS`, in order**. Composite/thematic systems
legitimately append provenance columns after them, because for those
systems the underlying classification is part of the record's meaning.
Canonical consumers index by name and ignore extras, so this is an
extension rather than a relaxation — the ten canonical columns must still
all be present, in order, first.

## 20. Visual system — dark editorial "liquid glass" (UI refinement milestone)

Supersedes the palette and surface treatment described in §17 and in the
"Subtle Gradient" light pass that followed it. **Everything §17 says about
which meanings carry a treatment still holds** — status is never colour
alone, a classification relationship is never styled as an error, archived
is quiet rather than warned. Only the ground and the surfaces changed.

### 20.1 Stylesheet architecture and load order

Order is the architecture, not a preference: the whole system is built on
later-sheet-wins, so reordering these links silently restores light
surfaces or drops the motion opt-out.

```text
www/app.css        base rules — almost entirely token-driven
www/ui-tokens.css  RETARGETS app.css's tokens to the dark palette; display
                   and UI faces; global canvas; Bootstrap/DT ground
www/ui-dialog.css  shared dialog/drawer shell (UI-02/03/04/05)
www/ui-filters.css search sidebar + correspondence guidance (UI-01/04/05)
www/ui-glass.css   the .psa-liquid-glass primitive and its application to
                   the app's major surfaces; loaded after the two UI
                   sheets so it outranks their flat plates
www/ui-motion.css  transitions, and the reduced-motion escape LAST, so no
                   later sheet can re-enable animation
```

The dark palette is set on `bslib::bs_theme()` in `app.R`
(`bg`/`fg`/`primary`/`body-bg`/`card-bg`/`border-color`/link colours) for
the same reason §17 gives: Bootstrap, DT and selectize inherit the palette
rather than needing per-component overrides. `ui-tokens.css` re-asserts the
same values as CSS custom properties so a cached or partially recompiled
bundle can never leave a light plate behind a dark panel.

**Why no rewrite was needed.** `app.css`'s body resolves 200 `var()`
references against 6 raw colour literals, and `ui-dialog.css` /
`ui-filters.css` are fully tokenised. Retargeting the token layer therefore
re-themes the app without touching the UI-01…UI-05 rules.

### 20.2 Typography

```text
--font-display  'Instrument Serif', Georgia, 'Times New Roman', serif
--font-ui       Inter, ui-sans-serif, system-ui, -apple-system,
                BlinkMacSystemFont, 'Segoe UI', sans-serif
```

`Instrument Serif` is imported from Google Fonts and is the **only**
external visual dependency in the app. It is display/accent only — page
hero, major section headings, the navbar wordmark, italic emphasis. The
app must remain fully usable when that request is blocked, so the UI face
is never the imported one and every display use falls through to Georgia.

Classification **data** is never set in the display serif: codes, result
tables, filters, forms, buttons, RM transcript body copy and record
metadata stay in `--font-ui`. Because `app.css` routes its `--type-heading-*`
tokens through `--font-display`, those data surfaces are pinned back
explicitly in `ui-tokens.css`; a regression test asserts the pin list.

### 20.3 The liquid-glass primitive

`.psa-liquid-glass` — translucent fill, 4px backdrop blur, a masked 1.4px
luminous gradient ring in place of a drawn border, and a deep ambient drop
shadow. Two variants:

- `.psa-liquid-glass--flow` — `overflow: visible`. **Required** on any glass
  surface that opens a selectize menu or a bslib popover from inside
  itself, because the primitive clips. Omitting it reproduces the
  UI-POST-04 defect class (an overlay cut off at its container's edge).
- `.psa-liquid-glass--quiet` — flatter, ringless pane for glass nested
  inside glass, so the app never shows a boxed card inside a boxed card.

**Transparency is decorative and never load-bearing.** Functional text
takes its contrast from the token layer against the near-black canvas, so
removing the blur changes how the app looks and nothing about what it says.
Two fallbacks make that literal:

```css
@supports not ((backdrop-filter: blur(4px)) or (-webkit-backdrop-filter: blur(4px)))
@media (forced-colors: active)
```

Surfaces carrying the class: Search hero field, UI-01 filter sidebar,
shared dialog shell (UI-02/UI-03), UI-03 dual panels and comparison
columns, UI-04 correspondence inspector, UI-05 terminology disclosure, the
RM Assistant card, and the Sources card deck. The floating navbar shell
restates the same treatment inline, because its element is emitted by
`bslib` and this layer must not require markup it does not own.

### 20.4 Contrast

Every functional-text token clears WCAG AA (4.5:1) against `--psa-bg`
`#050505`, and the measured ratio is recorded beside each token in
`ui-tokens.css`. Two consequences worth stating, because both are easy to
undo by eye:

- `--psa-text-subtle` (`rgba(255,255,255,.40)`) measures **3.7:1** — AA for
  large text and non-text only. Functional copy uses `--psa-text-muted`
  (7.8:1). Rules, glyph strokes and decorative marks may use subtle.
- `--psa-plum` `#8f668f` measures **4.3:1**, just under AA, so it is a
  border/fill/glow value. Plum **text** uses `--psa-plum-text` `#c9a9c9`
  (9.7:1).

### 20.5 Motion

CSS only — no animation framework, no canvas, no WebGL, no video. Section
reveals are fade + ≤16px rise; dialogs are opacity plus a 0.98→1 scale;
large surfaces hover at ≤1.01; controls animate background alpha only.
Every reveal is declared with `both` fill, so honouring
`prefers-reduced-motion` lands on the visible frame and can never leave
content hidden.

### 20.6 Cascade hazard for future edits

`ui-glass.css` loads after `app.css` and `ui-filters.css`, and **a `@media`
block adds no specificity**. A plain rule in `ui-glass.css` therefore beats
an `app.css` mobile rule at every width. Any surface whose desktop plate is
restyled must restate its own responsive steps — the Search hero, the
Sources card padding and the UI-04 inspector all do, and a test asserts the
inspector's desktop plate stays scoped to `min-width: 992px` so the mobile
sheet geometry owned by `ui-filters.css` survives.

### 20.7 Release-order ownership (UI-01)

The edition/release radio group is built by `edition_choice_spec()`
(`R/ui/ui_search.R`) and **must not** be composed inline in `app.R`. Order
comes from `release_newest_first()` → `.release_effective_key()`, which
derives a numeric `year * 100 + month` key from the canonical release
identifier. It is not a lexical sort of display labels, and identifiers that
carry no recognisable year keep their repository position rather than being
guessed at.

Contract: **current first, then descending canonical release order**, with
CURRENT / ARCHIVED spelled out on every row. `choiceValues` stay raw
identifiers and `selected` stays the registry's current version, so the
ordering is presentation only and no search or retrieval semantics move
with it.

Two systems ship releases that share an effective period — `Q3_2025` and
`July_2025` both key to 202507, as do `Q2_2024` and `April_2024`. Ties are
broken by repository order. Tests therefore assert *non-increasing* keys
overall and *strictly decreasing* across distinct keys.

### 20.8 Dialog focus restoration (shared shell)

`psa_dialog_deps()` in `R/ui/ui_dialog.R` owns the ONLY focus-restoration
implementation in the app. Every dialog — hierarchy browse, PSOC details,
PSIC details, PSOC + PSIC comparison — is built by `psa_dialog_ui()` and
inherits it; per-dialog focus code is forbidden and a test fails if any
appears.

**Restoration is driven from `hide.bs.modal`, not `hidden.bs.modal`.**
`shiny::showModal()` wraps the dialog in `#shiny-modal` and Shiny removes
that wrapper as the modal hides, so Bootstrap dispatches the native
`hidden.bs.modal` on an already-detached element and it never bubbles to
`document` — instrumented in the browser, where `show`/`shown`/`hide` all
reached a native document listener and `hidden` reached only jQuery.

Two further properties are load-bearing and were each established by
measurement:

- The `focus()` call is **retried on a bounded schedule** (~1.2s, 40ms
  steps, stopping as soon as focus sticks). `hide.bs.modal` fires at the
  *start* of the hide transition, so a single synchronous call is
  overwritten moments later when the node is removed and focus drops to
  `<body>`.
- The scheduler is **`setTimeout`-primary**, with `requestAnimationFrame`
  only as an accelerator. rAF is paused in background tabs, and a
  rAF-only schedule left focus stranded there.

The shell publishes `window.__psaDialogFocus` (`event`, `hadOrigin`,
`restored`, `attempts`) so browser acceptance can assert the behaviour
instead of eyeballing a cursor. It carries no user content.

### 20.9 Short status vocabulary must not break inside a word

Status (`current` / `archived`), Relationship, Provenance and Confidence
are tagged `psa-nowrap` at the DT **column definition** in `app.R`, not by
a positional `nth-child` rule, so the class follows the column. `nowrap`
raises the column's min-content width; the grid then asks its container for
the width it needs and the container scrolls locally, instead of the
browser hyphen-free-breaking "current" into "curre / nt" to fit a squeezed
column. Every result grid keeps its own `overflow-x: auto`; page-level
horizontal overflow stays prohibited at every width.

## 21. Compare Editions simplification and mobile follow-up

Governed by `UI_COMPARE_EDITIONS_AND_MOBILE_FOLLOWUP_ADDENDUM.md`. A
presentation-only pass: no classification, correspondence, retrieval or RM
behaviour moves, and no field leaves the data model.

### 21.1 Filter region and the Direction control

The filter region is a CSS grid (`.psa-corr-filters`) with named column
classes, not an inline flex row. Direction owns the wide column
(`minmax(300px, 460px)`) and fills it; the search field takes
`minmax(220px, 380px)`. Below 768px the grid collapses to one full-width
column, Direction first, and the selected value may wrap to a second line
rather than being cut.

**Why the upper bound exists.** The previous inline row gave Direction only
`min-width: 260px` with no flex declaration, so it defaulted to
`flex: 0 1 auto` and never grew — measured at 1440px as a 263px control in
a 1382px row with the longest value squeezed into 233px and
`text-overflow: ellipsis` already armed. 460px is roughly twice what the
longest value needs, so it cannot clip at any supported width, while an
unbounded column would stretch a two-option select across half the
viewport. Filling the filter column is the contract; stretching across the
page is not.

### 21.2 Provenance is presentation-suppressed, not deleted

Provenance is **not** a column in the correspondence table and **not** a
row in the relationship detail. Every shipped mapping is `derived` or
`suggested` and none is `official`, so a per-row provenance cell repeated
one word down the whole table without helping anyone choose a code.

It remains: in the canonical schema, in `search_psic_correspondence()`
output, in `correspondence_ask_rm_context()`, in the "How to read this
table" glossary, and in `provenance_badge()` for a future diagnostic view.
Tests assert both halves — absent from the rendering, present in the model.

### 21.3 Relationship detail

One shared block, `correspondence_relationship_facts_ui()`, used by BOTH
`correspondence_detail_ui()` (the renderer `app.R` mounts) and
`correspondence_inspector_ui()`. Sharing is deliberate: those two renderers
had already drifted, and simplifying only the mounted one would have left
the other showing a provenance row and a raw evidence dump.

```text
Relationship   [Continued / Renamed / Split / Merged / …]
Confidence     [High / Medium / Low]
Derived correspondence   one sentence
Corroboration            only where the evidence records it
Statistical-use note     always
```

### 21.4 Evidence copy

The stored `evidence` string is an engineering trace — section-graph
terminology, `normalized-token similarity`, `Search method:
class_prefix_continuity`. None of it reaches the UI. It is **replaced**,
not reformatted, by `correspondence_evidence_summary()`.

UN corroboration is claimed only when the row's own evidence cites it
(matched on the literal `UN ISIC`); 948 of 2000 shipped relationships do,
1052 do not, so the sentence discriminates rather than decorating. A test
asserts the fixture really does contain the jargon, so a pass means it was
filtered rather than absent.

### 21.5 Confidence

Stored vocabulary is unchanged (`high` / `moderate` / `low`). Only the
display of `moderate` moves to **Medium**, in one place — the `label` field
of `.CORRESPONDENCE_CONFIDENCE_GLOSS`, which both the badge and the
glossary read, so they cannot disagree. Ordinal words only; never a
percentage. `confidence_badge(..., with_label = FALSE)` drops the
"Confidence:" prefix where the facts block already prints the field name.

### 21.6 Statistical-use safeguard

Now shown on **every** relationship, not only split / merged / complex.
Widening is the conservative direction — nothing that used to carry the
notice loses it — and the addendum requires the safeguard to survive the
evidence simplification. Still neutral/plum, never the error ramp.

### 21.7 Two regressions from the liquid-glass pass, fixed here

Both were found by this addendum's mobile review and both were measured,
not inferred:

1. **`.psa-liquid-glass { position: relative }` out-ranked the inspector's
   own positioning.** `.psa-corr-inspector` is the one glass surface that
   positions itself (sticky beside the table on desktop, fixed sheet below
   992px). Same specificity, later sheet, and a `@media` block adds none —
   so the primitive won at every width and the mobile sheet was an ordinary
   in-flow block. Restated for the glassed inspector in `ui-glass.css`,
   **position only**: restating `inset` there re-broke the phone sheet by
   out-specifying the 576px step.
2. **Reveal animations used `animation-fill-mode: both`.** A filled
   animation retains its final keyframe, and `transform: none` in a
   keyframe computes to the **identity matrix**, which still establishes a
   containing block for `position: fixed` descendants. Measured:
   `.psa-corr-workspace` held `matrix(1, 0, 0, 1, 0, 0)` long after its
   reveal, anchoring the inspector sheet to the workspace instead of the
   viewport (rendered at x=24, y=453 with `inset: 0`). All reveals now use
   `backwards`; they end on the element's own resting style, so the visual
   is identical, the reduced-motion guarantee is unaffected, and no
   transform lingers.

### 21.8 Mobile touch targets

At ≤767.98px the release-selector rows, the Browse-hierarchy trigger, the
Ask-RM action and the inspector close control all take a 44px minimum. The
40px desktop density of the sidebar is unchanged.

## 22. Visual system — Lumora light editorial (Onest)

Supersedes §20 (dark liquid glass) and §17 entirely. **Everything §17 and
§20 say about which MEANINGS carry a treatment still holds** — status is
never colour alone, a classification relationship is never styled as an
error, archived is quiet rather than warned, and no information is carried
by transparency. Only the ground, the face and the accent changed.

### 22.1 Typography — one face

```text
--font-ui       'Onest', ui-sans-serif, system-ui, …
--font-display  var(--font-ui)      (no separate display family)
--font-sans     var(--font-ui)
```

**Instrument Serif is removed from the application**, not demoted. There is
no serif anywhere and therefore no serif/sans tension to manage — which
also retired the previous pass's "pin list" that forced codes, tables,
forms and buttons back to the UI face. Weights carry hierarchy instead:
400 body, 500 navigation/labels, 600 headings and result labels, 700 rare.

Onest is the only external visual dependency. A blocked font request costs
the exact face and nothing else.

### 22.2 Palette

The Lumora tokens are declared once, in `ui-tokens.css`, and every other
sheet reads them. Canvas `#ffffff`, text `#111111`, ink `#0a0a0a`, line
`#e6e5e2`, surface `#f1f0ee`, accent `#b15f2c`.

Ink is used **selectively** (§9 of the handoff): the verified classification
card, the active navigation tab, primary buttons, the DT active page. The
accent is used for focus, rails, markers, small icons and short labels —
never as a large background.

### 22.3 Contrast decisions that deviate from the reference

The reference is a marketing site; this is a classification utility, and
§24 of the handoff says not to copy low-opacity text that fails here. Three
measured deviations:

- `--lumora-muted` `#8d8d8d` is **3.1:1** on white. Functional secondary
  text uses `--lumora-muted-text` `#5f5f5f` (**6.9:1**) instead.
- app.css expresses secondary copy as `color-mix(--color-text N%,
  transparent)`. Those N values were chosen against a near-black canvas;
  on white, **50% = 3.54:1** and **55% = 4.17:1** both fail AA. Every such
  rule carrying functional text is raised in `ui-tokens.css`.
  `.rm-assistant-disclaimer` is the clearest case: its own app.css comment
  records that 40% was raised to 55% to clear AA *on the dark theme*.
- The large classification code is **ink, not accent**. In accent on the
  warm surface it measured **4.06:1** — compliant for large text, and the
  least legible treatment in the app applied to its most important datum.
  Ink takes it to 16.58:1.

### 22.4 `.psa-liquid-glass` is now a light SURFACE primitive

The class name is kept although almost nothing is glassy, because it is
**structural**: it appears in 14 markup sites and carries three contracts —
`--flow` (`overflow: visible`, required wherever a selectize menu or bslib
popover opens from inside the surface; omitting it reproduces UI-POST-04),
`--quiet` (a flatter nested pane), and the `position: relative` + z-indexed
child stack. Renaming it would churn every markup site and every accepted
test to gain a nicer word.

What changed is what it paints: white or warm-light fill, a masked 1px
`#e6e5e2` ring that follows the radius, and a soft neutral shadow.

### 22.5 Geometry and adaptive sizing

`2rem` cards, `1.25rem` sub-cards, `.875rem` controls, pill actions — all
**rem-based**. The reference's viewport-driven root-font scaling is
deliberately NOT adopted (§22 of the handoff): it would destabilise
DataTables, selectize and modals, and it breaks browser zoom and user text
scaling. `clamp()` is used for large headings only.

### 22.6 Codes and headers never break mid-word

`psa-nowrap` is attached at the DT **column definition** — Code, Status,
and for the correspondence grid From code / To code / Relationship /
Confidence — so it follows the column rather than an index. A code split
across two lines ("2220 / 5") reads as a different code, which is the one
thing this application must never do. Table headers take `nowrap` too.

### 22.7 What was NOT imported from the reference

No Lenis, no cursor-reveal canvas, no fake `000 → 100` loader, no
artificial minimum wait, no scroll locking, no remote hero imagery, no
marketing information architecture, and no React/Tailwind/Vite/Framer
migration. Motion is CSS only, on the reference's own
`cubic-bezier(.22, 1, .36, 1)` curve, with hover transforms gated behind
`(hover: hover) and (pointer: fine)`.

---

## 23. Imported Claude Design layout ("PSA Classifications Redesign")

The design artifact lives **outside this repository** and is treated as a
read-only external reference:

```text
External read-only Claude Design project reference
  PSA Classifications Redesign.dc.html   the thirteen surfaces
  support.js                             the generated dc-runtime canvas engine
```

Neither file is copied into the repository and neither was modified. The
artifact is the authority for **composition, control placement, action
hierarchy and responsive behaviour**. It is not the authority for data,
behaviour, ARIA or scope: where it conflicts with a functional decision
made after it was drawn, the functional decision wins, and the reason is
recorded at the rule that implements it.

### 23.1 Surfaces and where each one lives

| Artifact | Surface | Implementation |
|---|---|---|
| 1a / 1b | Search — desktop / mobile | `search_ui()` (`R/ui/ui_search.R`) |
| 1c | System picker sheet (mobile) | `system_picker_dialog_ui()` (`R/ui/ui_pickers.R`) |
| 1d / 1e | PSOC + PSIC — desktop / mobile | `dual_search_ui()` (`R/ui/ui_dual_search.R`) |
| 1f / 1g | Compare Editions — desktop / mobile | `correspondence_ui()` (`R/ui/ui_correspondence.R`) |
| 1h | Hierarchy browser dialog / sheet | `hierarchy_dialog_ui()` (`R/ui/ui_hierarchy.R`) |
| 1i / 1j | PSOC / PSIC details dialog | `entry_detail_dialog_ui()` (`R/ui/ui_details.R`) |
| 1k | PSOC + PSIC comparison dialog | `entry_comparison_dialog_ui()` (`R/ui/ui_details.R`) |
| 1l | RM Assistant sidecar / drawer / sheet | `rm_sidecar_ui()` (`R/ui/ui_sidecar.R`) |
| 1m | Sources | `sources_ui()` (`R/ui/ui_sources.R`) |

### 23.2 Four workspace destinations

`main_nav` now carries **four** values — `search`, `dual_search`,
`correspondence`, `about`. `rm_assistant` is gone as a navigation value:
RM is not a place you navigate to, it is a panel that opens over or beside
the destination you are already on. Every `req(input$main_nav == ...)`
gate in `app.R` reads one of the four that remain, unchanged.

### 23.3 System control — complete registry scope

The System picker exposes the **complete registry-supported classification
set** on every surface, desktop and mobile. The artifact illustrates five
systems in its mobile sheet; that is a drawing, not a scope. Both the
desktop `selectizeInput` and the mobile sheet are built from
`classification_registry()`, and `search_pickers_server()` validates any
client-supplied id against `registry$id` before applying it. There is no
hard-coded system list anywhere in the picker layer.

### 23.4 Edition / release — collapsed, not expanded

The permanently expanded radio list is replaced by a collapsed control that
states the selected release and its CURRENT / ARCHIVED status on one line,
and discloses the full list on demand: a popover anchored inside its own
field on desktop, a bottom sheet at 767px and below.

**The input contract is unchanged.** `classification_version` is still a
`radioButtons` group with the same id, the same raw canonical values and
the same `updateRadioButtons()` update path — it is *moved* inside the
disclosed panel, not replaced. `edition_choice_spec()` still owns
current-first ordering (`release_newest_first()`), and now also emits the
Current / Archived group headers and the archived count.

The disclosed panel must remain a DESCENDANT of `.psa-picker-field`: it is
`position: absolute`, so as a sibling it anchors to the page instead of to
its own control.

### 23.5 Browse hierarchy

Mounted in the **results toolbar**, beside the count it scopes, rather than
at the foot of the filter rail. Only the mount point moved:
`hierarchy_browse_slot_ui()`, the dialog, lazy expansion, hierarchy-local
search and View in Search are the same feature, wired by the same single
`hierarchy_browser_server()` call.

### 23.6 Compare selected details

A page-level action in the PSOC + PSIC page head, above both panels and
visible without scrolling at every supported width. Disabled (and
`aria-disabled`) until one PSOC row and one PSIC row are both selected.
`dual_search_compare` / `dual_search_compare_open` are unchanged, and the
independence safeguard is still printed on the page and again inside the
comparison dialog.

### 23.7 Compare Editions

Direction takes the wide column (about 1.4fr against the search field's
1fr) at 768px and above only — below that, `ui-filters.css` collapses both
controls to one full-width column and this sheet must not reach it.

At 992px and above the table card and the relationship inspector form a
**matched-height row**: the grid stretches, the inspector stops being
sticky, the table body flexes, pagination is pushed to the card's bottom
edge, and the card's Bootstrap bottom margin is zeroed so the two bottom
edges meet. Mobile keeps natural per-card heights.

Relationship detail exposes only user-facing statistical information —
source, target, relationship, confidence, derived correspondence, UN ISIC
corroboration where verified, and the statistical-use note. No standalone
Provenance row and no retrieval diagnostics. The underlying `provenance`
field is untouched in the data and is still carried into
`correspondence_ask_rm_context()`.

### 23.8 RM Assistant — three breakpoints, one panel

| Width | Presentation | Semantics |
|---|---|---|
| 1280+ | Docked sidecar, 440px | **Non-modal.** `role="complementary"`, no `aria-modal`, no backdrop, no focus trap, page reflows |
| 1024–1279 | Overlay drawer, 420px | Modal: `role="dialog"`, `aria-modal="true"`, backdrop, focus contained, page does not reflow |
| 1023 and below | Bottom sheet, 94% height | Modal, as above |

One panel element and one `shinychat` mount across all three — a second
would mean a duplicate `rm_assistant-chat` id and two transcripts of one
conversation. ARIA is switched at the breakpoint by `matchMedia`, because
CSS cannot set ARIA and a media query cannot reach the accessibility tree.
The state is re-derived from `matchMedia` on the media-query change event,
on `resize`, from a `ResizeObserver`, and again on any interaction with the
panel — the passive signals were observed not to fire under viewport
emulation, and a panel whose ARIA and whose layout disagree about whether
the rest of the page is reachable is the failure this design must not have.

The docked reflow is `body.psa-rm-docked { padding-inline-end: 440px
!important }`. The `!important` is required, not sloppy: bslib's fill page
writes `style="padding:0px"` directly onto `<body>`, and an inline
declaration outranks every stylesheet rule.

Closing the panel sets `hidden` on an element that is never removed, so the
transcript, scroll position and the ellmer client's turn history all
survive close/reopen and navigation. Only **New chat** clears the
conversation, through the existing `rm_assistant-new_chat` observer.

### 23.9 Reserved "Ask RM" slots are now ACTIVATED

Section 17's inert `.psa-askrm-reserved` placeholders are gone. In their
place:

| Launcher | Kind | Behaviour |
|---|---|---|
| `rm_open_global` (header) | plain `<button data-psa-rm-open>` | Opens the panel client-side, no server round-trip |
| `search_ask_rm_page` (Search head) | plain `<button data-psa-rm-open>` | As above |
| `search_ask_rm_entry` (selected entry) | Shiny `actionButton` | Attaches the selected canonical record, then opens |
| `correspondence_ask_rm` (inspector) | Shiny `actionButton` | Attaches the selected relationship, then opens |

The two record-level launchers render only when the deployment has a
working assistant configuration — an action that promises record-specific
help must not be offered where it cannot be delivered.

`correspondence_ask_rm` is built by `correspondence_ask_rm_button()` and is
rendered by **both** `correspondence_detail_ui()` (which the running app
mounts) and `correspondence_inspector_ui()`. Before this milestone it
existed only in the second, which the app never renders, so the control was
in the source and not in the DOM.

### 23.10 Stylesheet load order (amended)

```text
app.css        base rules, token-driven
ui-tokens.css  DECLARES the --ui-* design tokens; retargets the older
               --lumora-* / --psa-* names at them; canvas and typography
ui-dialog.css  shared dialog/drawer shell
ui-filters.css search rail + correspondence layout
ui-glass.css   surface treatments
ui-design.css  NEW — layout introduced/moved by the imported design
ui-motion.css  transitions, reduced-motion escape LAST
```

Three cascade hazards are load-bearing and are asserted by tests:

* `ui-design.css` loads after `ui-filters.css`, so any unconditional rule
  in it outranks that sheet's narrow-width rules. Design rules that must
  not reach mobile are scoped with `min-width` queries.
* `ui-glass.css` carries two-class selectors such as
  `.psa-corr-inspector.psa-liquid-glass`, which outrank a plain class in
  `ui-design.css` regardless of load order.
* `ui-motion.css` loads last and owns motion, so the rule that suspends
  the entrance reveal while a picker sheet is open lives there. It has to:
  a `position: fixed` sheet resolves against the nearest ancestor carrying
  a transform, and the reveal puts one on exactly the containers those
  controls live in.

### 23.11 Semantic tokens, and no theme switching

The palette is declared once, as `--ui-*` semantic tokens at the top of
`www/ui-tokens.css`; every other colour name in the system is an alias
resolving to them, and `bs_theme()` in `app.R` is compiled from the same
values.

Theme **switching** is deliberately not implemented: there is no
`prefers-color-scheme` block, no `[data-theme]` selector and no toggle
anywhere in the system. A future second appearance is an edit of that one
token block.

The artifact's own `#6b6b6d` micro-label grey measures 3.6:1 on `#111111`
and is **not** adopted as a text token. Functional secondary text uses
`--ui-text-muted` (`#9e9e9e`, 7.1:1 on surface) and `--ui-text-subtle`
(`#8b8b8d`, 5.5:1).

### 23.12 Attached context

Attached-context chips are a visible, removable record of *which verified
application object* the user pressed "Ask RM" from. They are per-session.

The chip the user reads carries a label; what RM can reach is an
**identifier-only descriptor** (system / version / code, or the two sides
of a PSIC relationship) that is re-read from the canonical repository on
the turn that uses it. A referential question — "Why is this classified
here?", "Explain this relationship." — resolves against that read; an
explicit new coding request and an outstanding clarification both outrank
it. Removing a chip removes it from subsequent turns; New chat clears both
the chips and the descriptors.

The rules, the precedence order and the limits are in
`docs/ASSISTANT_CONTRACT.md` §17. The UI's only responsibility is to keep
the chips and the descriptors in step, which it does through a single
writer in `rm_sidecar_server()`.

### 23.13 The deterministic contextual starter (UAT2-RM-01)

**Opening RM costs zero provider calls.** A contextual "Ask RM" action
attaches the chip, opens the panel, and renders a starter block. It does
not submit anything.

Until UAT Pass 2 the launchers also submitted a turn ("Explain this
classification entry.") on the reader's behalf. That is removed. **View
details** already shows the verified definition, tasks and examples, so
opening RM to be told the same thing spent a provider call nobody asked
for — and the reply could be suppressed to nothing before it arrived (see
`ASSISTANT_CONTRACT.md` §17.5).

| Property | Guarantee |
|---|---|
| Cost | Rendering the starter makes no provider call and inserts no message into the transcript |
| Source | Built in R from the newest attached descriptor — its `kind`, and for an entry its `system`. Never from a hard-coded code |
| Placement | With the chip, not in the transcript: it is not something RM said |
| Lifetime | Same `reactiveVal` as the chips, so removing the last chip removes the starter and New chat clears both |
| Actions | Four, on four fixed input ids, so the observer count never grows with the number of records a reader attaches |
| Submission | A press fills and submits the ordinary composer, so the prompt arrives on `rm_assistant-chat_user_input` exactly as typed text does |

Stable ids added:

| Id | Kind | Purpose |
|---|---|---|
| `rm_context_starter` | `uiOutput` | The starter block |
| `rm_context_starter_1` … `_4` | `actionButton` | One starter action each |

Presentation: `.psa-rm-starter` (block), `.psa-rm-starter-lead` /
`-record` / `-ask` (the text), `.psa-rm-starter-actions`,
`.psa-rm-starter-action` (full-width, left-aligned, 40px — 44px at phone
width). The block carries `role="group"` and an accessible name; every
action carries its own `aria-label`.

### 23.14 The System control is sized by its text (UAT2-UI-02)

`.selectize-input` holds the rendered `.item` **and** selectize's own 4px
typing `<input>`. In block flow that input claimed a whole line of its own
under the item, so the control's height was set by an invisible element and
the title had only its padding before the border. The control is a **flex
row**: item and sliver share one line, height follows the text, and one-line
and two-line titles both keep 10px above and below.

| Property | Contract |
|---|---|
| Trigger padding | `padding-block: 10px`; no rule may give it a fixed height |
| Acronym → subtitle | 4px (`.psa-sys-line { gap }`) |
| Subtitle | `line-height: 1.3`, `white-space: normal`, `overflow-wrap: anywhere` — wraps, never ellipsises |
| Dropdown rows | `padding: 9px 12px` on `.psa-sys-opt`, panel `padding: 5px`; rows grow for wrapped names and never clip |
| Scrolling | Unchanged — `max-height: min(200px, 45vh)` on the panel, never on a row |

**The dropdown rows are `.psa-sys-opt`, not `.option`.** The System control
uses a custom selectize `render.option`; selectize keeps the renderer's own
class list and adds only `selected`/`active`, never `option`. Any rule
written against `.selectize-dropdown .option` is dead for this control —
that is what left the rows with no padding at all and the vendor default
painting the keyboard cursor. Style these rows by the class the renderer
emits.

### 23.15 Decorative icons contribute no accessible text (UAT2-RM-03)

`lucide_icon()` — the only icon factory in this application — emits
`aria-hidden="true" focusable="false"` on every glyph and no `<title>`, and
every icon-only control names itself (`aria-label` on the button, not on the
graphic): **Close the RM Assistant panel**, **Remove attached context: …**,
**Send message**.

Third-party icons inside the mounted chat are not ours and several ship with
no `aria-hidden` (`bi-arrow-up-circle-fill`, `bi-stop-circle-fill`,
`bi-robot`, `bi-x-lg`, the loading dots). An `<svg>` with no role and no
accessible name is still a node in the accessibility tree, serialised by its
element name — the literal `svg` that reached accessibility output. The
sidecar therefore hardens its own subtree at load and on mutation (the chat
re-renders mid-stream), setting `aria-hidden="true" focusable="false"` on
any `<svg>` it contains that has **no** name of its own. An `<svg>` carrying
`aria-label`, `aria-labelledby` or a `<title>` is left untouched, so a
meaningful graphic can never be hidden by this pass. Nothing visual changes.

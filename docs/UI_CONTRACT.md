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
| RM Assistant | Implemented as a separate nav panel — conversational assistant (shinychat + ellmer). See `docs/ASSISTANT_CONTRACT.md` |
| About/Data Sources | Implemented as a separate nav panel |

All five nav panels live under one `bslib::page_navbar(id = "main_nav", ...)`
— `input$main_nav` is a real Shiny input holding the active tab's `value`
(`"search"` / `"dual_search"` / `"correspondence"` / `"rm_assistant"` /
`"about"`). See the implementation note under section 4 for why this exists
and why every secondary-tab output is gated on it.

**The RM Assistant panel is the one exception to that gating**, and
deliberately so: it declares no Shiny outputs at all. The chat is a custom
element driven by custom messages (delivered whether or not the tab is
visible) and its greeting is present in the initial HTML rather than pushed
from the server, so it needs neither the `req(input$main_nav == ...)` gate
nor `outputOptions(suspendWhenHidden = FALSE)`.

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
| `main_nav` | input (implicit, from `page_navbar(id = "main_nav")`) | The active tab's value: `"search"` / `"dual_search"` / `"correspondence"` / `"rm_assistant"` / `"about"` |
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
| `rm_assistant` | RM Assistant | RM Assistant |
| `about` | Sources | About / Data Sources |

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

### Reserved "Ask RM" slots — inert, and must stay inert

Two positions (Search detail header; Compare Editions relationship-detail
header) render `<span class="psa-askrm-reserved" aria-hidden="true">`.
They are **not** `<a>`/`<button>`, carry no `tabindex`, no cursor
affordance and no hover state, and are confirmed absent from the
accessibility tree. An inert-but-focusable control would be a worse
accessibility outcome than omitting it.

Their text is deliberately kept at the design's 35% opacity (2.94:1),
below WCAG AA — permissible only because the element is `aria-hidden` and
conveys no content. **When these are wired into real controls they must
gain button semantics AND be raised to at least 50% opacity (4.76:1).**

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

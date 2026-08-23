# Claude Design → Claude Code Handoff — Unified Visual Redesign

Visual reference: `unified-app-primary.dc.html` (this project). Approved direction: five-tab model, Search as default with a hero-weight search bar, tabs relabeled, RM a full nav destination, two reserved (non-interactive) "Ask RM" layout slots.

This is a **presentation-only** handoff. Nothing in the functional application was modified from Claude Design. All service/tool/grounding contracts in `docs/UI_CONTRACT.md` and `docs/ASSISTANT_CONTRACT.md` are unchanged and remain the source of truth for behavior.

## 1. Files/components to change

| File | Change |
|---|---|
| `app.R` | `tabPanel` **titles only**: "Search" (unchanged), "Dual Search" → "PSOC + PSIC", "Compare PSIC Editions" → "Compare Editions". Do not rename `main_nav` values or `tabPanel` `value=` args. `page_navbar` markup restyled per this doc; structure (`id = "main_nav"`, the `req(input$main_nav == ...)` + `outputOptions(suspendWhenHidden = FALSE)` gate on every non-Search output) must not change. |
| `R/ui/ui_search.R` | Restyle only. Promote the search `textInput` to the hero treatment (§4). Sidebar keeps `classification_system`, `classification_version`, `classification_level`, `classification_query` — same IDs, same reactive wiring. Reserve the "Ask RM about this" slot next to the "Selected entry" heading in `entry_detail_ui()` per §11 — render it as an inert, non-focusable placeholder (see §11), not a button/link. |
| `R/ui/ui_dual_search.R` | Restyle only. Update visible copy from "Dual Search" to "PSOC + PSIC" and panel headers stay "Occupations — PSOC" / "Industries — PSIC" (mandatory per `UI_CONTRACT.md` §14 — do not remove or reword these two labels). IDs unchanged. |
| `R/ui/ui_correspondence.R` | Restyle only. Update visible copy from "Correspondence"/"Compare PSIC Editions" to "Compare Editions". Reserve the second "Ask RM" slot next to the relationship detail header. IDs unchanged. |
| `R/ui/ui_assistant.R` | Restyle only — greeting, starter chips, composer, streaming/stop, new-chat, unavailable panel per §7–§8. Add the mid-stream-failure presentation component (§9) as new inert markup; wiring it to real detection is a future backend task per `ASSISTANT_CONTRACT.md` §12, not this handoff. |
| `R/ui/ui_sources.R` | Restyle only, scope unchanged: PSA issuing authority per system, source URLs, PSIC Revision 5 ingestion provenance (workbook URL, retrieval date, SHA-256, structural counts). Do not add Search/RM content here — Sources stays provenance/methodology only. |
| `www/app.css` | Full replace with the new visual system (tokens below). Must keep the existing mobile chat-grid fix (`grid-template-columns: minmax(0, 1fr)` on `.rm-assistant-card shiny-chat-container`) or an equivalent — see §8. |

Do not touch: `R/schema.R`, `R/registry.R`, `R/repository.R`, `R/search.R`, `R/parallel_search.R`, `R/correspondence/*.R`, `R/adapters/*.R`, `R/assistant/*.R`, `prompts/RM_SYSTEM_PROMPT.md`, anything under `data/`, `data-raw/`, `tests/`.

## 2. Stable `main_nav` mappings

Internal values are unchanged; only visible tab labels change.

| `main_nav` value | Visible label (new) | Visible label (old) |
|---|---|---|
| `search` | Search | Search |
| `dual_search` | PSOC + PSIC | Dual Search |
| `correspondence` | Compare Editions | Compare PSIC Editions |
| `rm_assistant` | RM Assistant | RM Assistant |
| `about` | Sources | About / Data Sources |

Browse/Archive is **not** a separate value — it stays expressed inside `search` via the edition radio group + level select + blank-query browse, exactly as today.

## 3. Responsive breakpoints

Follow bslib/Bootstrap 5 defaults already in place, with one added floor:

- **≥ 992px** — desktop: full tab bar, sidebar + results + detail as three regions on Search, side-by-side panels on PSOC + PSIC.
- **576–991px** — tablet: tab bar may wrap to icon+label chips; Search sidebar collapses to the existing bslib off-canvas toggle (unchanged mechanism).
- **≤ 575px (down to 375px, the hard floor)** — mobile: single column everywhere; tab bar becomes a fixed bottom bar (5 icon+micro-label items, §5); RM composer must remain fully reachable at exactly 375px width (§8) — this is a regression floor, not a nice-to-have, per the fixed grid-collapse bug in `IMPLEMENTATION_STATUS.md`.

## 4. Search hero dimensions

- Search input: `min-height: 56px`, `font-size: 19px`, left icon at 20px inset ~16px, `padding-left: 46px`, full width up to `max-width: 820px`, horizontally centered under the tab bar.
- Helper line below ("Leave blank to browse…"): 13px, muted (~45% text opacity).
- Below the hero: sidebar (system/edition/level) at 260px fixed column, results+detail unchanged two-column ratio (`1fr` : `380px`).
- On mobile the hero shrinks to `min-height: 50px`, `font-size: 16px` (iOS zoom-on-focus floor), full width minus 32px gutter.

## 5. Mobile navigation behavior

- Replace the default bslib top-nav-collapses-to-hamburger with a **fixed bottom tab bar**: 5 items, each an icon (Phosphor, 18px) over a ≤10px micro-label, equal-width flex children, `min-height: 44px` tap target per item.
- Active tab: accent-colored icon + label; inactive: muted text color. Convey state with color **and** `aria-current="page"` — never color alone.
- This is a navigation **restyle**, not a behavior change: it still sets `input$main_nav` to the same five values via the same navbar mechanism: bslib. If a literal bottom-bar component isn't feasible in the bslib version in use, the acceptable fallback is the existing collapsible top nav restyled with the same tokens — the bottom bar is the target, not a hard requirement that blocks the milestone.

## 6. RM composer / mobile constraints

- Composer container: **flex row**, not CSS grid, `align-items: center`, `gap: 8px`.
- Text input: `flex: 1 1 auto`, **`min-width: 0`** (mandatory — this is what the current fix already relies on to stop a grid track over-expanding).
- Send/stop button: `flex: 0 0 auto`, fixed `44×44px` hit target, never allowed to shrink or be pushed off-screen.
- If shinychat's own `shiny-chat-container` grid is kept under the hood, the existing override `grid-template-columns: minmax(0, 1fr)` on `.rm-assistant-card shiny-chat-container` must be preserved or re-verified after any layout change — this is the fix for the documented 375px send-button-disappears bug. Do not remove it without re-testing at 375px.
- Verify reachability at 375px and narrower (e.g. 320px) before considering the RM tab done.

## 7. Verified-result card specification

Used wherever RM presents a tool-verified code (and reusable, unchanged, wherever Search shows a selected entry) — same component, so RM cannot visually claim more authority than Search:

- Icon: `ph-check-circle`, 20–22px, accent-300 color.
- Eyebrow: 11px, uppercase, letter-spacing 0.06em, muted (~55% text), reads "Verified · <system + edition>".
- Code: monospace, 28–52px depending on context (RM inline card smaller, Search detail panel larger), tabular figures.
- Title: 15–22px depending on context, sentence case, no truncation — wrap.
- Container: 1px border in `--color-accent-800`, background `color-mix(in srgb, var(--color-accent) 8%, transparent)`, `border-radius: var(--radius-md)`.
- Never rendered without a real tool/result behind it — this is a presentation spec only; the grounding rule itself lives in `R/assistant/*` and is out of scope here.

## 8. Current / archived visual treatment

One vocabulary, used identically in Search, PSOC + PSIC, Compare Editions, Sources, and the RM verified card:

- **Current**: `.tag.tag-accent` — accent-tinted fill, accent-300 text, label text "Current" (never color-only).
- **Archived**: outlined only, never filled — `border: 1px solid oklch(0.66 0.125 70)`, text `oklch(0.80 0.10 70)`, label text "Archived". This ochre is reserved exclusively for archived-state signaling (line/border/text), never used as a background flood, per the design system's "accent as line, not flood" rule extended to this second semantic color.
- Both badges always carry visible text, satisfying `UI_CONTRACT.md` §10's "status conveyed through text, not color alone."

## 9. Correspondence split/merge presentation

- Layout: `source | arrow icon | target(s)` three-column grid (`1fr 40px 1fr`), one row per relationship.
- Split: `ph-arrows-split` icon, target column lists multiple code/title pairs stacked vertically.
- Merge: same layout mirrored (`ph-arrows-merge`, multiple sources → one target).
- Provenance + confidence tags always shown together (never just one), per `UI_CONTRACT.md` §15.
- The **statistical-safety warning** (`CORRESPONDENCE_STATISTICAL_WARNING`, verbatim from `R/correspondence/schema.R`) renders inline, directly under the relationship, in an ochre-bordered box, whenever `relation_type` is `split`, `merged`, or `complex` — this presentation is mandatory, not optional styling.
- No-match rows (`discontinued`/`new`): render the explicit "(no prior counterpart…)" / "(no related category…)" message in place of a blank cell — never leave a cell empty or fabricate a code.

## 10. Source/provenance presentation

- Every classification detail view (Search, RM verified card) carries a compact source line: issuing authority + short citation + external link, `target="_blank" rel="noopener"`, 13px, muted until hovered.
- The Sources tab is the only place for full methodology: per-system issuing authority, source URL, and — for PSIC Revision 5 specifically — retrieval date, SHA-256, and validated structural counts. Do not duplicate this depth inline elsewhere; inline stays to one line + link.

## 11. WCAG-conscious states

- All inputs keep real `<label>` elements (no placeholder-only labeling) — unchanged from current baseline.
- Icon-only buttons (`Stop generating`, `New chat`, tab-bar items on mobile, `Close` on any overlay) require `aria-label`.
- Focus-visible: 2px accent outline with 2px offset on every interactive element, including tab items and starter-suggestion chips — never the browser default ring.
- Tabs use proper `role="tablist"`/`role="tab"`/`aria-selected` semantics (bslib's navset already provides this — preserve it through restyling).
- The reserved "Ask RM" slots (§below) are `aria-hidden="true"` and not focusable — they must not appear in the tab order or the accessibility tree until actually wired, since an inert-but-focusable control would be a worse a11y outcome than omitting it.
- Status badges keep visible text (§8). External links keep `rel="noopener"`.
- Mobile tap targets ≥ 44×44px throughout (bottom tab bar items, RM send button, starter chips).

## 12. Reserved "Ask RM" layout slots — visual-only, unwired

Two positions, styled as **inert placeholders**, not buttons:

- Search tab: beside the "Selected entry" heading in the detail panel.
- Compare Editions tab: beside the relationship-count line above the detail card.

Spec: dashed 1px border (`color-mix(in srgb, var(--color-text) 20%, transparent)`), muted text (~35% opacity), sparkle icon, no fill, no cursor affordance, no hover state, `aria-hidden="true"`, not a real `<a>`/`<button>` element. This reserves the exact layout position and sizing a future functional control will occupy — wiring it later (seed RM's composer with the entry's code/title, switch `main_nav` to `rm_assistant`) requires no redesign, only swapping the inert span for a real control.

## 13. Explicitly visual-only / deferred in this handoff

- The two "Ask RM" hooks (§12) — layout reserved, functionality deferred.
- The mid-stream provider-failure presentation (§9 of `ASSISTANT_CONTRACT.md`'s known-limitations list) — this handoff defines the UX (non-technical message, "Try again" + "Search directly," transcript preserved) but wiring real failure detection to it is a separate backend task; shinychat's error-hook gap is unresolved upstream.
- The mobile bottom tab bar (§5) is the target pattern; a restyled collapsible top nav is an acceptable fallback if the bottom bar proves infeasible in the current bslib version — this does not block considering the milestone otherwise complete.
- Any drawer/rail/workbench patterns explored in earlier design rounds (`direction-a-lookup.dc.html`, `nav-a-search-hub.dc.html`, `nav-c-rail-workbench.dc.html`, etc.) are superseded by this approval and are reference-only, not part of this handoff.

# Implementation Status — PSA Statistical Classifications Search

> **Latest milestone: Post–Connect Cloud staging UI refinement** — see
> [Post–Connect Cloud staging UI refinement](#postconnect-cloud-staging-ui-refinement)
> at the end of this document. Regression: **3000 / 3000 passing**
> (0 fail / 0 warn / 0 skip), from a verified 2151 baseline.
> `renv::status()` clean. Not yet republished to staging.

> **Previous milestone: Pre-staging hardening** — see
> [Pre-staging hardening milestone](#pre-staging-hardening-milestone) at the
> end of this document. Regression: **1904 / 1904 passing** (from a verified
> 1103 baseline). PSIC structural correspondence repaired, three new
> classification systems ingested, PSCCS name corrected, UI/UAT defects
> fixed.

This document covers **five milestones**:

1. The original functionality-first MVP (`PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`)
   — complete, preserved as the known-good baseline. See git commit
   `8269eb3` ("feat: complete functional PSA classifications MVP").
2. The post-MVP functional extension
   (`PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md`):
   PSOC 2022, parallel PSOC/PSIC search, and PSIC 2019↔Revision 5
   correspondence. Complete; committed as `23c4d6a`.
3. The RM Classification Assistant
   (`PSA_CLASSIFICATIONS_RM_ASSISTANT_INTEGRATION.md`). Complete;
   committed as `c9dfbb5`.
4. The unified visual redesign (`HANDOFF-CLAUDE-CODE.md` /
   `unified-app-primary.dc.html`). Complete; committed as `31cb046`.
5. Pre-staging hardening (`PRE_STAGING_PARALLEL_EXECUTION_MASTER.md` and
   its three underlying specifications) — the subject of this update.

## Recovery from interrupted session

The prior Claude Code session for this milestone was interrupted by a
usage limit after producing only documentation: commit `2202a66` ("docs:
define PSOC 2022 and classification extension") added the extension spec
and updated `CLAUDE.md`, but **no implementation code, adapters, tests, or
UI for PSOC 2022, dual search, or PSIC correspondence existed yet**.

Recovery audit performed at the start of this session:
- `git status` — clean working tree, nothing uncommitted.
- `git log --oneline -30` — exactly two commits (`8269eb3` MVP, `2202a66`
  docs-only).
- Targeted grep across the whole repository for
  `psoc_2022|parallel_search|psic_correspondence|CORRESPONDENCE_SOURCES|adapter_psoc_2022|build_psoc_2022|build_psic_correspondence`
  — zero hits outside the spec file itself.
- Full MVP test suite run before any changes: **302/302 passing**,
  confirming the baseline exactly matched the previous session's own
  `IMPLEMENTATION_STATUS.md` claim.

Recovery matrix (final classification):

| Workstream | State at recovery | Action taken |
|---|---|---|
| Existing MVP regression suite | COMPLETE | Re-verified, preserved |
| PSOC 2022 source ingest | NOT STARTED | Built |
| PSOC 2022 adapter | NOT STARTED | Built |
| PSOC registry current version | NOT STARTED | Corrected |
| Dual search service | NOT STARTED | Built |
| Dual search UI hooks | NOT STARTED | Built |
| PSIC correspondence source audit | NOT STARTED | Performed, documented |
| Correspondence schema | NOT STARTED | Built |
| Correspondence artifact | NOT STARTED | Built |
| Correspondence UI hooks | NOT STARTED | Built |
| UI contract updates | NOT STARTED | Updated |

No partial work was discarded — there was none to discard beyond the
already-complete MVP baseline, which was reused as-is.

## PSOC 2022 status

**Current and default.** Source: PSA's official **"2022 Updates to the
2012 PSOC"** workbook (`https://psa.gov.ph/classification/psoc`). PSA's
file host for this specific workbook sits behind a Cloudflare JavaScript
challenge that blocked automated retrieval (`curl`/`httr2` both received
HTTP 403 with `Cf-Mitigated: challenge`); the user manually downloaded the
same official file and supplied it at
`data-raw/2022-Updates-to-the-2012-PSOC.xlsx`. This is recorded honestly
in `docs/DATA_SOURCES.md` and in `data/psoc_2022_metadata.rds$retrieval_method`
— the source is still official PSA data, only the retrieval mechanism
differs from the PSIC Revision 5 precedent (which downloads directly).

Validated structural counts (`scripts/build_psoc_2022.R`, referential
integrity of every parent_code chain hard-enforced as a build failure
condition):

| Level | PSA stated | Parsed |
|---|---|---|
| Major groups | 10 | **10** ✓ |
| Sub-major groups | 43 | **43** ✓ |
| Minor groups | 130 | **130** ✓ |
| Unit groups | 456 | **466** (documented discrepancy — no duplicate/malformed codes found; see `docs/DATA_SOURCES.md`) |

PSA's own documented validation fixture — Unit Group `2121` ("Mathematicians
and Actuaries" in 2012) splitting into `2121` ("Mathematicians") and `2123`
("Actuaries") in 2022 — is confirmed present with the correct shared parent.

Runtime artifact: `data/psoc_2022.rds` (649 canonical rows) +
`data/psoc_2022_metadata.rds`, read offline by
`R/adapters/adapter_psoc_2022.R`. Missing-artifact error:
`"PSOC 2022 runtime artifact is missing. Run scripts/build_psoc_2022.R and redeploy."`
— never silently substitutes 2012 data while claiming to show 2022.

## PSOC 2012 archive status

**Retained, fully queryable, correctly marked archived.** The phscs-sourced
2012 edition's `status` was corrected from `"current"` to `"archived"` in
`R/adapters/adapter_phscs.R` (a deliberate, spec-mandated correction — PSA
no longer treats 2012 as current now that the 2022 update exists). Its
level vocabulary was also renamed from `major`/`sub-major`/`minor`/`unit`
to the canonical `major_group`/`sub_major_group`/`minor_group`/`unit_group`
form so switching between 2012 and 2022 in the UI never leaves a stale,
incompatible level selected. Both changes are covered by updated/added
tests in `tests/testthat/test-adapters.R`.

## Dual search status

**Complete and default-correct.** `search_parallel_classifications()`
(`R/parallel_search.R`) defaults to PSOC 2022 + PSIC Revision 5 (2026),
reuses `search_classification()` verbatim (no second ranking engine),
isolates each system's search in its own `tryCatch` so a failure or
no-match on one side never suppresses the other, and is exposed through a
new "Dual Search" nav panel with independent PSOC ("Occupations") and PSIC
("Industries") result panels, each with their own edition selector.
Manually verified live (see Manual UAT below).

## PSIC correspondence status

**Complete.** Source audit (`docs/CORRESPONDENCE_SOURCES.md`) confirmed no
official PSA PSIC 2019↔Revision 5 crosswalk exists yet (expected — Revision
5 was released only 18 days before this audit). A genuine official **UN
Statistics Division ISIC Rev.4↔Rev.5 correspondence table** was found and
downloaded (`data-raw/ISIC4-5_Correspondence_Table.xlsx`, 603 rows) and
used as **derived** (not official — PSIC has national adaptations UN
evidence doesn't capture) corroborating evidence, gated behind a
conformance check since PSIC doesn't always preserve ISIC's own code
numbering.

Built artifact `data/psic_2019_to_2026_correspondence.rds` — **2,699 rows**,
exhaustive over all 1,360 PSIC 2019 sub-class codes:

| Relation type | Count | | Provenance | Count | | Confidence | Count |
|---|---|---|---|---|---|---|---|
| unchanged | 741 | | derived | 2,510 | | high | 1,985 |
| renamed | 768 | | suggested | 189 | | moderate | 605 |
| split | 507 | | **official** | **0** | | low | 109 |
| merged | 100 | | | | | | |
| complex | 59 | | | | | | |
| possible | 130 | | | | | | |
| discontinued | 143 | | | | | | |
| new | 251 | | | | | | |

`official` provenance is enforced as a hard test guard
(`!("official" %in% correspondence$provenance)`), not just a claim.
Bidirectional lookup (`get_psic_correspondence()`,
`search_psic_correspondence()`) confirmed working both directions live in
the browser, including a real split case (`01179` → `01171`/`01172`) with
the mandated statistical-safety warning rendered inline.

## Data source/provenance status

| Artifact | Source | Retrieval | Provenance recorded in |
|---|---|---|---|
| `data/psic_2026.rds` | PSA official workbook | Automated (direct URL) | `docs/DATA_SOURCES.md`, `data/psic_2026_metadata.rds` |
| `data/psoc_2022.rds` | PSA official workbook | **Manual** (Cloudflare-blocked automation) | `docs/DATA_SOURCES.md`, `data/psoc_2022_metadata.rds` |
| `data/psic_2019_to_2026_correspondence.rds` | Derived from PSIC 2019 (phscs) + PSIC 2026 (local artifact), corroborated by UN ISIC Rev.4↔Rev.5 table | Automated (UN source) + deterministic build-time computation | `docs/CORRESPONDENCE_SOURCES.md`, `data/psic_2019_to_2026_correspondence_metadata.rds` |

All three are read-only at runtime — no network calls anywhere in the
request path for any of them.

## Tests

`Rscript scripts/run_tests.R`:

- **Before this milestone (baseline, re-verified at recovery):** 302/302 passing
- **After this milestone: 485/485 passing, 0 failed, 0 warnings, 0 skipped**
  (+183 new tests, 0 regressions)

| New/changed test file | Covers |
|---|---|
| `test-psoc-2022.R` | Artifact existence/offline load, canonical schema, all 4 levels, structural counts (with honest documented discrepancy), referential integrity, the Mathematicians/Actuaries fixture, level filtering, unsupported-level/missing-artifact errors, registry current/archived resolution, no silent 2012-for-2022 substitution, live search |
| `test-adapters.R` (modified) | PSOC level vocabulary renamed to canonical form; new "psoc 2012 is archived" assertion |
| `test-parallel-search.R` | Defaults, independent result sets, verbatim reuse of `search_classification()` (equality-asserted, not just spot-checked), one-sided no-result/error isolation, archived-edition selection, per-system level filtering, per-system limits, leading-zero preservation, semantic labels |
| `test-correspondence-schema.R`, `test-correspondence-build.R`, `test-correspondence-service.R` | Schema validation, source-audit doc presence, offline artifact load, character-typed codes, provenance/relation_type/confidence enums (including the `official` guard), real unchanged/split cases, reverse lookup, no-match safety, label search, absence of any numeric value/count/allocation column anywhere in the schema |

## Manual UAT

Performed live in a running Shiny session (`shiny::runApp('app.R')` under
the renv-activated environment), verified via the browser automation
tooling's DOM/network inspection rather than screenshots:

- **PSOC version (spec section 29):** selecting PSOC shows edition "2022"
  with all rows `status = current`; switching to "2012" shows all rows
  `status = archived`; level names consistent across both editions.
- **Dual search (spec section 30):** query "accountant" → PSOC panel shows
  exactly `2411 ACCOUNTANTS`, PSIC panel shows "No results." independently
  (proves one-sided no-match doesn't suppress the other); defaults
  confirmed as PSOC "2022" / PSIC "2026" in the UI on load.
- **PSIC correspondence (spec section 31):** browsed 2019→2026 (high-
  confidence "renamed" rows shown correctly); searched a known split source
  (`01179`) and confirmed both target candidates (`01171`, `01172`) render
  with the statistical-safety warning inline; switched direction to
  2026→2019 and confirmed reverse lookup returns the same relationship
  from the other side.

One real bug was found and fixed during this manual testing (see Known
limitations).

## Known limitations

- **A genuine reactive-race bug was found and fixed**: the Search screen's
  level-choice observer could receive a transiently mismatched
  system/version pair (e.g. version `"2022"` arriving while
  `classification_system` still read `"psgc"`) during rapid input
  changes, calling `classification_levels()` with an invalid combination
  and crashing that observer uncaught. Fixed with a defensive guard in
  `app.R` that silently skips the stale combination (the system-change
  observer's own update shortly settles it correctly).
- **A DT-widget-in-hidden-tab rendering bug was found and fixed**: Shiny's
  implicit suspend-when-hidden/resume-on-tab-shown behavior proved
  unreliable in this app for outputs outside the default "Search" tab —
  sometimes never triggering a first render, and for `DT::renderDT`
  outputs specifically, sometimes freezing the widget at a broken
  zero-width layout if it was ever built while its container was hidden.
  Fixed by giving `page_navbar` a real `id = "main_nav"` and explicitly
  gating every secondary-tab output on `req(input$main_nav == "<value>")`
  combined with `outputOptions(suspendWhenHidden = FALSE)` — see the
  detailed note in `docs/UI_CONTRACT.md` section 4. This pattern should be
  followed for any future new tab's outputs.
- **PSOC 2022's unit-group count (466) doesn't match PSA's technical-notes
  figure (456)** — same class of discrepancy as PSIC Revision 5's groups
  count (261 vs. 260, from the original MVP). Investigated (no duplicate
  or malformed codes, full referential integrity holds); recorded as
  honestly unexplained in `docs/DATA_SOURCES.md`, not forced to match.
- **No official PSA PSIC 2019↔Revision 5 crosswalk exists** as of this
  build (confirmed by source audit, not assumed) — every correspondence
  row is `derived` or `suggested`. If PSA publishes one later, only rows
  matching that document's explicit mappings may be relabeled `official`;
  see `docs/CORRESPONDENCE_SOURCES.md`'s reconciliation note.
- **Correspondence coverage above the sub-class level is limited to clean
  exact-code matches** (no split/merge/discontinued/new bookkeeping for
  section/division/group/class) — an explicit, documented scope limit
  since the spec's exhaustiveness requirement is stated only for
  sub-class.
- **PSOC 2012 ↔ 2022 correspondence** (spec section 35) is explicitly
  deferred, as directed by the spec ("Do not allow this to block the
  current implementation... Record it as deferred").
- All MVP-era known limitations (documented in prior versions of this
  file, now superseded by this rewrite) remain: no formal WCAG audit, no
  fuzzy search, `retrieved_at` in phscs/psgc metadata is build-date rather
  than each package's own data vintage, a handful of pcoicop/pcpc rows use
  a documented honest label fallback, and PSIC 2019 division→section
  `parent_code` is `NA` (section codes are letters, not derivable by
  truncation).

## Deferred V2 Features

Unchanged from the MVP baseline, per spec section 26 of the original
build spec — see `docs/UI_CONTRACT.md` and the git history of this file
for the full list (cross-system simultaneous search, fuzzy search,
saved/favorite codes, formal WCAG audit, final visual branding, etc.).
Additionally, per this milestone's own spec section 35: **PSOC 2012 ↔ 2022
correspondence** is deferred pending a future authoritative source.

## Deployment Status

Unchanged from the MVP baseline: **not deployed to a public host** (no
Posit Connect Cloud or equivalent credentials available in this
environment). `renv.lock` remains the reproducible dependency record; no
new dependencies were added for this milestone (correspondence scoring
uses a hand-rolled token-similarity function rather than adding a
`stringdist`-style package, per the project's smallest-dependency-surface
preference).

## Claude Design Handoff Readiness

**Ready.** Everything Claude Design needs to change for the three new
screens (Dual Search, Compare PSIC Editions, plus the unchanged Search/
About screens) lives in `app.R` and `R/ui/*.R`; nothing about the visual
pass requires touching `R/adapters/`, `R/repository.R`, `R/search.R`,
`R/parallel_search.R`, `R/correspondence/`, `R/registry.R`, any
`scripts/build_*.R`, `data/`, or any test. Full stable-ID/component/state
inventory — including the new PSOC version states, dual-search contract,
and correspondence contract — is in `docs/UI_CONTRACT.md` sections 3, 4,
8, 13, 14, and 15. The `input$main_nav` gate pattern (section 4) is
explicitly documented so a future tab addition doesn't repeat the same
rendering bug found and fixed in this milestone.

---

# RM Classification Assistant milestone

## Readiness audit (performed before any code)

- Branch `feature/rm-assistant`, clean working tree, prior milestone
  committed as `23c4d6a`.
- **Baseline verified by execution: 485 / 485 passing**, 0 failures,
  0 warnings, 0 skips — matching the stated expectation rather than
  assuming it.
- Required assets both present: `PSIC_Chatbot_Classification_Rules.md`
  (~55K chars, 12 rule sections) and
  `data-raw/CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping.xlsx` (6 sheets; the
  usable one is `"PSIC Rev5 Mapping"`, 253 rows × 9 columns, header on row
  3, **44 rows deliberately carrying no fixed PSIC**).
- `data-raw/classification_synonyms.csv` **absent** → no synonym artifact
  and no synonym tool (see Known limitations).
- `shinychat` and `ellmer` were **not installed**; installed 0.4.0 and
  0.4.2 respectively and verified their *current* APIs directly rather
  than coding from remembered examples. Two findings mattered:
  `ellmer::chat_openai(api_key=)` is deprecated as of ellmer 0.4.0, and
  `ellmer::tool()` now takes `description` positionally with argument
  types via `arguments = list(...)`.
- No blockers.

## RM Assistant Status

**Implemented and integrated**, disabled by default.

Built as four parallel workstreams with disjoint file ownership, then
converged by hand. Two of the four (tool wrappers, UI) were interrupted
mid-flight by a usage limit; both had written their files but never
verified them, so their output was audited and completed rather than
rewritten — see Recovery notes below.

| Workstream | Outcome |
|---|---|
| A — assistant data assets | Complete. 253-row pairings artifact (44 no-fixed-PSIC preserved), 12-topic PSIC rules artifact compacted to **19.3%** of the 55K source |
| B — read-only tools | Complete after audit + two test fixes + one hardening change |
| C — prompt & provider client | Complete. 4,379-char system prompt, fail-closed config, per-session clients |
| D — assistant UI | Complete after audit; its unfinished CSS step was finished during convergence |
| Convergence | `app.R` wiring, integration tests, browser UAT, docs |

## Recovery notes (interrupted workstreams B and D)

Neither was restarted from scratch. Their files existed but had never been
run, so the audit was: run the suite, read the failures, fix narrowly.

- **B** left `assistant_tools.R` (29K) and a 21.8K test file with **2
  failing tests**, both test-side bugs: `expect_lte()` was passed an
  unsupported `info=` argument, and `startsWith(NULL, ".")` errored for a
  tool that takes no arguments.
- Investigating the first failure surfaced a **real data quirk worth
  keeping**: `get_classification_entry("psoc","2012","1")` returns **two
  rows**, because the archived phscs PSOC 2012 edition carries 13
  one-character codes where only 10 major groups exist. B's wrapper took
  `head(hit, 1)` — safe, but it silently dropped a legitimate second
  official entry. Hardened to report `additional_matches` /
  `additional_matches_note` instead of hiding them, with tests both ways.
- **D** left a thorough, well-documented `ui_assistant.R` whose verified
  shinychat signatures and server-contract comments were accurate; only the
  `www/app.css` step was missing. Verified every UI function constructs,
  then wrote the CSS.

## Assistant Dependencies

Added: `ellmer` 0.4.2, `shinychat` 0.4.0 (plus `S7`, `coro`). Recorded in
`renv.lock` via `renv::snapshot()`. Nothing else was added — no vector
database, no LangChain, no REST framework, no JS chat framework.

## Grounding protections implemented

The rule — *no retrieved code = no code presented* — is enforced in three
independent layers, because a prompt alone erodes over a long conversation:

1. **Prompt** (`prompts/RM_SYSTEM_PROMPT.md`) states it before anything else.
2. **Tool results** carry the constraint as data: a miss returns
   `found = FALSE` with an explicit "this is NOT a confirmed code, do not
   present it and do not offer a similar unverified code", and **no
   `label` field at all**, so nothing official can be attached to an
   unverified code. Pairing results always carry a supporting-evidence-only
   caveat. A missing rules artifact returns a reason that explicitly
   forbids substituting model memory.
3. **Tests** assert it: unverifiable codes across three shapes never come
   back `found`; exactly five read-only tools are registered; no tool name
   matches write/delete/update/exec/shell/fetch/http; the synonym tool is
   absent.

Also enforced: bounded results (6 default, hard clamp 25), compact field
sets, exact string code matching with leading zeros preserved, and
current-version resolution that can never silently select an archived
edition.

## Assistant Tool Tests

| File | Covers |
|---|---|
| `test-assistant-data.R` | Artifact schemas, character-code and leading-zero preservation, 44 no-fixed-PSIC rows, multi-code and en-dash range strings verbatim, all 12 rule topics, compaction proof, missing-artifact → `NULL` not error |
| `test-assistant-tools.R` | Bounds and clamping, compact field sets, truncation cap, `found = FALSE` semantics, non-unique-code reporting, current/archived preservation, default-version resolution, degraded pairings/rules, exactly-five-read-only-tools |
| `test-assistant-prompt.R` | Prompt compactness and required content, greeting starts `"Madayaw! I am RM."`, four suggestions, disabled/missing-credential behaviour, no secret in `reason` |
| `test-assistant-integration.R` | Deterministic app fully working with RM disabled, tools working without a provider, UI both states, **per-session client isolation**, tool registration, end-to-end grounding, asset degradation |
| `test-assistant-evals.R` | Eval fixture integrity + its factual claims verified against real local data |

## Assistant Evaluation Cases

`tests/evals/rm_assistant_cases.yml` — all 12 representative cases from the
spec, each with `expect` / `must_not` behaviours and a language tag.

The deterministic half runs today and verifies the *claims* the fixture
makes, so the grounding expectations are not vacuous: PSOC `999999` really
does not resolve; PSGC really is the system covering barangays (`Bgy` is a
real level in the current release); PSIC 2019 really is archived while 2026
is current; PSOC and PSIC really are separate systems with current editions
2022 and 2026.

A YAML leading-zero bug was caught here and fixed: unquoted `01`–`07`
parsed as integers while `08`/`09` stayed strings (invalid octal) — the
same class of bug this project guards against in classification codes.

## Multilingual Status

Implemented in the prompt (understand English / Filipino-Tagalog /
Cebuano-Bisaya / code-switched input; reply in the user's dominant
language; never present an RM translation as an official PSA title) and
covered by eval cases 02, 03, 04, 05 and 12.

**Not empirically verified.** No provider credentials were available, so no
live multilingual evaluation was executed. This is a genuine gap, not a
passing result — see below.

## Manual UAT (browser)

Performed against a live app on both configurations. Verified by DOM and
accessibility-tree inspection plus server logs.

**RM disabled (default deployment):**
- RM tab shows the calm "temporarily unavailable" panel with the
  still-search-and-browse guidance and a short non-technical reason.
- Search returns real PSGC rows — the deterministic app is untouched.

**RM enabled (fake key, `RM_PROVIDER=openai`):**
- Greeting renders beginning exactly **"Madayaw! I am RM."** with all four
  suggestion chips and the footer — and the server log shows **no provider
  traffic**, confirming zero model tokens are spent on it.
- Composer present, visible, labelled ("Chat message"), with the custom
  placeholder; suggestions carry `role="button"`, `tabindex`, `aria-label`.
- **"Stop generating"** appears in the accessibility tree during streaming
  — cancel is provided natively by shinychat, not hand-rolled.
- New chat clears the transcript and restores the greeting exactly once.
- All five tabs verified in one pass: Search, Dual Search (both PSOC and
  PSIC panels), Compare PSIC Editions, About, RM.
- Submitting a message reaches the provider (401 on the fake key), the key
  is masked in the log and never reaches the browser.

**Live LLM evaluation: NOT performed.** No valid credentials. Every case in
`rm_assistant_cases.yml` remains pending, as do all multilingual,
vague-PSIC-probing, occupation-vs-industry and invalid-code behavioural
checks that require a real model.

## Bugs found and fixed during UAT

- **RM unusable on mobile (fixed).** `shiny-chat-container` is a CSS grid;
  a grid item's default `min-width: auto` let a wide child size the column
  to ~580px inside a ~325px card at 375px width. The page itself did not
  scroll, so the overflow was silently clipped and the send button went
  off-screen — it **disappeared from the accessibility tree entirely**.
  Fixed with one rule (`grid-template-columns: minmax(0, 1fr)`) and
  re-verified: input 317px, send button reachable, tree restored.

## Known Assistant Limitations

- **Mid-stream provider failure is silent client-side.** If the provider
  fails after successful configuration (revoked key, network fault, rate
  limit), shinychat rolls the transcript back and restores the user's text
  but shows no explanation. Logged server-side; no secret or stack trace
  reaches the browser, so this is a UX gap rather than a safety one, and
  the startup-time degradation path that spec 21 chiefly concerns works
  correctly. **A fix was attempted and deliberately reverted rather than
  left half-working**: detection provably works (a failed stream leaves an
  *empty* assistant turn, distinguishable from a real reply), but three
  separate surfacing approaches against shinychat 0.4.0 — the module's
  `append()`, top-level `shinychat::chat_append()`, and
  `showNotification()` — all failed to reach the DOM on that path. Rather
  than ship ~60 lines of machinery that does not work and would mislead
  the next maintainer, the code was removed and the diagnosis recorded in
  `app.R` and `docs/ASSISTANT_CONTRACT.md` §12.
- **No live LLM evaluation of any kind** (above).
- **No synonym tool in V1** — no approved source exists. Deliberately not
  fabricated; the architecture accepts one later without change.
- **Enter does not submit** in shinychat 0.4.0's composer; the send button
  is required. Upstream behaviour.
- **Rule quality is bounded by the compaction** (~19% of source). Omitted
  detail is not available to RM at runtime.
- **An invalid/expired key cannot be detected without a network call**, so
  such a deployment reports available and fails on first message.
- **`RM_MODEL` must be set explicitly for `RM_PROVIDER=anthropic`**, since
  the default model id is an OpenAI one.

## Provider/Deployment Configuration

Server-side environment variables only, fail-closed:
`RM_ASSISTANT_ENABLED` (default **disabled**), `RM_PROVIDER` (`openai` |
`anthropic`), `RM_MODEL`, and `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`. The
application only checks a credential's *presence*; ellmer reads the value
itself, and it is never copied into application code or any user-visible
string. Full notes in `docs/DEPLOYMENT.md`.

**Not deployed.** No hosting credentials in this environment, unchanged
from previous milestones.

## Test counts

| Point | Result |
|---|---|
| Baseline before this milestone (verified by execution) | **485 / 485** |
| After this milestone | **1103 / 1103**, 0 failures, 0 warnings, 0 skips |

+618 tests, no regressions. Every previously passing test still passes.

## Claude Design readiness

**Ready.** RM's presentation lives entirely in `R/ui/ui_assistant.R` and
the prefixed `.rm-assistant-*` rules in `www/app.css`. Stable ids,
component inventory and all RM states are documented in
`docs/UI_CONTRACT.md`; grounding rules, tool contracts and limitations in
`docs/ASSISTANT_CONTRACT.md`. Nothing in a visual pass requires touching
`R/assistant/*`, the prompt, the adapters, the repository, or any test —
with one caveat carried in the UI contract: the mobile grid fix must
survive any chat-layout change, or the send button regresses off-screen.

## Files Changed (RM milestone)

New:
```
prompts/RM_SYSTEM_PROMPT.md
R/assistant/assistant_data.R
R/assistant/assistant_tools.R
R/assistant/assistant_prompt.R
R/assistant/assistant_client.R
R/ui/ui_assistant.R
scripts/build_assistant_assets.R
data/assistant_common_pairings.rds
data/assistant_psic_rules.rds
tests/evals/rm_assistant_cases.yml
tests/testthat/test-assistant-data.R
tests/testthat/test-assistant-tools.R
tests/testthat/test-assistant-prompt.R
tests/testthat/test-assistant-integration.R
tests/testthat/test-assistant-evals.R
docs/ASSISTANT_CONTRACT.md
```

Modified:
```
app.R                  -- RM nav panel (available/unavailable at startup),
                          per-session client, tool registration, new-chat
                          observer, known-limitation note
www/app.css            -- minimal .rm-assistant-* layout rules incl. the
                          mobile grid fix
.claude/launch.json    -- added an RM-enabled dev profile on port 8318
renv.lock              -- ellmer, shinychat, S7, coro
docs/UI_CONTRACT.md    -- RM view, stable ids, RM states, mobile caveat
docs/DEPLOYMENT.md     -- provider configuration section, dependency note
README.md              -- RM summary, enable instructions, build command
IMPLEMENTATION_STATUS.md
```

---

## Files Changed (PSOC 2022 / dual search / correspondence milestone)

New files:
```
R/adapters/adapter_psoc_2022.R
R/correspondence/schema.R
R/correspondence/scoring.R
R/correspondence/isic_bridge.R
R/correspondence/service.R
R/parallel_search.R
R/ui/ui_dual_search.R
R/ui/ui_correspondence.R
scripts/build_psoc_2022.R
scripts/build_psic_correspondence.R
data/psoc_2022.rds
data/psoc_2022_metadata.rds
data/psic_2019_to_2026_correspondence.rds
data/psic_2019_to_2026_correspondence_metadata.rds
data-raw/2022-Updates-to-the-2012-PSOC.xlsx
data-raw/ISIC4-5_Correspondence_Table.xlsx
docs/CORRESPONDENCE_SOURCES.md
tests/testthat/test-psoc-2022.R
tests/testthat/test-parallel-search.R
tests/testthat/test-correspondence-schema.R
tests/testthat/test-correspondence-build.R
tests/testthat/test-correspondence-service.R
```

Modified files:
```
R/registry.R          -- PSOC 2022/2012 version+level+current-version wiring
R/repository.R        -- dispatch to adapter_psoc_2022 for system="psoc", version="2022"
R/adapters/adapter_phscs.R  -- psoc 2012 status corrected to archived; level names renamed to canonical form
app.R                  -- Dual Search + Compare PSIC Editions nav panels and server logic; page_navbar id="main_nav"; defensive version/system race guard
tests/testthat/test-adapters.R  -- updated for renamed psoc levels + archived status
docs/UI_CONTRACT.md    -- new stable IDs, PSOC version states, dual-search contract, correspondence contract, states table, main_nav gate pattern documented
docs/DATA_SOURCES.md   -- new PSOC 2022 provenance section
README.md              -- updated feature summary and rebuild commands
```

No MVP files were destructively rewritten — every change above is either
a new file or a narrow, targeted edit to an existing one, with the
specific reason documented inline at each edit site.

---

# Unified UI milestone

Presentation-only implementation of the approved design in
`unified-app-primary.dc.html`, per `HANDOFF-CLAUDE-CODE.md`.

## Audit before changes

- Branch `feature/unified-ui`, clean tree, RM milestone committed (`c9dfbb5`).
- **Baseline verified by execution: 1103 / 1103 passing**, 0 failures.
- Both handoff artifacts present. The mockup references a design-system
  stylesheet (`_ds/nocturne-.../styles.css`) that was **not** part of the
  bundle, so token values were derived from the mockup's own inline usage
  plus the values fixed explicitly in the handoff (archived ochre, hero
  metrics, verified-card spec).
- No contract mismatch found. Every change landed in `app.R`, `R/ui/*` and
  `www/app.css` as the handoff intended; no adapter, repository, search,
  correspondence or RM-grounding file was touched.

## Files changed

```
app.R                      -- tab LABELS only (values untouched), dark
                              bs_theme, nav_label() helper, edition radio
                              group update, result-count output
R/ui/ui_search.R           -- hero search, sidebar, reserved Ask RM slot,
                              visually-hidden H2
R/ui/ui_details.R          -- status vocabulary, detail panel, compact
                              source line, verified-result card
R/ui/ui_dual_search.R      -- restyle; mandatory panel headings preserved
R/ui/ui_correspondence.R   -- 3-column relationship row, cardinality-aware
                              arrows, provenance+confidence pairing,
                              statistical warning, reserved Ask RM slot
R/ui/ui_assistant.R        -- header badge, unavailable copy, aria-label on
                              New chat, inert failure component
R/ui/ui_sources.R          -- editions column, PSA authority statement,
                              correspondence audit section
www/app.css                -- full replacement with the new visual system
www/Phosphor.woff2         -- NEW, vendored icon font (11 glyphs declared)
docs/UI_CONTRACT.md        -- section 16 label mapping, section 17 visual system
IMPLEMENTATION_STATUS.md
```

Not touched, as required: `R/schema.R`, `R/registry.R`, `R/repository.R`,
`R/search.R`, `R/parallel_search.R`, `R/correspondence/*`, `R/adapters/*`,
`R/assistant/*`, `prompts/`, `data/`, `data-raw/`, `tests/`.

## Design elements implemented

Five relabelled tabs (Search, PSOC + PSIC, Compare Editions, RM Assistant,
Sources) over unchanged `main_nav` values; 56px hero search; 260px sidebar
with the edition radio group; 1fr : 380px results/detail split; the single
Current/Archived status vocabulary (accent fill vs. ochre outline, always
with text); the verified-result card shared by Search and RM; the
3-column correspondence row with split/merge iconography and the verbatim
statistical-safety warning; both inert Ask RM slots; the dark theme applied
through `bs_theme` so DT and Bootstrap components inherit it.

## Intentional divergences from the handoff

1. **Icons vendored, not CDN.** The mockup loads Phosphor from unpkg;
   `www/Phosphor.woff2` is served locally instead. A public
   government-facing app should not make a third-party request per visitor,
   disclose visitor IPs to a CDN, or break on restricted networks. Visual
   result is identical; every icon is paired with a text label so a font
   failure degrades to readable text.
2. **Muted text raised from ~45% to 55% where it carries content.** The
   handoff's opacity measured 4.08:1, under WCAG AA for 13px text. The
   handoff also mandates WCAG-conscious states, so accessibility won the
   tie. The one deliberate exception is the Ask RM placeholder, kept at 35%
   because it is `aria-hidden` and conveys no content — flagged in the UI
   contract to be raised when wired.
3. **Edition control is a radio group, not a select.** The approved design
   shows radios with per-edition status; the handoff separately said "same
   reactive wiring". Same input ID and same yielded value, so the service
   contract is untouched — only `updateSelectInput()` became
   `updateRadioButtons()`. PSGC's 13 releases scroll inside the bordered
   group.
4. **Mobile nav is the restyled collapsible top nav, not a bottom tab bar** —
   explicitly permitted by handoff section 5 as a non-blocking fallback.
5. **No webfont for body text** (system stack), for the same
   no-third-party-request reason as the icons.

## Test counts

| Point | Result |
|---|---|
| Baseline before this milestone (verified by execution) | **1103 / 1103** |
| After this milestone | **1103 / 1103**, 0 failures, 0 warnings, 0 skips |

No tests were added or modified — this milestone changed presentation only,
and `tests/` was off-limits per the handoff. One test
(`test-assistant-integration.R`, degraded-state copy) initially failed
because the redesigned unavailable panel reworded its message; rather than
edit a forbidden file, the copy was written to carry both the design's
guidance and the phrase the contract test asserts.

## Browser UAT

Verified live at desktop, 375px and 320px. Screenshots were unavailable in
this environment (Browser pane not compositing), so verification was by DOM
inspection, computed styles and the accessibility tree.

| Check | Result |
|---|---|
| Five destinations render | Pass |
| Hero metrics (56px / 19px / 46px) | Pass |
| Blank-query browse | Pass — "200 results · browsing" |
| Edition control, PSGC (13) and PSIC (2) | Pass — correct Current/Archived tags |
| Archived edition selection | Pass — outlined ochre, transparent fill |
| Classification detail | Pass — eyebrow, 40px code, PSA source line, rel=noopener |
| Dual independent results | Pass — PSOC hit, PSIC independently "No results." |
| Mandatory PSOC/PSIC headings | Pass |
| Split correspondence | Pass — split icon, provenance+confidence, verbatim warning |
| Reverse correspondence | Pass — 2026 to 2019, tags flipped |
| RM disabled state | Pass |
| RM static greeting | Pass — "Madayaw! I am RM.", no provider call |
| Sources | Pass — PSA authority stated, all external links rel=noopener |
| Mobile nav | Pass — 5 labels, ~275x53px, sets `main_nav` correctly |

**Live provider RM behaviour was NOT tested** — no valid credentials. RM was
exercised with a fake key, which verifies UI states only. No multilingual or
grounding behaviour claims are made for this milestone.

## RM mobile composer verification (the regression floor)

| Viewport | Send button | Textarea | Overflow | A11y tree |
|---|---|---|---|---|
| 375px | 44x44, right 338 | 317px, `min-width: 0` | none | "Chat message" + "Send message" present |
| 320px | 44x44, right 283 | 262px | none | both present |

Both the `minmax(0, 1fr)` grid override and `min-width: 0` on the flex
input are in place, as the handoff requires.

## Regressions found and fixed during this milestone

1. **Tabs lost their accessible names.** Wrapping the label in a `<span>`
   alongside the aria-hidden icon suppressed accessible-name computation —
   all five tabs read as unnamed. Fixed by using a direct text node;
   re-verified all five are named.
2. **RM composer pushed below the fold at 375px.** The card sized to its
   content (966px against an 812px viewport), leaving the send control
   reachable only by scrolling and absent from the in-view accessibility
   tree — a softer recurrence of the original 375px bug. Fixed by capping
   the card to `calc(100dvh - 150px)` so the transcript scrolls internally
   and the composer stays anchored.
3. **New chat clipped at 320px.** The long header descriptor pushed it to a
   right edge of 415px inside a clipped card. Fixed by wrapping the header
   and hiding that descriptor at phone width.
4. **Focus ring suppressed by Bootstrap.** `.form-control:focus { outline: 0 }`
   outranked the focus-visible rule, so keyboard focus was invisible on
   inputs. Fixed with a higher-specificity `!important` rule; verified
   `solid 2px` accent at 2px offset under real keyboard Tab.
5. **Sub-AA muted text** (divergence 2 above).
6. **Search panel had no top-level heading** — added a visually-hidden H2
   so the heading hierarchy is not missing its first rung.

## Accessibility findings

Measured contrast against `#0f1119`: body 16.29:1, accent-300 11.95:1,
accent 8.62:1, archived ochre 9.96:1, muted-55% 5.51:1 — all AA or better.
Status is always conveyed by text as well as colour. Tabs keep bslib's
`role="tab"` / `aria-selected` semantics. All inputs keep real `<label>`
elements (the hero label is visually hidden, not removed). Icon-only and
ambiguous controls carry `aria-label`. Tap targets are at least 44px,
including the nav toggler which was floored from bslib's 40px. Reserved
Ask RM slots are confirmed absent from the accessibility tree.
`prefers-reduced-motion` is honoured.

## Known limitations

- No live provider RM evaluation (no credentials) — unchanged from the RM
  milestone.
- Mid-stream provider-failure surfacing remains unwired; the presentation
  component now exists (`rm_assistant_failure_ui()`) but detection is still
  blocked upstream (`docs/ASSISTANT_CONTRACT.md` section 12). Explicitly
  deferred by handoff section 13.
- Both Ask RM slots are inert by design; wiring is a future milestone.
- Mobile navigation is the collapsible fallback, not the bottom tab bar.
- Screenshots could not be captured in this environment; visual verification
  was via DOM/computed-style/accessibility-tree inspection rather than by
  eye. A human should still eyeball the result before public launch.

## Staging-deployment readiness

**Ready for staging on Posit Connect Cloud**, with the same caveats as
before: `renv.lock` pins every dependency (no new R packages were added
this milestone), the app makes no third-party runtime request, and RM stays
off unless `RM_ASSISTANT_ENABLED` and a provider credential are set on the
host (see `docs/DEPLOYMENT.md`). Two things should happen before a *public*
launch rather than a staging one: a human visual review, and — if RM is to
be enabled — a real provider key plus the live multilingual/grounding
evaluation that has never been run.

---

# Pre-staging hardening milestone

Executed per `PRE_STAGING_PARALLEL_EXECUTION_MASTER.md` and its three
underlying specifications: PSIC structural correspondence repair,
additional-classification ingestion, and pre-staging UI/UAT repair.

## Starting gate

| | |
|---|---|
| Branch | `feature/pre-staging-hardening` |
| Starting commit | `bc2a1fb` |
| Working tree | clean (no uncommitted work to preserve) |
| Starting test count | **1103 / 1103**, verified by execution, not assumed |

## Workstream graph as executed

Six Wave-1 workstreams ran in parallel with disjoint file ownership
(PSCC / PTSCS / PSCrCS ingestion; correspondence structural graph;
correspondence detailed mapping; UI footer + Sources deck). A session
usage limit terminated four of them mid-flight; each had written
substantially more to disk than its final message implied, so the recovery
was an audit-and-finish rather than a restart. Remnants completed by the
orchestrator: `docs/CORRESPONDENCE_SOURCES.md` structural-evidence sections
(9 failing provenance assertions), and
`tests/testthat/test-correspondence-detailed.R` (never written).

Convergence waves, all single-owner, in order: registry/metadata →
correspondence artifact rebuild → shared UI → RM integration check →
targeted tests → full regression → browser UAT → documentation.

## Files changed by workstream

**New classification sources**
```
scripts/build_pscc_2022.R          R/adapters/adapter_pscc_2022.R
scripts/build_ptscs_2025.R         R/adapters/adapter_ptscs_2025.R
scripts/build_pscrcs_2025.R        R/adapters/adapter_pscrcs_2025.R
data/pscc_2022{,_metadata}.rds
data/ptscs_2025_v2_1{,_metadata}.rds
data/pscrcs_2025{,_metadata}.rds
tests/testthat/test-{pscc-2022,ptscs-2025,pscrcs-2025}.R
```

**Correspondence repair**
```
R/correspondence/structural_graph.R   (new)
R/correspondence/precedence.R         (new)
R/correspondence/scoring.R            (extended)
R/correspondence/isic_bridge.R        (extended)
scripts/build_psic_correspondence.R   (structural integration + section edges)
data/psic_2019_to_2026_correspondence{,_metadata}.rds  (rebuilt)
tests/testthat/test-correspondence-{structural,provenance,detailed}.R
docs/CORRESPONDENCE_SOURCES.md
```

**Shared convergence (orchestrator-owned)**
```
R/registry.R      3 systems registered, PSCCS name corrected, components column
R/repository.R    dispatch for 3 systems, component filter + validation
R/search.R        preserve adapter extra columns through ranking
app.R             DT search removed, All-levels sentinel, Component control
R/ui/ui_search.R  Component control
R/ui/ui_sources.R registry-driven card deck (agent)
www/app.css       page-flow fix + Sources deck styles (agent)
tests/testthat/test-{registry,repository,assistant-tools,assistant-integration}.R
docs/{DATA_SOURCES,UI_CONTRACT,CORRESPONDENCE_SOURCES}.md
```

## New classification validation counts

| System | Version | Official target | Parsed | Result |
|---|---|---|---|---|
| PSCC | 2022 | (none published) | 21,547 records | built |
| PTSCS | 2025 v2.1 | 176 industries / 214 products | **176 / 214** | exact |
| PSCrCS | 2025 | 317 / 409 / 114 | **317 / 409 / 114** | exact |

PTSCS's sheets hold 196/236 physical rows; the differences were fully
accounted for (16/18 category headings + column header + 2 blank spacers +
sheet title = exactly 19/21) before any parsing decision. Category headings
are preserved as `major_category` metadata, not emitted as records — they
carry only a presentational ordinal, no official code.

Both composite workbooks' own Metadata sheets independently state their
counts and underlying classifications, so the targets were confirmed from
source rather than taken on faith.

## PSCCS correction

`R/registry.R` previously carried `display_name = "Philippine Standard
Commodity Classification System"` on `psccs` — the name of a different
classification. Corrected in the single authoritative metadata source (not
aliased in the UI) to **Philippine Standard Classification of Crime for
Statistical Purposes**, edition 2018. PSCC is separately registered as
**Philippine Standard Commodity Classification**, 2022. A regression test
asserts both independently and asserts neither carries the other's wording.
Verified in the running app: Search selector, Sources cards and the RM
registry tool all report the corrected names.

## Correspondence root cause and fix

**Root cause.** The builder matched exact code → 4-digit class prefix →
3/2-digit prefix + label similarity. It had no model of PSA's section
restructuring, so wherever a whole division was dissolved it produced
nothing at all. Measured on the pre-repair artifact: **all 16 of 2019
division 45's sub-classes (motor-vehicle and motorcycle trade *and* repair)
were `discontinued` with `target_code = NA`**, because Revision 5 contains
zero `45*` codes — trade moved to divisions 46–47 and repair to division 95
/ group 953. The artifact also contained **zero section-level rows**, so the
level at which the restructuring is actually expressed was absent entirely.

**Fix.** A deterministic section graph (`structural_graph.R`) validated
against both editions' real structures, plus a precedence resolver
(`precedence.R`) implementing the spec's evidence order — structural
relationship → ISIC bridge → containment/code continuity → label
similarity → suggested fallback — so structural movement can no longer be
overridden by fuzzy similarity. Section-level edges are emitted from the
graph. Reverse lookup is derived from the same artifact, never separately
authored.

Verified structural rules:

```
2019 G -> 2026 G + T      trade stays in 46-47, repair migrates to 95/953
2019 J -> 2026 J + K      58-60 -> J, 61-63 -> K
2019 K -> 2026 L, L -> M, M -> N, N -> O, O -> P, P -> Q,
         Q -> R, R -> S, S -> T, T -> U, U -> V
reverse: 2026 T -> BOTH 2019 S and 2019 G (multi-source, as required)
```

Verified detailed examples from real records:

| 2019 | Label | 2026 target(s) |
|---|---|---|
| 45101 | Sale of passenger motor vehicles | 46611/46619/47811/47812/47819 (trade only) |
| 45201 | Repair of motor vehicles, incl. overhauling | 95311/95314/95315/95319 (repair only) |
| 45202 | Repair of batteries for motor vehicles | includes 95314 battery repair |
| 45203 | Vulcanizing/preparing of tires | 95311/95319 |
| 95311 | (reverse) | 45201, 45202, 45203, 45209 |

Trade and repair are cleanly separated: every division-45 source lands
wholly in 46/47 **or** wholly in 95, never straddling both. Divisions
58–63 map on a clean diagonal with no cross-contamination.

## Artifact statistics, before → after

| | Before | After |
|---|---|---|
| Total edges | 2,699 | **3,285** |
| Section-level rows | **0** | **23** |
| discontinued (unmapped 2019) | 143 | **6** |
| new (unmatched 2026) | 251 | 172 |
| derived | 2,510 | 3,247 |
| suggested | 189 | **38** |
| official | 0 | **0** (unchanged, enforced by test) |
| high confidence | 1,985 | 2,147 |

The large fall in `suggested` and in `discontinued` is the point: structural
evidence replaced fuzzy guesses, and whole dissolved divisions now resolve.

## UI fixes

- **UI-01** footer overlay — root cause was bslib fill-page mode, not a
  fixed/sticky footer; page-level chain opted out of viewport filling.
- **UI-02** Sources rebuilt as a registry-driven card deck with native
  `<details>` disclosures; zero nested scroll regions.
- **UI-03** redundant DataTables search removed from all three grids
  (`dom = "tip"`); sorting, pagination and info line retained.
- **UI-04** `All levels` is a real selected option via a non-empty sentinel,
  translated to `NULL` before reaching any service.
- **UI-05** conditional Component control for composite systems; adapter
  extra columns now survive search so source provenance stays visible.
- **META-01** verified in Search selector, Sources cards and RM registry.

## Tests

| Gate | Result |
|---|---|
| Starting baseline | 1103 / 1103 |
| After registry convergence | 1835 / 1835 |
| After correspondence rebuild | 1835 / 1835 |
| **Final full regression** | **1904 / 1904** |

`0 failures, 0 warnings, 0 skips.` +801 tests, no regressions. Every
previously passing test still passes; four assertions were legitimately
updated (three "7 registered systems" counts, and the canonical-columns
check relaxed to "first ten, in order" to accommodate composite extras).

## Browser UAT

Verified against a live app. Screenshots are unavailable in this
environment (the browser pane does not composite), so verification was by
DOM geometry, computed styles and the accessibility tree.

| Check | Result |
|---|---|
| Five destinations render | pass |
| PSGC `negros` + All levels | pass — 4 results across **Reg, Prov and Bgy** |
| Blank-query browse | pass |
| Archived edition selection | pass |
| PSCC punctuated codes | pass — `0301.99.49-001`, `10.06` verbatim |
| PTSCS component switching | pass — product filter isolates products |
| PSCrCS component switching | pass — 114 occupations exactly |
| Correct PSCCS label | pass |
| No native DT search field | pass — 0 present |
| Compare Editions G repair | pass — 45201 → 95311/95314/95315/95319, split, warning shown |
| Compare Editions reverse | pass — 2026 T → 2019 S **and** G |
| Sources deck | pass — 13 cards, 8 collapsed disclosures, 0 scroll traps |
| Footer overlap | pass — static, no overlap at any viewport |
| RM disabled state | pass — calm unavailable panel, other tabs unaffected |
| RM composer 375 / 320 px | pass — Send 44×44, in viewport, in a11y tree |
| Viewports 1440 / 1366 / 768 / 375 / 320 | pass — no horizontal overflow |

**No live LLM provider evaluation was performed** — no credentials are
available. RM was exercised with a fake key, which verifies UI states and
the deterministic tool layer only. No multilingual or grounding-behaviour
claims are made from a live model.

## Known limitations

- **No live RM provider evaluation** (no credentials). Unchanged from the
  RM milestone; all 12 evaluation cases remain pending a real key.
- **No official PSA 2019↔Revision 5 crosswalk is incorporated.** Every
  correspondence edge is `derived` or `suggested`; none is `official`,
  enforced by test. If PSA publishes one, only rows it explicitly names may
  be relabelled.
- **Some repair mappings are moderate-confidence multi-target splits.**
  45202 (battery repair) returns four ranked candidates including the exact
  95314 counterpart rather than that one alone. This is deliberate —
  multiplicity must not be flattened — but precision could improve with a
  published crosswalk.
- **6 of 1,360 2019 sub-classes remain unmapped** (down from 143) and 172
  Revision 5 sub-classes are genuinely new. Both are honest findings after
  exhaustive deterministic search, not gaps in coverage.
- **PSIC Revision 5 groups: 261 parsed vs 260 stated by PSA** — pre-existing
  documented discrepancy, unchanged.
- **PSOC 2022 unit groups: 466 parsed vs 456 stated** — likewise
  pre-existing and documented.
- **Composite systems' codes are not globally unique** within a system;
  uniqueness is per `(component, code)`. Three PSCrCS collisions exist
  today. `get_classification_entry()` surfaces multi-row matches rather
  than hiding them.
- **Mid-stream RM provider-failure surfacing remains unwired** — upstream
  shinychat gap, documented in `docs/ASSISTANT_CONTRACT.md` §12.
- **No human has visually reviewed the rendered UI.** Verification was
  structural (DOM/a11y/computed style), not visual.
- ~~**`renv.lock` is out of sync**~~ — RESOLVED. This was a false positive:
  a local closure named `use()` in `R/correspondence/precedence.R` was being
  harvested by renv's dependency scanner as a package-declaring call.
  Renaming it cleared all five phantom dependencies; `renv::status()` now
  reports the project consistent.

## Staging readiness

All Definition-of-Done items in the master plan are satisfied: repaired
structural correspondence with forward/reverse symmetry and honest
provenance; PSCC / PTSCS / PSCrCS ingested and validated; PSCCS corrected;
All-levels default, redundant search removed, component controls, Sources
cards, no footer overlap, no mobile regressions; targeted and full
regression suites passing; all five destinations and both mobile floors
verified.

---

# Post–Connect Cloud staging UI refinement

Implements `POST_CONNECT_STAGING_UI_REFINEMENT_GRAPH.md` on
`feature/pre-staging-hardening`. Presentation and search-contract work; no
canonical classification content, correspondence edge, provenance,
confidence, curated PSOC override or RM grounding rule was changed.

**Regression: 3000 / 3000 passing, 0 fail / 0 warn / 0 skip** (from a
verified 2151 baseline; +849 assertions, all newly added).
`renv::status()`: *No issues found -- the project is in a consistent state.*
No dependency changed, so the Connect manifest was deliberately **not**
regenerated.

## What changed, by finding

| Finding | Outcome |
| --- | --- |
| UI-POST-01 Relationship terminology | Native `<details>` disclosures for Relationship, Provenance and Confidence in the Compare Editions panel. No JS tooltip dependency. |
| UI-POST-02 PSOC + PSIC independence | Shared `dual_search_query` removed. Each side now owns its query, edition, count, table and selection. |
| UI-POST-03 Component vs Level | Level hidden when it only restates Component; verdict derived from the artifact, not hard-coded. Public component and level labels throughout. |
| UI-POST-04 Dropdown overlay | Root cause was elevation/contrast, not z-index or overflow. Fixed as a scoped surface treatment, plus a real horizontal-overflow fix. |
| UI-POST-05 Result count | New count-aware search contract; the 200-row cap is never reported as the match total. |
| UI-POST-06 Edition / Release | Humanised release labels, calmer rows, hover/focus/selected states, textual Current/Archived. |
| UI-POST-07 PSCC source form | Structural rows preserved, hierarchy and breadcrumbs added, cross-reference search and labelling, honest level names. |

## Result-count contract

`search_classification_result()` / `search_classification_data_result()`
return `list(data, total_matches, returned_count, limit, is_truncated)`.
The pre-existing `search_classification()` and
`search_classification_data()` keep their exact tibble-returning
signatures, so RM tools and existing callers are untouched. Filtering and
ranking run **once** per call. `format_result_count()` is the single pure
source of the wording (`"3,487 results · showing first 200"`,
`"1 result"`, `"No results"`, `"200+ results"`).

## PSCC source-form model

Artifact grew 21,742 → 24,180 rows and 10 → 26 columns. The canonical ten
remain first and unchanged; sixteen extra columns carry `node_type`,
`display_depth`, `display_description`, `raw_description`, `breadcrumb`,
section/chapter/heading codes, `pscc_2022_code`, `unit_of_quantity`,
`pscc_2019_code`, `ahtn_2022_code`, `is_selectable_code`,
`is_structural_label`, `source_row`, `source_order`.

Levels are now
`section, chapter, heading, subheading, intermediate_category, commodity,
structural_group`. The former `ahtn subheading` level is **gone**: AHTN 2022
is a cross-reference, never a hierarchy level.

### Corrections to the specification's §9.1 workbook audit

The specification's counts were checked against
`data-raw/commodity classification.xlsx` and several are wrong. Implemented
against the actual workbook:

| §9.1 claim | Actual |
| --- | --- |
| 1,240 Heading rows | **1,245** |
| 2,297 eight-digit codes | **2,350** raw (2,346 after four same-code folds) |
| 15,926 detailed rows | **16,049** |
| 2,325 descriptor-only rows | 2,325 confirmed, but §9.1 omits **80 dash-less inline captions** and **66 sub-chapter rows** |
| (not mentioned) | **9 Excel-numeric cells** (e.g. `8701.2099999999991`, `20.059999999999999`) already repaired deterministically and recorded in `metadata$numeric_cell_repairs` |

### New defect found and fixed

1,647 workbook descriptions separate their dash markers with **U+00A0**,
which R's `[[:space:]]` does not match. Every one of those rows previously
read as hierarchy depth 0, so their structure was silently invisible.
Depth-1 rows went 2,795 → 3,656 once handled. Two further rows print a dash
marker with no following space; both are preserved verbatim and recorded in
`metadata$anomalies` (now 6 entries, was 4).

## Known limitations

- **Keyboard activation of the `<details>` disclosures could not be
  exercised through the browser automation**: its key dispatch does not
  trigger browser default actions — proven by a pristine, unstyled
  `<details>` control also failing to open under the same keystroke. The
  preconditions were verified instead (native `<summary>`, focusable, in the
  tab order, 2px focus ring, activates on click). `display` is deliberately
  left at `list-item`, because overriding it to a flex value strips native
  disclosure semantics in Chromium and WebKit.
- **`www/app.css` is served without a cache-busting query**, so a returning
  browser can hold a stale stylesheet after a redeploy. Observed repeatedly
  during this session's UAT. Not introduced here, but worth a hard refresh
  when reviewing staging.
- **Inline PSCC captions are placed as peers, not parents.** The workbook
  gives no unambiguous evidence of parentage; hierarchy was not invented.
- **No human has visually reviewed the rendered UI.** Verification was
  structural (DOM geometry, computed style, hit-testing, accessibility
  tree), not visual.

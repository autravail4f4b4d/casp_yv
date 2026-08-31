# Assistant Contract — RM Classification Assistant

The stable interface for RM, the conversational assistant embedded in the
PSA Statistical Classifications Search application. Read this alongside
`docs/UI_CONTRACT.md` (presentation) and `docs/DATA_SOURCES.md` /
`docs/CORRESPONDENCE_SOURCES.md` (classification provenance).

## 1. Purpose and boundary

RM helps a user who does not already know which classification system they
need, which code or wording to search, or how to describe an occupation or
establishment. It understands English, Filipino/Tagalog, Cebuano/Bisaya and
code-switched input, decides which read-only application tool to consult,
applies PSA's PSIC classification rules, asks one discriminating question
when evidence is insufficient, and explains a verified result.

**RM is not a source of classification codes.** The application's
classification repository is the sole authority for codes, labels,
editions, hierarchy, status and provenance. RM is a language interface on
top of it.

## 2. The absolute grounding rule

> RM must never state a PSOC, PSIC, PSGC, PSCED, PCOICOP, PCPC, PSCCS or any
> other classification code as the answer unless that exact code was
> returned by a registered application tool from a recognised local
> classification source.

The model **may** interpret, translate, normalise, compare, choose search
terms, pick tools, ask clarifying questions and explain retrieved results.
The model **may not** manufacture a code from memory, autocomplete an
unverified code, substitute model knowledge for a failed lookup, call an
unverified candidate official, or silently switch editions.

If a lookup fails, RM says the classification could not be verified from
the application's data.

This rule is enforced in three independent places, deliberately — a prompt
alone can be eroded by a long conversation:

| Layer | Enforcement |
|---|---|
| Prompt | `prompts/RM_SYSTEM_PROMPT.md` states the rule first, before anything else |
| Tool results | Every unverifiable lookup returns `found = FALSE` with an explicit "do not present this as an answer" instruction *inside the tool result* |
| Tests | `tests/testthat/test-assistant-tools.R` and `test-assistant-integration.R` assert no label is ever attached to an unverified code, and that only five read-only tools exist |

## 3. Evidence priority

```
1. Exact current/selected application classification record
2. Exact archived application classification record
3. Application hierarchy / description / provenance metadata
4. PSIC classification rules
5. Confirmed common PSOC/PSIC pairing table
6. Curated multilingual synonym table   (NOT AVAILABLE IN V1 - see §7)
7. LLM linguistic interpretation
```

A lower layer never overrides a contradictory official record.

## 4. Registered tools

Exactly five tools are registered. All are strictly read-only: no writes, no
file mutation, no shell, no network, no `eval`/`parse` of model input, no
model-driven path access. `rm_assistant_tools()` returns them as
`ellmer::tool()` objects, annotated `read_only_hint = TRUE`,
`destructive_hint = FALSE`, `open_world_hint = FALSE`.

Defined in `R/assistant/assistant_tools.R`.

### `assistant_search_classification(system, query, version = NULL, level = NULL, limit = 6)`
Wraps `search_classification()`. Resolves the system's **current** version
when `version` is omitted — never an archived edition by accident. Returns
`total_matches` plus at most `limit` compact rows (default 6, hard-clamped
to 25) with fields:
`system, version, level, code, label, short_description, status, source`.
`short_description` is `description` truncated to 200 characters. The full
canonical schema — notably `source_url` and `parent_code` — is deliberately
withheld here; that is what the entry tool is for.

### `assistant_get_classification_entry(system, version = NULL, code)`
Wraps `get_classification_entry()`. **This is the verification tool**: RM
calls it before presenting any code as an answer.

- Hit: `found = TRUE` plus `system, version, level, code, label, description, parent_code, status, source, source_url`.
- Miss: `found = FALSE`, the requested code echoed only as `requested_code`, and a message stating it is NOT a confirmed code and that a similar unverified code must not be offered instead. **No `label` field is present on a miss** — nothing official can be attached to an unverified code.
- Codes are matched as exact strings; leading zeros are never lost.
- **Codes are not guaranteed unique** within a system+version. The archived phscs PSOC 2012 edition carries 13 one-character codes where only 10 major groups exist, so `code = "1"` legitimately resolves to more than one row. The tool returns the first match and adds `additional_matches` / `additional_matches_note` rather than silently hiding the rest.

### `assistant_classification_registry()`
Compact registry: `id, display_name, current_version, available_versions, category` per system. The adapter metadata graph is not sent to the model.

### `assistant_search_common_pairings(occupation = NULL, psoc_code = NULL, industry_context = NULL, original_psic = NULL, limit = 6)`
Case-insensitive literal substring search (never regex) over the reviewed
CBMS pairing table. Returns at most `limit` rows with
`occupation, confirmed_psoc, confirmed_psoc_label, psoc_confidence, psoc_provenance, psoc_curation_note, source_industry, original_psic, psic_rev5_code, psic_rev5_rule, mapping_confidence, mapping_note, has_fixed_psic`.

Three behaviours are load-bearing:

- **The occupation layer and the industry layer are graded separately.** `psoc_confidence` grades the occupation mapping; `mapping_confidence` grades the PSIC mapping. They are different judgements and are never conflated. `confirmed_psoc_label` is the official PSOC 2022 title resolved from the canonical repository at build time, never copied from the workbook, so the pairing table cannot disagree with the classification of record.
- **No-fixed-PSIC rows are preserved as no-code evidence.** 44 of the 253 rows deliberately carry no Revision 5 code because the establishment's actual activity must be reported. Those rows keep `psic_rev5_code = NA` and `has_fixed_psic = FALSE`. They are never filled in from `original_psic` and never dropped.
- **Every result carries a caveat field**, verbatim: *"Supporting evidence only. These are reviewed common PSOC-PSIC pairings, not an authority. A pairing does NOT establish a particular establishment's PSIC — the establishment's actual economic activity does. Any code taken from here must still be verified with `assistant_get_classification_entry()` before it is presented as an answer."* This lives in the tool result, not just the prompt.

`psic_rev5_code` may be a multi-code string (`"96211 / 96220"`) or a range
(`"01171–01189"`, en dash). These are preserved verbatim; RM must still
verify any individual code it intends to present.

### `assistant_get_psic_rule(topic)`
Returns one compact rule (`topic, title, rule, example`) from the 12-topic
artifact — never all 12, and never the full 55K-character source document.
Valid topics:

```
unit_of_classification   economic_activity        principal_activity
secondary_activity       ancillary_activity       independent_mixed
top_down_bottom_up       horizontal_integration   vertical_integration
outsourced_subcontracted vague_information        common_mistakes
```

An unknown topic returns the list of valid topics rather than erroring.

## 5. PSOC vs PSIC — the separation that must not erode

```
PSOC = occupation / the kind of work a person performs
PSIC = economic activity / the industry of an establishment or enterprise
```

A worker's occupation must never determine the employer's PSIC. The
canonical failing case is *"Accountant ko sa private company. Unsay PSIC sa
company?"* — RM must ask what the company actually does, not infer an
industry from the occupation. A common pairing may accelerate a PSOC
lookup; it never establishes a particular establishment's PSIC.

For PSIC, vague terms (`contractor`, `trading`, `general services`,
`financial services`, `online business`) are insufficient on their own: RM
probes rather than guesses, and preserves principal / secondary / ancillary
and horizontal / vertical / outsourced logic from the rules artifact.

## 6. Multilingual behaviour

Input: English, Filipino/Tagalog, Cebuano/Bisaya, Taglish, Bislish, mixed
phrasing, colloquialisms, spelling variants. No language selector.

Output: reply in the user's dominant language where practical; clear
English when uncertain.

**Official classification titles are preserved exactly as stored.** An RM
translation or paraphrase is never presented as an official PSA title.

## 7. Synonyms — deliberately absent in V1

`data-raw/classification_synonyms.csv` does not exist, so no synonym
artifact was built and **`assistant_lookup_synonyms` is not registered as a
tool**. A stub exists that reports unavailability, and a test asserts the
tool is absent from the registered list. This is intentional: a fabricated
synonym table would be an ungrounded path to a code. The architecture
accommodates one later without change — build the artifact, then register
the tool.

## 8. Provider configuration

All configuration is server-side environment variables. No secret appears
in `app.R`, client HTML, JavaScript, a committed `.Renviron`, or this
repository.

| Variable | Default when unset | Meaning |
|---|---|---|
| `RM_ASSISTANT_ENABLED` | **disabled** (fail-closed) | Master switch. `false`/`0`/`no`/`off`/empty disable |
| `RM_PROVIDER` | `openai` | `openai` or `anthropic` |
| `RM_MODEL` | `gpt-4o-mini` | Model id |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | — | Read by ellmer itself; presence is only *checked* here, the value is never read into a variable or passed through the deprecated `api_key=` argument |

Fail-closed is deliberate: an unconfigured public deployment must not
attempt a billable call on every message.

`rm_assistant_status()` returns `list(enabled, available, reason)`. `reason`
is short, non-technical and safe to show a public user; provider error text
and stack traces are logged server-side only.

**Session isolation:** `create_rm_chat_client()` constructs a NEW `ellmer`
`Chat` on every call and caches nothing. An `ellmer` `Chat` is mutable R6
holding conversation turns; a shared client would leak one public user's
conversation into another's. Only the immutable system prompt text is
memoised.

If tool registration fails, the client is discarded and `NULL` returned
rather than handing back a tool-less client that would answer from model
memory.

## 9. Degradation

| Condition | Behaviour |
|---|---|
| `RM_ASSISTANT_ENABLED` false / credentials missing / prompt file missing | RM panel renders `rm_assistant_unavailable_ui()`; Search, Browse/Archive, Dual Search and Compare PSIC Editions are entirely unaffected |
| Common-pairings artifact missing | Pairing tool returns `available = FALSE` with "do not invent pairings from memory"; official search and verification continue |
| PSIC rules artifact missing | Rule tool returns `available = FALSE` and **explicitly instructs that model memory must not be substituted**; RM tells the user detailed rule assistance is unavailable and falls back to official text search |
| Classification lookup fails | Structured error result; RM does not guess. No stack trace reaches the user |
| Provider fails mid-stream | **Known limitation — see §12** |

## 10. Token discipline

Compact system prompt (~4.4K chars). Static greeting — no model call is
spent generating it. Bounded tool results (6 classification candidates, 6
pairings). One rule retrieved at a time, never the 55K source. Immutable
artifacts memoised once per R process. No embeddings or vector search in
V1.

Intended interaction shape:
`understand intent → smallest retrieval → bounded shortlist → verify the selected candidate → answer`.

## 11. Evaluation cases

`tests/evals/rm_assistant_cases.yml` holds the 12 representative cases from
the specification, each with `expect` / `must_not` behaviours. The file
serves two distinct purposes:

- **Deterministic** (`tests/testthat/test-assistant-evals.R`, runs today, no API key): structural integrity of the fixture, plus verification of the factual claims it makes about local data — e.g. that PSOC `999999` genuinely does not resolve, that PSGC really is the system covering barangays, and that PSIC 2019 really is archived while 2026 is current. This keeps the grounding expectations from becoming vacuous.
- **Live** (requires a provider): the `user` turns replayed against a real RM session and judged against `expect` / `must_not`.

**No live evaluation has been run** — no provider credentials were
available in the build environment. Record any future run's date, model and
per-case outcome in `IMPLEMENTATION_STATUS.md`.

## 12. Known limitations

- **Mid-stream provider failure is silent client-side.** If the provider fails *after* successful configuration (revoked key, network fault, rate limit), shinychat rolls the transcript back and restores the user's text but shows nothing explaining why. The failure is logged server-side and no secret or stack trace reaches the browser, so this is a UX gap, not a safety one. A fix was attempted and deliberately reverted rather than left half-working: detection was proven to work (a failed stream leaves an *empty* assistant turn on the client, distinguishable from a real reply), but three separate surfacing approaches against shinychat 0.4.0 — the chat module's `append()`, top-level `shinychat::chat_append()`, and `showNotification()` — all failed to reach the DOM on the errored-stream path. Revisit when shinychat exposes an error hook on its chat module.
- **No live multilingual or behavioural evaluation has been performed** (§11).
- **The provider round-trip on a handled coding turn cannot be suppressed from this application's layer.** `shinychat::chat_mod_server()` hard-codes `client$stream_async(...)` inside its own `input$chat_user_input` observer, exposes no cancel or skip on its returned handle, and `ellmer::Chat`'s methods are locked bindings, so the call cannot be intercepted without forking shinychat or proxying the Chat object. The turn is therefore still sent, with **no tools offered** and its output never appended (§15.1); the cost is tokens, not correctness. Revisit if shinychat gains a "server already answered" path.
- **An explanation turn still leaves one contentless assistant bubble.** The carrier in §15.2 removes it for coding turns by streaming the deterministic answer, but an explanation's text can only be validated once the stream is complete, so the streaming message stays empty and the guarded reply is appended after it. Coding turns — the whole named regression matrix — are unaffected.
- **The `svg` transcript artefact is fixed at both mechanisms it was traced to, but final confirmation needs a live browser.** Both causes are proven in R against the installed shinychat 0.4.0: suppressed `NULL` chunks injecting `<shinychat-raw-html></shinychat-raw-html>` into the markdown buffer (executed directly), and `chunk_end` committing an empty assistant message that is then rendered with a raw `<svg>` placeholder icon (read from the shipped reducer). This worktree has no provider credential, so the DOM was not re-observed after the fix.
- **Enter does not submit** in shinychat 0.4.0's composer; the send button is required. Upstream behaviour, not configured here.
- **`assistant_get_psic_rule()` quality is bounded by the compaction.** The 12 rules are a hand-authored ~19% distillation of the source document, reviewable in `scripts/build_assistant_assets.R`. Rule text the compaction omits is not available to RM at runtime.
- **The pairing workbook's `mapping_confidence` is PSA-source confidence**, not a calibrated probability, and is passed through unmodified.
- **Curated occupation mappings are an application judgement, not PSA correspondence.** `psoc_provenance` is `source_workbook` for the published mapping or `curated` for an approved manual correction recorded in `data-raw/curated_psoc_overrides.csv`; the value is deliberately outside the `official`/`derived`/`suggested` correspondence vocabulary so a curated mapping can never read as an official PSA table. Curated rows are `High` confidence, carry their rationale and any retained ambiguity in `psoc_curation_note`, and are still subject to the pairing caveat: the code must be verified with `assistant_get_classification_entry()` before it is presented. An override is declared as either a `correction` (the workbook's code is replaced) or a `confirmation` (the workbook's code was already right and only the review outcome is recorded), so a confirmation can never be read as a code change. The build hard-fails if the workbook no longer carries the code an override says it carries, if an override matches more or fewer than one row, if it targets a code that does not exist in the canonical PSOC 2022 repository, or if the declared kind disagrees with whether the code actually moved.

## 13. What a design pass may and may not change

May change freely: all presentation in `R/ui/ui_assistant.R` and the
assistant CSS in `www/app.css`, provided the stable ids in
`docs/UI_CONTRACT.md` survive.

Must not change without backend review: the grounding rule and its three
enforcement points; the tool list, argument names and result field sets;
the pairing caveat and no-fixed-PSIC handling; the no-model-memory
instruction in the degraded rule result; the fail-closed default of
`RM_ASSISTANT_ENABLED`; and per-session client construction.

## 14. Clarification lifecycle

### 14.1 Turn precedence

Every turn is resolved in this fixed order, entirely in R, before any
provider call:

```text
explicit new coding request   >  stale pending clarification
valid bounded clarification reply  >  fresh global retrieval
```

`assistant_explicit_new_coding_request(text)` is TRUE only when the turn
carries an explicit coding signal (`psoc`, `psic`, `code`,
`classification`, `classify`, `coding`, or any other registered system id)
**and** a substantive subject survives after the signal tokens and the
ordinary request scaffolding are stripped. A bare `psic`, `what is the
code` or `please give me the code` therefore remains an answer to the
outstanding question; `statistician at PSA psoc psic` starts a new one.

### 14.2 Pending state schema

`assistant_turn_set_pending()` stores canonical option identity, not
display prose:

```text
pending = list(
  active            = TRUE,
  route             = "contextual_coding",
  requested_systems = c("psoc", "psic"),
  occupation, establishment_activity, wage_payer,
  missing_slot      = "establishment_activity_detail",
  question          = "<the deterministic question, verbatim>",
  system            = "psic",
  parent_code       = "8531",
  options           = list(list(index = 1L, code = "85312", label = "..."),
                           list(index = 2L, code = "85314", label = "...")),
  packet            = <the clarification_required packet that asked>
)
```

`options` and `packet` are what make a reply resolvable: the options carry
the codes the coding service already verified, and the packet carries every
fact that is **not** the answered slot (a resolved PSOC, for instance), so
completing the slot preserves them instead of re-deriving them from the
reply text.

### 14.3 Bounded resolution

When a question offers options, the reply is resolved against **those
options and nothing else**. No lexical, fuzzy, n-gram, semantic or global
retrieval is reachable from this path. Resolution order:

1. **Ordinal / positional reference** — `1`–`4`, `1st`–`4th`,
   `first`–`fourth`, `option N`, `the Nth`, `Nth one`, `former`, `latter`,
   with `the` optional throughout. Case-insensitive, punctuation and
   whitespace tolerant. `former`/`latter` resolve **only** when exactly two
   options exist; with three or more they identify nothing and are refused.
   An index beyond the option count is refused, never clamped.
2. **Exact option label**, normalised for case and punctuation.
3. **Unique token subset** — every token of the reply appears in exactly
   one option's label (`upland` → `Growing of rice in upland`). A subset
   that fits more than one option (`special needs`, `growing of rice`) is
   **not** a match.

A selected option is re-verified against the canonical repository before it
can become an answer (`assistant_verified_option_half()`): unknown code, or
any edition status other than `current`, returns nothing and the question is
asked again.

A reply the bounded set cannot interpret re-asks **the same question**,
unchanged, with the same options and the same pending state. The
application never invents a second, differently worded question for the
same slot.

### 14.4 Short ambiguous replies

For an **open** activity slot (no options), a reply consisting of a single
qualifier from `ASSISTANT_AMBIGUOUS_SHORT_REPLIES` — `residential`,
`private`, `public`, `government`, `commercial`, `hospital`, `school`,
`farm`, … — names a setting, not an activity, and is refused rather than
retrieved. The question narrows instead
(`assistant_narrow_activity_question()`), naming no code. The refusal is
strictly single-token: `residential construction` says what the
establishment does and still resolves normally.

### 14.5 Cleanup

Pending state is cleared when the clarification resolves, when an explicit
new coding request supersedes it, on New chat, and when the session ends.
A resolved turn leaves no pending state.

## 15. Deterministic rendering and the explanation policy

### 15.1 Deterministic only, by default

For a `resolved`, `clarification_required` or `no_verified_match` coding
packet the contract is:

```text
deterministic packet -> deterministic render -> END TURN
```

The model is **never** invoked to add prose to a coding answer, and its
output is never appended automatically. On a handled route it is offered no
tools at all, its streamed text is suppressed chunk by chunk, and the
authoritative rendering is what the transcript receives.

### 15.2 One message per turn

`assistant_turn_set_render()` / `assistant_turn_take_render()` hand this
turn's authoritative rendering to the **first** content chunk of the
stream, so the streaming assistant message carries the answer itself. This
exists because `shinychat`'s `chunk_end` reducer commits a streaming
message to the transcript whether or not anything was written into it: a
fully suppressed turn previously left a contentless assistant bubble —
rendered with shinychat's raw `<svg>` placeholder icon — sitting beside the
real answer. If the provider emits no content chunk at all, app.R appends
the same text instead, so the answer never depends on the model speaking.

Suppressed chunks return `""`, never `NULL`. `shinychat::chat_append_message()`
branches on the value: a character scalar is appended verbatim, while a
`NULL` is routed through `pre_process_ui()`, which appends the literal
markup `<shinychat-raw-html></shinychat-raw-html>` into the transcript once
per suppressed chunk.

### 15.3 Explanation policy

The model may speak only when the user explicitly asks it to —
`assistant_explanation_requested()` matches short meta questions such as
`why?`, `explain this`, `what does this mean?`, `what is the difference?`,
`bakit?`, `pakipaliwanag`. Such a turn:

- is **not** coded and is **not** treated as a clarification reply;
- leaves the pending state and the latest packet exactly as they were;
- keeps the `contextual_coding` route, so the response guard still runs.

The generated text is appended only if it passes
`assistant_guard_response()`. It cannot change codes, labels, status,
`allowed_codes` or clarification state, because none of those are re-derived
on an explanation turn. If the explanation fails or is rejected, the
deterministic facts already rendered remain sufficient.

After every handled coding turn `assistant_ground_turns()` replaces the
model's own discarded assistant turn in the provider history with the text
the user actually saw. The history stays alternating (no turn is added),
an explanation request has the real answer in context, and one turn's
spontaneous language change cannot seed the next.

### 15.4 Transcript hygiene

`assistant_transcript_artifacts()` rejects generated prose containing
`<svg`/`svg`, `shinychat-raw-html`, `shiny-tool-request`,
`shiny-tool-result`, a registered tool name, an `assistant_*(` call, the
words `tool request`/`tool result`/`tool call`, or a raw JSON object. A
rejected reply is replaced by the deterministic rendering. The
deterministic renderer cannot produce any of these by construction — it
emits only markdown built from packet fields — and this is asserted
directly over the renders of the whole regression matrix.

The bare word `clear`, which the governing specification also lists, is
deliberately **not** treated as an artefact in generated prose: it is
ordinary English ("that is clear"), and rejecting a reply for containing it
would discard sound explanations. It cannot appear from this application's
side, because the deterministic renderer never emits it — which is the
property actually asserted.

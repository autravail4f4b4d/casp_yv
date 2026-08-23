# CLAUDE.md

## Project

This repository is the **PSA Statistical Classifications Search** application.

It is an R Shiny + `bslib` public-facing reference application for Philippine statistical classifications.

### Historical implementation references

The original MVP specification is:

`PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`

The completed post-MVP classification extension specification is:

`PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md`

These remain architectural and regression references.

### Current authoritative milestone

The current implementation specification is:

`PSA_CLASSIFICATIONS_RM_ASSISTANT_INTEGRATION.md`

Read that file before modifying the application for the current milestone.

If an older implementation document conflicts with the RM specification, preserve the verified classification baseline and follow the RM specification for assistant-related work.

---

## Verified Functional Baseline

The classification application is already functionally complete for the pre-assistant baseline.

The verified baseline includes:

- PSIC Revision 5 / 2026 PSIC as current;
- PSIC 2019 retained as archived;
- PSOC 2022 as current/default;
- PSOC 2012 retained as archived;
- deterministic classification search;
- Browse / Archive behavior;
- parallel PSOC + PSIC search;
- bidirectional PSIC 2019 ↔ 2026 correspondence;
- correspondence provenance: `official`, `derived`, `suggested`;
- split, merge/complex, reverse-lookup, no-match, and confidence states;
- offline normalized runtime artifacts;
- PSA-oriented source/provenance metadata;
- stable service and UI contracts documented in `docs/UI_CONTRACT.md`.

The last verified functional baseline had:

```text
485 / 485 tests passing
0 failures
0 warnings
0 skips
```

Do not weaken or bypass this baseline to implement RM.

If repository state differs, verify Git state and run the tests before assuming the baseline is intact.

---

## Current Implementation Phase — RM Classification Assistant

The current milestone is the implementation of the **RM Classification Assistant** defined in:

`PSA_CLASSIFICATIONS_RM_ASSISTANT_INTEGRATION.md`

The current work must:

1. add RM as a normal chat experience inside the existing Shiny application;
2. use `shinychat` for the chat UI;
3. use `ellmer` for model/tool integration;
4. reuse the existing classification repository and service functions;
5. keep all model-facing tools read-only;
6. create one mutable chat client per Shiny user session;
7. preserve Search, Browse / Archive, Dual Search, and PSIC Correspondence behavior;
8. keep the deterministic app usable when RM is disabled, misconfigured, or unavailable;
9. build compact local assistant assets from approved source files;
10. implement only minimal functional assistant presentation in this phase;
11. update `docs/UI_CONTRACT.md`;
12. create and maintain `docs/ASSISTANT_CONTRACT.md`;
13. update `IMPLEMENTATION_STATUS.md`;
14. stop before the final unified visual redesign.

The final UI/UX pass remains a separate **Claude Design** phase.

---

## Engineering Method

Use graph engineering with parallel workstreams where dependencies allow.

Use bounded implementation loops:

1. Inspect.
2. Implement the smallest complete change.
3. Run the targeted test.
4. Diagnose failures.
5. Patch narrowly.
6. Re-test.
7. Freeze the workstream when its acceptance criteria pass.

Parallelize independent workstreams where supported.

Do not allow multiple agents to modify the same files concurrently.

Use explicit file ownership for parallel workstreams.

Use tests as persistent behavioral verification rather than repeatedly re-reading or re-reasoning about completed behavior.

Do not refactor unrelated working code simply because a new milestone is being implemented.

---

## Context and Token Efficiency

Do not repeatedly read the entire repository.

At the beginning of a new or resumed session:

1. inspect `git status`;
2. inspect the current branch;
3. inspect recent commits;
4. read `CLAUDE.md`;
5. read `IMPLEMENTATION_STATUS.md`;
6. read the current milestone specification;
7. confirm the relevant baseline tests;
8. inspect only files needed for the active workstream.

Before each workstream:

- use targeted searches;
- inspect existing tests and contracts first;
- read only relevant files;
- consume workstream/subagent summaries before reopening all changed files;
- use passing tests as compressed behavioral memory.

Each parallel workstream should report:

- status;
- files changed;
- tests run;
- test results;
- public contracts added or changed;
- unresolved risks.

Do not duplicate work across agents.

---

## Architecture Rules

Maintain strict separation between:

1. classification data sources/adapters;
2. canonical classification repository;
3. deterministic search/version/correspondence services;
4. assistant evidence/tool layer;
5. assistant provider/client layer;
6. Shiny reactive/controller layer;
7. presentation/UI layer.

Classification, correspondence, and assistant tool logic should be testable without launching the full Shiny UI where practical.

Do not place classification-specific transformation logic directly inside Shiny reactives.

Do not place assistant grounding logic directly inside UI rendering code.

The UI must depend on stable service/tool contracts.

The assistant must reuse the existing classification repository. Do not create a second classification repository or duplicate the deterministic search engine.

---

## Classification Data Rules

PSA is the authoritative classification source.

`phscs` and `psgc` are software/data-access mechanisms, not the issuing authority.

### PSIC

PSIC Revision 5 / 2026 PSIC is current and must remain supported.

PSIC 2019 must remain available as an archived reference.

Do not bypass the existing supplemental PSIC Revision 5 ingestion merely because `phscs` changes in the future.

Any future migration to package-provided Revision 5 data must preserve:

- canonical schema;
- provenance;
- archive behavior;
- version behavior;
- correspondence behavior;
- tests.

Runtime classification search must not require PSA website availability.

### PSOC

PSOC 2022 is current/default and must remain supported.

PSOC 2012 must remain available as an archived reference.

Do not silently fall back to 2012 while displaying 2022.

Preserve the normalized offline PSOC 2022 artifact and source metadata.

### Codes

Never:

- fabricate classification codes or labels;
- convert codes to numeric values where formatting or leading zeros matter;
- silently substitute one edition for another;
- label archived editions as current;
- suppress required version/status/source metadata.

---

## Correspondence Rules

The PSIC 2019 ↔ 2026 correspondence layer is part of the verified baseline.

Preserve:

- bidirectional lookup;
- one-to-one relationships;
- split relationships;
- merge/complex relationships;
- no-match states;
- qualitative confidence;
- provenance;
- statistical safety warnings.

Allowed provenance values:

```text
official
derived
suggested
```

Never label inferred or algorithmically generated correspondence as `official`.

Classification correspondence must never be used to automatically redistribute historical statistical values among revised categories.

Do not simplify one-to-many, many-to-one, or complex relationships into a false one-to-one mapping for UI convenience.

---

## RM Assistant — Absolute Grounding Rule

The most important assistant rule is:

> **No retrieved code = no classification code presented as the answer.**

RM must never present a PSOC, PSIC, PSGC, PSCED, PCOICOP, PCPC, PSCCS, or other classification code as the answer unless that exact code was returned by a registered read-only application tool from a recognized local classification source.

The model may:

- interpret natural language;
- normalize descriptions;
- translate conversational phrasing;
- choose tools;
- search;
- compare candidates;
- ask clarifying questions;
- explain verified results.

The model may not:

- invent a code from memory;
- autocomplete an unverified code;
- replace a failed lookup with model knowledge;
- present an unverified candidate as authoritative.

If a code cannot be verified, RM must say that it could not verify it from the application's available classification data.

---

## RM Assistant — Evidence Priority

Use this evidence hierarchy:

```text
1. Exact current/selected application classification record
2. Exact archived application classification record
3. Application hierarchy / description / provenance metadata
4. PSIC classification rules
5. Confirmed common PSOC/PSIC pairing table
6. Curated multilingual synonym table
7. LLM linguistic interpretation
```

Lower-priority evidence must never override contradictory official classification data.

---

## RM Assistant — PSOC and PSIC Separation

Preserve:

```text
PSOC = occupation / kind of work performed by a person
PSIC = principal economic activity / industry of an establishment or enterprise
```

A person's occupation must not determine a private establishment's PSIC by itself.

For PSOC:

- use duties and main tasks;
- search official PSOC candidates;
- ask one short discriminating question when multiple candidates remain plausible.

For PSIC:

- determine what the establishment actually does;
- apply the approved PSIC rules;
- probe vague descriptions rather than guessing;
- preserve principal, secondary, ancillary, horizontal/vertical integration, and outsourced/subcontracted logic where applicable.

Do not classify a business solely from vague terms such as:

- contractor;
- trading;
- general services;
- financial services;
- online business.

Ask what activity is actually performed.

---

## RM Assistant — Approved Source Assets

The assistant may use approved local source artifacts such as:

```text
PSIC_Chatbot_Classification_Rules.md
data-raw/CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping.xlsx
data-raw/classification_synonyms.csv
```

Inspect actual filenames before implementation.

Build compact runtime artifacts instead of parsing the raw workbook/rules file on every turn.

Recommended runtime assets:

```text
data/assistant_common_pairings.rds
data/assistant_psic_rules.rds
data/assistant_synonyms.rds
```

The common PSOC/PSIC pairing table is supporting evidence only.

It must not override official classification logic or be treated as a universal PSIC mapping.

Rows indicating no fixed PSIC must remain no-code evidence.

---

## RM Assistant — Model-Facing Tools

Keep the model-facing tool surface small, bounded, and read-only.

Expected wrappers include:

```text
assistant_search_classification()
assistant_get_classification_entry()
assistant_classification_registry()
assistant_search_common_pairings()
assistant_get_psic_rule()
assistant_lookup_synonyms()   # only if synonym data exists
```

These must wrap existing deterministic application services.

Do not expose:

- shell execution;
- arbitrary filesystem writes;
- arbitrary URL fetching;
- database mutations;
- delete/update actions;
- credentials or secrets.

Tool results must be compact and bounded.

Do not send entire classification tables to the model.

---

## RM Assistant — Session Isolation

Create a separate mutable `ellmer` chat client inside each Shiny user session.

Do not reuse one global mutable chat object across public users.

Public users must not share conversational state.

Immutable classification and assistant assets may be cached globally where safe.

---

## RM Assistant — Provider Configuration

Keep the provider configurable.

Do not hard-code credentials.

Example environment variables may include:

```text
OPENAI_API_KEY
RM_MODEL
RM_ASSISTANT_ENABLED
```

Real credentials must never be committed to:

- R source files;
- JavaScript;
- HTML;
- Markdown documentation;
- `.Renviron`;
- `.env`;
- test fixtures.

`.Renviron` and `.env*` must remain ignored by Git.

If credentials are absent or RM is disabled:

- the base classification app must still start;
- deterministic Search/Browse/Dual Search/Correspondence must still work;
- RM should hide cleanly or show an unavailable state.

---

## RM Assistant — Failure and Degradation

Assistant failure must never break the deterministic application.

### Provider unavailable

Show a clean unavailable state and direct users to the ordinary classification search.

### Classification tool error

Do not continue by guessing.

### Pairing artifact unavailable

Continue using official classification search. Do not disable RM solely because optional pairing evidence is unavailable.

### PSIC rules artifact unavailable

Do not silently substitute model memory for detailed PSIC methodology.

Degrade safely to ordinary official classification search.

---

## Multilingual Behavior

RM should accept:

- English;
- Filipino/Tagalog;
- Cebuano/Bisaya;
- Taglish;
- Bislish/Cebuano-English;
- mixed Filipino/Cebuano/English;
- common occupational/business colloquialisms;
- reasonable spelling and grammar variation.

Do not require users to select a language.

Respond primarily in the user's language when practical.

Official classification titles must remain exactly as stored unless an official translated title exists.

Never present an assistant translation as an official PSA title.

---

## Token and Cost Discipline

Optimize for low token usage without compromising grounding.

Do not inject into every request:

- full classification tables;
- all archived editions;
- full correspondence artifacts;
- the entire PSIC rules Markdown;
- the full pairing workbook;
- the entire synonym table.

Prefer:

```text
intent
→ smallest relevant tool call
→ bounded shortlist
→ verify likely answer
→ concise response
```

Use a static greeting.

Cache immutable local assistant assets once per R process where practical.

Do not add embeddings/vector search in V1 unless evaluation demonstrates a real retrieval gap.

---

## Scope Restrictions

For the current RM milestone, do not introduce unless the current specification genuinely requires it:

- PostgreSQL;
- SQLite;
- Redis;
- vector databases;
- LangChain;
- REST APIs;
- Plumber;
- GraphQL;
- React;
- Next.js;
- Vue;
- a second frontend;
- a second deployment;
- authentication;
- user accounts;
- admin CMS;
- assistant write/update/delete tools;
- runtime PSA API dependency;
- persistent public chat-history storage;
- final branding/decorative redesign.

Expected new assistant dependencies are primarily:

```text
shinychat
ellmer
```

Prefer the smallest dependency surface that satisfies the RM specification.

---

## UI

Use Shiny + `bslib` for the application and `shinychat` for RM.

During this milestone:

- implement a functional RM Assistant navigation/view;
- use a static opening greeting beginning **“Madayaw! I am RM.”**;
- support streaming;
- support cancel/stop;
- support fresh/new chat;
- support starter suggestions;
- support mobile/narrow layouts;
- provide accessible labels and states;
- keep styling minimal and semantic;
- do not perform the final unified visual redesign.

Create and maintain:

```text
docs/UI_CONTRACT.md
docs/ASSISTANT_CONTRACT.md
```

The future Claude Design pass must be able to redesign presentation without rewriting:

- classification adapters;
- repository logic;
- deterministic search;
- archive/version behavior;
- PSIC correspondence;
- assistant grounding/tool contracts;
- assistant source normalization.

---

## Testing

Use `testthat` for deterministic/unit/integration behavior.

Run targeted tests after each workstream.

Before declaring the RM milestone complete:

1. run all assistant-specific tests;
2. run the full regression suite;
3. confirm all valid classification tests remain passing;
4. perform browser UAT;
5. verify streaming/cancel/new-chat behavior;
6. verify provider-disabled/unavailable behavior;
7. verify session isolation;
8. verify the no-code-without-retrieval rule;
9. verify vague PSIC cases probe instead of guessing;
10. verify PSOC does not determine private-company PSIC;
11. verify English, Filipino/Tagalog, Cebuano/Bisaya, and mixed-language evaluation cases;
12. verify Search/Browse/Dual Search/Correspondence remain functional.

Do not claim a test passed unless it was actually executed.

Do not claim browser UAT passed unless it was actually performed.

Do not claim deployment succeeded unless remote deployment was actually performed.

Maintain representative assistant evaluation fixtures such as:

```text
tests/evals/rm_assistant_cases.yml
```

or an equivalent repository-consistent format.

---

## Security and Data Integrity

Never:

- fabricate classification codes or labels;
- silently substitute an edition;
- expose provider credentials;
- expose secrets in frontend code;
- expose shell/filesystem mutation tools to the model;
- persist public users' personal data without an approved requirement;
- expose raw provider stack traces to users;
- let provider/model failure break the deterministic application;
- allow assistant inference to outrank contradictory local classification data.

All registered model tools must remain read-only.

---

## Git and Change Discipline

Before significant work:

1. inspect current branch;
2. inspect `git status`;
3. inspect relevant diffs;
4. confirm baseline tests.

Do not discard uncommitted work unless explicitly instructed.

Do not commit automatically unless explicitly requested.

When a previous session was interrupted, recover actual repository state before implementing.

Do not modify historical milestone tags.

Prefer milestone-specific branches.

---

## Completion

Maintain:

`IMPLEMENTATION_STATUS.md`

For the current RM milestone it must accurately identify:

- verified starting baseline;
- RM implementation status;
- assistant dependencies;
- assistant runtime assets;
- assistant tool contracts;
- prompt/client status;
- UI integration status;
- assistant tests/evals;
- full regression result;
- browser UAT;
- multilingual status;
- provider/deployment configuration;
- degradation behavior;
- known limitations;
- deferred enhancements;
- Claude Design handoff readiness.

The RM implementation phase is complete only when the acceptance criteria in:

`PSA_CLASSIFICATIONS_RM_ASSISTANT_INTEGRATION.md`

are satisfied.

Stop before the final major visual redesign.

---

## Current Milestone Summary

```text
Verified Classification Application
        │
        ├── Search
        ├── Browse / Archive
        ├── PSOC 2022 current / 2012 archived
        ├── PSIC 2026 current / 2019 archived
        ├── Dual PSOC + PSIC Search
        ├── PSIC 2019 ↔ 2026 Correspondence
        │
        └── RM Classification Assistant
                ├── shinychat
                ├── ellmer
                ├── read-only grounded tools
                ├── multilingual interaction
                ├── PSIC rule retrieval
                ├── common-pairing evidence
                ├── no code without retrieval
                ├── safe degradation
                └── session-isolated chat state
```

After RM passes its tests and browser UAT, update the contracts/status documents and hand the complete functional application back to **Claude Design** for the final unified UI/UX pass.

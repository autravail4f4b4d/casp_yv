# RM Classification Assistant — Web App Integration Handoff

**Feature:** Grounded conversational assistant for the PSA Statistical Classifications Search web application  
**Assistant name:** RM  
**Primary application:** Existing R Shiny statistical classifications search MVP  
**Primary assistant stack:** `shinychat` + `ellmer` + existing application service/repository functions  
**Deployment target:** Same Shiny deployment as the existing app (for example Posit Connect Cloud or equivalent)  
**Design principle:** Conversationally intelligent, deterministically grounded, read-only, low-overhead, and fail-safe  
**Implementation method:** Graph engineering + bounded loop engineering + parallel workstreams where contracts permit  
**Primary source artifacts:**

- `PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`
- `PSIC_Chatbot_Classification_Rules.md`
- `CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping(2).xlsx`
- existing normalized PSIC Revision 5 artifact and classification repository produced by the base app

---

# 0. EXECUTIVE IMPLEMENTATION DIRECTIVE

Add **RM**, a normal chat-style assistant, to the existing PSA Statistical Classifications Search application.

RM must make the application feel substantially easier and more intelligent for users who do not already know:

- which classification system they need;
- which code or description to search;
- how to describe an occupation or establishment;
- whether more information is needed before a PSOC or PSIC can be selected;
- how to distinguish a current edition from an archived reference;
- how common Cebuano/Bisaya, Filipino/Tagalog, English, or code-switched descriptions relate to official classification terminology.

RM is **not** an alternative source of classification codes.

The existing application repository remains the source of truth for official classification entries, editions, hierarchy, status, and provenance.

The assistant's role is to:

1. understand natural-language questions;
2. normalize messy descriptions into useful search concepts;
3. decide which existing read-only application tools to consult;
4. apply the PSIC classification rules when PSIC reasoning is required;
5. consult the confirmed common PSOC/PSIC pairing table as supporting evidence;
6. ask a concise discriminating question when information is insufficient or ambiguous;
7. explain a verified result in plain language;
8. respond naturally in English, Filipino/Tagalog, Cebuano/Bisaya, or mixed language where practical.

The assistant must **never invent a statistical classification code**.

---

# 1. REQUIRED USER EXPERIENCE

## 1.1 Normal chatbot interface

Implement RM as a conventional conversational interface using `shinychat`.

For the initial integration, prefer a dedicated application navigation panel:

```text
Search
Browse / Archive
RM Assistant
About / Data Sources
```

This is preferable to redesigning the existing Search screen during the first assistant implementation.

The assistant view should contain:

- assistant/user chat bubbles;
- a persistent text input at the bottom;
- streamed assistant replies;
- a cancel/stop control while a reply is streaming;
- a clear/new-chat control;
- optional starter suggestion cards;
- a short footer/disclaimer;
- mobile-friendly fill behavior.

Do not create a separate React/Next.js chat application.

Do not introduce a second deployment.

---

## 1.2 Required opening greeting

Use a static opening message so that no model tokens are spent generating it.

Recommended text:

> **Madayaw! I am RM.** I can assist you in finding and understanding Philippine statistical classifications such as PSOC, PSIC, PSGC, PSCED, PCOICOP, PCPC, and PSCCS. You can describe an occupation, business activity, code, or classification in English, Filipino/Tagalog, Cebuano/Bisaya, or a mix of these languages. If I need more information to narrow down the correct classification, I’ll ask you a short follow-up question.

Optional second line:

> I use the classification data and rules available in this application, so I may ask for clarification rather than guess.

Recommended initial suggestion cards:

```text
Find the PSOC for an occupation
Help me classify a business under PSIC
Explain a classification code
Which classification system should I use?
```

These suggestions should populate or submit the chat input using the normal `shinychat` suggestion behavior.

---

## 1.3 Assistant response style

RM should normally respond in a concise, practical format.

For a sufficiently supported result:

```text
Likely classification: PSOC 4311 — Accounting and bookkeeping clerks

Why it fits:
You described accounts-payable and bookkeeping/record-maintenance work.

Edition: 2022 PSOC
Status: Current/available in the selected application edition
Source: Philippine Statistics Authority

If your main work is instead auditing or professional accounting rather than maintaining accounting records, tell me and I can narrow it further.
```

For ambiguous input:

```text
I found more than one plausible occupation.

Which takes most of your working time:
1. assisting customers and selling merchandise; or
2. operating the cash register?

That distinction will help me narrow the PSOC.
```

For insufficient PSIC information:

```text
I can help with the PSIC, but “contractor” is not specific enough to classify.

What does the business actually do—for example, residential construction, electrical installation, cleaning, security, IT services, or another activity?
```

RM should not bury users in methodology unless they ask for it.

---

# 2. NON-NEGOTIABLE GROUNDING RULES

## 2.1 No retrieved code = no code in the answer

This is the most important rule.

```text
RM MUST NOT state a PSOC, PSIC, PSGC, PSCED,
PCOICOP, PCPC, PSCCS, or other classification
code as the answer unless that exact code has been
returned by a registered application tool from a
recognized local classification source.
```

The LLM may:

- interpret;
- translate;
- normalize;
- compare;
- choose search terms;
- decide which tool to call;
- ask clarifying questions;
- explain retrieved results.

The LLM may **not** manufacture a code from memory.

---

## 2.2 Official repository outranks all assistant inference

Evidence priority:

```text
1. Exact current/selected application classification record
2. Exact archived application classification record
3. Application hierarchy / description / provenance metadata
4. PSIC classification rules
5. Confirmed common PSOC/PSIC pairing table
6. Curated multilingual synonym table
7. LLM linguistic interpretation
```

A lower-priority layer must never override a contradictory official classification record.

---

## 2.3 The common pairing workbook is evidence, not an authority over PSIC logic

The uploaded mapping workbook contains useful reviewed/common mappings, including:

- occupation;
- confirmed 2022 PSOC;
- source industry/context;
- original PSIC;
- PSIC Revision 5 code(s);
- Revision 5 description/rule;
- mapping confidence;
- mapping notes;
- PSA source.

It also deliberately contains cases where **no fixed PSIC exists** because the actual company/establishment activity must be reported.

Therefore:

```text
A common PSOC–PSIC pairing may strengthen or accelerate
a candidate lookup, but it must not be used to infer an
establishment's PSIC solely from a worker's occupation.
```

Example:

```text
"accountant in a private company"
```

may be enough to search PSOC candidates, but it is **not** enough to infer the company's PSIC.

For PSIC, RM must ask what the establishment actually does when that information is missing.

---

## 2.4 PSIC must follow the PSIC rules file

For PSIC questions, preserve the decision logic from:

```text
PSIC_Chatbot_Classification_Rules.md
```

RM must recognize, when applicable:

- establishment versus enterprise;
- actual economic activity;
- principal activity;
- secondary activity;
- ancillary activity;
- independent mixed activities;
- horizontally integrated activities;
- vertically integrated activities;
- outsourced/subcontracted activities;
- vague or insufficient descriptions;
- common classification mistakes.

Important behavior:

```text
If the activity description is insufficient,
PROBE rather than GUESS.
```

For multiple activities, use the principal-activity logic defined in the rules file.

Do not classify by:

- business name alone;
- physical appearance;
- the most visible activity;
- a secondary or ancillary activity;
- the word "contractor" or "outsourced";
- a vague term such as "trading", "financial services", "online business", or "general services".

---

## 2.5 PSOC behavior

The current source set contains a confirmed/common 2022 PSOC mapping table but does **not** contain a dedicated full PSOC reasoning rules document equivalent to the PSIC rules file.

Therefore, in V1:

- use the official PSOC repository to retrieve candidate occupations;
- use occupation descriptions/tasks supplied by the user to search and disambiguate;
- use reviewed common mappings as supporting evidence;
- ask about main duties when multiple PSOC candidates remain plausible;
- do not claim a detailed PSOC methodological rule that is not present in the source material.

A future enhancement may add:

```text
PSOC_Chatbot_Classification_Rules.md
```

without changing the assistant architecture.

---

# 3. MULTILINGUAL BEHAVIOR

## 3.1 Supported conversational input

RM should accept:

- English;
- Filipino/Tagalog;
- Cebuano/Bisaya;
- Taglish;
- Bislish / Cebuano-English;
- mixed Filipino/Cebuano/English phrasing;
- common occupational and business colloquialisms;
- spelling variants and minor grammatical errors.

Do not require users to select a language before asking a question.

---

## 3.2 Response language

Default behavior:

```text
If the user primarily writes in Cebuano/Bisaya:
    respond naturally in Cebuano/Bisaya where practical.

If the user primarily writes in Filipino/Tagalog:
    respond naturally in Filipino/Tagalog where practical.

If the user writes in English:
    respond in English.

If the user code-switches:
    a natural mixed-language response is acceptable.

If uncertain:
    use clear English.
```

Official classification titles should be preserved as stored in the application.

An assistant translation or explanation must not be presented as an official PSA title unless the application source explicitly provides that translated title.

---

## 3.3 Synonym strategy

Do not delay V1 until a large multilingual dictionary exists.

Use two layers:

```text
LLM language normalization
          +
curated synonym lookup
```

Recommended optional source file:

```text
data-raw/classification_synonyms.csv
```

Recommended normalized runtime artifact:

```text
data/assistant_synonyms.rds
```

Suggested schema:

```text
term
language
normalized_concept
classification_system
candidate_code
candidate_label
ambiguity_group
confidence
verified
notes
```

Allow a synonym to point to multiple candidates.

Example conceptual behavior:

```text
"tindera"
    → shop salesperson candidate
    → cashier candidate
    → ask which duty is primary if retrieval remains ambiguous
```

Never treat one colloquial word as an unconditional code mapping unless it has been reviewed and is unambiguous in context.

---

# 4. ASSISTANT ARCHITECTURE

Use the existing application's functional-core architecture.

```text
                         USER
                           │
                           ▼
                 ┌──────────────────┐
                 │ shinychat UI     │
                 │ RM Assistant     │
                 └────────┬─────────┘
                          │
                          ▼
                 ┌──────────────────┐
                 │ ellmer Chat      │
                 │ per user session │
                 └────────┬─────────┘
                          │
                   registered tools
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌───────────────┐ ┌────────────────┐ ┌───────────────────┐
│ Classification│ │ Assistant local│ │ Rule / terminology│
│ service layer │ │ evidence layer │ │ layer             │
└───────┬───────┘ └───────┬────────┘ └─────────┬─────────┘
        │                 │                    │
        │                 │                    │
        ▼                 ▼                    ▼
existing functions    common_pairings.rds   psic_rules.rds
classification data   synonyms.rds          compact rules
phscs / psgc /
PSIC 2026 snapshot
```

The assistant must reuse the same application service functions already required by the base app.

Do not copy classification tables into the system prompt.

Do not create a second repository abstraction.

---

# 5. REQUIRED ASSISTANT TOOLS

Keep the tool surface small.

Tool arguments and results should be simple and compact because both consume model tokens.

## 5.1 `assistant_search_classification()`

Wrap the existing:

```r
search_classification(
  system,
  version,
  query,
  level = NULL,
  limit = ...
)
```

Assistant tool contract:

```r
assistant_search_classification(
  system,
  query,
  version = NULL,
  level = NULL,
  limit = 6
)
```

Behavior:

1. resolve default/current version if version is omitted;
2. call the existing repository/service function;
3. return at most 6 candidates by default;
4. return only fields useful to the assistant.

Compact result fields:

```text
system
version
level
code
label
short_description
status
source
```

Do not return 100 search rows to the LLM.

The normal Search UI may still show the full application result set.

---

## 5.2 `assistant_get_classification_entry()`

Wrap:

```r
get_classification_entry(system, version, code)
```

Use this to verify a candidate before RM presents it as an answer.

Return:

```text
system
version
level
code
label
description
parent_code
status
source
source_url
```

If the exact entry is not found:

```text
found = false
```

RM must not present that code as verified.

---

## 5.3 `assistant_classification_registry()`

Wrap the existing registry.

Use for questions such as:

```text
Which classification should I use?
What classification covers occupations?
What classification covers industries?
```

Return a compact list of:

```text
id
display_name
current_version
available_versions
category_or_scope
```

Do not send the entire adapter metadata graph to the LLM.

---

## 5.4 `assistant_search_common_pairings()`

Build from:

```text
CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping(2).xlsx
```

Runtime artifact:

```text
data/assistant_common_pairings.rds
```

Recommended callable interface:

```r
assistant_search_common_pairings(
  occupation = NULL,
  psoc_code = NULL,
  industry_context = NULL,
  original_psic = NULL,
  limit = 6
)
```

Return only:

```text
occupation
confirmed_psoc
source_industry
original_psic
psic_rev5_code
psic_rev5_rule_or_description
mapping_confidence
mapping_note
```

Special handling:

```text
If PSIC Rev. 5 code is missing or mapping confidence is N/A:
    preserve that signal;
    do not fill in a code;
    let RM ask for the establishment activity if necessary.
```

The workbook's rows with “No fixed PSIC code in the source document” must remain no-code evidence.

---

## 5.5 `assistant_get_psic_rule()`

Do not inject the entire long PSIC rules Markdown into every conversation.

Create a compact local rules artifact at build time.

Recommended rule keys:

```text
unit_of_classification
economic_activity
principal_activity
secondary_activity
ancillary_activity
independent_mixed
top_down_bottom_up
horizontal_integration
vertical_integration
outsourced_subcontracted
vague_information
common_mistakes
```

Callable interface:

```r
assistant_get_psic_rule(topic)
```

Return only the requested compact rule and, where useful, one short source example.

The full original Markdown remains documentation and evaluation material.

---

## 5.6 `assistant_lookup_synonyms()` — optional but recommended

If a curated synonym table exists:

```r
assistant_lookup_synonyms(
  term,
  language = NULL,
  system = NULL,
  limit = 8
)
```

Return candidate concepts/codes only.

The assistant must still verify any resulting code using `assistant_get_classification_entry()`.

---

# 6. TOOL-CALL POLICY

RM should prefer the smallest number of calls necessary.

General order:

```text
1. Understand intent.
2. If exact code + known system/version:
       verify exact entry.
3. Else:
       search relevant classification.
4. If common occupation/context appears:
       optionally search common pairings.
5. For PSIC reasoning:
       retrieve only the relevant PSIC rule.
6. If one candidate is sufficiently supported:
       verify exact entry.
7. If ambiguity remains:
       ask one discriminating question.
```

Avoid this pattern:

```text
search every classification
+ search pairings
+ load every rule
+ load synonym table
+ then answer
```

Use tools only as required by the question.

---

# 7. INTENT ROUTING

The model may perform intent routing linguistically, but the following conceptual map should be included in its instructions.

```text
occupation / job / work / duties
    → PSOC

industry / establishment / business activity
    → PSIC

geographic code / region / province / city / municipality / barangay
    → PSGC

education / level / field / program classification
    → PSCED where supported by the application

individual consumption expenditure
    → PCOICOP where supported

products / commodities
    → PCPC where supported

construction-related statistical classification
    → PSCCS where supported

uncertain classification system
    → query classification registry
    → explain or ask one clarifying question
```

Do not force every query into PSOC or PSIC.

---

# 8. REQUIRED SYSTEM PROMPT

Create:

```text
prompts/RM_SYSTEM_PROMPT.md
```

Use the following as the initial prompt.

---

## RM SYSTEM PROMPT

You are **RM**, the conversational classification assistant inside a Philippine statistical classifications search application.

Your purpose is to help users find, understand, and narrow down official statistical classifications available through this application.

Users may write in English, Filipino/Tagalog, Cebuano/Bisaya, or code-switched combinations. Understand these naturally. Reply in the user's main language when practical. Preserve official classification labels exactly as returned by the application.

### Absolute grounding rule

Never state that a PSOC, PSIC, PSGC, PSCED, PCOICOP, PCPC, PSCCS, or other classification code is the answer unless that exact code has been returned by one of your registered classification tools.

Do not invent, recall from memory, autocomplete, or infer an unverified classification code.

If a tool cannot verify the code, say that you could not verify it from the application's available classification data.

### Use the application, not model memory

Use the registered tools to:

- search classifications;
- verify exact entries;
- inspect classification versions/status;
- consult common reviewed PSOC/PSIC pairings;
- consult relevant PSIC classification rules;
- consult curated synonyms where available.

The application's classification repository is authoritative for the codes and labels shown to the user.

### PSOC

For occupation questions, determine what work the person actually performs. Use duties, main tasks, and occupational descriptions to search candidate PSOC entries.

If two or more occupations remain plausible, ask one short question that best distinguishes them.

Do not infer the employer's PSIC from the worker's PSOC or occupation alone.

### PSIC

For industry questions, determine what the establishment or enterprise actually does.

Follow the PSIC rules available through the PSIC rule tool.

In particular:

- distinguish establishment from enterprise when it matters;
- identify the actual goods produced or services provided;
- classify according to the principal activity when required;
- distinguish secondary and ancillary activities;
- recognize independent mixed, horizontal, vertical, and subcontracted/outsourced situations;
- do not classify by business name or physical appearance;
- do not treat vague terms such as trading, contractor, financial services, online business, or general services as sufficient for a detailed classification.

When the information is insufficient, ask a targeted probing question instead of guessing.

### Common pairings

The common PSOC/PSIC mapping table is supporting evidence only.

A common pairing does not prove that an establishment has that PSIC.

If the pairing record has no fixed PSIC or says the specific company activity must be reported, preserve that uncertainty and ask about the establishment's actual activity.

### Ambiguity

Prefer one high-information follow-up question over several generic questions.

Do not give a low-confidence code merely to avoid asking a question.

### Response style

Be concise, helpful, and professional.

When a classification is supported, normally provide:

1. classification system;
2. verified code and official label;
3. concise reason it fits;
4. edition/version;
5. current/archive status when relevant;
6. source/provenance when useful;
7. one brief caveat or follow-up only if needed.

Do not expose internal tool syntax, raw JSON, or hidden reasoning.

Do not imply that an assistant translation is an official PSA translation.

### Scope

If a user asks for information outside the classifications available in the application, say so clearly rather than fabricating an answer.

---

# 9. STATIC GREETING AND STARTER SUGGESTIONS

Do not ask the LLM to generate the greeting.

Use a static `shinychat` greeting/message.

Conceptual implementation:

```r
rm_greeting <- "
**Madayaw! I am RM.** I can assist you in finding and understanding
Philippine statistical classifications such as PSOC, PSIC, PSGC,
PSCED, PCOICOP, PCPC, and PSCCS.

You can describe an occupation, business activity, code, or
classification in English, Filipino/Tagalog, Cebuano/Bisaya, or
a mix of these languages.

Here are a few things you can ask:

- <span class='suggestion submit'>Find the PSOC for an occupation</span>
- <span class='suggestion submit'>Help me classify a business under PSIC</span>
- <span class='suggestion submit'>Explain a classification code</span>
- <span class='suggestion submit'>Which classification system should I use?</span>
"
```

Footer:

```text
RM is an assistant for classification search and interpretation.
Verified codes come from the classification data available in this application.
When details are insufficient, RM may ask a follow-up question rather than guess.
```

---

# 10. SHINY MODULE CONTRACT

Use a Shiny module so each user session has its own LLM chat state.

Recommended conceptual files:

```text
R/
  assistant/
    assistant_client.R
    assistant_tools.R
    assistant_data.R
    assistant_prompt.R
  ui/
    ui_assistant.R
```

Stable module ID:

```text
rm_assistant
```

UI:

```r
rm_assistant_ui <- function(id) {
  ns <- shiny::NS(id)

  shinychat::chat_mod_ui(
    id,
    messages = rm_greeting
  )
}
```

Server concept:

```r
rm_assistant_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {

    client <- create_rm_chat_client()

    register_rm_tools(client)

    shinychat::chat_mod_server(
      id,
      client = client
    )
  })
}
```

Exact function signatures should be adjusted to the installed versions of `shinychat` and `ellmer` at implementation time.

Important:

```text
Create a new ellmer chat client INSIDE each Shiny user session.
Do not reuse one mutable chat client globally across public users.
```

---

# 11. MODEL-PROVIDER CONFIGURATION

Keep the provider configurable.

Do not hard-code provider credentials in source code.

Example environment variables:

```text
OPENAI_API_KEY
RM_MODEL
RM_ASSISTANT_ENABLED
```

Recommended behavior:

```text
If RM_ASSISTANT_ENABLED is false
or required provider credentials are missing:
    keep the deterministic search/browse app functional;
    show the RM panel as unavailable or hide it cleanly.
```

Do not let assistant configuration failure break the classification search app.

Do not place API keys in:

- `app.R`;
- JavaScript;
- client HTML;
- committed `.Renviron`;
- repository documentation containing real secrets.

---

# 12. BUILD-TIME ASSISTANT DATA NORMALIZATION

The runtime assistant should not parse the Excel workbook or the full rules Markdown on every user turn.

Create:

```text
scripts/build_assistant_assets.R
```

Inputs:

```text
data-raw/CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping.xlsx
PSIC_Chatbot_Classification_Rules.md
data-raw/classification_synonyms.csv     # optional
```

Outputs:

```text
data/assistant_common_pairings.rds
data/assistant_psic_rules.rds
data/assistant_synonyms.rds              # if source exists
```

The build script should validate:

### Pairings

- required columns exist;
- PSOC codes remain character strings;
- original PSIC codes remain character strings;
- Revision 5 codes remain character strings;
- blank/no-fixed-code rows remain blank;
- mapping confidence is preserved;
- source industry/context is preserved.

### PSIC rules

- required rule topics are extracted;
- no speaker-note appendix is unnecessarily inserted into runtime rules;
- the compact runtime artifact preserves the substantive rule logic.

### Synonyms

- language is present;
- term is nonblank;
- multiple-candidate synonyms are allowed;
- `verified` is preserved;
- no synonym silently creates an official code that does not exist in the classification repository.

---

# 13. TOKEN-EFFICIENCY RULES

This feature must be optimized for low token usage without sacrificing grounding.

## 13.1 Never put classification tables into the prompt

Do not send:

- all PSOC rows;
- all PSIC rows;
- all pairings;
- all archived versions;
- the entire rules document;
- the speaker-note appendix

on every request.

Retrieve only what is needed.

---

## 13.2 Use a compact system prompt

The runtime system prompt should be the compact RM prompt in this document.

Do not append the complete `PSIC_Chatbot_Classification_Rules.md` to each conversation.

Detailed PSIC rules must be pulled only when needed through:

```r
assistant_get_psic_rule(topic)
```

---

## 13.3 Limit tool results

Recommended defaults:

```text
classification search: 6 candidates
pairing search:        6 candidates
synonym lookup:        8 candidates
```

Return only the fields needed for reasoning.

Do not return long provenance descriptions repeatedly.

---

## 13.4 Verify only the likely answer

Preferred pattern:

```text
search → shortlist → verify selected code → answer
```

Avoid:

```text
search → verify every candidate → search again → load every rule → answer
```

unless ambiguity genuinely requires it.

---

## 13.5 Use deterministic fast paths where easy

Optional optimization after the basic assistant works:

```text
If the user enters an exact code
AND the active classification system/version is known:
    query the local repository directly first.
```

The final conversational explanation may still use the LLM, but the retrieval does not need a broad semantic search.

Do not delay the first working assistant to implement this optimization.

---

## 13.6 Cache immutable assistant assets

Load once per R process where practical:

```text
assistant_common_pairings.rds
assistant_psic_rules.rds
assistant_synonyms.rds
```

Do not reread the XLSX or Markdown on every message.

Classification data should follow the base application's existing in-memory/cache behavior.

---

## 13.7 Do not add embeddings/vector search in V1

The first assistant should rely on:

```text
LLM language understanding
+
existing deterministic search
+
common pairings
+
curated synonyms
+
classification rules
```

Add semantic/vector retrieval only if real evaluation data later demonstrates a retrieval gap.

---

# 14. GRAPH ENGINEERING PLAN

Implement as a dependency graph.

```text
                         ┌───────────────────────┐
                         │ A. Contract/Foundation│
                         └───────────┬───────────┘
                                     │
              ┌──────────────────────┼────────────────────────┐
              ▼                      ▼                        ▼
   ┌──────────────────┐   ┌────────────────────┐   ┌────────────────────┐
   │ B. Assistant data│   │ C. Tool wrappers   │   │ D. UI + prompt     │
   │ normalization    │   │ + grounding        │   │ module             │
   └─────────┬────────┘   └──────────┬─────────┘   └─────────┬──────────┘
             │                       │                       │
             └──────────────┬────────┴──────────┬────────────┘
                            ▼                   ▼
                    ┌────────────────┐   ┌─────────────────┐
                    │ E. Chat client │   │ F. Unit/eval    │
                    │ integration    │   │ tests           │
                    └───────┬────────┘   └────────┬────────┘
                            └──────────┬───────────┘
                                       ▼
                              ┌──────────────────┐
                              │ G. Shiny app     │
                              │ integration/UAT  │
                              └─────────┬────────┘
                                        ▼
                   ┌────────────────────┼────────────────────┐
                   ▼                    ▼                    ▼
          ┌────────────────┐  ┌──────────────────┐  ┌──────────────────┐
          │ H. Deployment  │  │ I. Security/cost │  │ J. Final audit   │
          │ config/docs    │  │ guardrails       │  │ + handoff        │
          └────────────────┘  └──────────────────┘  └──────────────────┘
```

Do not build the assistant as one monolithic `app.R` patch.

---

# 15. PARALLEL WORKSTREAMS

## Wave 0 — contract/foundation

Inspect only:

```text
CLAUDE.md if present
repository tree
app.R
R/registry.R
R/repository.R
R/search.R
R/metadata.R
R/ui/
tests/testthat/
docs/UI_CONTRACT.md
IMPLEMENTATION_STATUS.md
```

Confirm:

- base service functions exist and pass tests;
- current system/version contracts;
- current Shiny navigation IDs;
- actual installed `shinychat` and `ellmer` APIs.

Do not reread all classification source data.

---

## Wave 1A — assistant data assets

File ownership:

```text
scripts/build_assistant_assets.R
R/assistant/assistant_data.R
data/assistant_common_pairings.rds
data/assistant_psic_rules.rds
data/assistant_synonyms.rds
tests/testthat/test-assistant-data.R
```

Tasks:

1. normalize common pairings workbook;
2. extract compact PSIC rules;
3. optionally normalize synonyms;
4. validate no-code rows;
5. preserve mapping confidence and source context;
6. test character-code preservation.

Do not touch UI files.

---

## Wave 1B — tool wrappers

File ownership:

```text
R/assistant/assistant_tools.R
tests/testthat/test-assistant-tools.R
```

Implement:

```text
assistant_search_classification()
assistant_get_classification_entry()
assistant_classification_registry()
assistant_search_common_pairings()
assistant_get_psic_rule()
assistant_lookup_synonyms()      # if data exists
```

Tests must verify:

- tools return bounded results;
- exact codes are not modified;
- unavailable code returns `found = false`;
- no-code pairing remains no-code;
- archived/current metadata is preserved;
- tool outputs do not contain unnecessary full tables.

Do not touch UI files.

---

## Wave 1C — prompt and client

File ownership:

```text
prompts/RM_SYSTEM_PROMPT.md
R/assistant/assistant_prompt.R
R/assistant/assistant_client.R
tests/testthat/test-assistant-prompt.R
```

Tasks:

- write/load compact RM prompt;
- create provider-configurable ellmer client;
- register tools;
- ensure client is created per user session;
- fail cleanly when assistant credentials are absent.

Do not modify classification search logic.

---

## Wave 1D — assistant UI

File ownership:

```text
R/ui/ui_assistant.R
www/app.css                # minimal assistant adjustments only
```

Tasks:

- normal chat UI;
- static greeting;
- starter suggestions;
- footer;
- fill/mobile behavior;
- accessible label/title;
- no decorative redesign.

Do not alter repository/search contracts.

---

# 16. CONVERGENCE WORKSTREAM

After Wave 1 components pass their tests:

Integrate:

```text
assistant data
+
assistant tools
+
RM prompt/client
+
assistant UI
```

into the application.

Modify the smallest possible set of shared files, likely:

```text
app.R
R/ui/navigation file if present
renv.lock / dependency files
docs/UI_CONTRACT.md
```

Do not duplicate business logic in Shiny server code.

---

# 17. LOOP ENGINEERING RULES

Every assistant workstream must use a bounded loop.

```text
INSPECT CONTRACT
      ↓
IMPLEMENT SMALLEST COMPLETE CHANGE
      ↓
RUN TARGETED TEST
      ↓
EVALUATE
   ├── pass → freeze workstream contract
   └── fail → identify smallest cause
                  ↓
              patch once
                  ↓
              retest
```

Constraints:

1. Maximum three repair iterations per acceptance criterion.
2. Do not rewrite passing base-app functions.
3. Do not refactor unrelated classification adapters.
4. Do not tune visual design during assistant grounding work.
5. Do not repeatedly load the full rules Markdown into agent context.
6. Use tests as compressed memory.
7. Each parallel workstream returns:
   - files changed;
   - tests run;
   - result;
   - unresolved risk;
   - whether a public contract changed.
8. Main integration agent reads summaries before reopening implementation files.
9. If a contract defect is found in the base app, patch it centrally rather than working around it independently in multiple assistant files.
10. Stop when acceptance criteria pass.

---

# 18. TOKEN-EFFICIENT CLAUDE CODE OPERATING RULES

For the implementation agent:

- read this handoff once;
- read only the relevant existing files for the active workstream;
- grep for service function names rather than rereading the repository;
- do not give two subagents the same task;
- parallelize only after the public contracts are known;
- do not ask subagents to summarize the entire repo;
- do not paste full classification datasets into prompts;
- do not paste the full 55k+ character PSIC rules document into each subagent prompt;
- point the data-normalization workstream to the rules file and exact sections it needs to extract;
- keep tool result schemas small;
- encode behavioral requirements in tests instead of repeating them in prompts.

---

# 19. P0 ACCEPTANCE TESTS

## 19.1 UI

- [ ] `RM Assistant` is available from normal app navigation.
- [ ] The first message begins with **“Madayaw! I am RM.”**
- [ ] Chat input remains anchored and usable on narrow/mobile viewport.
- [ ] Assistant replies stream.
- [ ] User can stop/cancel a streaming reply.
- [ ] User can start a fresh chat.
- [ ] Starter suggestions work.
- [ ] Existing Search/Browse views still work unchanged.

---

## 19.2 Grounding

- [ ] RM never returns a code that was not returned by a classification tool.
- [ ] Exact retrieved code preserves leading zeros where applicable.
- [ ] Version and archive/current status are preserved.
- [ ] Source/provenance remains PSA-oriented.
- [ ] Missing exact entry is reported as unverified rather than fabricated.

---

## 19.3 PSIC rules

- [ ] “Contractor” alone causes a probing question.
- [ ] “Trading” alone causes a probing question.
- [ ] A hotel + restaurant case can use principal-activity information rather than the business name/appearance.
- [ ] An internal commissary-only activity can be treated as ancillary where the source facts support it.
- [ ] Vertically integrated description can retrieve the relevant rule.
- [ ] Horizontally integrated description can retrieve the relevant rule.
- [ ] Outsourced activity is classified by the actual service/activity, not the word “outsourced”.

---

## 19.4 PSOC/PSIC distinction

- [ ] An occupation description can be used to search PSOC.
- [ ] “Accountant employed by a private company — what is the company's PSIC?” does not infer PSIC from occupation.
- [ ] A no-fixed-PSIC mapping record triggers establishment-activity probing.
- [ ] Confirmed/common mappings are described as supporting evidence, not universal rules.

---

## 19.5 Multilingual

- [ ] English occupation description works.
- [ ] Filipino/Tagalog occupation description works sufficiently to retrieve/search candidates.
- [ ] Cebuano/Bisaya occupation description works sufficiently to retrieve/search candidates.
- [ ] Mixed-language input does not fail.
- [ ] Official labels are not translated and presented as official unless the application actually provides them.

---

## 19.6 Other classifications

- [ ] Geography question can route toward PSGC.
- [ ] “Which classification should I use?” can consult the registry.
- [ ] RM does not invent unsupported classification systems.
- [ ] Archived edition questions retain archived status rather than calling them “wrong”.

---

# 20. REPRESENTATIVE EVALUATION CASES

Create:

```text
tests/evals/rm_assistant_cases.yml
```

or an equivalent compact fixture.

Minimum cases:

### Case 1 — exact PSOC-like work description

```text
User:
I maintain accounts payable and bookkeeping records.

Expected:
search PSOC;
return only a verified candidate;
briefly explain task match.
```

### Case 2 — Cebuano occupation description

```text
User:
Ako kasagaran naga-assist sa customer ug naga-arrange sa mga baligya sa tindahan.

Expected:
understand as retail/shop work;
search PSOC;
if multiple candidates remain, ask a duty-based question.
```

### Case 3 — ambiguous salesperson/cashier

```text
User:
Tindera ko, usahay cashier pud.

Expected:
do not immediately force one code;
ask which activity occupies most of the work.
```

### Case 4 — vague PSIC

```text
User:
Contractor among business.

Expected:
ask what contracting work the establishment actually performs.
```

### Case 5 — occupation does not determine private PSIC

```text
User:
Accountant ko sa private company. Unsay PSIC sa company?

Expected:
ask what the company/establishment actually does.
```

### Case 6 — common government pairing

```text
User:
Bookkeeping clerk in an LGU.

Expected:
pairing may support PSOC and government-industry context;
verify any code from official repository before presenting.
```

### Case 7 — principal activity

```text
User:
We operate a restaurant and catering service, but most earnings are from catering.

Expected:
use PSIC principal-activity rule;
search/verify the appropriate current PSIC candidate.
```

### Case 8 — ancillary activity

```text
User:
Our commissary prepares ingredients only for our own restaurant and catering operations.

Expected:
recognize ancillary/supporting character under the PSIC rules.
```

### Case 9 — no-result protection

```text
User:
Give me PSOC 999999 for this occupation.

Expected:
verify;
if absent, say it cannot be verified;
do not repeat it as a valid classification.
```

### Case 10 — system discovery

```text
User:
I need the classification code for a barangay.

Expected:
route toward PSGC.
```

### Case 11 — archived edition

```text
User:
Is this old PSIC edition wrong?

Expected:
explain that archived editions may be valid for historical data;
preserve edition/status.
```

### Case 12 — mixed language

```text
User:
Ang business namo kay nag-buy and sell ug electrical supplies wholesale sa hardware stores.

Expected:
understand product + wholesale context;
search PSIC;
verify returned code;
do not classify merely from “buy and sell”.
```

---

# 21. FAILURE AND DEGRADATION BEHAVIOR

## LLM unavailable

The base Search/Browse app must continue to work.

Display:

```text
RM Assistant is temporarily unavailable.
You can still search and browse all classifications using the main application.
```

Do not crash the Shiny session.

---

## Classification tool error

RM must not continue by guessing.

User-facing behavior:

```text
I couldn't verify that classification from the application's data just now.
Please use the main search or try again.
```

Log the developer-facing error without exposing stack traces.

---

## Pairings artifact missing

RM may continue using official classification search.

Do not disable the whole assistant.

Record the degraded evidence source.

---

## PSIC rules artifact missing

For detailed PSIC classification reasoning:

- do not silently substitute model memory;
- fall back to basic official text search;
- state that the detailed classification-rule assistance is unavailable;
- preserve normal Search/Browse functionality.

---

# 22. SECURITY AND PRIVACY

The assistant is public-facing.

Enforce:

- server-side API credentials only;
- HTML escaping for user text where required;
- no arbitrary file execution;
- no arbitrary URL fetching initiated from model arguments;
- no shell tools exposed to the LLM;
- no write/delete/update tools;
- no direct database mutation;
- no authentication data in prompts;
- no user personal data intentionally persisted in V1;
- no raw provider error/stack trace shown publicly.

Registered model tools must be **read-only**.

---

# 23. COST CONTROLS

Implement simple cost/latency controls:

- compact system prompt;
- bounded tool results;
- no full dataset injection;
- no full rules injection;
- static greeting;
- use one model client per session;
- avoid automatic model-generated welcome messages;
- avoid model calls when the assistant is disabled;
- optional per-session maximum turn count if public abuse becomes a concern;
- optional server-side rate limiting in a later deployment hardening pass.

Do not implement a complex metering database in V1.

---

# 24. OPTIONAL P1 ENHANCEMENTS — DO NOT BLOCK V1

After P0 passes:

- “Ask RM about this result” from the selected result detail view;
- “Open in Search” action from a verified RM answer;
- programmatically synchronize the Search tab to a verified assistant result;
- richer multilingual synonym dictionary;
- feedback buttons such as “Helpful / Needs review”;
- human-reviewed correction workflow;
- usage analytics;
- separate PSOC reasoning rules document;
- semantic/vector retrieval if evaluation proves necessary;
- persistent user chat history if a future authenticated version requires it.

Do not implement these before the grounded core assistant works.

---

# 25. RECOMMENDED REPOSITORY ADDITIONS

```text
psa-classifications/
├── app.R
├── R/
│   ├── registry.R
│   ├── repository.R
│   ├── search.R
│   ├── versions.R
│   ├── metadata.R
│   ├── assistant/
│   │   ├── assistant_client.R
│   │   ├── assistant_tools.R
│   │   ├── assistant_data.R
│   │   └── assistant_prompt.R
│   └── ui/
│       ├── ui_search.R
│       ├── ui_details.R
│       ├── ui_sources.R
│       └── ui_assistant.R
├── prompts/
│   └── RM_SYSTEM_PROMPT.md
├── data/
│   ├── psic_2026.rds
│   ├── assistant_common_pairings.rds
│   ├── assistant_psic_rules.rds
│   └── assistant_synonyms.rds
├── data-raw/
│   ├── PSIC_Revision_5_Detailed_Structure_30July2026.xlsx
│   ├── CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping.xlsx
│   └── classification_synonyms.csv
├── scripts/
│   ├── build_psic_2026.R
│   └── build_assistant_assets.R
├── tests/
│   ├── testthat/
│   │   ├── test-assistant-data.R
│   │   ├── test-assistant-tools.R
│   │   ├── test-assistant-prompt.R
│   │   └── test-assistant-integration.R
│   └── evals/
│       └── rm_assistant_cases.yml
├── docs/
│   ├── UI_CONTRACT.md
│   ├── DATA_SOURCES.md
│   ├── DEPLOYMENT.md
│   └── ASSISTANT_CONTRACT.md
└── IMPLEMENTATION_STATUS.md
```

If the repository is already organized differently, preserve the existing structure and make the smallest compatible adjustment.

---

# 26. DEPENDENCY DELTA

Add only what is required.

Likely new R dependencies:

```text
shinychat
ellmer
```

Use existing dependencies for:

```text
shiny
bslib
dplyr
stringr
tibble
purrr
readxl
testthat
```

Do not add LangChain, a vector database, a REST API framework, or a JavaScript chat framework for V1.

At implementation time, inspect the installed package versions and use their current documented APIs.

---

# 27. DOCUMENTATION UPDATES

Update:

```text
docs/UI_CONTRACT.md
```

with:

- new `RM Assistant` view;
- stable module ID `rm_assistant`;
- initial/loading/streaming/error/unavailable states;
- assistant does not alter existing classification search semantics.

Create:

```text
docs/ASSISTANT_CONTRACT.md
```

containing:

- assistant purpose;
- grounding hierarchy;
- tool list;
- tool input/output contracts;
- model-provider configuration;
- no-code-without-retrieval rule;
- multilingual behavior;
- degradation behavior;
- evaluation cases;
- known limitations.

Update:

```text
IMPLEMENTATION_STATUS.md
```

with:

```text
## RM Assistant Status
## Assistant Dependencies
## Assistant Tool Tests
## Assistant Evaluation Cases
## Multilingual Status
## Known Assistant Limitations
## Provider/Deployment Configuration
```

---

# 28. CURRENT IMPLEMENTATION REFERENCES TO VERIFY

Use current official package documentation during implementation.

`shinychat`:

```text
https://posit-dev.github.io/shinychat/r/articles/get-started.html
https://posit-dev.github.io/shinychat/r/reference/chat_app.html
```

`ellmer` tool calling:

```text
https://ellmer.tidyverse.org/articles/tool-calling.html
https://ellmer.tidyverse.org/reference/tool.html
```

Important current behaviors to verify against the installed versions:

- `chat_mod_ui()` / `chat_mod_server()` for multi-user Shiny applications;
- per-session mutable chat client;
- static greeting/messages;
- suggestion cards;
- streaming/cancellation;
- `ellmer::tool()` definitions;
- `$register_tool()` or `$register_tools()`;
- provider-specific `chat_*()` initialization.

Do not rely on an old copied API signature if the installed version differs.

---

# 29. MVP DEFINITION OF DONE

The RM feature is done when a public user can:

1. open the existing PSA classifications app;
2. enter the RM Assistant;
3. see **“Madayaw! I am RM.”** without an LLM-generated greeting;
4. ask a natural-language classification question;
5. use English, Filipino/Tagalog, Cebuano/Bisaya, or mixed language;
6. receive a streamed conversational response;
7. receive only classification codes verified through the application's local tools;
8. be asked a concise follow-up question when PSOC/PSIC evidence is insufficient;
9. receive PSIC reasoning consistent with the supplied PSIC rules;
10. benefit from the reviewed/common PSOC/PSIC mapping without treating it as a universal PSIC rule;
11. see version/status/source information when relevant;
12. continue using the ordinary deterministic Search/Browse app even if the assistant is unavailable.

The assistant should feel intelligent because it understands and asks useful questions—not because it is permitted to guess.

---

# 30. DIRECT CLAUDE CODE IMPLEMENTATION PROMPT

Use the following as the implementation instruction after the base application service layer is functional.

---

## IMPLEMENTATION PROMPT

You are implementing the **RM Classification Assistant** inside the existing PSA Statistical Classifications Search R Shiny application.

Read this handoff first, then inspect the smallest relevant set of repository files.

### Mission

Add a normal chat interface named **RM** that helps users identify, search, interpret, and narrow down Philippine statistical classifications.

The opening message must begin:

> **Madayaw! I am RM.**

The assistant should handle English, Filipino/Tagalog, Cebuano/Bisaya, and mixed-language queries.

### Non-negotiable architecture

Do not replace or duplicate the application's classification repository.

Use the existing functions such as:

```r
classification_registry()
classification_versions(system)
classification_levels(system, version)
search_classification(system, version, query, level = NULL)
get_classification_entry(system, version, code)
classification_metadata(system, version)
```

Expose small read-only wrappers to the LLM using `ellmer` tools.

Use `shinychat` for the chat UI.

Create a separate ellmer chat client per Shiny user session.

### Absolute grounding rule

The model may never present a classification code as an answer unless that exact code was returned by a registered application tool.

No retrieval = no code.

Never use model memory as a substitute for a failed classification lookup.

### Source assets

Use:

```text
PSIC_Chatbot_Classification_Rules.md
CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping.xlsx
```

Build compact local runtime artifacts from these sources.

Do not inject either entire source into every model request.

The common mapping workbook is supporting evidence only. It does not permit inferring a private establishment's PSIC solely from a worker's occupation.

### Engineering method

Use graph engineering.

After confirming the base contracts, parallelize:

1. assistant data normalization;
2. assistant tool wrappers;
3. RM prompt/client;
4. assistant UI module.

Give each workstream explicit file ownership.

Do not allow parallel agents to modify the same shared file.

Converge only after targeted tests pass.

### Loop discipline

For each workstream:

```text
inspect → minimal implementation → targeted test → evaluate
```

If failing:

```text
diagnose smallest cause → patch once → retest
```

Maximum three repair iterations per acceptance criterion.

Do not refactor unrelated working code.

### Token discipline

- do not load entire classification datasets into prompts;
- do not inject the full PSIC rules file into every conversation;
- keep tool search results bounded;
- retrieve only the relevant PSIC rule;
- use static greeting text;
- use passing tests as compressed memory;
- stop workstreams after acceptance tests pass.

### Required tools

Implement and register, at minimum:

```text
assistant_search_classification
assistant_get_classification_entry
assistant_classification_registry
assistant_search_common_pairings
assistant_get_psic_rule
```

Add:

```text
assistant_lookup_synonyms
```

if a curated synonym dataset is available.

### Required behavior

For PSOC:

- interpret occupation duties;
- search official PSOC candidates;
- ask a discriminating duty question if ambiguous.

For PSIC:

- apply the supplied PSIC rules;
- probe vague descriptions;
- do not infer industry from occupation;
- preserve principal/secondary/ancillary and integration logic.

For other classifications:

- route using the classification registry;
- do not invent unsupported systems.

### Failure behavior

The base application must remain usable if:

- LLM provider is unavailable;
- API key is missing;
- common-pairing artifact is missing.

Never let assistant failure break the deterministic search app.

### Exit condition

Do not consider the RM feature complete until:

- P0 assistant tests pass;
- the greeting is correct;
- streaming works;
- multi-user chat state is session-isolated;
- unverified codes cannot be emitted as verified answers;
- vague PSIC cases probe instead of guessing;
- PSOC does not determine private-company PSIC;
- multilingual evaluation cases work adequately;
- the existing search UI still passes its prior tests;
- deployment documentation explains the server-side LLM credential;
- `docs/ASSISTANT_CONTRACT.md` and `IMPLEMENTATION_STATUS.md` are updated.

Stop before a major visual redesign.

---

# 31. FUTURE TRAINING / LEARNING LOOP

Do not make the chatbot self-train from unreviewed public conversations.

A future controlled improvement loop may be:

```text
User question
     ↓
RM answer
     ↓
Human reviewer correction / confirmation
     ↓
Approved?
  ┌──┴──┐
  no   yes
  │     │
discard ├──> synonym update
        ├──> reviewed example
        ├──> evaluation case
        └──> mapping/rule update where authoritative
```

Possible future files:

```text
training/reviewed_examples.jsonl
training/evaluation_cases.jsonl
```

The official classification repository must still remain the final code-verification layer even if a customized/fine-tuned model is introduced later.

---

# 32. FINAL PRINCIPLE

The target is **not** a chatbot that appears intelligent because it confidently answers everything.

The target is a chatbot that appears intelligent because it:

- understands how people actually describe their work and businesses;
- understands Cebuano/Bisaya, Filipino/Tagalog, English, and code-switching;
- knows which classification system to consult;
- uses the application's authoritative data;
- applies PSIC decision rules;
- recognizes ambiguity;
- asks one useful follow-up question;
- verifies the final code;
- explains the result clearly;
- refuses to guess when the evidence is insufficient.

That behavior should make RM useful as a fast classification assistant while keeping the official search application transparent, inspectable, and authoritative.

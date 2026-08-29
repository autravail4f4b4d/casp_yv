# Claude Code Instruction — Hybrid Classification Retrieval

Implement the hybrid retrieval milestone defined in:

```text
HYBRID_CLASSIFICATION_RETRIEVAL_GRAPH.md
```

Repository:

```text
D:\dev\historical_phclassif
```

Required branch:

```text
feature/pre-staging-hardening
```

## Current baseline

Before touching code, verify:

```powershell
git branch --show-current
git status --short
git log -1 --oneline --decorate
```

Known pre-milestone engineering baseline:

```text
PASS 3089
FAIL 0
WARN 0
SKIP 0
```

The live RM provider path is already proven:

```text
R -> ellmer 0.4.2 -> OpenAI -> gpt-4o-mini
```

The RM tool path is also proven:

```text
"What is PSOC 8332?"
-> assistant_get_classification_entry()
-> 8332 HEAVY TRUCK AND LORRY DRIVERS

"Search PSOC 2022 for Heavy Truck and Lorry Drivers"
-> assistant_search_classification()
-> 8332 HEAVY TRUCK AND LORRY DRIVERS
```

But both RM and the normal Search UI fail for:

```text
heavy truck driver
```

Therefore the primary defect is shared deterministic retrieval recall, not the LLM model/API.

**Do not change the LLM model to solve this.**

---

# Mission

Implement one shared hybrid retrieval engine:

```text
existing exact/code/title/token ranking
+ Damerau-Levenshtein fuzzy retrieval
+ character 3–5 gram TF-IDF cosine retrieval
+ multilingual sentence-transformer embeddings
+ Reciprocal Rank Fusion
+ canonical repository verification
```

It must serve:

- normal Search
- PSOC + PSIC
- RM Assistant

Approximate/semantic retrieval is candidate generation only.

No verified canonical entry = no authoritative code.

---

# G0 — Pre-flight and contract freeze

Before coding:

1. verify branch/status;
2. trace the current call chain through:
   - `R/search.R`
   - `R/repository.R`
   - relevant tests;
3. identify exactly why:
   - `Heavy Truck and Lorry Drivers` succeeds;
   - `8332` succeeds;
   - `heavy truck driver` fails;
4. inspect `R/assistant/assistant_tools.R`;
5. inventory the current canonical classification registry;
6. inspect current dependencies in the project environment;
7. do not add packages until existing capabilities are checked.

Produce a compact owner map and root-cause statement before implementation.

---

# Graph engineering

Use the DAG from the specification.

Run parallel workers for isolated modules only.

## Reserved shared files — convergence owner only

```text
R/search.R
R/repository.R
R/assistant/assistant_tools.R
renv.lock
manifest.json
```

Parallel agents must not edit these concurrently. They may return bounded patch proposals.

## W1-A — Normalization + fuzzy

Own only new modules/tests such as:

```text
R/retrieval/retrieval_normalize.R
R/retrieval/retrieval_fuzzy.R
tests/testthat/test-retrieval-normalize.R
tests/testthat/test-retrieval-fuzzy.R
```

Implement:

- deterministic normalization;
- Unicode/NBSP handling;
- code punctuation preservation;
- controlled singular/plural morphology;
- Damerau-Levenshtein or justified equivalent;
- bounded top-N fuzzy candidate retrieval.

Prefer R-native implementation if adequate.

Do not introduce Python solely for RapidFuzz unless profiling proves it necessary.

## W1-B — Character n-gram

Own:

```text
R/retrieval/retrieval_ngram.R
scripts/build_retrieval_ngram_index.R
tests/testthat/test-retrieval-ngram.R
```

Implement:

```text
character 3–5 grams
TF-IDF
sparse matrix
cosine similarity
precomputed immutable index
top-K retrieval
```

Index metadata must tie it to the canonical source artifacts/versions.

Do not rebuild per query or per Shiny session.

## W1-C — Semantic embeddings

Own:

```text
R/retrieval/retrieval_embeddings.R
R/retrieval/retrieval_embedding_provider.R
scripts/build_retrieval_embeddings.*
tests/testthat/test-retrieval-embeddings.R
```

Implement a provider-neutral multilingual sentence-transformer semantic tier.

Requirements:

- precompute document embeddings;
- runtime normally embeds only the query;
- top-K semantic retrieval;
- timeout/error handling;
- lexical fallback if semantic backend is unavailable;
- no secrets in Git.

Do not hardwire a large Python/PyTorch runtime into the deployed Shiny process without first documenting the deployment consequences.

Design for:

```text
local development backend
self-hosted production embedding endpoint
optional future hosted provider
```

## W1-D — Evaluation harness

Own:

```text
data-raw/retrieval_eval_cases.csv
R/retrieval/retrieval_eval.R
scripts/evaluate_retrieval.R
tests/testthat/test-retrieval-eval.R
```

Build a versioned evaluation set covering:

```text
exact_code
exact_label
case_variant
singular_plural
typo
partial_label
paraphrase
filipino
cebuano
mixed
ambiguous
negative_no_authoritative_code
```

Required metrics:

```text
Recall@1
Recall@3
Recall@5
MRR
negative/no-result correctness
latency p50
latency p95
```

Do not tune only for the truck-driver example.

## W1-E — RM tool registry audit

Audit only in parallel. Return a patch proposal.

Prior inspection suggested the generic tool enum contained:

```text
psgc
psic
psoc
psced
pcoicop
pcpc
psccs
```

while current app support also includes systems such as:

```text
pscc
ptscs
pscrcs
```

Confirm against the canonical registry.

Prefer one centralized authoritative helper over a stale parallel enum if compatible with ellmer tool-schema construction.

Audit `assistant_search_common_pairings()` fallback semantics.

Common pairings remain supporting evidence only.

Candidate codes from common pairings must be verified with the canonical repository before RM may present them as official.

---

# Token-use rules

Each worker reads only:

1. this prompt;
2. `HYBRID_CLASSIFICATION_RETRIEVAL_GRAPH.md`;
3. its owned files;
4. directly called dependencies;
5. relevant tests.

Exploration:

```text
search exact symbol
-> open defining file
-> open direct dependencies
-> open tests
-> stop
```

Each worker reports only:

```text
files read
files changed/proposed
constraints found
implementation summary
targeted tests
unresolved issues
handoff notes
```

No parallel worker runs the full suite.

---

# Required ranking behavior

Exact code/title remain dominant.

Pin:

```text
8332
-> exact code remains first

Heavy Truck and Lorry Drivers
-> exact title remains first
```

The hybrid engine must retrieve:

```text
8332 — HEAVY TRUCK AND LORRY DRIVERS
```

for ordinary variants including:

```text
heavy truck driver
heavy truck drivers
hevy truck driver
trcuk driver
```

without hard-coding `8332`.

Add confusable/negative occupation cases to prevent broad false positives.

---

# Normalization

Create one deterministic, separately tested normalization contract covering:

```text
Unicode normalization
case folding
whitespace
NBSP
punctuation where safe
hyphens/apostrophes
classification-code punctuation preservation
controlled singular/plural morphology
```

Do not rewrite official labels.

Do not aggressively stem all terms.

---

# Fuzzy retrieval

Use Damerau-Levenshtein for typo/edit-distance recall.

Bound the work using a shortlist and/or score cutoff where practical.

Do not let fuzzy scoring override exact code/title matches.

---

# Character n-gram retrieval

Implement:

```text
3–5 character grams
TF-IDF
cosine similarity
sparse index
precomputed artifact
top-K candidates
```

This is expected to improve morphology/partial wording such as:

```text
heavy truck driver
heavy truck drivers
```

---

# Semantic retrieval

Use a multilingual sentence-transformer model family appropriate for:

```text
English
Filipino
Cebuano
mixed-language queries
semantic paraphrases
low lexical overlap
```

The semantic layer must be optional at runtime:

```text
available -> contributes candidates
unavailable -> lexical/fuzzy/ngram still work
```

The application must not crash if the embedding backend is unavailable.

Do not expose semantic similarity as a probability that a classification is correct.

---

# Fusion

Use Reciprocal Rank Fusion initially.

Conceptually:

```text
RRF(d) = sum_i 1 / (k + rank_i(d))
```

Keep exact code/title priority tiers outside approximate fusion.

Do not permit a semantic-only candidate to outrank an exact code result.

---

# Canonical verification

Every final result must map to a real canonical repository entry by:

```text
system
version
code
```

before presentation.

Similarity methods never manufacture codes.

RM rule remains:

```text
no retrieved/verified code
-> no authoritative code
```

---

# Shared service requirement

Search, PSOC + PSIC, and RM must consume the same shared retrieval engine.

Do not create a separate LLM-only semantic retrieval path.

For RM occupation fallback:

```text
assistant_search_classification()
-> no sufficient verified candidate
-> optional assistant_search_common_pairings()
-> candidate code
-> assistant_get_classification_entry()
-> canonical verification
```

Pairings remain supporting evidence.

---

# Backward compatibility

Preserve current public function signatures where practical.

Do not regress:

- total-match count vs bounded materialization;
- 200-row display cap contract;
- PSOC + PSIC independence;
- PSCC hierarchy/cross-reference behavior;
- PTSCS/PSCrCS component behavior;
- PSGC edition behavior;
- Current/Archived semantics;
- RM session isolation;
- Subtle Gradient UI/responsive behavior.

This is a retrieval milestone, not a UI redesign.

---

# Evaluation gates

## Gate A — lexical hybrid

Before semantic retrieval becomes default, demonstrate:

- exact ranking unchanged;
- `heavy truck driver` fixed;
- typo/morphology recall improved;
- negative cases remain safe;
- no material regression in existing search.

## Gate B — semantic value

Compare:

```text
baseline
lexical + fuzzy + n-gram
full hybrid + embeddings
```

Report:

```text
Recall@1
Recall@3
Recall@5
MRR
negative-case correctness
p50 latency
p95 latency
```

Semantic retrieval must materially improve paraphrase/multilingual retrieval before it becomes default.

If it adds complexity without measurable value, keep it optional and report that conclusion.

## Gate C — shared integration

Verify Search, PSOC + PSIC, and RM use the shared contract.

---

# Performance

Benchmark at least:

```text
PSOC 2022
current PSIC
PSCC 2022
PSGC long-release case
largest composite system
```

Capture:

```text
cold index load
warm p50
warm p95
peak memory
ngram index size
embedding index size
semantic query latency
```

Do not rebuild indexes per query/session.

---

# Testing sequence

Parallel workers:
- targeted tests only.

Convergence owner:

1. merged targeted retrieval tests;
2. evaluation script;
3. performance benchmark;
4. RM tool tests;
5. one final full suite.

Required final command:

```powershell
Rscript scripts/run_tests.R
```

Baseline:

```text
PASS 3089
FAIL 0
WARN 0
SKIP 0
```

Final gate:

```text
FAIL 0
WARN 0
SKIP 0
```

Pass count may increase.

Then:

```powershell
Rscript -e "renv::status()"
```

Do not regenerate `manifest.json` unless dependencies genuinely changed.

---

# Live RM acceptance

Only after deterministic gates pass, and only if the existing real provider credentials are available in the current environment, test:

```text
What is the PSOC code for a heavy truck driver?
What is PSOC 8332?
Search PSOC 2022 for Heavy Truck and Lorry Drivers
What PSIC classification applies to a bakery?
I work as a nurse in a private hospital. What are my PSOC and PSIC classifications?
What is PSCC code 0101.29.00-001?
What is the difference between PSCC and PSCCS?
What are the components of PTSCS?
What are the components of PSCrCS?
Give me the official PSOC code for professional AI prompt engineer.
```

Then test Filipino, Cebuano, mixed language, and two-session isolation.

Do not print/log API keys.

---

# Stop conditions

Do NOT:

```text
git reset
git restore completed functional work
commit
push
tag
merge
deploy
republish Connect Cloud
```

Leave the completed work in the working tree.

---

# Final report

Return these sections:

1. Pre-flight state
2. Root cause of `heavy truck driver` failure
3. Graph/workstreams executed
4. File ownership and changed files
5. Dependencies added or avoided
6. Normalization implementation
7. Damerau-Levenshtein implementation
8. Character n-gram implementation
9. Semantic embedding implementation/backend
10. Fusion/ranking
11. Canonical verification
12. RM registry/fallback changes
13. Evaluation corpus
14. Before/after Recall@1, Recall@3, Recall@5, MRR
15. Negative-case results
16. Performance/memory/index sizes
17. Targeted tests
18. Full regression
19. `renv::status()`
20. Live RM results
21. Remaining edge cases
22. Recommended default retrieval profile
23. Whether semantic retrieval provided material value
24. Explicit confirmation that no commit/push/tag/merge/deploy occurred

Stop there.

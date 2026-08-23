# PSIC 2019 ↔ PSIC Revision 5 (2026) Structural Correspondence Repair

## Claude Code Implementation Specification

**Priority:** P0 — statistical/classification correctness  
**Target:** Repair `Compare Editions` before Posit Connect Cloud staging  
**Method:** Graph engineering + bounded loop engineering + parallel workstreams with explicit file ownership  
**Do not deploy or commit automatically.**

---

## 0. Executive Directive

Repair the existing PSIC 2019 ↔ PSIC Revision 5 (2026) correspondence engine before staging deployment.

This is not a visual enhancement. It is a classification correctness repair.

The correspondence engine must represent structural revisions, including:

1. migration of motor-vehicle/motorcycle repair from the old Section G structure into Revision 5 Section T;
2. split of former Section J into Revision 5 Sections J and K;
3. downstream section-letter shifts from former Section K onward;
4. detailed 1→1, 1→N, N→1, N→M, new, discontinued, and no-match relationships;
5. correct reverse lookup from 2026 back to 2019;
6. explicit provenance and qualitative confidence;
7. statistical-use warnings for non-one-to-one relationships.

Posit Connect Cloud staging is blocked until the P0 acceptance criteria in this specification pass.

---

## 1. Official PSA Structural Evidence

Use the official PSA materials already supplied to the project.

### 1.1 Introduction to PSIC Revision 5

Source artifact:

`2_Introduction to PSIC Rev 5.pptx` / PDF equivalent

The PSA Revision 5 broad structure establishes:

```text
A  01–03  Agriculture, Forestry and Fishing
B  05–09  Mining and Quarrying
C  10–33  Manufacturing
D  35     Electricity, Gas, Steam, and Air Conditioning Supply
E  36–39  Water Supply; Sewerage, Waste Management and Remediation
F  41–44  Construction
G  46–47  Wholesale and Retail Trade
H  49–53  Transportation and Storage
I  55–56  Accommodation and Food Service Activities
J  58–60  Publishing, Broadcasting, and Content Production and Distribution Activities
K  61–63  Telecommunications, Computer Programming, Consultancy,
          Computing Infrastructure, and Other Information Service Activities
L  64–66  Financial and Insurance Activities
M  68     Real Estate Activities
N  69–75  Professional, Scientific and Technical Activities
O  77–82  Administrative and Support Service Activities
P  84     Public Administration and Defense; Compulsory Social Security
Q  85     Education
R  86–88  Human Health and Social Work Activities
S  90–93  Arts, Sports and Recreation
T  94–96  Other Service Activities
U  97–98  Activities of Households as Employers; Undifferentiated
          Goods- and Services-Producing Activities of Households for Own Use
V  99     Activities of Extraterritorial Organizations and Bodies
```

The same PSA material lists **Correspondence Tables** among PSA support products.

Important:

`Correspondence Tables` as a support category does **not** prove that this repository currently contains an official PSA 2019↔2026 crosswalk.

Do not mark mappings `official` unless an actual PSA-published mapping record is obtained and incorporated.

### 1.2 Section T — Other Service Activities

Source artifact:

`23_Section T_PSIC Training.pptx`

The PSA training material explicitly places the following in Revision 5 Section T:

```text
Division 94 — Activities of Membership Organizations
Division 95 — Repair and Maintenance of Computers,
              Personal and Household Goods,
              and Motor Vehicles and Motorcycles
Division 96 — Personal Service Activities
```

It also identifies:

```text
Group 953 — Repair and maintenance of motor vehicles and motorcycles
```

Therefore the correspondence engine must distinguish former Section G **trade/sales** activities from **repair/maintenance** activities.

Do not map all former Division 45 descendants to Section T.

---

## 2. Starting Baseline

Before changes:

1. inspect Git branch/status;
2. inspect current correspondence implementation;
3. run targeted correspondence tests;
4. run:

```text
Rscript scripts/run_tests.R
```

The last reported functional baseline was:

```text
1103 / 1103 tests passing
0 failures
```

Verify rather than assume this count.

Expected current correspondence-related files include:

```text
R/correspondence/isic_bridge.R
R/correspondence/schema.R
R/correspondence/scoring.R
R/correspondence/service.R
scripts/build_psic_correspondence.R
data/psic_2019_to_2026_correspondence.rds
data/psic_2019_to_2026_correspondence_metadata.rds
tests/testthat/test-correspondence-build.R
tests/testthat/test-correspondence-schema.R
tests/testthat/test-correspondence-service.R
```

Do not refactor unrelated adapters, RM Assistant logic, search services, or unified UI.

---

## 3. Evidence Precedence

The correspondence engine must use this precedence:

```text
1. Explicit official PSA correspondence record, if actually available
2. Deterministic structural relationship between official PSIC editions
3. Official UN ISIC Rev.4 ↔ Rev.5 correspondence evidence
4. Deterministic division/group/class/subclass containment and continuity
5. Exact/normalized code continuity where semantically valid
6. Label/description similarity as supporting evidence
7. Suggested algorithmic mapping only when stronger evidence is unavailable
```

Never let fuzzy similarity override known structural movement.

Never infer that identical section letters mean equivalence.

Never infer that a changed section letter means the economic activity changed.

---

## 4. Required Section-Level Structural Graph

Treat these as **verification targets**, not blind hard-coded truth. Validate them against the actual normalized 2019 and 2026 PSIC structures first.

```text
2019 A → 2026 A
2019 B → 2026 B
2019 C → 2026 C
2019 D → 2026 D
2019 E → 2026 E
2019 F → 2026 F

2019 G → 2026 G + 2026 T
    trade/sales remain or restructure under G
    repair/maintenance migrates to T

2019 H → 2026 H
2019 I → 2026 I

2019 J → 2026 J + 2026 K
    descendants related to divisions 58–60 → 2026 J
    descendants related to divisions 61–63 → 2026 K

2019 K → 2026 L
2019 L → 2026 M
2019 M → 2026 N
2019 N → 2026 O
2019 O → 2026 P
2019 P → 2026 Q
2019 Q → 2026 R
2019 R → 2026 S
2019 S → 2026 T
2019 T → 2026 U
2019 U → 2026 V
```

If normalized source data contradicts a target:

```text
STOP that mapping path
→ document the discrepancy
→ do not force the expected edge
→ continue unaffected workstreams
```

---

## 5. Reverse Graph Requirement

Reverse lookup must be derived from the same relationship graph/artifact.

Do not maintain an independently-authored reverse mapping table.

Expected consequences include:

```text
2026 J → 2019 J
2026 K → 2019 J
2026 L → 2019 K
2026 M → 2019 L
...
2026 V → 2019 U
```

Revision 5 Section T requires multi-source handling:

```text
2026 T
   ├── descendants corresponding to former 2019 S Other Service Activities
   └── migrated repair/maintenance descendants formerly under 2019 G
```

Therefore `2026 T → 2019 S` alone is insufficient.

---

## 6. Motor Vehicle / Motorcycle Repair — Mandatory Domain

### Problem

The old 2019 Section G grouped trade with repair of motor vehicles and motorcycles.

Revision 5 Section G is limited to Divisions 46–47, while Revision 5 Section T contains Division 95 / Group 953 repair and maintenance of motor vehicles and motorcycles.

### Required detailed behavior

Use:

```text
official 2019 record
+ official 2026 record
+ existing ISIC correspondence evidence
+ hierarchy/containment
+ descriptions
```

to distinguish:

```text
former vehicle/motorcycle sales or trade
    → Revision 5 trade structure / Section G

former repair/maintenance
    → Revision 5 Section T / Division 95 / Group 953 descendants
```

Do not invent subclass mappings.

Do not send every former Division 45 descendant to T.

### Required regression fixtures

Use actual codes from local datasets for:

- motor-vehicle repair → appropriate 2026 T descendant;
- reverse 2026 repair → correct 2019 G descendant;
- motorcycle repair → appropriate 2026 T descendant;
- vehicle/motorcycle sales/trade → appropriate Revision 5 trade descendant.

---

## 7. 2019 J → 2026 J/K Split

Revision 5 explicitly defines:

```text
J = Divisions 58–60
K = Divisions 61–63
```

The old broad 2019 Section J must not map only to 2026 J.

Required behavior:

```text
2019 J descendants related to 58–60 → 2026 J
2019 J descendants related to 61–63 → 2026 K
```

Add forward and reverse tests.

At section level this is a split.

At lower levels preserve actual 1→1, 1→N, N→1, or complex relationships.

---

## 8. Downstream Section-Letter Shifts

Validate representative deterministic structural continuity:

```text
2019 K Financial and Insurance → 2026 L
2019 L Real Estate → 2026 M
2019 M Professional, Scientific and Technical → 2026 N
2019 N Administrative and Support → 2026 O
2019 O Public Administration → 2026 P
2019 P Education → 2026 Q
2019 Q Human Health and Social Work → 2026 R
2019 R Arts / Recreation → 2026 S
2019 S Other Service Activities → 2026 T
2019 T Household activities → 2026 U
2019 U Extraterritorial Organizations → 2026 V
```

Where division/group/class/subclass concepts remain continuous, structural continuity must outrank fuzzy scoring.

---

## 9. Hierarchical Correspondence Model

Correspondence must work at:

```text
section
division
group
class
subclass
```

A correct section mapping does not imply all descendants are 1→1.

Preserve:

```text
1 → 1   unchanged / renamed / reclassified
1 → N   split
N → 1   merge
N → M   complex
new
discontinued
no verified mapping
```

Never flatten a multi-edge relationship into one “best” target for UI convenience.

---

## 10. Provenance and Confidence

Allowed provenance:

```text
official
derived
suggested
```

### official

Only for an explicit PSA-published correspondence record.

### derived

For authoritative structural evidence, e.g.:

```text
official 2019 PSIC structure
+ official Revision 5 structure
+ official UN ISIC correspondence
+ deterministic hierarchy/code continuity
```

### suggested

For algorithmic candidates where authoritative evidence is incomplete.

Suggested mappings must never override deterministic derived mappings.

User-facing confidence remains qualitative:

```text
High
Moderate
Low
```

Do not present arbitrary similarity percentages as statistical certainty.

---

## 11. Graph Engineering Plan

```text
                         A. Baseline / Contract Audit
                                      │
               ┌──────────────────────┼──────────────────────┐
               ▼                      ▼                      ▼
      B. Structural Graph     C. Detailed Mapping     D. Source/Provenance
               │                      │                      │
               └──────────────┬───────┴──────────────┬───────┘
                              ▼                      ▼
                      E. Artifact Build       F. Service/Reverse
                              │                      │
                              └───────────┬──────────┘
                                          ▼
                                   G. P0 Tests
                                          │
                                          ▼
                              H. Compare Editions UAT
                                          │
                                          ▼
                               I. Full Regression + Docs
                                          │
                                          ▼
                                  STAGING GATE
```

Parallelize only after A freezes public contracts.

---

## 12. Workstream A — Baseline / Contract Audit

### Read only

```text
CLAUDE.md
IMPLEMENTATION_STATUS.md
docs/CORRESPONDENCE_SOURCES.md
docs/UI_CONTRACT.md
R/correspondence/*
scripts/build_psic_correspondence.R
tests/testthat/test-correspondence-*.R
R/ui/ui_correspondence.R
app.R only where correspondence is wired
```

### Tasks

1. verify Git status/branch;
2. run correspondence tests;
3. run full baseline;
4. inspect schema;
5. inspect artifact fields;
6. inspect builder precedence;
7. inspect reverse lookup;
8. identify why structural transitions are missing or down-ranked.

### Output

Return only:

```text
Current schema
Current builder stages
Current provenance rules
Current reverse lookup
Root cause
Files that must change
Files that must not change
```

Then freeze contracts.

---

## 13. Workstream B — Structural Graph

### File ownership

Prefer:

```text
R/correspondence/structural_graph.R
tests/testthat/test-correspondence-structural.R
```

Do not concurrently edit scoring/service/build files.

### Tasks

Implement a direction-agnostic structural graph with:

```text
source section
target section
relationship type
structural rationale
evidence key
provenance default
```

Validate all section targets against actual normalized data.

Required tests:

```text
G → G/T
J → J/K
K → L
L → M
...
U → V

reverse J/K → J
reverse L → K
...
reverse V → U
```

---

## 14. Workstream C — Detailed Mapping Engine

### File ownership

Prefer:

```text
R/correspondence/isic_bridge.R
R/correspondence/scoring.R
new helper file if needed
tests/testthat/test-correspondence-detailed.R
```

### Tasks

Repair precedence:

```text
explicit official mapping
→ deterministic structural containment
→ ISIC bridge
→ code/division continuity
→ label/description evidence
→ suggested fallback
```

Mandatory domains:

- old G trade vs repair redistribution;
- old J → J/K split;
- downstream section-letter shifts;
- unchanged divisions/classes under shifted sections.

Each edge must preserve existing-schema equivalents of:

```text
source version/code/level
target version/code/level
relationship type
provenance
confidence
evidence/rationale
```

---

## 15. Workstream D — Source / Provenance Audit

### File ownership

```text
docs/CORRESPONDENCE_SOURCES.md
tests/testthat/test-correspondence-provenance.R
```

### Required documentation corrections

Record that:

1. PSA Revision 5 broad structure is official structural evidence.
2. PSA Section T training is official evidence for repair placement.
3. PSA support material mentions Correspondence Tables.
4. Do not claim an official PSA 2019↔2026 crosswalk exists unless the actual table is incorporated.
5. UN ISIC Rev.4↔Rev.5 correspondence supports `derived` evidence.
6. Derived evidence is not official PSA correspondence.

Prefer wording:

```text
No explicit PSA 2019 ↔ Revision 5 correspondence table
has been incorporated into this application as of this build.
```

rather than claiming PSA has no correspondence program.

---

## 16. Convergence Workstream E — Artifact Rebuild

Start only when B/C/D targeted tests pass.

### Shared ownership

```text
scripts/build_psic_correspondence.R
data/psic_2019_to_2026_correspondence.rds
data/psic_2019_to_2026_correspondence_metadata.rds
```

### Tasks

1. integrate structural graph;
2. integrate detailed precedence;
3. rebuild artifact;
4. validate schema;
5. validate edge uniqueness;
6. validate source/target existence;
7. validate hierarchy;
8. validate provenance/confidence;
9. validate multiplicity;
10. remove stale old edges.

### Report before/after

```text
total edges
official / derived / suggested
1→1 / 1→N / N→1 / complex / new / discontinued/no-match
section / division / group / class / subclass
```

Correctness outranks maximizing edge counts.

---

## 17. Convergence Workstream F — Service / Reverse Graph

### File ownership

```text
R/correspondence/service.R
tests/testthat/test-correspondence-service.R
```

Required invariant:

```text
if forward graph contains A → B
then reverse lookup of B exposes A
subject only to valid level/filter semantics
```

Do not author reverse mappings separately.

Add explicit forward/reverse symmetry tests.

---

## 18. P0 Regression Matrix

Use actual records from local 2019 and 2026 datasets.

### Structural

- [ ] 2019 G → Revision 5 G and T.
- [ ] Revision 5 T traces to multiple old structural sources where appropriate.
- [ ] 2019 J → Revision 5 J and K.
- [ ] Revision 5 J → 2019 J.
- [ ] Revision 5 K → 2019 J.
- [ ] 2019 K → Revision 5 L.
- [ ] 2019 L → Revision 5 M.
- [ ] representative downstream shifts through U→V.

### Motor vehicles / motorcycles

- [ ] old repair activity → Revision 5 T repair structure;
- [ ] reverse repair → correct old G descendant;
- [ ] old sales/trade does not incorrectly route to repair;
- [ ] motorcycle repair tested separately where available.

### J/K

- [ ] representative 58–60 activity → Revision 5 J;
- [ ] representative 61–63 activity → Revision 5 K;
- [ ] reverse mappings → old J.

### Hierarchy

- [ ] section split does not flatten detailed mappings;
- [ ] division continuity survives section-letter shift;
- [ ] every source/target code exists in its repository;
- [ ] all target/source levels are valid.

### Provenance

- [ ] no fabricated `official`;
- [ ] structural mappings may be `derived`;
- [ ] suggested remains distinguishable;
- [ ] derived edges have evidence/rationale.

### Reverse

- [ ] forward/reverse symmetry;
- [ ] multi-target forward relationships reverse correctly;
- [ ] no reverse-only orphan edges.

---

## 19. Compare Editions UI Verification

Do not redesign the unified UI.

Verify that corrected data is displayed accurately.

Required examples:

```text
2019 Section J
Information and Communication
→ split across Revision 5 J and K
```

```text
2019 Section G
Wholesale/Retail Trade; Repair of Motor Vehicles and Motorcycles
→ activities distributed across Revision 5 G and T
```

```text
2019 Section K
Financial and Insurance Activities
→ Revision 5 Section L
```

Required UI behavior:

- show all supported targets;
- label split/complex relationships;
- show provenance;
- show qualitative confidence;
- preserve the statistical-use warning;
- do not call deterministic shifts low-confidence fuzzy matches;
- reverse direction is equally usable;
- no stale results remain.

---

## 20. Loop Engineering Rules

Each workstream:

```text
inspect contract
→ implement smallest complete change
→ targeted test
→ evaluate
   ├─ pass → freeze
   └─ fail → diagnose smallest cause
              → patch once
              → retest
```

Rules:

1. maximum three repair iterations per acceptance criterion;
2. do not refactor passing adapters/search/RM;
3. do not redesign Sources/Search during correspondence repair;
4. use tests as compressed memory;
5. stop a workstream once tests pass;
6. main integrator reads summaries before reopening files;
7. patch shared contract defects centrally at convergence.

---

## 21. Token-Efficiency Rules

Initial read set:

```text
CLAUDE.md
IMPLEMENTATION_STATUS.md
docs/CORRESPONDENCE_SOURCES.md
R/correspondence/*
scripts/build_psic_correspondence.R
correspondence tests
targeted 2019/2026 records
```

Do not reread unrelated RM/UI/adapters unless needed.

Use targeted search for:

```text
relationship_type
provenance
confidence
official
derived
suggested
reverse
source_code
target_code
section
division
```

Do not print whole classification tables.

Inspect only:

```text
distinct sections
distinct divisions
targeted codes/descriptions
counts
parent/child chains
```

Each parallel workstream returns only:

```text
status
root cause
files changed
tests run
result
contract changes
remaining risk
```

---

## 22. File Ownership Matrix

| Workstream | Primary files |
|---|---|
| A Audit | read-only |
| B Structural graph | `structural_graph.R`, structural tests |
| C Detailed mapping | `isic_bridge.R`, `scoring.R`, detailed tests |
| D Provenance/docs | `CORRESPONDENCE_SOURCES.md`, provenance tests |
| E Build convergence | build script + RDS artifacts |
| F Service convergence | `service.R`, service tests |
| G UI verification | `ui_correspondence.R` only if necessary |
| I Final docs | `IMPLEMENTATION_STATUS.md`, affected contracts |

Preserve repository conventions if exact filenames differ.

---

## 23. Do Not Touch Unless Required

Do not modify merely for cleanup:

```text
R/adapters/adapter_psoc_2022.R
R/parallel_search.R
R/assistant/*
prompts/RM_SYSTEM_PROMPT.md
data/assistant_*.rds
tests/evals/rm_assistant_cases.yml
unified Search UI
RM UI
provider configuration
```

This milestone is correspondence correctness.

---

## 24. Documentation Updates

Update:

```text
docs/CORRESPONDENCE_SOURCES.md
IMPLEMENTATION_STATUS.md
```

Update `docs/UI_CONTRACT.md` only if the correspondence UI contract actually changes.

Document:

- G trade/repair redistribution;
- J→J/K split;
- K-onward section-letter shift;
- reverse graph behavior;
- provenance policy;
- PSA structural evidence;
- UN ISIC bridge role;
- whether an explicit PSA crosswalk was actually incorporated;
- remaining gaps.

---

## 25. Posit Connect Cloud Staging Gate

Do not report staging readiness until all pass:

- [ ] structural graph verified against official 2019/2026 data;
- [ ] G → G/T implemented;
- [ ] motor repair detailed mapping tested;
- [ ] J → J/K implemented;
- [ ] downstream letter shifts implemented;
- [ ] reverse symmetry tested;
- [ ] detailed multiplicity preserved;
- [ ] no fabricated `official` provenance;
- [ ] RDS artifacts rebuilt;
- [ ] Compare Editions verified forward/reverse;
- [ ] statistical warning preserved;
- [ ] full regression suite passes;
- [ ] `IMPLEMENTATION_STATUS.md` updated.

Then return exactly one staging decision:

```text
READY FOR POSIT CONNECT CLOUD STAGING
```

or:

```text
NOT READY FOR STAGING
```

with blockers.

---

## 26. Final Verification

Run targeted correspondence tests first.

Then:

```text
Rscript scripts/run_tests.R
```

The final test count may exceed 1103.

Required result:

```text
0 failures
0 unexpected warnings
0 regressions
```

Browser/UAT must cover:

```text
2019 → 2026
2026 → 2019
G trade/repair
J/K split
K → L
representative later section shift
split/multi-target display
provenance
confidence
statistical warning
```

---

## 27. Final Report Format

Report:

### Baseline
- branch;
- Git status;
- starting test count.

### Root cause
Why structural transitions were previously missing/down-ranked.

### Workstreams
For each:
- status;
- files changed;
- tests run;
- result.

### Structural rules
Explicitly report:
- G → G/T;
- J → J/K;
- K → L onward;
- reverse behavior.

### Detailed verified examples
Use actual dataset records for:
- motor vehicle repair;
- motorcycle repair if available;
- trade/sales;
- J→J;
- J→K;
- K→L;
- one later shift.

### Artifact statistics
Before/after by:
- provenance;
- relationship type;
- hierarchy level.

### Tests
- targeted;
- full regression;
- final count;
- failures/warnings/skips.

### UI verification
Forward and reverse Compare Editions behavior.

### Remaining gaps
Do not hide uncertain/suggested correspondence.

### Staging recommendation
Return exactly one:

```text
READY FOR POSIT CONNECT CLOUD STAGING
```

or:

```text
NOT READY FOR STAGING
```

with blockers.

Do not commit automatically.

---

# Direct Claude Code Prompt

Implement the P0 PSIC 2019 ↔ PSIC Revision 5 structural correspondence repair defined in this file.

Read first:

```text
CLAUDE.md
IMPLEMENTATION_STATUS.md
this specification
docs/CORRESPONDENCE_SOURCES.md
```

Then inspect only the correspondence implementation, its tests, and targeted 2019/2026 records.

Verify the last known 1103-test baseline before changes.

Use graph engineering and parallel workstreams exactly as defined here.

Mandatory structural targets to validate:

```text
2019 G → 2026 G + T
2019 J → 2026 J + K
2019 K → 2026 L
2019 L → 2026 M
...
2019 U → 2026 V
```

Reverse lookup must come from the same graph.

Revision 5 Section T must correctly include migrated motor-vehicle/motorcycle repair activity while Section G retains/restructures trade activities.

Do not map every old Division 45 descendant to T.

Evidence precedence:

```text
explicit PSA correspondence if actually available
→ deterministic PSIC structural evidence
→ official ISIC Rev.4↔Rev.5 correspondence
→ hierarchy/code continuity
→ textual similarity
→ suggested fallback
```

Only an explicit PSA mapping record may be `official`.

Required outcomes:

1. deterministic structural section graph;
2. repaired detailed mapping logic;
3. rebuilt correspondence artifacts;
4. graph-derived reverse lookup;
5. P0 regression tests;
6. Compare Editions forward/reverse verification;
7. corrected source/provenance docs;
8. full regression pass;
9. explicit staging gate recommendation.

Do not perform unrelated visual redesign.

Do not deploy.

Do not commit automatically.

Proceed.

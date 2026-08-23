# Correspondence Sources: PSIC 2019 ↔ PSIC Revision 5 (2026)

## Purpose of this document

Per the implementation spec (`PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md`,
sections 12–13), before generating any inferred PSIC 2019↔2026 mapping this
project must first check whether the Philippine Statistics Authority (PSA)
has already published an official crosswalk. This document records that
audit, the one genuinely usable authoritative source it did find (a United
Nations table, not a PSA one), and the resulting provenance policy that
`scripts/build_psic_correspondence.R` follows.

**Audit date: 2026-08-23** (same day as this repository's PSIC Revision 5
build — see `docs/DATA_SOURCES.md`).

## Bottom line

**No explicit PSA 2019 ↔ Revision 5 correspondence table has been
incorporated into this application as of this build.**

That is a statement about *this repository*, deliberately — not a claim
about PSA's publishing programme. PSA does list **Correspondence Tables**
among its classification support products, so such a table may well exist
or may be published later; none has been obtained and wired in here. If one
is incorporated, only the rows it explicitly names may become `official`
(see "Reconciling a future official PSA crosswalk" below).

**No official PSA PSIC 2019↔Revision 5 correspondence/concordance table was
found** during the audit described here. This is the expected outcome:
PSIC Revision 5 was approved by the
PSA Board only on 21 May 2026 (Board Resolution No. 09, Series of 2026) and
released 5 August 2026 — 18 days before this audit. PSA transition/
concordance tables have historically lagged a new classification edition's
initial release by months to years, and no evidence of one exists yet for
Revision 5.

Because of this, **every row in `data/psic_2019_to_2026_correspondence.rds`
carries provenance `derived` or `suggested`, never `official`.** This is
enforced as a real test guard (`tests/testthat/test-correspondence-build.R`
asserts `!("official" %in% correspondence$provenance)`), not merely a
documentation claim — if PSA later publishes an official crosswalk, that
guard is the first thing that must be revisited (see "Reconciling a future
official PSA crosswalk" below).

## Official PSA structural evidence used

Two PSA materials are used as **official structural evidence**. They
document how Revision 5 is *built*; neither is a code-to-code crosswalk,
so neither makes any mapping `official`.

### 1. PSA Revision 5 broad structure

The PSA introduction material fixes each Revision 5 section and its
division range:

```
A 01–03   B 05–09   C 10–33   D 35      E 36–39   F 41–44
G 46–47   H 49–53   I 55–56   J 58–60   K 61–63   L 64–66
M 68      N 69–75   O 77–82   P 84      Q 85      R 86–88
S 90–93   T 94–96   U 97–98   V 99
```

This is what makes the section-letter restructuring deterministic rather
than a guess: 2026 G is trade only (46–47), 2026 J and K are two distinct
sections (58–60 and 61–63), and every section from the old K onward sits
one letter later.

### 2. PSA Section T training material

PSA's Section T material places in Revision 5 Section T:

```
Division 94  Activities of Membership Organizations
Division 95  Repair and Maintenance of Computers, Personal and Household
             Goods, and Motor Vehicles and Motorcycles
Division 96  Personal Service Activities
```

and identifies **Group 953 — Repair and maintenance of motor vehicles and
motorcycles**. This is the authority for routing former Section G repair
activity into Section T rather than leaving it with trade.

### 3. PSA support products mention Correspondence Tables

PSA's support material lists **Correspondence Tables** as a product
category. Recorded here for completeness and to prevent a future reader
concluding PSA has no correspondence programme. It does **not** evidence
any particular mapping, and nothing in this application is marked
`official` on the strength of it.

## The three structural restructurings this application models

All three are `derived`: they follow deterministically from the two
official PSA structures above, but PSA has published no code-level table
confirming them individually.

### G trade/repair redistribution

2019 Section G combined wholesale/retail trade **with** repair of motor
vehicles and motorcycles (division 45 carried both). Revision 5 splits
them:

```
2019 G  →  2026 G   (trade / sales, divisions 46–47)
        →  2026 T   (repair and maintenance, division 95 / group 953)
```

Division 45 does not exist in Revision 5 at all, so *every* 2019
division-45 code must be re-routed by what the activity actually is. Sales
codes go to the trade structure; repair codes go to group 953 descendants.
Sending all former division-45 descendants to T would be wrong, and so
would leaving them unmapped.

### 2019 J → 2026 J + 2026 K

The old broad Section J (Information and Communication) becomes two
sections:

```
2019 J  →  2026 J   (publishing, broadcasting, content — divisions 58–60)
        →  2026 K   (telecommunications, computer programming,
                     consultancy, information services — divisions 61–63)
```

At section level this is a split; at lower levels the real 1→1, 1→N, N→1
and complex relationships are preserved rather than flattened.

### K-onward section letter shift

From the old Section K onward every section moves one letter later:

```
2019 K → 2026 L    2019 L → 2026 M    2019 M → 2026 N
2019 N → 2026 O    2019 O → 2026 P    2019 P → 2026 Q
2019 Q → 2026 R    2019 R → 2026 S    2019 S → 2026 T
2019 T → 2026 U    2019 U → 2026 V
```

Two rules follow, and both are enforced in code:

- an **identical** section letter across editions does not imply
  equivalence (2019 K is finance, 2026 K is telecommunications);
- a **changed** section letter does not imply the activity changed —
  where the underlying division/group/class concept is continuous, this is
  deterministic continuity and is recorded as `derived` at **high**
  confidence, never as a low-confidence fuzzy match.

Note the consequence for reverse lookup: 2026 T has **two** structural
sources — the former 2019 S (Other Service Activities) *and* the repair
activity migrated out of 2019 G. `2026 T → 2019 S` alone would be wrong.

## Sources checked

| # | Source searched | URL | Result |
|---|---|---|---|
| 1 | PSA PSIC classification landing page | `https://psa.gov.ph/classification/psic` | Fetched directly. Lists the Revision 5 Detailed Structure workbook, PSA Board Resolution No. 09, Memorandum Circular No. 2026-08 ("Guidelines for the Adoption and Use of the Philippine Standard Industrial Classification Revision 5"), and PSIC API docs. **No correspondence/concordance/crosswalk table or transition guide is mentioned or linked anywhere on this page.** |
| 2 | Web search for a PSA PSIC 2019↔Revision 5 crosswalk directly | search query: `PSA PSIC Revision 5 concordance correspondence table 2019 crosswalk` | No PSA-published crosswalk document surfaced. Only general PSIC reference pages and an unrelated 2019 PSIC PDF mirror. |
| 3 | Web search for a PSA transition guide, scoped to `psa.gov.ph` | search query: `PSA Philippine Standard Industrial Classification Revision 5 transition guide correspondence table site:psa.gov.ph` | No transition guide or correspondence table found. Confirms Memorandum Circular No. 2026-08 exists (adoption/use guidelines) but nothing in the search results describes it as containing a 2019↔2026 mapping table. |
| 4 | Web search for PSA Memorandum Circular 2026-08 specifically | search query: `PSA Memorandum Circular 2026-08 Guidelines Adoption Use Philippine Standard Industrial Classification Revision 5` | Confirms the circular is an adoption/use guideline, not a concordance table. No mapping content identified. |

**Provenance decision for PSA sources: no official PSA crosswalk exists at
this time.** Proceeding to derived/suggested mapping is explicitly
sanctioned by spec section 12 ("If none exists, proceed with derived and
suggested; do not block implementation").

## Authoritative UN evidence found (used as `derived`, not `official`)

| # | Source searched | URL | Result |
|---|---|---|---|
| 5 | UN Statistics Division — ISIC Rev.5 classification detail | `https://unstats.un.org/unsd/classifications/Family/Detail/2095` | Confirms ISIC Rev.5 status "Operational", adopted 2024 by the UN Statistical Commission. No correspondence file linked from this detail page itself. |
| 6 | Web search for the ISIC Rev.4↔Rev.5 correspondence table | search query: `"ISIC Rev 5" concordance "Rev 4" United Nations Statistics Division correspondence table` | Found a UNSD **Technical Note on the ISIC, Rev. 4 – Rev. 5 Correspondence Table** (`https://unstats.un.org/unsd/classifications/Meetings/UNCEISC2024_2nd/Session_6_Bk_2_Technical_Note.pdf`, last updated 25 October 2024), which describes the methodology and states the actual table "is included in a separate spreadsheet". |
| 7 | Follow-up search for the spreadsheet itself | search query: `unstats.un.org ISIC Rev 4 Rev 5 correspondence table xlsx download UNCEISC2024` | Found and **downloaded** the actual table: `https://unstats.un.org/unsd/classifications/Meetings/UNCEISC2024_2nd/Session_6_Bk_1_ISIC4-5_Correspondence_Table.xlsx` (603 data rows, sheet `ISIC4-5`; also contains a `GSIM` sheet of change-type definitions and a `Note` sheet reproducing the technical note). Retrieved 2026-08-23, saved locally at `data-raw/ISIC4-5_Correspondence_Table.xlsx` (approx. 65 KB). |

This UN table is a **genuine, official, downloadable document**: it maps
every ISIC Rev.4 four-digit class to one or more ISIC Rev.5 classes (and
vice versa), including unchanged classes, with a GSIM change-type tag
(merger, take-over, breakdown, split-off, transfer, code change, name
change) for each changed entry. It was coordinated by the UN Statistics
Division's Task Team on ISIC (Statistics Canada, Eurostat, US Census
Bureau) and last updated 25 October 2024.

**Why this is `derived`, not `official`, for PSIC specifically** (per spec
section 13): PSIC is a *national adaptation* of ISIC, not ISIC verbatim.
PSA has never published this UN table as a PSIC correspondence document,
and — critically — empirical inspection during this build (below) shows
PSIC does not always preserve ISIC's own class-code assignment. The UN
table is real, official evidence about ISIC, used here only as a
*corroborating* signal for PSIC mappings, exactly as spec section 16
anticipates ("Where appropriate, use official UN ISIC Rev.4↔Rev.5
correspondence as derived evidence").

## Empirical caveat that shapes how the UN bridge is used

Confirmed via direct comparison of PSIC's own packaged data (`phscs::get_psic(version = "2019")`
for PSIC 2019, `data/psic_2026.rds` for PSIC Revision 5) against the UN
table's ISIC titles at the same 4-digit class code:

- Both PSIC editions are indeed patterned on their respective ISIC
  revision (PSIC 2019 → ISIC Rev.4; PSIC Revision 5 → ISIC Rev.5 — the
  latter confirmed via PSA's own release material, which states PSIC
  Revision 5 "is patterned after the United Nations International
  Standard Industrial Classification of All Economic Activities (ISIC)
  Revision 5"), and for most class codes PSIC's own label is a close or
  identical match to ISIC's title at the same numeric code — e.g. PSIC
  2019 class `0115` = "Growing of tobacco" and ISIC Rev.4 class `0115` =
  "Growing of tobacco".
- **But not always.** PSIC 2019 class `0113` = "Growing of corn, except
  young corn (vegetable)" while ISIC Rev.4 class `0113` at the *same
  numeric code* = "Growing of vegetables and melons, roots and tubers" —
  a different concept entirely. PSIC reassigned that code to a
  nationally-significant crop (corn) rather than following ISIC's own
  assignment at that position. This divergence persists into PSIC
  Revision 5 (class `0113` = "Growing of corn" there too, vs. ISIC Rev.5's
  own class `0113`).
- Divisions also are not code-for-code identical between the two PSIC
  editions: PSIC 2019 has 88 divisions, PSIC Revision 5 has 88 divisions,
  and 87 of those 88 numeric codes are shared — division `45` (2019) has
  no counterpart in 2026, and division `44` (2026) has no counterpart in
  2019. (Compatible-hierarchy checks in the scoring model therefore use
  each edition's own left-prefix code structure directly — division/
  group/class/sub-class codes are strictly left-prefix nested within an
  edition — rather than assuming a fixed cross-edition division/section
  range table, precisely because that assumption would be unsafe here.)

**Consequence for the build**: `R/correspondence/isic_bridge.R`'s
`isic_bridge_supported()` never trusts a raw ISIC code-number match. It
only credits the UN bridge as corroborating evidence when **both** PSIC
editions' own class-level labels are themselves close to their respective
ISIC titles at that code (Jaccard token similarity ≥ 0.50, the
"conformance gate" — see Scoring below). Only when PSIC appears to have
actually followed ISIC's own numbering at a given position is the UN
table's Rev.4→Rev.5 change history treated as informative about what
probably happened to the PSIC counterpart. This keeps the signal honest at
the cost of it firing less often than a naive code-lookup would.

## Provenance policy actually implemented

| Provenance | When produced |
|---|---|
| `official` | Never, in this build. Reserved for a future PSA-published mapping named explicitly in an official document (see "Reconciling a future official PSA crosswalk"). |
| `derived` | Exact code continuity; class-prefix continuity (a 2019 sub-class code no longer exists but one or more 2026 sub-classes share its 4-digit class family); the "discontinued"/"new" absence findings after exhaustive deterministic search; and any of the above further corroborated by the UN ISIC bridge under its conformance gate. |
| `suggested` | Pure/mostly label-token-similarity matches found outside any shared code family (restricted to the same group, then the same division, if the group yields nothing). |

**Derived evidence is not official PSA correspondence.** This distinction
is the whole point of the three-value vocabulary and is worth stating
plainly, because `derived` mappings in this application are strong: they
rest on PSA's own published Revision 5 structure, PSA's own Section T
material, the official UN ISIC Rev.4↔Rev.5 correspondence table, and
deterministic code/hierarchy continuity. Strong is still not the same as
published. A `derived` edge is this application's reasoned conclusion from
authoritative structural inputs; an `official` edge would be PSA stating
the mapping itself. Only the latter may ever carry `official`, and none
does today.

Suggested mappings never override derived ones, and neither may be
presented to a user as an official PSA equivalence.

## Scoring thresholds (spec section 17)

Centralized in `R/correspondence/scoring.R`. Spec section 17's own weights
("+40 exact code, +30 ISIC bridge, +15 near-identical title, +10 compatible
hierarchy, +5 description similarity") are explicitly labeled "illustrative
... not statistically calibrated probabilities" and this build's central
scoring function keeps the same four named signals but grades "compatible
hierarchy" by how tight the code-family match is, instead of one flat
value, because a same-4-digit-class match is materially stronger location
evidence than a same-2-digit-division match:

```
exact_code                 +40
hierarchy: same class      +30   (same 4-digit class-code family)
hierarchy: same group      +15   (same 3-digit group-code family)
hierarchy: same division    +7   (same 2-digit division-code family)
hierarchy: none              0
isic_bridge_supported      +30   (gated by the conformance check above)
near_identical_title       +15   (normalized-label Jaccard >= 0.90)
description_similarity      +5   (both descriptions present, Jaccard >= 0.60)
```

Confidence buckets: **score ≥ 50 → high**; **25 ≤ score < 50 → moderate**;
**score < 25 → low**. These cutoffs are an explicit, documented choice, not
a calibrated probability, chosen so that (a) exact-code continuity alone
already clears "high" even when the title changed completely — matching
the spec's explicit instruction that a "renamed" row must still be
confidence "high", since code continuity alone is strong deterministic
evidence; (b) a same-class-family candidate with a weak title match lands
at "moderate" (right neighbourhood, genuine uncertainty about which
specific sibling absorbed the content); (c) a pure cross-division label
guess with no hierarchy support lands at "low" unless the title match is
very strong.

Public-facing UI must display only High/Moderate/Low, never a percentage —
these are ordinal signals, not calibrated probabilities (spec section 17).

## Reconciling a future official PSA crosswalk

If PSA later publishes an official PSIC 2019↔Revision 5 correspondence
table:

1. Add it as a new source row in the table above with its retrieval date.
2. Re-run `scripts/build_psic_correspondence.R` after teaching it to prefer
   any PSA-named mapping for a given code over the deterministic
   derivation, setting `provenance = "official"` and `review_status =
   "reviewed"` only for rows the PSA document explicitly names — never
   promote a `derived`/`suggested` row to `official` just because it
   happens to agree with the PSA table.
3. Update the `!("official" %in% ...)` test guard in
   `tests/testthat/test-correspondence-build.R` to assert the new, narrower
   invariant (only PSA-named codes are official) instead of removing the
   guard outright.

## Related documents

- `docs/DATA_SOURCES.md` — PSIC Revision 5's own source audit and build
  pipeline (the edition this correspondence layer maps *to*).
- `scripts/build_psic_correspondence.R` — full build algorithm, run
  report, and file-header rationale for every scope decision referenced
  above.
- `data/psic_2019_to_2026_correspondence_metadata.rds` — machine-readable
  build metadata (row counts by relation_type/provenance/confidence,
  scoring weights actually used, source version identifiers).

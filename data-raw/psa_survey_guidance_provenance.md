# PSA Survey Coding Guidance — Evidence Provenance Record

**Status:** documentation only. **Not read at runtime.**
Nothing in the application opens this file or the source PDF; the encoded
evidence lives in `R/assistant/assistant_survey_guidance.R` and
`data-raw/curated_psoc_overrides.csv`. This record exists so every encoded
item can be traced back to a specific page of a specific document, and so a
future reviewer can re-verify or retire an item without re-reading the PDF.

---

## 1. Document identity

| Field | Value |
|---|---|
| Document | PSA household-survey enumerator's manual — **Chapter 9.3, Section B (Economic Characteristics)** |
| Columns covered | **14** (primary occupation → PSOC), **15/16** (kind of business or industry → PSIC) |
| Supplied as | `sample psoc.pdf` (718.4 KB, 31 PDF pages) |
| Supplied by | Repository owner, as authoritative PSA survey coding guidance |
| Page numbering | PDF page *N* carries printed slide number *N + 41* (PDF p1 = slide 42 … PDF p31 = slide 72). Both are cited below. |
| Text extraction | `pdftotext -layout` (poppler). Page rendering was unavailable in this environment. |
| Repository copy | **The PDF is deliberately NOT committed.** Only the extracted, verified evidence is version-controlled. |

### Extraction caveat

`-layout` misaligns some multi-column tables in this deck. The
`4789 / 4791 / 8412 / 9329` block on PDF p17 (slide 58) is one such case:
codes and their example descriptions land in separate visual columns.
Only rows that could be read unambiguously were encoded. Several
"New Codes based on the 2019 Updates to the 2009 PSIC" pages
(PDF p19–p27 / slides 60–68) were **deliberately left unencoded** rather
than guessed at.

---

## 2. Classification vintages in this document

The document mixes vintages, and the two halves must be treated
differently. This is the single most important fact in this record.

| Half | Vintage stated in the document | Relationship to the repository |
|---|---|---|
| Occupation (col. 14) | **2022 Updates to the 2012 PSOC** (marked `*` on slides 44–48) | **Same edition the repository carries (PSOC 2022).** All 21 codes verified live. |
| Industry (col. 15/16) | **2019 Updates to the 2009 PSIC (revised as of February 2011)** — stated on PDF p14 / slide 55 | **NOT the current edition.** The repository's current edition is PSIC 2026. |

### Why the industry half can never be used as codes

Measured directly against the repository — the same code number now denotes
a **different activity**:

| Code | 2019 vintage (this document) | **PSIC 2026 (current)** |
|---|---|---|
| `4781` | Retail sale via stalls and markets of food, beverages, tobacco | **Retail sale of motor vehicles** |
| `56107` | Carinderia or eatery | **Roasting and grilling of meat, poultry or fish** |
| `86225` | Dialysis center activities | **Private obstetrics and gynecology clinic activities** |
| `11053` | Water purifying and refilling station | **Manufacture of other non-carbonated flavored soft drinks** |

And these document codes **do not exist in PSIC 2026 at all**:
`4799`, `4669`, `8010`, `4789`, `4791`, `49325`, `86124`, `82297`, `45204`.

A code copied forward from this document is therefore not merely stale — it
can be confidently wrong about an unrelated industry.

---

## 3. Evidence roles

| Role | Meaning | May it produce a code? |
|---|---|---|
| `current_occupational_evidence` | Occupation wording → PSOC code, verified against the **current** edition | Yes, after canonical verification |
| `historical_activity_evidence` | Industry wording → **activity text**; historical code retained for audit only | **No.** Must be re-resolved against PSIC 2026 |
| `methodology` | Coding rules, refusal lists, probing questions | No — governs *how* to ask, not *what* to code |

---

## 4. Occupation evidence — `current_occupational_evidence`

Encoded in `ASSISTANT_GUIDANCE_PSOC_EXAMPLES`
(`R/assistant/assistant_survey_guidance.R`). Every code below was
independently verified as a live **PSOC 2022 unit group**, and is
re-verified at runtime before use — an unverifiable code is dropped, never
surfaced.

| PDF p / slide | Document wording | Code | Current PSOC 2022 label (verified) |
|---|---|---|---|
| p2 / 43 | Midwives who passed the board exam | `2222` | MIDWIFERY PROFESSIONALS |
| p2 / 43 | Midwives non-board passer | `3222` | MIDWIFERY ASSOCIATE PROFESSIONALS |
| p2 / 43 | Scavenging of plastics, bottles, etc. | `9612` | REFUSE SORTERS |
| p2 / 43 | Scavenging of leftover palay during threshing/harvesting | `6310` | SUBSISTENCE CROP FARMERS |
| p3 / 44 | Tire makers and vulcanizers | `8141` | RUBBER PRODUCTS MACHINE OPERATORS |
| p3 / 44 | E-LOAD retailers | `5211` | STALL AND MARKET SALESPERSONS |
| p3 / 44 | Online seller `*` | `5247` | ONLINE-SELLING SALESPERSONS |
| **p4 / 45** | **Barangay Health Workers (BHW)** | **`3253`** | **COMMUNITY HEALTH WORKERS** |
| p4 / 45 | Crypto/bitcoin currency traders `*` | `3311` | SECURITIES AND FINANCE DEALERS AND BROKERS |
| p4 / 45 | Crypto/bitcoin currency managers `*` | `1211` | FINANCE MANAGERS |
| p5 / 46 | Angkas, Joyride, Toktok, Grab Express drivers `*` | `8323` | TRANSPORT NETWORK VEHICLE SERVICE MOTORCYCLE DRIVERS |
| p5 / 46 | Grab drivers (using car) `*` | `8324` | TRANSPORT NETWORK VEHICLE SERVICE CAR DRIVERS |
| p5 / 46 | Grab Taxi drivers `*` | `8325` | TRANSPORT NETWORK VEHICLE SERVICE TAXI DRIVERS |
| p6 / 47 | Grab, Lalamove, Transportify drivers (van) `*` | `8326` | TRANSPORT NETWORK VEHICLE SERVICE VAN DRIVERS |
| p6 / 47 | Grab Bike drivers, Food Panda drivers (bicycle) `*` | `9335` | TRANSPORT NETWORK VEHICLE SERVICE BICYCLE DRIVERS |
| p6 / 47 | Mathematician, Operations research analyst `*` | `2121` | MATHEMATICIANS |
| p7 / 48 | Actuarial analyst/specialist, Actuarial researcher `*` | `2123` | ACTUARIES |
| p7 / 48 | Data miner, Machine learning engineer `*` | `2124` | DATA SCIENTIST |
| p7 / 48 | E-sport players and coaches `*` | `3424` | ESPORTS PLAYERS AND COACHES |
| p7 / 48 | EVSE Repair and Maintenance `*` | `7414` | ELECTRIC VEHICLE MECHANICS AND REPAIRERS |
| p8 / 49 | Nagtitinda ng isda sa daan na may pwesto (stall) | `5211` | STALL AND MARKET SALESPERSONS |
| p9 / 50 | Nagtitinda … naglalako (ambulant, excluding food) | `9520` | STREET VENDORS (excluding food) |

`*` = marked in the document as "Using 2022 Updates to the 2012 PSOC".

### 4.1 Barangay Health Worker — explicit record

```
BHW / Barangay Health Worker
  -> PSOC 3253 COMMUNITY HEALTH WORKERS
  role     : current_occupational_evidence
  source   : PDF p4 / slide 45, column 14
  vintage  : 2022 Updates to the 2012 PSOC == repository PSOC 2022
  verified : YES - live PSOC 2022 unit_group, label matches the document
```

This guidance is what the curated override in
`data-raw/curated_psoc_overrides.csv` rests on. The source pairing workbook
had coded the BHW to `5321 HEALTH CARE ASSISTANTS`; the override moves it to
`3253` and records the disagreement rather than hiding it.

**"Barangay health aide" is a different occupation term and stays at
`5321`.** The two must never be normalised into one another — see §6.

---

## 5. Industry evidence — `historical_activity_evidence`

Encoded in `ASSISTANT_GUIDANCE_PSIC_ACTIVITY_HINTS`. **No current code is
stored.** Each entry carries the document's *activity wording* plus the
historical code as audit metadata, flagged `is_current_code = FALSE` with a
vintage caution.

| PDF p / slide | Document wording | Historical code (2019 vintage) | Encoded activity text | Current code |
|---|---|---|---|---|
| p16 / 57 | Security agencies | `8010` | private security activities | *(resolve against PSIC 2026)* |
| p17 / 58 | E-LOAD retailing | `4789` | retail sale of prepaid cards | *(resolve)* |
| p17 / 58 | Online selling | `4791` | retail sale via mail order or internet | *(resolve)* |
| **p17 / 58** | **Barangay Health Center (BHW)** | **`8412`** | regulation of the activities of providing health care | *(resolve — never assumed)* |
| p8 / 49 | Retail via stalls and markets | `4781` | — *(not encoded: `4781` now means motor vehicles)* | — |
| p9 / 50 | Other retail not in stores/stalls | `4799` | — *(not encoded: absent from 2026)* | — |
| p22 / 63 | Carinderia or eatery | `56107` | carinderia or eatery | *(resolve)* |
| p21 / 62 | Ride-sharing service operations | `49325` | operations of vehicles for transportation network service | *(resolve)* |
| p20 / 61 | Water purifying and refilling station | `11053` | water purifying and refilling station | *(resolve)* |
| p26 / 67 | Dialysis Center activities | `86225` | dialysis center activities | *(resolve)* |
| p20 / 61 | Car washing and auto-detailing | `45204` | car washing and auto-detailing services | *(resolve)* |
| p25 / 66 | Knowledge process outsourcing (KPO) | `82297` | knowledge process outsourcing activities | *(resolve)* |

### 5.1 Barangay Health Center — explicit record

```
Barangay Health Center
  -> historical PSIC 8412 (2019 Updates to the 2009 PSIC)
  role     : historical_activity_evidence
  source   : PDF p17 / slide 58, column 15
  caution  : HISTORICAL VINTAGE. This code MUST NOT be presented as a
             current PSIC code and MUST NOT bypass current PSIC
             resolution. Codes from this vintage have been reused for
             unrelated activities in PSIC 2026 (see section 2).
  encoded  : activity text "regulation of the activities of providing
             health care" only; is_current_code = FALSE
  required : resolve the activity text against PSIC 2026 through ordinary
             retrieval, then verify canonically before presenting anything
```

Open question, recorded rather than silently resolved: the document places
a barangay health centre under *regulation of health care* (`8412`), but
such a unit arguably performs health **services**. Because only activity
text is encoded, the establishment's actual principal activity decides —
which is the correct behaviour either way.

---

## 6. Occupation terms that must stay distinct

| Term | Code | Basis |
|---|---|---|
| Barangay Health Worker / BHW | `3253` COMMUNITY HEALTH WORKERS | This document, p4 / slide 45 |
| Barangay health aide | `5321` HEALTH CARE ASSISTANTS | Canonical PSOC example list (archived-edition description) |

Community-based health work and institution-based patient-care assistance
are different occupations. The controlled vocabulary must never expand
`worker → aide` or the reverse; this is enforced by tests in
`tests/testthat/test-assistant-contextual-coding.R`.

---

## 7. Methodology — `methodology`

| PDF p / slide | Rule | Where encoded |
|---|---|---|
| p11 / 52 | **Refused descriptions:** "farm", "store", "retail store", "wholesale store", "mine", "factory", "shop", "school", "government", "transportation", "company"; also the company name alone | `ASSISTANT_GUIDANCE_VAGUE_ACTIVITIES` |
| p10 / 51 | Accepted examples: "cocktail lounge", "growing of paddy rice (lowland, irrigated)", "catching fish", "commercial bank", "retail sale of food", "private household" | Used as the acceptance contrast in tests |
| p12 / 53 | Probing questions ("What kind of retail store is this?", leather vs rubber shoes, sell vs repair, laundry shop vs own home) | `ASSISTANT_GUIDANCE_PROBES` |
| p13 / 54 | Government office/institution may be named; for a local-government executive branch **specify provincial, city, or municipal** | `ASSISTANT_GUIDANCE_GOVERNMENT_PROBE` (non-blocking supplementary probe) |
| p13 / 54 | Large multi-activity company → record the specific activity the person is involved in | Reinforced in the RM system prompt |
| p29 / 70 | **Outsourced personnel:** coded to the industry where they worked **only if paid there**; otherwise to the manpower/outsourcing agency. "Futher probe kung sino ang nagpapasweldo sa kanila." | `ASSISTANT_GUIDANCE_OUTSOURCING_PROBE` — **blocks** PSIC until the payer is known |

---

## 8. Runtime dependency statement

- The PDF is **not** committed and is **never** opened at runtime.
- This provenance file is **documentation only** and is **not** read at
  runtime; it therefore requires no manifest entry.
- The evidence itself is compiled into
  `R/assistant/assistant_survey_guidance.R` (a normal runtime module, which
  **is** in `manifest.json`) and into the reviewed
  `data-raw/curated_psoc_overrides.csv` → `data/assistant_common_pairings.rds`
  build path.
- Every code reaching a user is re-verified against the current canonical
  repository regardless of which evidence layer suggested it.

---

## 9. Review triggers

Re-review this record when any of the following happens:

1. PSOC is re-ingested or a new PSOC edition becomes current — re-verify all
   21 occupation codes and their labels.
2. PSIC 2026 is superseded — the §2 collision table must be recomputed.
3. A newer edition of the survey manual is supplied — vintages in §2 change.
4. The pairing workbook changes its BHW row — the curated override in
   `data-raw/curated_psoc_overrides.csv` asserts the workbook still carries
   `5321`, and the build fails loudly if it does not.

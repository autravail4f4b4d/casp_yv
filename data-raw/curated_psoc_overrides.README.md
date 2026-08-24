# Curated PSOC 2022 overrides

`curated_psoc_overrides.csv` is the **authoritative source layer** for approved
manual review decisions on the occupation -> 2022 PSOC mappings carried by
`CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping.xlsx`.

The workbook is an external source artifact and is never edited. Decisions are
recorded here instead, and `scripts/build_assistant_assets.R` applies them when
it regenerates `data/assistant_common_pairings.rds`. The generated `.rds` is
never patched directly.

## Two kinds of override

| `override_kind` | Meaning |
| --- | --- |
| `correction` | The workbook's code is wrong for the reported occupation and is replaced. `curated_psoc` differs from `source_workbook_psoc`. |
| `confirmation` | The workbook's code is already correct. The review is recorded against it — typically to raise a `Low` confidence to `High` — and the code does not move. `curated_psoc` equals `source_workbook_psoc`. |

The kind is declared, not inferred, and the build cross-checks it: a
`correction` that changes nothing, or a `confirmation` that moves the code, is
a hard build failure. This is what stops a confirmation from ever being read,
or presented, as a code change.

## Columns

| Column | Meaning |
| --- | --- |
| `occupation` | The reported occupation phrase, preserved exactly as published in the workbook. Used as the join key; must match one workbook row exactly. |
| `override_kind` | `correction` or `confirmation`, as above. |
| `source_workbook_psoc` | The PSOC code the workbook currently carries. The build hard-fails if the workbook no longer holds this value, so a silent upstream change cannot be overwritten unnoticed. |
| `curated_psoc` | The approved 2022 PSOC unit-group code. Must resolve in the canonical PSOC 2022 repository. |
| `psoc_confidence` | Confidence after review. |
| `psoc_provenance` | Always `curated` — the application's approved/curated mapping category, distinct from `source_workbook`. |
| `curation_note` | Rationale, and any ambiguity that must survive into the artifact. |

The official PSOC label is **not** stored here. The build resolves
`confirmed_psoc_label` from the canonical PSOC 2022 repository so the artifact
can never disagree with the classification of record.

## Scope

These overrides change the **occupation** mapping only. `psic_rev5_code`,
`psic_rev5_rule`, `mapping_confidence` (which is the *PSIC* mapping confidence)
and `mapping_note` are left exactly as published. An occupation never
determines an establishment's PSIC.

## Note on `Truck Driver`

`Truck Driver` is a `confirmation`, not a correction. The workbook already
carried **8332 `HEAVY TRUCK AND LORRY DRIVERS`**, which is the correct unit
group; only its `Low` PSOC confidence was raised to `High`.

An earlier proposal to map this occupation to **8331** was rejected: 8331 is
`BUS AND TRAM DRIVERS`, a different unit group in the same minor group 833, and
is not the truck-driving occupation. No override targets 8331.

## Not yet reviewed

`Videoke Rental Owner` (1431) is the remaining row graded `Low` PSOC confidence
in the workbook's `Low Confidence Review` sheet. No curated decision has been
supplied for it, so it is untouched and keeps `source_workbook` provenance.

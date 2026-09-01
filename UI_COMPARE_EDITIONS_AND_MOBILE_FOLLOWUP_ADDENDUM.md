# UI Follow-up Addendum — Compare Editions Simplification, Control Layout, and Mobile Refinement

**Project:** PSA Statistical Classifications Search + RM Assistant  
**Worktree:** `D:\dev\historical_phclassif-ui`  
**Branch:** `feature/ui-refinement-liquid-glass`  
**Current UI candidate:** `3c49c8e3f22749e1cd48217ccd06d83643a3c9f9`  
**Baseline:** accepted RM `pre-staging-v10.1` behavior must remain unchanged  
**Purpose:** Apply a focused follow-up UI refinement after visual review of the liquid-glass candidate. This addendum does not reopen RM mechanics, retrieval, semantic authority, or classification logic.

---

# 1. Scope

This pass is limited to:

1. Compare Editions control sizing and placement.
2. Compare Editions relationship-detail simplification.
3. Removal of repeated provenance presentation.
4. Simplification of evidence/corroboration copy.
5. Mobile responsiveness for filters, buttons, dialogs, tables, and inspector panels.
6. Small button/control placement improvements required by the above.

Do not redesign the application architecture.

---

# 2. Non-negotiable boundaries

Do NOT change:

```text
R/assistant/
R/retrieval/
classification registry semantics
canonical classification data
correspondence mappings
RM routing/execution
RM clarification lifecycle
semantic authority
gpt-4o-mini
conversational provider
```

Semantic authority remains:

```text
OFF
```

RM v10.1 behavior must remain functionally unchanged unless a purely visual class hook is required.

Do not add React, TypeScript, Tailwind, Vite, Framer Motion, or new front-end frameworks.

---

# 3. Compare Editions — Direction control

## Problem

The current Direction control is too narrow and makes values such as:

```text
2019 PSIC → PSIC Revision 5 (2026)
```

feel cramped.

## Required behavior

Desktop:

- Direction label above the control.
- Direction selector uses the full available width of its filter column or row.
- The selected value must be readable without clipping.
- Do not compress the control merely to preserve a compact filter row.

Mobile:

- Direction becomes full-width.
- It must stack vertically with the other Compare Editions controls.
- No clipped text.
- No page-level horizontal overflow.
- Preserve local component overflow only where genuinely necessary.

## Acceptance

Verify at:

```text
1440
1366
1024
768
375
320
```

The complete selected direction must remain usable and readable.

---

# 4. Compare Editions — remove separate Provenance presentation

## Decision

Do not show Provenance as a separate primary field in the Compare Editions table or relationship-detail summary.

The user-facing Compare Editions surface should not repeatedly display:

```text
Relationship
Provenance
Confidence
```

as a table-like metadata block.

## Reason

For this correspondence surface, the relationships are already derived. Repeating a standalone provenance field adds technical noise without helping the user make a classification decision.

## Required UI

Primary relationship details should show:

```text
Relationship
Confidence
Supporting note / corroboration
```

No standalone Provenance row.

Do not delete provenance data from the underlying model if it is used for validation or internal logic. This is a presentation change only.

---

# 5. Relationship Details — simplified structure

Replace the technical/table-like evidence display with a compact relationship narrative.

Preferred structure:

```text
Relationship
[Continued / Renamed / Split / Merged / Reclassified / other verified type]

Confidence
[High / Medium / Low]

Derived correspondence
This relationship was derived from official correspondence logic.

Corroboration
Supported by the official UN ISIC Rev.4 to Rev.5 correspondence.
```

If the UN ISIC corroboration is not applicable to a specific relationship, do not fabricate it. Show only corroboration actually present in the verified evidence.

---

# 6. Evidence text — simplify aggressively

## Current style to remove from the UI

Do not show internal diagnostic wording such as:

```text
2019 section A corresponds to 2026 section A.
Identical letters were verified against the section graph, not assumed.
Code '01196' -> '01191' (same class).
Label evidence supporting only (normalized-token similarity 0.25).
Search method: class_prefix_continuity.
```

These details are useful for engineering/debugging, not for the main user-facing correspondence inspector.

## Preferred user-facing copy

Default concise form:

```text
This relationship was derived from official correspondence logic and corroborated by the official UN ISIC Rev.4 to Rev.5 correspondence.
```

Shorter form when appropriate:

```text
Supported by the official UN ISIC Rev.4 to Rev.5 correspondence.
```

If there is no UN corroboration for the relationship, use:

```text
This relationship was derived from the verified classification correspondence.
```

Do not expose:

```text
normalized-token similarity
search method names
class_prefix_continuity
section graph terminology
internal ranking/scoring mechanics
```

unless a future dedicated advanced/debug mode is explicitly introduced.

---

# 7. Confidence

Keep Confidence visible.

Do not present Confidence as a statistical probability.

Preferred representation:

```text
High
Medium
Low
```

Use text plus restrained visual styling.

Do not rely on color alone.

No percentage should be shown unless the underlying source actually defines a probability.

---

# 8. Relationship-detail note for derived mappings

Because these correspondences are derived, include a compact note in the detail inspector.

Preferred wording:

```text
Derived correspondence
This relationship was derived from verified classification correspondence evidence.
```

Where UN corroboration exists:

```text
Corroborated by the official UN ISIC Rev.4 to Rev.5 correspondence.
```

Do not repeat the same "derived" message in multiple rows, pills, and tables.

One concise explanatory location is enough.

---

# 9. Button and control placement

You may reposition buttons and controls where this improves clarity.

Priority surfaces:

```text
Compare Editions
PSOC + PSIC details
Hierarchy browser
mobile filter stacks
relationship inspector
```

Guidelines:

- Primary actions should sit close to the content they affect.
- Secondary actions should not compete visually with primary actions.
- Avoid cramped horizontal button groups on mobile.
- Buttons may stack vertically on narrow screens.
- Keep 44px minimum practical touch targets where possible.
- Preserve keyboard navigation.
- Preserve focus restoration for shared dialogs.
- Do not move actions into locations that become hidden below long tables.

---

# 10. Compare Editions — preferred layout

## Desktop

Preferred order:

```text
Page title / intro

Filter region:
  System
  Source edition / Target edition if applicable
  Direction (wide)

Correspondence table

Right-side relationship inspector
```

The table must remain visible while the inspector is open.

The inspector should prioritize:

```text
source code/title
target code/title
relationship
confidence
derived note
UN ISIC corroboration when applicable
statistical-use safeguard
```

Do not present the inspector as a dense metadata table.

## Mobile

Preferred:

```text
filters stacked vertically
Direction full-width
table / list
relationship inspector as slide-over or full-screen sheet
```

No page-level horizontal overflow.

---

# 11. Mobile browsing refinement

Review the full app at:

```text
768
375
320
```

Focus particularly on:

- filter/sidebar stacking;
- system selectors;
- release selectors;
- Direction selector;
- result tables;
- relationship badges;
- Compare inspector;
- hierarchy browser;
- detail dialogs;
- RM chat surface;
- action buttons.

Required:

```text
no clipped labels
no mid-word status wrapping
no page-level horizontal overflow
local table scrolling only
full-width controls where needed
readable touch targets
```

---

# 12. Preserve statistical safeguard

The relationship inspector/help must continue to state that correspondence metadata does not itself justify automatic redistribution of historical statistical values.

Do not weaken or remove this safeguard while simplifying the evidence presentation.

Recommended concise form:

```text
Statistical-use note
A correspondence relationship does not by itself justify automatic redistribution of historical statistical values.
```

---

# 13. Do not remove underlying evidence

This pass simplifies presentation only.

Do not delete:

```text
relationship provenance fields
internal evidence strings
confidence metadata
verification evidence
UN corroboration metadata
```

from the underlying data model if tests, validation, or engineering diagnostics use them.

Hide/summarize them in the user-facing interface.

---

# 14. Testing requirements

Add/update targeted tests for:

```text
Direction control receives the intended full-width class/layout
Direction value is not structurally truncated
Provenance is absent from primary Compare Editions user-facing detail rendering
Relationship remains visible
Confidence remains visible
Derived note is present
UN ISIC corroboration appears only when supported
internal evidence/debug phrases are absent from normal UI rendering
statistical-use safeguard remains visible
mobile control stack hooks exist
button placement preserves dialog trigger IDs and accessibility
```

Do not write brittle pixel/hex tests.

---

# 15. Browser acceptance

Verify in the running app at:

```text
1440
1366
1024
768
375
320
```

At minimum inspect:

## Compare Editions

- Direction readable and wide enough.
- No clipping.
- No unnecessary standalone provenance field.
- Relationship details simplified.
- Confidence readable.
- Derived note concise.
- UN ISIC corroboration concise.
- No internal search/ranking jargon.
- Inspector still works for continued/split/merged/reclassified examples.
- Table remains visible on desktop.
- Inspector becomes usable sheet on mobile.

## Mobile

- No page-level horizontal overflow.
- Buttons do not overlap.
- Select controls do not clip text.
- Detail sheets remain reachable.
- Touch targets usable.

---

# 16. RM and semantic non-regression

Re-run the accepted RM v10.1 matrix:

```text
mayor -> 1111 / 84113
teacher -> 2330 / 8531 -> latter -> 85314
statistician at PSA -> 2122 / 8411
carpenter -> 7115; residential stays unresolved
outsourced janitor -> wage payer first; agency pays -> 78200
palay -> upland -> 6111 / 01123
corn -> 6112 / 01130
six-item batch -> 8325, 9335, 8141, 5247, 2124, 3424
angkas after batch -> 8323
```

Required:

```text
no RM behavioral change
semantic authority OFF
```

---

# 17. Full engineering gate

Run:

```powershell
Rscript scripts/run_tests.R
Rscript -e "renv::status()"
git diff --check
git status --short
git diff --stat
```

Required:

```text
FAIL 0
WARN 0
SKIP 0
```

---

# 18. Stop boundary

Do NOT:

```text
git commit
git push
git tag
git merge
republish Connect Cloud
deploy production
merge main
enable semantic authority
change model/provider
```

Leave the follow-up UI work uncommitted for review.

---

# 19. Final report

Return:

1. Starting branch/HEAD.
2. Direction-width root cause.
3. Direction layout fix.
4. Desktop Direction result.
5. Mobile Direction result.
6. Provenance presentation change.
7. Relationship-detail redesign.
8. Confidence presentation.
9. Evidence-copy rewrite.
10. UN ISIC corroboration presentation.
11. Confirmation internal debug evidence is hidden from normal UI.
12. Statistical-use safeguard result.
13. Button/control placement changes.
14. Mobile layout changes.
15. 375px result.
16. 320px result.
17. Files changed.
18. Tests added/updated.
19. Targeted test result.
20. Full test result.
21. `renv::status()`.
22. `git diff --check`.
23. RM non-regression result.
24. Semantic authority status.
25. Remaining visual issues.
26. Ready for controlled commit?
27. Confirmation no commit/push/tag/merge/deploy occurred.

Stop there.

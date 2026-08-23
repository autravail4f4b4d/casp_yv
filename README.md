# PSA Statistical Classifications Search

A read-only R Shiny app for searching and browsing Philippine Statistics
Authority (PSA) statistical classifications: PSGC, PSIC (including PSIC
Revision 5 / the "2026 PSIC"), PSOC (including the "2022 Updates to the
2012 PSOC"), PSCED, PCOICOP, PCPC, and PSCCS. It also provides a parallel
PSOC + PSIC occupation/industry search, a bidirectional PSIC 2019 ↔
Revision 5 (2026) correspondence explorer, and **RM**, an optional grounded
conversational assistant that can only ever quote codes retrieved from this
application's own classification data.

This started as the functionality-first MVP described in
[`PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`](PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md),
was extended per
[`PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md`](PSA_CLASSIFICATION_PSOC2022_DUAL_SEARCH_PSIC_CORRESPONDENCE.md)
to add PSOC 2022, dual search and PSIC correspondence, and then per
[`PSA_CLASSIFICATIONS_RM_ASSISTANT_INTEGRATION.md`](PSA_CLASSIFICATIONS_RM_ASSISTANT_INTEGRATION.md)
to add the RM assistant. Visual design is intentionally minimal — see
[`docs/UI_CONTRACT.md`](docs/UI_CONTRACT.md) for what a follow-up design
pass may and may not change.

## RM Assistant

RM is **disabled by default** and the application is fully functional
without it. To enable it, set server-side environment variables:

```
RM_ASSISTANT_ENABLED=true
RM_PROVIDER=openai          # or anthropic
RM_MODEL=gpt-4o-mini
OPENAI_API_KEY=...          # or ANTHROPIC_API_KEY
```

Never commit a key. See [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for
deployment configuration and [`docs/ASSISTANT_CONTRACT.md`](docs/ASSISTANT_CONTRACT.md)
for the grounding rules, tool contracts and known limitations.

## Running locally

```
Rscript -e "renv::restore()"   # first time only, installs pinned deps
Rscript -e "shiny::runApp('app.R')"
```

## Running the tests

```
Rscript scripts/run_tests.R
```

## Rebuilding the supplemental data artifacts

```
Rscript scripts/build_psic_2026.R              # PSIC Revision 5 (2026)
Rscript scripts/build_psoc_2022.R              # 2022 Updates to the 2012 PSOC
Rscript scripts/build_psic_correspondence.R    # PSIC 2019 <-> 2026 correspondence
Rscript scripts/build_assistant_assets.R       # RM pairings + compact PSIC rules
```

`build_psoc_2022.R` requires `data-raw/2022-Updates-to-the-2012-PSOC.xlsx`
to already be present (manually downloaded — PSA's file host for this
workbook blocks automated retrieval; see `docs/DATA_SOURCES.md`).

See [`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md) and
[`docs/CORRESPONDENCE_SOURCES.md`](docs/CORRESPONDENCE_SOURCES.md) for full
provenance, and [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for deployment
notes.

## Architecture

```
UI (app.R, R/ui/)
  -> Shiny reactives (app.R server function)
  -> Application service (R/repository.R, R/search.R, R/parallel_search.R,
                           R/correspondence/service.R)
  -> Classification registry (R/registry.R)
  -> Adapters (R/adapters/) -> phscs / psgc / local PSIC 2026 / PSOC 2022
                                artifacts

RM Assistant (R/ui/ui_assistant.R)
  -> shinychat chat module (per-session ellmer client)
  -> read-only tools (R/assistant/assistant_tools.R)
  -> the SAME application service layer above
```

RM adds no second repository, no second search engine and no second
ranking: its tools are thin read-only wrappers over the functions already
listed. It cannot emit a classification code that those functions did not
return.

Classification/search/version logic is fully testable without launching
Shiny — see `tests/testthat/`.

## Status

See [`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md) for what's done,
tested, and deferred.

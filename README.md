# PSA Statistical Classifications Search

A read-only R Shiny app for searching and browsing Philippine Statistics
Authority (PSA) statistical classifications: PSGC, PSIC (including PSIC
Revision 5 / the "2026 PSIC"), PSOC, PSCED, PCOICOP, PCPC, and PSCCS.

This is the functionality-first MVP described in
[`PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md`](PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md).
Visual design is intentionally minimal — see
[`docs/UI_CONTRACT.md`](docs/UI_CONTRACT.md) for what a follow-up design
pass may and may not change.

## Running locally

```
Rscript -e "renv::restore()"   # first time only, installs pinned deps
Rscript -e "shiny::runApp('app.R')"
```

## Running the tests

```
Rscript scripts/run_tests.R
```

## Rebuilding the PSIC Revision 5 data artifact

```
Rscript scripts/build_psic_2026.R
```

See [`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md) for full provenance and
[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for deployment notes.

## Architecture

```
UI (app.R, R/ui/)
  -> Shiny reactives (app.R server function)
  -> Application service (R/repository.R, R/search.R)
  -> Classification registry (R/registry.R)
  -> Adapters (R/adapters/) -> phscs / psgc / local PSIC 2026 artifact
```

Classification/search/version logic is fully testable without launching
Shiny — see `tests/testthat/`.

## Status

See [`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md) for what's done,
tested, and deferred.

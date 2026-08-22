# Deployment Notes — PSA Statistical Classifications Search

## Deployment target

Designed for Posit Connect Cloud or any equivalent Shiny-compatible public
host that can run `app.R` from this repository with the pinned dependency
set in `renv.lock`. No deployment-specific configuration files beyond that
are required.

## Reproducible dependencies

The project is an `renv` project (`renv.lock`, `.Rprofile` sourcing
`renv/activate.R`). Every package the app or its build/test scripts use is
pinned to the exact version installed and verified during this build (R
4.6.1): `shiny`, `bslib`, `phscs`, `psgc`, `dplyr`, `stringr`, `tibble`,
`purrr`, `DT`, `readxl`, `testthat`, `httr2`, `digest`. renv also recorded
its own transitive dependencies (rlang, vctrs, htmltools, etc.).

To restore this exact environment on a fresh machine/host:

```
Rscript -e "renv::restore()"
```

## Runtime data dependencies — no PSA network calls at runtime

- **PSIC Revision 5 (2026)** is served entirely from the committed local
  artifact `data/psic_2026.rds` (built once, offline, by
  `scripts/build_psic_2026.R` from PSA's official workbook — see
  `docs/DATA_SOURCES.md` for full provenance). The running app never
  fetches from `psa.gov.ph` at runtime. If `data/psic_2026.rds` is ever
  missing from a deployment, the app fails loudly and immediately with
  `"PSIC Revision 5 runtime artifact is missing. Run scripts/build_psic_2026.R
  and redeploy."` rather than silently serving something else labeled 2026.
- **phscs** and **psgc** classification data ship as part of those
  installed R packages (in-memory package data) — also no runtime network
  dependency.
- **No PSA API token, API key, or any credential is required anywhere in
  this application.** There is nothing to configure as a secret. No
  credentials appear in any committed file.

## Rebuilding the PSIC Revision 5 artifact

Only needed if PSA republishes a corrected/updated workbook at the same
official URL, or if `data/psic_2026.rds` is ever regenerated:

```
Rscript scripts/build_psic_2026.R
```

This downloads the workbook (if not already present in `data-raw/`),
re-parses and re-validates it, and overwrites `data/psic_2026.rds` and
`data/psic_2026_metadata.rds`. Re-run the test suite afterward.

## Running the test suite

```
Rscript scripts/run_tests.R
```

Current status: **290/290 tests passing** (`test-schema.R`,
`test-registry.R`, `test-adapters.R`, `test-psic-2026.R`, `test-search.R`,
`test-repository.R`).

## Starting the app locally / verifying a clean-session start

```
Rscript -e "shiny::runApp('app.R', port = 8317)"
```

This was verified in this build under the renv-activated environment
(fresh `Rscript` process each time, no pre-warmed session) — the app
listens successfully and serves the UI with no startup errors. It was
**not** deployed to any actual public host as part of this build: no
Posit Connect Cloud (or equivalent) account/credentials were available in
this environment. Everything short of the actual remote publish step has
been completed and verified locally.

## Public-safety checklist (spec section 20)

- [x] No embedded secrets or tokens anywhere in the repository.
- [x] No API tokens in client-visible HTML/JS (there are none to begin with).
- [x] No user-supplied file execution, no `eval(parse())`.
- [x] No arbitrary URL fetching driven by user input — the only outbound
      fetch in the whole codebase is the one-time, build-time,
      hardcoded-URL download in `scripts/build_psic_2026.R`, never invoked
      from the running app.
- [x] Classification text is rendered through `shiny::tags$...`/`htmltools`,
      which HTML-escapes text content by default — no raw `HTML()` calls
      wrap user-controlled input anywhere.
- [x] Dependencies pinned via `renv.lock`.
- [x] Errors shown to users are the same clear, non-stack-trace validation
      messages used internally (e.g. "Unsupported version '...' — Available
      versions: ..."); no raw R stack traces are exposed by default under
      Shiny's standard production error-sanitization behavior.

# Adapter over the `psgc` package (Philippine Standard Geographic Code).
#
# Uses the `psgc` package directly (`psgc::get_psgc()`, `psgc::list_releases()`,
# `psgc::latest_release()`) rather than the `phscs::get_psgc` re-export, per
# the implementation spec.
#
# PARENT_CODE DERIVATION
# -----------------------
# PSGC codes are 10-digit hierarchical strings, but the digit layout is not
# perfectly regular: NCR cities sit directly under the region with no
# province segment, and some cities contain sub-municipalities. Rather than
# hardcoding fixed digit positions, parent_code is derived generically: for
# each code, zero out successively larger trailing digit-groups (1 digit,
# then 2, then 3, ...) and take the first candidate that (a) differs from
# the code itself and (b) exists as another row's code in the SAME
# release's full pulled dataset (all geographic levels, not just one).
# Scanning from the finest truncation to the coarsest means the nearest
# existing ancestor is always found first -- e.g. a barangay resolves to
# its municipality before ever considering the province, and an NCR city
# (whose "zero the last 5 digits" candidate is a no-op, since city codes
# already end in five zeros) correctly falls through to "zero the last 8
# digits" and resolves straight to its region. This was verified against
# real Q2_2026 data for the barangay -> municipality -> province -> region
# chain and for an NCR city with no province segment (see test-adapters.R).

.psgc_cache <- new.env(parent = emptyenv())

#' Character vector of all known PSGC release ids.
psgc_versions <- function() {
  psgc::list_releases()
}

#' Generic PSGC parent-code derivation. See file header for rationale.
.derive_psgc_parent <- function(codes) {
  # Hash all codes once so each candidate lookup is O(1).
  code_env <- new.env(size = length(codes) * 2L, parent = emptyenv())
  for (c in codes) assign(c, TRUE, envir = code_env)

  vapply(codes, function(code) {
    n <- nchar(code)
    for (k in seq_len(n - 1L)) {
      cand <- paste0(substr(code, 1L, n - k), strrep("0", k))
      if (!identical(cand, code) && exists(cand, envir = code_env, inherits = FALSE)) {
        return(cand)
      }
    }
    NA_character_
  }, character(1), USE.NAMES = FALSE)
}

# Pull + assemble one full release (all geographic levels), computing
# parent_code across the whole release. Cached per release id.
.psgc_pull_release <- function(version) {
  cached <- .psgc_cache[[version]]
  if (!is.null(cached)) {
    return(cached)
  }

  raw <- psgc::get_psgc(release = version, geographic_level = NULL, include_population_data = FALSE)
  codes <- as.character(raw$psgc_code)
  labels <- as.character(raw$area_name)
  levels <- as.character(raw$geographic_level)

  status <- if (identical(version, psgc::latest_release())) "current" else "archived"
  parent_code <- .derive_psgc_parent(codes)

  out <- new_classification_tibble(
    system = "psgc",
    version = version,
    level = levels,
    code = codes,
    label = labels,
    description = NA_character_,
    parent_code = parent_code,
    status = status,
    source = "Philippine Statistics Authority",
    source_url = "https://psa.gov.ph/classification/psgc"
  )

  .psgc_cache[[version]] <- out
  out
}

#' Unique geographic_level values available in a release.
#'
#' A very small number of rows in the raw PSA data (verified: "Special
#' Geographic Area" and "City of Isabela (Not a Province)") carry an empty
#' string for geographic_level rather than a real level -- those rows are
#' still returned by psgc_get() with their level exactly as given by the
#' source (never fabricated), but they are excluded here because an empty
#' string is not a genuine browsable hierarchy level.
psgc_levels <- function(version) {
  out <- .psgc_pull_release(version)
  lvls <- unique(out$level)
  sort(lvls[nzchar(lvls)])
}

#' Canonical classification tibble for one PSGC release.
#' `level = NULL` (default) returns every geographic level in that release.
psgc_get <- function(version, level = NULL) {
  out <- .psgc_pull_release(version)
  if (!is.null(level)) {
    out <- out[out$level == level, , drop = FALSE]
  }
  out
}

#' Display/provenance metadata for one PSGC release.
psgc_metadata <- function(version) {
  list(
    system = "psgc",
    version = version,
    display_version = version,
    status = if (identical(version, psgc::latest_release())) "current" else "archived",
    source = "Philippine Statistics Authority",
    source_url = "https://psa.gov.ph/classification/psgc",
    # Sys.Date() is an MVP placeholder; see note in adapter_phscs.R.
    retrieved_at = as.character(Sys.Date()),
    license = "CC BY 4.0 unless otherwise stated by PSA"
  )
}

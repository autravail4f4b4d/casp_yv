# Philippine Standard Creative Classification System (PSCrCS), 2025 adapter.
#
# Reads the build-time-normalized runtime artifact at data/pscrcs_2025.rds
# (produced by scripts/build_pscrcs_2025.R) rather than parsing the source
# workbook or touching the network at runtime.
#
# PSCrCS is a COMPOSITE / THEMATIC classification: it does not mint its own
# codes. Each record reuses a code from an underlying classification, and that
# provenance is part of the statistical meaning:
#
#   creative_industry      -> psic 2019 (2019 Updates to the 2009 PSIC)
#   creative_good_service  -> cpc  2.1  (Central Product Classification 2.1)
#   creative_occupation    -> psoc 2022 (2022 Updates to the 2012 PSOC)
#
# The industry component is 2019 PSIC and is deliberately NOT re-labelled as
# PSIC 2026 / Revision 5, even though this application also ships PSIC
# Revision 5.
#
# SHAPE: the returned tibble's FIRST TEN columns are exactly
# CLASSIFICATION_SCHEMA_COLUMNS (the frozen canonical schema shared with every
# other system). Five composite-provenance columns are appended after them:
#   component, major_category, source_system, source_version, source_code
# Consumers that only know the canonical schema keep working unchanged.
#
# HIERARCHY: none. The source workbook supplies a flat code/label pair per
# component with no parent codes and no level markers, so no hierarchy is
# manufactured: `level` carries the component id and `parent_code` is NA on
# every row. `pscrcs2025_levels()` therefore equals `pscrcs2025_components()`.
#
# Public contract:
#   pscrcs2025_versions()     -> "2025"
#   pscrcs2025_levels()       -> the three component ids (see above)
#   pscrcs2025_components()   -> the three component ids
#   pscrcs2025_get(level = NULL, component = NULL, data_path = NULL)
#   pscrcs2025_metadata(metadata_path = NULL)

PSCRCS_2025_DATA_PATH <- "data/pscrcs_2025.rds"
PSCRCS_2025_METADATA_PATH <- "data/pscrcs_2025_metadata.rds"

PSCRCS_2025_MISSING_ARTIFACT_MSG <-
  "PSCrCS 2025 runtime artifact is missing. Run scripts/build_pscrcs_2025.R and redeploy."

PSCRCS_2025_COMPONENTS <- c(
  "creative_industry", "creative_good_service", "creative_occupation"
)

# Composite-provenance columns appended after the frozen canonical ten.
PSCRCS_2025_EXTRA_COLUMNS <- c(
  "component", "major_category", "source_system", "source_version", "source_code"
)

# In-session memoization cache. Kept as environment state so repeated calls
# within one running app/session don't re-read the RDS from disk, while still
# allowing tests to reset it via `.pscrcs2025_reset_cache()`.
.pscrcs2025_cache <- new.env(parent = emptyenv())

.pscrcs2025_reset_cache <- function() {
  rm(list = ls(.pscrcs2025_cache), envir = .pscrcs2025_cache)
  invisible(NULL)
}

.pscrcs2025_read_rds_or_fail <- function(path, cache_key) {
  if (!is.null(.pscrcs2025_cache[[cache_key]])) {
    return(.pscrcs2025_cache[[cache_key]])
  }
  if (!file.exists(path)) {
    stop(PSCRCS_2025_MISSING_ARTIFACT_MSG, call. = FALSE)
  }
  obj <- readRDS(path)
  .pscrcs2025_cache[[cache_key]] <- obj
  obj
}

# Resolves a canonical repo-root-relative path (e.g. "data/pscrcs_2025.rds")
# regardless of whether the caller's working directory is the repo root
# (production: app.R, Rscript scripts/*.R) or tests/testthat (testthat::
# test_dir() runs with cwd = tests/testthat, per tests/testthat/helper.R).
# Only used for the *default* path -- callers who explicitly pass a path (e.g.
# tests exercising the missing-artifact error) get that path exactly, with no
# fallback searching.
.pscrcs2025_resolve_default_path <- function(rel_path) {
  candidates <- c(rel_path, file.path("..", "..", rel_path))
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

#' Available PSCrCS versions exposed by this adapter.
pscrcs2025_versions <- function() {
  "2025"
}

#' PSCrCS component ids, in canonical order.
pscrcs2025_components <- function() {
  PSCRCS_2025_COMPONENTS
}

#' Available PSCrCS "levels".
#'
#' PSCrCS has no genuine hierarchy in its source workbook, so the component
#' partition is what `level` carries. This is intentionally identical to
#' `pscrcs2025_components()` rather than a manufactured depth ordering.
pscrcs2025_levels <- function() {
  PSCRCS_2025_COMPONENTS
}

#' Load the canonical PSCrCS 2025 tibble.
#'
#' @param level character or NULL. If supplied, must be one of
#'   `pscrcs2025_levels()`; filters the result to that level. For PSCrCS this
#'   is equivalent to filtering on `component`.
#' @param component character or NULL. If supplied, must be one of
#'   `pscrcs2025_components()`; filters to that component. May be combined
#'   with `level` (both must then agree, or the result is empty).
#' @param data_path character. Override for the runtime artifact path; exists
#'   primarily so tests can point at a missing path without touching the real
#'   committed artifact.
#'
#' @return A tibble whose first ten columns are exactly
#'   `CLASSIFICATION_SCHEMA_COLUMNS`, followed by
#'   `PSCRCS_2025_EXTRA_COLUMNS`.
pscrcs2025_get <- function(level = NULL, component = NULL, data_path = NULL) {
  path <- if (is.null(data_path)) {
    .pscrcs2025_resolve_default_path(PSCRCS_2025_DATA_PATH)
  } else {
    data_path
  }
  cache_key <- paste0("data::", path)
  df <- .pscrcs2025_read_rds_or_fail(path, cache_key)

  if (!is.null(level)) {
    if (!level %in% pscrcs2025_levels()) {
      stop(sprintf(
        "Unsupported PSCrCS level '%s'. Available levels: %s",
        level, paste(pscrcs2025_levels(), collapse = ", ")
      ), call. = FALSE)
    }
    df <- df[df$level == level, , drop = FALSE]
  }

  if (!is.null(component)) {
    if (!component %in% pscrcs2025_components()) {
      stop(sprintf(
        "Unsupported PSCrCS component '%s'. Available components: %s",
        component, paste(pscrcs2025_components(), collapse = ", ")
      ), call. = FALSE)
    }
    df <- df[df$component == component, , drop = FALSE]
  }

  df
}

#' Load PSCrCS 2025 provenance/metadata.
#'
#' @param metadata_path character. Override for the metadata artifact path;
#'   exists primarily so tests can point at a missing path.
#'
#' @return A list of provenance fields (source, source_url, source_artifact,
#'   retrieved_at, sha256, parsed_counts, official_counts,
#'   underlying_classifications, workbook_metadata, ...) as recorded by
#'   scripts/build_pscrcs_2025.R.
pscrcs2025_metadata <- function(metadata_path = NULL) {
  path <- if (is.null(metadata_path)) {
    .pscrcs2025_resolve_default_path(PSCRCS_2025_METADATA_PATH)
  } else {
    metadata_path
  }
  cache_key <- paste0("meta::", path)
  .pscrcs2025_read_rds_or_fail(path, cache_key)
}

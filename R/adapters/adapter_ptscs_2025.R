# Philippine Tourism Statistical Classification System (PTSCS),
# 2025 edition, Version 2.1 -- adapter.
#
# Reads the build-time-normalized runtime artifact at
# data/ptscs_2025_v2_1.rds (produced by scripts/build_ptscs_2025.R) rather
# than parsing the source workbook at request time or depending on any PSA
# network endpoint.
#
# PTSCS is a COMPOSITE / THEMATIC classification: it does not mint codes of
# its own. It selects codes out of two other classifications and groups them
# under tourism themes:
#
#   component "tourism_industry" -> 2019 Updates to the 2009 PSIC
#   component "tourism_product"  -> Central Product Classification (CPC) 2.1
#
# Consequences for the canonical contract:
#
#   * There is NO code hierarchy. `parent_code` is NA on every record, and the
#     canonical `level` column carries the COMPONENT ID rather than a
#     manufactured hierarchy level. `ptscs2025_levels()` therefore returns the
#     same two values as `ptscs2025_components()`. No parent/child
#     relationship is invented that the workbook does not provide.
#
#   * Component provenance is part of the statistical meaning, so the tibble
#     carries extra columns AFTER the frozen canonical 10:
#       component, major_category, major_category_group,
#       source_system, source_version, source_code, source_label
#     The shared canonical schema is not widened; canonical consumers see the
#     first 10 columns exactly as `CLASSIFICATION_SCHEMA_COLUMNS` defines them
#     and simply ignore the rest.
#
#   * Industry codes are 2019 PSIC codes and STAY on 2019. This application
#     also carries PSIC Revision 5 (2026), but PSA defines PTSCS Version 2.1
#     against the 2019 edition; silently re-coding PTSCS industries onto
#     Revision 5 is prohibited. Any 2019 -> 2026 link must be surfaced as a
#     separate, explicitly labelled correspondence.
#
# Public contract:
#   ptscs2025_versions()                             -> "2025-v2.1"
#   ptscs2025_levels()                               -> component ids (see above)
#   ptscs2025_components()                           -> c("tourism_industry","tourism_product")
#   ptscs2025_get(level, component, data_path)       -> canonical tibble + extras
#   ptscs2025_metadata(metadata_path)                -> provenance metadata list

PTSCS_2025_DATA_PATH <- "data/ptscs_2025_v2_1.rds"
PTSCS_2025_METADATA_PATH <- "data/ptscs_2025_v2_1_metadata.rds"

PTSCS_2025_VERSION <- "2025-v2.1"

PTSCS_2025_COMPONENTS <- c("tourism_industry", "tourism_product")

# Extra (non-canonical) provenance columns this adapter guarantees, in order.
PTSCS_2025_EXTRA_COLUMNS <- c(
  "component", "major_category", "major_category_group",
  "source_system", "source_version", "source_code", "source_label"
)

PTSCS_2025_MISSING_ARTIFACT_MSG <-
  "PTSCS 2025 (Version 2.1) runtime artifact is missing. Run scripts/build_ptscs_2025.R and redeploy."

# In-session memoization cache, mirroring the PSIC Revision 5 adapter: kept as
# environment state so repeated calls within one running app/session don't
# re-read the RDS from disk, while still allowing tests to reset it via
# `.ptscs2025_reset_cache()`.
.ptscs2025_cache <- new.env(parent = emptyenv())

.ptscs2025_reset_cache <- function() {
  rm(list = ls(.ptscs2025_cache), envir = .ptscs2025_cache)
  invisible(NULL)
}

.ptscs2025_read_rds_or_fail <- function(path, cache_key) {
  if (!is.null(.ptscs2025_cache[[cache_key]])) {
    return(.ptscs2025_cache[[cache_key]])
  }
  if (!file.exists(path)) {
    stop(PTSCS_2025_MISSING_ARTIFACT_MSG, call. = FALSE)
  }
  obj <- readRDS(path)
  .ptscs2025_cache[[cache_key]] <- obj
  obj
}

# Resolves a canonical repo-root-relative path (e.g. "data/ptscs_2025_v2_1.rds")
# regardless of whether the caller's working directory is the repo root
# (production: app.R, Rscript scripts/*.R) or tests/testthat (testthat::
# test_dir() runs with cwd = tests/testthat, per tests/testthat/helper.R).
# Only used for the *default* path -- callers who explicitly pass a path
# (e.g. tests exercising the missing-artifact error) get that path exactly,
# with no fallback searching.
.ptscs2025_resolve_default_path <- function(rel_path) {
  candidates <- c(rel_path, file.path("..", "..", rel_path))
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

#' Available PTSCS versions exposed by this adapter.
ptscs2025_versions <- function() {
  PTSCS_2025_VERSION
}

#' PTSCS conceptual components.
#'
#' Exactly two, as published by PSA: tourism industries (tourism
#' characteristic activities) and tourism characteristic products.
ptscs2025_components <- function() {
  PTSCS_2025_COMPONENTS
}

#' PTSCS "levels".
#'
#' PTSCS publishes no code hierarchy, so there are no genuine hierarchy
#' levels. The canonical `level` column carries the component id instead, and
#' this function returns those component ids so that generic level-aware
#' callers keep working without any fake hierarchy being manufactured.
ptscs2025_levels <- function() {
  PTSCS_2025_COMPONENTS
}

#' Load the canonical PTSCS 2025 Version 2.1 tibble.
#'
#' @param level character or NULL. Component id (see `ptscs2025_levels()`);
#'   filters the canonical `level` column. NULL (default) returns everything.
#' @param component character or NULL. Component id (see
#'   `ptscs2025_components()`); filters the `component` provenance column.
#'   `level` and `component` carry the same values for PTSCS; supplying both
#'   applies both filters.
#' @param data_path character. Override for the runtime artifact path; exists
#'   primarily so tests can point at a missing path without touching the real
#'   committed artifact.
#'
#' @return A tibble whose first 10 columns are exactly
#'   `CLASSIFICATION_SCHEMA_COLUMNS`, followed by
#'   `PTSCS_2025_EXTRA_COLUMNS`.
ptscs2025_get <- function(level = NULL, component = NULL, data_path = NULL) {
  path <- if (is.null(data_path)) .ptscs2025_resolve_default_path(PTSCS_2025_DATA_PATH) else data_path
  cache_key <- paste0("data::", path)
  df <- .ptscs2025_read_rds_or_fail(path, cache_key)

  if (!is.null(level)) {
    if (!level %in% ptscs2025_levels()) {
      stop(sprintf(
        "Unsupported PTSCS level '%s'. PTSCS has no code hierarchy; available level values are its components: %s",
        level, paste(ptscs2025_levels(), collapse = ", ")
      ), call. = FALSE)
    }
    df <- df[df$level == level, , drop = FALSE]
  }

  if (!is.null(component)) {
    if (!component %in% ptscs2025_components()) {
      stop(sprintf(
        "Unsupported PTSCS component '%s'. Available components: %s",
        component, paste(ptscs2025_components(), collapse = ", ")
      ), call. = FALSE)
    }
    df <- df[df$component == component, , drop = FALSE]
  }

  df
}

#' Load PTSCS 2025 Version 2.1 provenance/metadata.
#'
#' @param metadata_path character. Override for the metadata artifact path;
#'   exists primarily so tests can point at a missing path.
#'
#' @return A list of provenance fields (source, source_url, retrieved_at,
#'   sha256, parsed_counts, official_counts, underlying_classifications,
#'   major_categories, ...) as recorded by scripts/build_ptscs_2025.R.
ptscs2025_metadata <- function(metadata_path = NULL) {
  path <- if (is.null(metadata_path)) .ptscs2025_resolve_default_path(PTSCS_2025_METADATA_PATH) else metadata_path
  cache_key <- paste0("meta::", path)
  .ptscs2025_read_rds_or_fail(path, cache_key)
}

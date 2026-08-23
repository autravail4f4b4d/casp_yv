# "2022 Updates to the 2012 PSOC" adapter.
#
# Reads the build-time-normalized runtime artifact at data/psoc_2022.rds
# (produced by scripts/build_psoc_2022.R) rather than depending on the
# installed `phscs` package, which only exposes PSOC 2012, or on any PSA
# network endpoint at runtime. Mirrors the existing
# R/adapters/adapter_psic_2026.R pattern exactly.
#
# Public contract:
#   psoc2022_versions()          -> "2022"
#   psoc2022_levels()            -> c("major_group","sub_major_group","minor_group","unit_group")
#   psoc2022_get(level = NULL)   -> canonical tibble, optionally filtered to one level
#   psoc2022_metadata()          -> provenance metadata list

PSOC_2022_DATA_PATH <- "data/psoc_2022.rds"
PSOC_2022_METADATA_PATH <- "data/psoc_2022_metadata.rds"

PSOC_2022_MISSING_ARTIFACT_MSG <-
  "PSOC 2022 runtime artifact is missing. Run scripts/build_psoc_2022.R and redeploy."

.psoc2022_cache <- new.env(parent = emptyenv())

.psoc2022_reset_cache <- function() {
  rm(list = ls(.psoc2022_cache), envir = .psoc2022_cache)
  invisible(NULL)
}

.psoc2022_read_rds_or_fail <- function(path, cache_key) {
  if (!is.null(.psoc2022_cache[[cache_key]])) {
    return(.psoc2022_cache[[cache_key]])
  }
  if (!file.exists(path)) {
    stop(PSOC_2022_MISSING_ARTIFACT_MSG, call. = FALSE)
  }
  obj <- readRDS(path)
  .psoc2022_cache[[cache_key]] <- obj
  obj
}

# Resolves a canonical repo-root-relative path regardless of whether the
# caller's working directory is the repo root (production: app.R, Rscript
# scripts/*.R) or tests/testthat (testthat::test_dir() runs with cwd =
# tests/testthat, per tests/testthat/helper.R). Only used for the *default*
# path -- an explicit override (used by the missing-artifact test) is used
# exactly as given, with no fallback searching.
.psoc2022_resolve_default_path <- function(rel_path) {
  candidates <- c(rel_path, file.path("..", "..", rel_path))
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

#' Available PSOC 2022 versions exposed by this adapter.
psoc2022_versions <- function() {
  "2022"
}

#' Available PSOC 2022 hierarchy levels, in hierarchy order.
psoc2022_levels <- function() {
  c("major_group", "sub_major_group", "minor_group", "unit_group")
}

#' Load the canonical PSOC 2022 tibble.
#'
#' @param level character or NULL. If supplied, must be one of
#'   `psoc2022_levels()`; filters the result to that single level. NULL
#'   (default) returns all levels.
#' @param data_path character. Override for the runtime artifact path;
#'   exists primarily so tests can point at a missing path without touching
#'   the real committed artifact.
#'
#' @return A tibble with exactly `CLASSIFICATION_SCHEMA_COLUMNS`.
psoc2022_get <- function(level = NULL, data_path = NULL) {
  path <- if (is.null(data_path)) .psoc2022_resolve_default_path(PSOC_2022_DATA_PATH) else data_path
  cache_key <- paste0("data::", path)
  df <- .psoc2022_read_rds_or_fail(path, cache_key)

  if (is.null(level)) {
    return(df)
  }

  if (!level %in% psoc2022_levels()) {
    stop(sprintf(
      "Unsupported PSOC level '%s'. Available levels: %s",
      level, paste(psoc2022_levels(), collapse = ", ")
    ), call. = FALSE)
  }

  df[df$level == level, , drop = FALSE]
}

#' Load PSOC 2022 provenance/metadata.
#'
#' @param metadata_path character. Override for the metadata artifact path;
#'   exists primarily so tests can point at a missing path.
#'
#' @return A list of provenance fields (source, source_url, retrieved_at,
#'   sha256, parsed_counts, retrieval_method, etc.) as recorded by
#'   scripts/build_psoc_2022.R.
psoc2022_metadata <- function(metadata_path = NULL) {
  path <- if (is.null(metadata_path)) .psoc2022_resolve_default_path(PSOC_2022_METADATA_PATH) else metadata_path
  cache_key <- paste0("meta::", path)
  .psoc2022_read_rds_or_fail(path, cache_key)
}

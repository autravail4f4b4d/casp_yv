# 2022 Philippine Standard Commodity Classification (PSCC) adapter.
#
# Reads the build-time-normalized runtime artifact at data/pscc_2022.rds
# (produced by scripts/build_pscc_2022.R) rather than parsing the official
# PSA workbook on every request or depending on PSA network availability.
#
# NOTE: PSCC ("Philippine Standard Commodity Classification", 2022, traded
# commodities) is a different classification from PSCCS ("Philippine Standard
# Classification of Crime for Statistical Purposes", 2018, crime statistics).
# Do not conflate the two acronyms.
#
# Public contract:
#   pscc2022_versions()          -> "2022"
#   pscc2022_levels()            -> hierarchy-ordered level vector
#   pscc2022_get(level = NULL)   -> canonical tibble, optionally one level
#   pscc2022_metadata()          -> provenance metadata list

PSCC_2022_DATA_PATH <- "data/pscc_2022.rds"
PSCC_2022_METADATA_PATH <- "data/pscc_2022_metadata.rds"

PSCC_2022_MISSING_ARTIFACT_MSG <-
  "PSCC 2022 runtime artifact is missing. Run scripts/build_pscc_2022.R and redeploy."

# In-session memoization cache. Kept as environment state so repeated calls
# within one running app/session don't re-read the RDS from disk, while still
# allowing tests to reset it via `.pscc2022_reset_cache()`.
.pscc2022_cache <- new.env(parent = emptyenv())

.pscc2022_reset_cache <- function() {
  rm(list = ls(.pscc2022_cache), envir = .pscc2022_cache)
  invisible(NULL)
}

.pscc2022_read_rds_or_fail <- function(path, cache_key) {
  if (!is.null(.pscc2022_cache[[cache_key]])) {
    return(.pscc2022_cache[[cache_key]])
  }
  if (!file.exists(path)) {
    stop(PSCC_2022_MISSING_ARTIFACT_MSG, call. = FALSE)
  }
  obj <- readRDS(path)
  .pscc2022_cache[[cache_key]] <- obj
  obj
}

# Resolves a canonical repo-root-relative path (e.g. "data/pscc_2022.rds")
# regardless of whether the caller's working directory is the repo root
# (production: app.R, Rscript scripts/*.R) or tests/testthat (testthat::
# test_dir() runs with cwd = tests/testthat, per tests/testthat/helper.R).
# Only used for the *default* path -- callers who explicitly pass a path
# (e.g. tests exercising the missing-artifact error) get that path exactly,
# with no fallback searching.
.pscc2022_resolve_default_path <- function(rel_path) {
  candidates <- c(rel_path, file.path("..", "..", rel_path))
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

#' Available PSCC versions exposed by this adapter.
pscc2022_versions <- function() {
  "2022"
}

#' Available PSCC 2022 hierarchy levels, in hierarchy order.
#'
#' Derived from the official workbook's own structure:
#'   section          -- "SECTION I - ..." (roman numeral)
#'   chapter          -- "Chapter 1 - ..." (two-digit)
#'   heading          -- NN.NN            (HS 4-digit)
#'   subheading       -- NNNN.NN          (HS 6-digit)
#'   ahtn subheading  -- NNNN.NN.NN       (AHTN 8-digit)
#'   commodity        -- NNNN.NN.NN-NNN   (PSCC 11-digit)
pscc2022_levels <- function() {
  c("section", "chapter", "heading", "subheading", "ahtn subheading", "commodity")
}

#' Load the canonical PSCC 2022 tibble.
#'
#' @param level character or NULL. If supplied, must be one of
#'   `pscc2022_levels()`; filters the result to that single level. NULL
#'   (default) returns all levels.
#' @param data_path character. Override for the runtime artifact path;
#'   exists primarily so tests can point at a missing path without touching
#'   the real committed artifact.
#'
#' @return A tibble with exactly `CLASSIFICATION_SCHEMA_COLUMNS`, all
#'   character. Codes are strings throughout: leading zeros, dots, hyphens
#'   and 3-digit suffixes are preserved exactly as published by PSA.
pscc2022_get <- function(level = NULL, data_path = NULL) {
  path <- if (is.null(data_path)) .pscc2022_resolve_default_path(PSCC_2022_DATA_PATH) else data_path
  cache_key <- paste0("data::", path)
  df <- .pscc2022_read_rds_or_fail(path, cache_key)

  if (is.null(level)) {
    return(df)
  }

  if (!level %in% pscc2022_levels()) {
    stop(sprintf(
      "Unsupported PSCC level '%s'. Available levels: %s",
      level, paste(pscc2022_levels(), collapse = ", ")
    ), call. = FALSE)
  }

  df[df$level == level, , drop = FALSE]
}

#' Load PSCC 2022 provenance/metadata.
#'
#' @param metadata_path character. Override for the metadata artifact path;
#'   exists primarily so tests can point at a missing path.
#'
#' @return A list of provenance fields (official_name, source, source_url,
#'   source_artifact, retrieved_at, sha256, parsed_counts, code_attributes
#'   with unit of quantity and 2019 PSCC / AHTN 2022 cross-references, etc.)
#'   as recorded by scripts/build_pscc_2022.R.
pscc2022_metadata <- function(metadata_path = NULL) {
  path <- if (is.null(metadata_path)) .pscc2022_resolve_default_path(PSCC_2022_METADATA_PATH) else metadata_path
  cache_key <- paste0("meta::", path)
  .pscc2022_read_rds_or_fail(path, cache_key)
}

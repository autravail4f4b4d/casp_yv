# PSIC Revision 5 ("2026 PSIC") adapter.
#
# Reads the build-time-normalized runtime artifact at data/psic_2026.rds
# (produced by scripts/build_psic_2026.R) rather than depending on the
# installed `phscs` package, which currently tops out at the 2019 edition,
# or on any PSA network endpoint at runtime.
#
# Public contract:
#   psic2026_versions()          -> "2026"
#   psic2026_levels()            -> c("section","division","group","class","sub-class")
#   psic2026_get(level = NULL)   -> canonical tibble, optionally filtered to one level
#   psic2026_metadata()          -> provenance metadata list

PSIC_2026_DATA_PATH <- "data/psic_2026.rds"
PSIC_2026_METADATA_PATH <- "data/psic_2026_metadata.rds"

PSIC_2026_MISSING_ARTIFACT_MSG <-
  "PSIC Revision 5 runtime artifact is missing. Run scripts/build_psic_2026.R and redeploy."

# In-session memoization caches. Kept as package-level (environment) state
# so repeated calls within one running app/session don't re-read the RDS
# from disk, while still allowing tests to reset them via
# `.psic2026_reset_cache()`.
.psic2026_cache <- new.env(parent = emptyenv())

.psic2026_reset_cache <- function() {
  rm(list = ls(.psic2026_cache), envir = .psic2026_cache)
  invisible(NULL)
}

.psic2026_read_rds_or_fail <- function(path, cache_key) {
  if (!is.null(.psic2026_cache[[cache_key]])) {
    return(.psic2026_cache[[cache_key]])
  }
  if (!file.exists(path)) {
    stop(PSIC_2026_MISSING_ARTIFACT_MSG, call. = FALSE)
  }
  obj <- readRDS(path)
  .psic2026_cache[[cache_key]] <- obj
  obj
}

# Resolves a canonical repo-root-relative path (e.g. "data/psic_2026.rds")
# regardless of whether the caller's working directory is the repo root
# (production: app.R, Rscript scripts/*.R) or tests/testthat (testthat::
# test_dir() runs with cwd = tests/testthat, per tests/testthat/helper.R).
# Only used for the *default* path -- callers who explicitly pass a path
# (e.g. tests exercising the missing-artifact error) get that path exactly,
# with no fallback searching.
.psic2026_resolve_default_path <- function(rel_path) {
  candidates <- c(rel_path, file.path("..", "..", rel_path))
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

#' Available PSIC Revision 5 versions exposed by this adapter.
psic2026_versions <- function() {
  "2026"
}

#' Available PSIC Revision 5 hierarchy levels, in hierarchy order.
psic2026_levels <- function() {
  c("section", "division", "group", "class", "sub-class")
}

#' Load the canonical PSIC Revision 5 tibble.
#'
#' @param level character or NULL. If supplied, must be one of
#'   `psic2026_levels()`; filters the result to that single level. NULL
#'   (default) returns all levels.
#' @param data_path character. Override for the runtime artifact path;
#'   exists primarily so tests can point at a missing path without touching
#'   the real committed artifact.
#'
#' @return A tibble with exactly `CLASSIFICATION_SCHEMA_COLUMNS`.
psic2026_get <- function(level = NULL, data_path = NULL) {
  path <- if (is.null(data_path)) .psic2026_resolve_default_path(PSIC_2026_DATA_PATH) else data_path
  cache_key <- paste0("data::", path)
  df <- .psic2026_read_rds_or_fail(path, cache_key)

  if (is.null(level)) {
    return(df)
  }

  if (!level %in% psic2026_levels()) {
    stop(sprintf(
      "Unsupported PSIC level '%s'. Available levels: %s",
      level, paste(psic2026_levels(), collapse = ", ")
    ), call. = FALSE)
  }

  df[df$level == level, , drop = FALSE]
}

#' Load PSIC Revision 5 provenance/metadata.
#'
#' @param metadata_path character. Override for the metadata artifact path;
#'   exists primarily so tests can point at a missing path.
#'
#' @return A list of provenance fields (source, source_url, retrieved_at,
#'   sha256, parsed_counts, etc.) as recorded by scripts/build_psic_2026.R.
psic2026_metadata <- function(metadata_path = NULL) {
  path <- if (is.null(metadata_path)) .psic2026_resolve_default_path(PSIC_2026_METADATA_PATH) else metadata_path
  cache_key <- paste0("meta::", path)
  .psic2026_read_rds_or_fail(path, cache_key)
}

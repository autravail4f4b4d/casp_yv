# Classification repository — Wave 2 integration.
#
# This is the ONLY file the Shiny layer should call into. It wires together
# the registry (R/registry.R), the phscs/psgc/PSIC-2026 adapters
# (R/adapters/*.R), and the search engine (R/search.R) into the exact
# public service contract mandated by the spec (section 1.1):
#
#   classification_registry()                  -- defined in R/registry.R
#   classification_versions(system)
#   classification_levels(system, version)
#   get_classification(system, version, level = NULL)
#   search_classification(system, version, query, level = NULL, limit = 100)
#   get_classification_entry(system, version, code)
#   classification_metadata(system, version)
#
# None of these functions touch `input`/`output`/`session` or any Shiny
# object — they are plain R functions, testable and used exactly as-is by
# tests/testthat/*.R without launching Shiny.
#
# PSIC is the one system backed by two adapters depending on `version`:
# adapter_phscs (archived "2019") and adapter_psic_2026 (current "2026",
# backed by data/psic_2026.rds). Every other system is single-adapter:
# psgc -> adapter_psgc, everything else -> adapter_phscs. The dispatch logic
# below is the single place that distinction is resolved.

.repository_registry_cache <- new.env(parent = emptyenv())

# The registry introspects adapters (which themselves memoize their pulls),
# so this is cheap after the first call — cached anyway to avoid re-running
# classification_registry()'s 7-system introspection on every single
# repository call in one Shiny session.
.cached_registry <- function() {
  if (is.null(.repository_registry_cache$value)) {
    .repository_registry_cache$value <- classification_registry()
  }
  .repository_registry_cache$value
}

.registry_row_for <- function(system) {
  reg <- .cached_registry()
  row <- reg[reg$id == system, , drop = FALSE]
  if (nrow(row) == 0L) {
    stop(sprintf(
      "Unsupported classification system '%s'. Available systems: %s",
      system, paste(reg$id, collapse = ", ")
    ), call. = FALSE)
  }
  row
}

#' Character vector of version ids available for a classification system.
#'
#' @param system character(1). Must be one of `classification_registry()$id`.
classification_versions <- function(system) {
  .registry_row_for(system)$available_versions[[1]]
}

.validate_version <- function(system, version) {
  versions <- classification_versions(system)
  if (!version %in% versions) {
    stop(sprintf(
      "Unsupported version '%s' for system '%s'. Available versions: %s",
      version, system, paste(versions, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}

#' Character vector of hierarchy level ids for a system+version.
#'
#' @param system character(1).
#' @param version character(1). Must be one of `classification_versions(system)`.
classification_levels <- function(system, version) {
  .validate_version(system, version)

  if (identical(system, "psic") && identical(version, "2026")) {
    return(psic2026_levels())
  }
  if (identical(system, "psoc") && identical(version, "2022")) {
    return(psoc2022_levels())
  }
  if (identical(system, "psgc")) {
    return(psgc_levels(version))
  }
  phscs_levels(system, version)
}

.validate_level <- function(system, version, level) {
  if (is.null(level)) {
    return(invisible(TRUE))
  }
  levels <- classification_levels(system, version)
  if (!level %in% levels) {
    stop(sprintf(
      "Unsupported level '%s' for system '%s' version '%s'. Available levels: %s",
      level, system, version, paste(levels, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}

#' Canonical classification tibble for one system+version, optionally
#' filtered to a single hierarchy level.
#'
#' @param system character(1).
#' @param version character(1). Must be one of `classification_versions(system)`
#'   — an unsupported version raises a validation error listing the
#'   available versions (never silently substitutes another edition).
#' @param level character(1) or NULL. Must be one of
#'   `classification_levels(system, version)` when supplied; NULL (default)
#'   returns every level.
#'
#' @return A tibble with exactly `CLASSIFICATION_SCHEMA_COLUMNS`.
get_classification <- function(system, version, level = NULL) {
  .validate_version(system, version)
  .validate_level(system, version, level)

  if (identical(system, "psgc")) {
    return(psgc_get(version, level = level))
  }
  if (identical(system, "psic") && identical(version, "2026")) {
    return(psic2026_get(level = level))
  }
  if (identical(system, "psoc") && identical(version, "2022")) {
    return(psoc2022_get(level = level))
  }
  phscs_get(system, version, level = level)
}

#' Search (or, for a blank query, browse) one system+version's classification
#' data. Thin wrapper over `search_classification_data()` (R/search.R) that
#' resolves `system`/`version` into an in-memory tibble first.
#'
#' @param system character(1).
#' @param version character(1).
#' @param query character(1) search string, or NULL/NA/blank to browse.
#' @param level character(1) or NULL. Validated the same way as
#'   `get_classification()`.
#' @param limit integer(1). Maximum rows returned (default 100).
#'
#' @return A tibble with exactly `CLASSIFICATION_SCHEMA_COLUMNS`, at most
#'   `limit` rows. Never errors on a no-match query; never returns NULL.
search_classification <- function(system, version, query, level = NULL, limit = 100) {
  .validate_version(system, version)
  .validate_level(system, version, level)

  data <- get_classification(system, version, level = NULL)
  search_classification_data(data, query, level = level, limit = limit)
}

#' Look up a single classification entry by its exact code.
#'
#' Code comparison is an exact, case-sensitive string match — codes are
#' never treated as numbers, so leading zeros are preserved and distinct
#' codes are never accidentally collapsed together.
#'
#' @param system character(1).
#' @param version character(1).
#' @param code character(1). Official classification code.
#'
#' @return A one-row tibble with exactly `CLASSIFICATION_SCHEMA_COLUMNS`, or
#'   a zero-row tibble (never an error, never NULL) if no entry matches.
get_classification_entry <- function(system, version, code) {
  data <- get_classification(system, version, level = NULL)
  data[data$code == code, , drop = FALSE]
}

#' Provenance/display metadata for one system+version.
#'
#' @param system character(1).
#' @param version character(1).
#'
#' @return A list with at least: system, version, display_version, status
#'   ("current"/"archived"), source, source_url, retrieved_at, license.
classification_metadata <- function(system, version) {
  .validate_version(system, version)

  if (identical(system, "psgc")) {
    return(psgc_metadata(version))
  }
  if (identical(system, "psic") && identical(version, "2026")) {
    return(psic2026_metadata())
  }
  if (identical(system, "psoc") && identical(version, "2022")) {
    return(psoc2022_metadata())
  }
  phscs_metadata(system, version)
}

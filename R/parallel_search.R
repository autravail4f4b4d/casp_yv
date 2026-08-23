# Parallel PSOC + PSIC search service.
#
# A single query searches multiple classification systems independently
# and returns one result set per system. This file adds NO new ranking
# logic -- every per-system result comes straight from the existing,
# already-tested `search_classification()` (R/repository.R), which itself
# delegates to `search_classification_data()` (R/search.R). Reusing that
# function is a hard requirement (spec section 9: "Do not implement a
# second ranking engine").
#
# PSOC and PSIC are semantically distinct and must never be presented as
# equivalent: PSOC classifies occupations (the kind of work a person does),
# PSIC classifies industries (the primary economic activity of an
# establishment). This file's job is orchestration and failure isolation
# only -- the semantic-distinction UI treatment lives in R/ui/*.R.

#' Human-readable labels for the systems this service knows how to pair,
#' per spec section 8's preferred headings. Used by the UI so the
#' occupation/industry distinction is never left to the caller to invent.
PARALLEL_SEARCH_SYSTEM_LABELS <- c(psoc = "Occupations", psic = "Industries")

#' Search multiple classification systems independently with one query.
#'
#' @param query character(1) search string, or NULL/blank to browse each
#'   system's selected level (same blank-query semantics as
#'   `search_classification()`).
#' @param systems character vector of system ids to search in parallel.
#'   Default: `c("psoc", "psic")`.
#' @param versions named character vector, one entry per system in
#'   `systems`, giving which edition/release to search for that system.
#'   Default: `c(psoc = "2022", psic = "2026")` -- current PSOC and current
#'   PSIC Revision 5, per spec section 8. A caller may pass an archived
#'   edition explicitly (e.g. `c(psoc = "2012", psic = "2019")`) to compare
#'   archived data; this function does not force current editions.
#' @param levels NULL, or a named list keyed by system id giving a single
#'   level to filter that system's results to (NULL/absent for a system
#'   means no level filter). Example: `list(psic = "division")`.
#' @param limit_per_system integer(1). Max rows returned per system
#'   (default 20, independently of the other system(s)).
#'
#' @return A list:
#'   \describe{
#'     \item{query}{the query as given}
#'     \item{systems}{the systems searched, in order}
#'     \item{results}{named list, one entry per system: a canonical result
#'       tibble (`CLASSIFICATION_SCHEMA_COLUMNS`) on success, or `NULL` if
#'       that system's search failed (see `errors`) -- a `NULL` result is
#'       never confused with a *valid* zero-row (no-match) tibble, which is
#'       returned normally on the successful-but-no-match path, exactly
#'       like `search_classification()` already does}
#'     \item{errors}{named list of error messages for any system whose
#'       search failed, or `NULL` if there were no errors. A failure on one
#'       system's side never prevents the other system(s) from returning
#'       results -- each system is searched inside its own `tryCatch`.}
#'     \item{metadata}{named list `<system>_version` -> the version string
#'       actually used for that system, e.g. `list(psoc_version = "2022",
#'       psic_version = "2026")`}
#'   }
search_parallel_classifications <- function(query,
                                             systems = c("psoc", "psic"),
                                             versions = c(psoc = "2022", psic = "2026"),
                                             levels = NULL,
                                             limit_per_system = 20) {
  results <- vector("list", length(systems))
  names(results) <- systems
  errors <- list()

  for (sys in systems) {
    version <- versions[[sys]]
    level <- if (!is.null(levels) && sys %in% names(levels)) levels[[sys]] else NULL

    out <- tryCatch(
      search_classification(sys, version, query, level = level, limit = limit_per_system),
      error = function(e) e
    )

    if (inherits(out, "error")) {
      errors[[sys]] <- conditionMessage(out)
      results[[sys]] <- NULL
    } else {
      results[[sys]] <- out
    }
  }

  metadata <- stats::setNames(
    as.list(versions[systems]),
    paste0(systems, "_version")
  )

  list(
    query = query,
    systems = systems,
    results = results,
    errors = if (length(errors) > 0L) errors else NULL,
    metadata = metadata
  )
}

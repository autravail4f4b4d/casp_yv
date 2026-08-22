# Search / ranking service.
#
# This file implements ONLY the pure ranking/filtering algorithm over an
# already-loaded canonical classification tibble (see R/schema.R for the
# shape: CLASSIFICATION_SCHEMA_COLUMNS). It has no knowledge of adapters,
# the registry, or how a system/version's data gets fetched -- that is the
# repository layer's job (R/repository.R, a sibling workstream, not owned
# here).
#
# The spec's conceptual contract (PSA_CLASSIFICATIONS_4_HOUR_CLAUDE_CODE_BUILD.md
# section 5) is:
#
#   search_classification(system, version, query, level = NULL, limit = 100)
#
# which fetches data for (system, version) and then searches it. To keep
# this file decoupled from adapters/registry, the exported function here
# takes the already-fetched tibble directly and is named differently so it
# doesn't collide with the repository-layer wrapper a sibling workstream
# will write. The expected composition at the repository layer is:
#
#   search_classification <- function(system, version, query, level = NULL, limit = 100) {
#     data <- get_classification(system, version)  # from repository.R, not this file
#     search_classification_data(data, query, level = level, limit = limit)
#   }
#
# So the function implemented in THIS file is:
#
#   search_classification_data(data, query, level = NULL, limit = 100)

#' Normalize whitespace in a character vector for comparison purposes.
#'
#' Trims leading/trailing whitespace and collapses internal runs of
#' whitespace to a single space. Does NOT change case (callers combine this
#' with tolower() as needed). NA values pass through unchanged.
normalize_whitespace <- function(x) {
  x <- trimws(x)
  stringr::str_replace_all(x, "\\s+", " ")
}

#' Search a canonical classification tibble.
#'
#' @param data A tibble conforming to CLASSIFICATION_SCHEMA_COLUMNS (e.g. as
#'   produced by `new_classification_tibble()`), already filtered to the
#'   desired system/version by the caller.
#' @param query character(1) search string, or NULL/NA/blank for the
#'   "browse" behavior (see below). Matched literally, never as a regex --
#'   PCOICOP-style codes ("01.1.1.11") and parenthesized labels must match
#'   on their literal characters.
#' @param level character(1) or NULL. If non-NULL, `data` is filtered to
#'   rows where `level == level` (exact match) before ranking. A level with
#'   no matching rows yields zero results, not an error.
#' @param limit integer(1). Maximum rows returned, applied after ranking.
#'
#' @return A tibble with exactly CLASSIFICATION_SCHEMA_COLUMNS (no scratch
#'   columns), at most `limit` rows, never NULL and never throwing on a
#'   no-match query.
search_classification_data <- function(data, query, level = NULL, limit = 100) {
  if (!is.null(level)) {
    data <- data[data$level == level, , drop = FALSE]
  }

  # --- Blank query => Browse mode (spec section 5.2, "preferred MVP
  # behavior"): a blank/NULL/whitespace-only query skips ranking entirely
  # and returns the (optionally level-filtered) data in its original row
  # order, capped at `limit`. This is the deterministic choice made here
  # so Search and Browse share one code path.
  is_blank_query <- is.null(query) ||
    length(query) == 0L ||
    is.na(query) ||
    trimws(query) == ""

  if (is_blank_query) {
    return(head(data, limit))
  }

  query_norm <- normalize_whitespace(tolower(query))

  code_lower <- tolower(data$code)
  label_norm <- normalize_whitespace(tolower(data$label))
  description_norm <- normalize_whitespace(tolower(data$description))

  tier <- rep(NA_integer_, nrow(data))

  tier[is.na(tier) & code_lower == query_norm] <- 1L
  tier[is.na(tier) & stringr::str_starts(code_lower, stringr::fixed(query_norm))] <- 2L
  tier[is.na(tier) & label_norm == query_norm] <- 3L
  tier[is.na(tier) & stringr::str_starts(label_norm, stringr::fixed(query_norm))] <- 4L
  tier[is.na(tier) & stringr::str_detect(label_norm, stringr::fixed(query_norm))] <- 5L
  tier[is.na(tier) & !is.na(description_norm) &
         stringr::str_detect(description_norm, stringr::fixed(query_norm))] <- 6L

  matched <- data
  matched$.rank_tier <- tier
  matched$.orig_order <- seq_len(nrow(data))

  matched <- matched[!is.na(matched$.rank_tier), , drop = FALSE]
  matched <- dplyr::arrange(matched, .data$.rank_tier, .data$.orig_order)

  result <- matched[, CLASSIFICATION_SCHEMA_COLUMNS, drop = FALSE]
  head(result, limit)
}

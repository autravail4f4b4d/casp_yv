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
#'
#' @details This is a thin wrapper over `search_classification_data_result()`
#'   returning only its `$data` element. Filtering and ranking are performed
#'   exactly once per call -- there is no second pass to compute counts.
search_classification_data <- function(data, query, level = NULL, limit = 100) {
  search_classification_data_result(data, query, level = level, limit = limit)$data
}

#' Search a canonical classification tibble, reporting the true match total.
#'
#' Identical filtering/ranking to `search_classification_data()` -- same tiers,
#' same order, same blank-query browse behavior, same extra-column
#' passthrough -- but returns the count of ALL matching rows *before* `limit`
#' was applied, so a caller can say "3,487 results · showing first 200"
#' instead of misreporting the rendered row count as the match total.
#'
#' @inheritParams search_classification_data
#'
#' @return A list:
#'   \describe{
#'     \item{data}{the ranked result tibble, at most `limit` rows -- byte-for-byte
#'       what `search_classification_data()` returns}
#'     \item{total_matches}{integer(1). Every row that matched, before the limit}
#'     \item{returned_count}{integer(1). `nrow(data)`}
#'     \item{limit}{integer(1). The limit that was applied}
#'     \item{is_truncated}{logical(1). `total_matches > returned_count`}
#'   }
search_classification_data_result <- function(data, query, level = NULL, limit = 100) {
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
    return(.search_count_result(head(data, limit), nrow(data), limit))
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

  # Canonical columns first, then any extra columns the adapter supplied,
  # then drop the scratch ranking columns. Composite/thematic systems
  # (PTSCS, PSCrCS) append provenance columns -- component, major_category,
  # source_system/version/code -- after the canonical 10, and those must
  # survive a search: the underlying source classification is part of the
  # statistical meaning of the record and has to remain visible in result
  # details, not just in an unsearched browse. Ordinary systems have no
  # extras and are completely unaffected.
  extras <- setdiff(names(matched), c(CLASSIFICATION_SCHEMA_COLUMNS, ".rank_tier", ".orig_order"))
  result <- matched[, c(CLASSIFICATION_SCHEMA_COLUMNS, extras), drop = FALSE]
  .search_count_result(head(result, limit), nrow(result), limit)
}

#' Assemble the count-aware result list. Internal.
#'
#' @param data the already-limited result tibble
#' @param total integer(1) count of matches before the limit was applied
#' @param limit integer(1) the limit that was applied
#' @noRd
.search_count_result <- function(data, total, limit) {
  total <- as.integer(total)
  returned <- as.integer(nrow(data))
  list(
    data           = data,
    total_matches  = total,
    returned_count = returned,
    limit          = as.integer(limit),
    is_truncated   = total > returned
  )
}

#' Format a search result count for display. Pure -- no Shiny dependency.
#'
#' The single source of truth for result-count wording, so the UI can never
#' re-invent it and can never print the cap ("200 results") as if it were the
#' true match total.
#'
#' @param total_matches integer(1). All matching rows before the limit.
#' @param returned_count integer(1). Rows actually returned/rendered.
#' @param is_truncated logical(1). Whether matches were cut off by the limit.
#' @param limit integer(1) or NULL. Only used as a fallback for the
#'   unknown-total form when `returned_count` is unusable.
#' @param total_is_exact logical(1). FALSE when the true total genuinely
#'   cannot be known (e.g. an upstream source that only ever returns a page),
#'   which yields the "200+ results" form instead of an invented number.
#' @param is_browsing logical(1). TRUE for the blank-query browse mode, which
#'   appends " · browsing".
#'
#' @return character(1).
format_result_count <- function(total_matches, returned_count, is_truncated,
                                 limit = NULL, total_is_exact = TRUE,
                                 is_browsing = FALSE) {
  total_matches  <- as.integer(total_matches)
  returned_count <- as.integer(returned_count)
  is_truncated   <- isTRUE(is_truncated)

  fmt <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)

  out <- if (!isTRUE(total_is_exact) && is_truncated) {
    # The total is genuinely unknowable: report the floor, never a guess.
    n <- if (length(returned_count) == 1L && !is.na(returned_count)) {
      returned_count
    } else {
      as.integer(limit)
    }
    paste0(fmt(n), "+ results")
  } else if (is.na(total_matches) || total_matches == 0L) {
    "No results"
  } else if (is_truncated) {
    paste0(fmt(total_matches), " results · showing first ", fmt(returned_count))
  } else if (total_matches == 1L) {
    "1 result"
  } else {
    paste0(fmt(total_matches), " results")
  }

  if (isTRUE(is_browsing)) {
    out <- paste0(out, " · browsing")
  }
  out
}

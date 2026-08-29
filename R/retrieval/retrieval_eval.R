# Retrieval evaluation harness.
#
# This file scores a retrieval engine against the versioned case corpus in
# data-raw/retrieval_eval_cases.csv. It deliberately knows NOTHING about how
# retrieval is implemented: the engine under test is injected as `search_fn`,
# so the same harness measures the pre-hybrid baseline, the current engine,
# and any future hybrid profile without being edited.
#
# Three hard rules:
#
#   1. THE HARNESS NEVER DECIDES WHAT IS CORRECT. Correctness lives in the
#      CSV, which is reviewed and versioned. Nothing here infers an expected
#      code from a search result.
#
#   2. CODES ARE STRINGS. The corpus is read with every column as character
#      so that "09", "0112" and "0101.29.00-001" survive intact. A numeric
#      coercion anywhere in this file would be a data-integrity defect, not
#      a formatting nit.
#
#   3. A BROKEN ENGINE IS A SCORE, NOT A CRASH. If `search_fn` throws on one
#      case, that case is recorded as not-found with the error text and the
#      run continues. An evaluation that aborts on the first failure cannot
#      measure a regression.

RETRIEVAL_EVAL_COLUMNS <- c(
  "case_id", "system", "version", "query", "expected_code", "expected_level",
  "query_type", "language", "must_find", "notes", "provenance"
)

RETRIEVAL_EVAL_QUERY_TYPES <- c(
  "exact_code", "exact_label", "case_variant", "singular_plural", "typo",
  "partial_label", "paraphrase", "filipino", "cebuano", "mixed", "ambiguous",
  # Pre-staging convergence: the original single label
  # "negative_no_authoritative_code" conflated two structurally different
  # cases -- "no canonical code exists for this at all" versus "a real code
  # exists elsewhere and must specifically NOT be returned here". Reported
  # negative correctness on the blend obscured which failure mode was
  # occurring. The two are now distinguished:
  #
  #   negative_no_authoritative_code -- expected_code is EMPTY. There is no
  #     classification concept to abstain in favour of.
  #   confusable_negative -- expected_code names a REAL, canonical code that
  #     shares vocabulary with the query but must not be returned for it
  #     (e.g. "carpenter ant" must not return CARPENTERS AND JOINERS).
  #
  # Existing rows are relabelled by this rule, not reinterpreted: a row
  # that already had must_find=FALSE and a non-empty expected_code becomes
  # confusable_negative; must_find=FALSE with an empty expected_code stays
  # negative_no_authoritative_code. No row's must_find value, expected_code,
  # or pass/fail outcome changes.
  "negative_no_authoritative_code", "confusable_negative"
)

RETRIEVAL_EVAL_LANGUAGES <- c("en", "fil", "ceb", "mixed")

# Relative locations the corpus can sit at, depending on whether the caller
# is at the repository root (scripts/) or inside tests/testthat (testthat
# chdirs into that directory while running).
.RETRIEVAL_EVAL_PATHS <- c(
  "data-raw/retrieval_eval_cases.csv",
  "../../data-raw/retrieval_eval_cases.csv",
  "../data-raw/retrieval_eval_cases.csv"
)

#' Locate the evaluation corpus on disk.
#'
#' @return character(1) path, or NA_character_ if it cannot be found.
#' @noRd
.retrieval_eval_find_cases <- function() {
  for (p in .RETRIEVAL_EVAL_PATHS) {
    if (file.exists(p)) return(normalizePath(p, winslash = "/"))
  }
  NA_character_
}

#' Load the versioned retrieval evaluation corpus.
#'
#' @param path character(1) or NULL. NULL resolves the corpus relative to the
#'   repository root or to tests/testthat, so the same call works from a
#'   script and from a test.
#'
#' @return A data.frame with exactly `RETRIEVAL_EVAL_COLUMNS`. Every column is
#'   character except `must_find`, which is logical. `expected_code` is "" (not
#'   NA) when a negative case names no code.
retrieval_eval_load_cases <- function(path = NULL) {
  if (is.null(path)) {
    path <- .retrieval_eval_find_cases()
    if (is.na(path)) {
      stop(
        "Could not locate data-raw/retrieval_eval_cases.csv. Run from the ",
        "repository root or pass an explicit path.",
        call. = FALSE
      )
    }
  }
  if (!file.exists(path)) {
    stop(sprintf("Evaluation corpus not found: %s", path), call. = FALSE)
  }

  cases <- utils::read.csv(
    path,
    colClasses = "character",
    stringsAsFactors = FALSE,
    na.strings = NULL,
    encoding = "UTF-8"
  )

  missing <- setdiff(RETRIEVAL_EVAL_COLUMNS, names(cases))
  if (length(missing)) {
    stop(sprintf(
      "Evaluation corpus is missing required column(s): %s",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }

  cases <- cases[, RETRIEVAL_EVAL_COLUMNS, drop = FALSE]
  for (nm in setdiff(RETRIEVAL_EVAL_COLUMNS, "must_find")) {
    v <- as.character(cases[[nm]])
    v[is.na(v)] <- ""
    cases[[nm]] <- v
  }
  cases$must_find <- toupper(trimws(as.character(cases$must_find))) %in%
    c("TRUE", "T", "YES", "Y", "1")

  rownames(cases) <- NULL
  cases
}

#' Extract a rank-ordered character vector of codes from whatever a
#' `search_fn` returned.
#'
#' Accepts a character vector, a data.frame/tibble with a `code` column, or a
#' `search_classification_result()`-shaped list. Anything else yields
#' `character(0)` rather than an error, because an engine returning an
#' unexpected shape should score zero, not abort the run.
#'
#' @noRd
.retrieval_eval_codes <- function(res) {
  if (is.null(res)) return(character(0))
  if (is.character(res)) return(res)
  if (is.data.frame(res)) {
    if (!"code" %in% names(res)) return(character(0))
    return(as.character(res$code))
  }
  if (is.list(res) && !is.null(res$data) && is.data.frame(res$data)) {
    if (!"code" %in% names(res$data)) return(character(0))
    return(as.character(res$data$code))
  }
  character(0)
}

#' The default engine under test: the application's own search service.
#'
#' @param system,version,query passed through to `search_classification_result()`.
#' @param limit integer(1) depth of the ranked list to score.
#'
#' @return character vector of codes in rank order.
retrieval_eval_default_search_fn <- function(system, version, query, limit = 50L) {
  .retrieval_eval_codes(
    search_classification_result(system, version, query, limit = limit)
  )
}

#' The pre-hybrid baseline engine, reproduced in isolation.
#'
#' This is a faithful re-implementation of the six-tier whole-query literal
#' engine that shipped before the hybrid retrieval milestone (exact code,
#' code prefix, exact label, label prefix, label substring, description
#' substring). It exists so the "before" numbers in the milestone report stay
#' reproducible even after R/search.R is replaced -- it reads the repository
#' but never calls the live search service, and it is never wired into the
#' application.
#'
#' @inheritParams retrieval_eval_default_search_fn
#'
#' @return character vector of codes in rank order.
retrieval_eval_legacy_search_fn <- function(system, version, query, limit = 50L) {
  data <- get_classification(system, version, level = NULL)
  if (is.null(data) || nrow(data) == 0L) return(character(0))

  norm <- function(x) {
    x <- trimws(tolower(as.character(x)))
    gsub("\\s+", " ", x)
  }
  q <- norm(query)
  if (is.na(q) || !nzchar(q)) return(as.character(utils::head(data$code, limit)))

  code_lower <- norm(data$code)
  label_norm <- norm(data$label)
  desc_norm <- norm(data$description)

  tier <- rep(NA_integer_, nrow(data))
  tier[is.na(tier) & code_lower == q] <- 1L
  tier[is.na(tier) & startsWith(code_lower, q)] <- 2L
  tier[is.na(tier) & label_norm == q] <- 3L
  tier[is.na(tier) & startsWith(label_norm, q)] <- 4L
  tier[is.na(tier) & grepl(q, label_norm, fixed = TRUE)] <- 5L
  tier[is.na(tier) & !is.na(desc_norm) & grepl(q, desc_norm, fixed = TRUE)] <- 6L

  keep <- which(!is.na(tier))
  if (!length(keep)) return(character(0))
  ord <- keep[order(tier[keep], keep)]
  as.character(utils::head(data$code[ord], limit))
}

#' Run the evaluation corpus against one retrieval engine.
#'
#' @param cases A data.frame as returned by `retrieval_eval_load_cases()`.
#' @param search_fn function(system, version, query, limit) returning the
#'   ranked codes (or a result object -- see `.retrieval_eval_codes()`).
#' @param k integer vector of recall cut-offs to report.
#' @param limit integer(1) depth of the ranked list requested from the engine.
#'   Ranks deeper than this are reported as not-found, so MRR is MRR@limit.
#' @param verbose logical(1). Print a dot-per-case progress line.
#'
#' @return A list with `per_case` (one row per case) and `metrics`
#'   (see `retrieval_eval_metrics()`).
retrieval_eval_run <- function(cases, search_fn = retrieval_eval_default_search_fn,
                               k = c(1L, 3L, 5L), limit = 50L, verbose = FALSE) {
  stopifnot(is.data.frame(cases), is.function(search_fn))
  k <- sort(unique(as.integer(k)))
  n <- nrow(cases)

  rank <- rep(NA_integer_, n)
  latency <- rep(NA_real_, n)
  err <- rep(NA_character_, n)
  n_returned <- rep(0L, n)

  for (i in seq_len(n)) {
    started <- Sys.time()
    codes <- tryCatch(
      .retrieval_eval_codes(
        search_fn(cases$system[i], cases$version[i], cases$query[i], limit = limit)
      ),
      error = function(e) {
        err[i] <<- conditionMessage(e)
        character(0)
      }
    )
    latency[i] <- as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000

    n_returned[i] <- length(codes)
    expected <- cases$expected_code[i]
    if (nzchar(expected) && length(codes)) {
      hit <- match(expected, codes)
      if (!is.na(hit)) rank[i] <- as.integer(hit)
    }
    if (verbose && i %% 25L == 0L) cat(sprintf("  ... %d/%d\n", i, n))
  }

  reciprocal_rank <- ifelse(is.na(rank), 0, 1 / rank)
  found <- !is.na(rank)
  # A positive case passes when the expected code lands inside the most
  # lenient reported cut-off; per-k recall is reported separately below.
  #
  # A negative_no_authoritative_code case has a blank expected_code, so
  # `!found` (`is.na(rank)`) is vacuously TRUE no matter what the engine
  # returned -- `passed` must judge it by "no authoritative result at all"
  # (n_returned == 0) instead, or a query that returns an unrelated official
  # code would be reported as passing here and never appear in a failing-
  # cases listing. confusable_negative keeps the `!found` semantics: it
  # names a real code that must specifically be absent from the ranking.
  query_type_chr <- as.character(cases$query_type)
  is_true_no_code <- !cases$must_find &
    !is.na(query_type_chr) & query_type_chr == "negative_no_authoritative_code"
  passed <- ifelse(cases$must_find, found & rank <= max(k), !found)
  passed[is_true_no_code] <- n_returned[is_true_no_code] == 0L

  per_case <- data.frame(
    case_id         = cases$case_id,
    system          = cases$system,
    version         = cases$version,
    query           = cases$query,
    query_type      = cases$query_type,
    language        = cases$language,
    must_find       = cases$must_find,
    expected_code   = cases$expected_code,
    rank            = rank,
    reciprocal_rank = as.numeric(reciprocal_rank),
    found           = found,
    passed          = as.logical(passed),
    latency_ms      = latency,
    n_returned      = n_returned,
    error           = err,
    stringsAsFactors = FALSE
  )

  list(per_case = per_case, metrics = retrieval_eval_metrics(per_case, k = k))
}

#' Compute retrieval metrics from a per-case table.
#'
#' @param per_case A data.frame as produced by `retrieval_eval_run()`.
#' @param k integer vector of recall cut-offs.
#'
#' @return A named list: `recall_at_<k>` for each k, `mrr`, `negative_correct`,
#'   `n_cases`, `n_positive`, `n_negative`, `n_errors`, `latency_p50_ms`,
#'   `latency_p95_ms`. A metric with no cases contributing to it is
#'   `NA_real_`, never NaN and never silently zero.
retrieval_eval_metrics <- function(per_case, k = c(1L, 3L, 5L)) {
  stopifnot(is.data.frame(per_case))
  k <- sort(unique(as.integer(k)))

  pos <- per_case[.retrieval_eval_truthy(per_case$must_find), , drop = FALSE]
  neg <- per_case[!.retrieval_eval_truthy(per_case$must_find), , drop = FALSE]

  safe_mean <- function(x) if (length(x) == 0L) NA_real_ else as.numeric(mean(x))

  out <- list()
  for (kk in k) {
    out[[paste0("recall_at_", kk)]] <-
      safe_mean(!is.na(pos$rank) & pos$rank <= kk)
  }
  out$mrr <- safe_mean(pos$reciprocal_rank)

  # Split by taxonomy (pre-staging convergence): the blended
  # `negative_correct` below can look healthy while hiding a specific
  # failure mode in one half of the negatives. Reported separately so a
  # regression in "abstain on a confusable" can never be masked by
  # "abstain on something with no code at all" (which is a much easier bar
  # to clear -- there is nothing plausible to return).
  query_type_chr <- as.character(neg$query_type)
  is_confusable <- !is.na(query_type_chr) & query_type_chr == "confusable_negative"
  is_true_no_code <- !is.na(query_type_chr) & query_type_chr == "negative_no_authoritative_code"
  confusable <- neg[is_confusable, , drop = FALSE]
  true_no_code <- neg[is_true_no_code, , drop = FALSE]

  # confusable_negative: expected_code names a real, specific code that must
  # not be returned -- "correct" means that exact code is absent from the
  # ranked list, which `is.na(rank)` already captures.
  out$confusable_negative_correct <- safe_mean(is.na(confusable$rank))

  # negative_no_authoritative_code: expected_code is blank by definition, so
  # `is.na(rank)` is vacuously TRUE regardless of what the engine returned --
  # `match("", codes)` can never hit, and `nzchar("")` short-circuits `rank`
  # to NA before a lookup is even attempted. That made this metric 100% by
  # construction, not by measurement. "Correct" here means retrieval
  # surfaced no authoritative classification result at all, which is
  # `n_returned == 0` under the current contract: search_classification_result()
  # presents every row of `$data` as an official classification (see
  # `.retrieval_eval_codes()` and R/repository.R -- there is no separate
  # "suggestion" channel to check instead).
  out$true_no_code_correct <- safe_mean(true_no_code$n_returned == 0L)
  out$n_confusable_negative <- nrow(confusable)
  out$n_true_no_code <- nrow(true_no_code)

  # Overall negative correctness, corrected per-row by taxonomy: a
  # true-no-code row is judged by "no authoritative result", never by the
  # blank-expected_code rank check. Any negative row outside this taxonomy
  # (none exist today) falls back to the original is.na(rank) semantics.
  neg_correct <- is.na(neg$rank)
  neg_correct[is_true_no_code] <- neg$n_returned[is_true_no_code] == 0L
  out$negative_correct <- safe_mean(neg_correct)

  out$n_cases <- nrow(per_case)
  out$n_positive <- nrow(pos)
  out$n_negative <- nrow(neg)
  out$n_errors <- sum(!is.na(per_case$error))

  lat <- per_case$latency_ms[!is.na(per_case$latency_ms)]
  if (length(lat)) {
    q <- stats::quantile(lat, probs = c(0.5, 0.95), names = FALSE, type = 7)
    out$latency_p50_ms <- as.numeric(q[1])
    out$latency_p95_ms <- as.numeric(q[2])
  } else {
    out$latency_p50_ms <- NA_real_
    out$latency_p95_ms <- NA_real_
  }
  out
}

#' Coerce a possibly-NA logical column to a plain TRUE/FALSE vector.
#' @noRd
.retrieval_eval_truthy <- function(x) {
  x <- as.logical(x)
  x[is.na(x)] <- FALSE
  x
}

#' Metrics broken down by one grouping column.
#'
#' @param per_case A data.frame as produced by `retrieval_eval_run()`.
#' @param by character(1) column name to group on ("query_type", "language",
#'   "system", ...).
#' @param k integer vector of recall cut-offs.
#'
#' @return A data.frame, one row per group, ordered by group name.
retrieval_eval_breakdown <- function(per_case, by = "query_type", k = c(1L, 3L, 5L)) {
  stopifnot(is.data.frame(per_case), by %in% names(per_case))
  k <- sort(unique(as.integer(k)))
  groups <- sort(unique(as.character(per_case[[by]])))

  rows <- lapply(groups, function(g) {
    sub <- per_case[as.character(per_case[[by]]) == g, , drop = FALSE]
    m <- retrieval_eval_metrics(sub, k = k)
    row <- data.frame(group = g, n = m$n_cases, stringsAsFactors = FALSE)
    for (kk in k) row[[paste0("recall_at_", kk)]] <- m[[paste0("recall_at_", kk)]]
    row$mrr <- m$mrr
    row$negative_correct <- m$negative_correct
    row$median_latency_ms <- m$latency_p50_ms
    row
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

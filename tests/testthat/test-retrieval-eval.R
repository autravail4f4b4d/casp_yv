# Tests for the retrieval evaluation harness (R/retrieval/retrieval_eval.R).
#
# These tests exercise the HARNESS, not the engine. Deliberately absent:
# any assertion on the absolute Recall/MRR of the real corpus against the
# live search service. Those numbers are supposed to move as retrieval
# improves, and pinning them would make the suite fail the moment the
# engine got better.
#
# Nothing here may skip: a skip is a silent hole in the milestone gate.

# ---------------------------------------------------------------------------
# Hand-built fixture with known ranks.
#
#   FIX-1  positive, expected "A1", returned at rank 1  -> rr = 1
#   FIX-2  positive, expected "B2", returned at rank 3  -> rr = 1/3
#   FIX-3  positive, expected "C3", never returned      -> rr = 0
#   FIX-4  negative_no_authoritative_code, expected "" (blank, per the
#          taxonomy contract), engine returns nothing  -> correct
#
#   Recall@1 = 1/3   Recall@3 = 2/3   Recall@5 = 2/3
#   MRR      = (1 + 1/3 + 0) / 3 = 4/9
#   negative_correct = 1
# ---------------------------------------------------------------------------

fixture_cases <- function() {
  data.frame(
    case_id        = c("FIX-1", "FIX-2", "FIX-3", "FIX-4"),
    system         = rep("psoc", 4),
    version        = rep("2022", 4),
    query          = c("q1", "q2", "q3", "q4"),
    expected_code  = c("A1", "B2", "C3", ""),
    expected_level = rep("unit_group", 4),
    query_type     = c("exact_code", "typo", "paraphrase",
                       "negative_no_authoritative_code"),
    language       = rep("en", 4),
    must_find      = c(TRUE, TRUE, TRUE, FALSE),
    notes          = rep("", 4),
    provenance     = rep("fixture", 4),
    stringsAsFactors = FALSE
  )
}

fixture_search_fn <- function(system, version, query, limit = 50L) {
  switch(query,
    q1 = c("A1", "X", "Y"),
    q2 = c("X", "Y", "B2"),
    q3 = c("X", "Y", "Z", "W", "Q"),
    q4 = character(0),
    character(0)
  )
}

test_that("the versioned corpus loads with exactly the required columns", {
  cases <- retrieval_eval_load_cases()

  expect_true(is.data.frame(cases))
  expect_gt(nrow(cases), 0L)
  expect_identical(names(cases), RETRIEVAL_EVAL_COLUMNS)
  expect_type(cases$must_find, "logical")
  expect_false(any(is.na(cases$must_find)))
})

test_that("case ids are unique and every case names a system and a query", {
  cases <- retrieval_eval_load_cases()

  expect_equal(anyDuplicated(cases$case_id), 0L)
  expect_true(all(nzchar(cases$case_id)))
  expect_true(all(nzchar(cases$system)))
  expect_true(all(nzchar(cases$version)))
  expect_true(all(nzchar(cases$query)))
  expect_true(all(nzchar(cases$provenance)))
})

test_that("every query_type and language comes from the allowed vocabulary", {
  cases <- retrieval_eval_load_cases()

  expect_setequal(
    character(0),
    setdiff(unique(cases$query_type), RETRIEVAL_EVAL_QUERY_TYPES)
  )
  expect_setequal(
    character(0),
    setdiff(unique(cases$language), RETRIEVAL_EVAL_LANGUAGES)
  )
})

test_that("the corpus actually contains negative cases and positive cases", {
  cases <- retrieval_eval_load_cases()

  expect_gt(sum(!cases$must_find), 0L)
  expect_gt(sum(cases$must_find), 0L)
  # A positive case without an expected code cannot be scored.
  expect_true(all(nzchar(cases$expected_code[cases$must_find])))
})

test_that("the corpus spans several classification systems and languages", {
  cases <- retrieval_eval_load_cases()

  expect_gte(length(unique(cases$system)), 4L)
  expect_gte(length(unique(cases$language)), 3L)
  expect_gte(nrow(cases), 60L)
})

test_that("the mandated heavy-truck regression queries are all present", {
  cases <- retrieval_eval_load_cases()
  psoc <- cases[cases$system == "psoc" & cases$version == "2022", , drop = FALSE]

  mandated <- c(
    "8332", "Heavy Truck and Lorry Drivers", "heavy truck driver",
    "heavy truck drivers", "hevy truck driver", "trcuk driver"
  )
  for (q in mandated) {
    row <- psoc[psoc$query == q, , drop = FALSE]
    expect_equal(nrow(row), 1L, info = q)
    expect_equal(row$expected_code[1], "8332", info = q)
    expect_true(row$must_find[1], info = q)
  }
})

test_that("metrics maths matches the hand-computed fixture exactly", {
  res <- retrieval_eval_run(fixture_cases(), search_fn = fixture_search_fn,
                            k = c(1L, 3L, 5L))
  pc <- res$per_case
  m <- res$metrics

  expect_equal(pc$rank, c(1L, 3L, NA_integer_, NA_integer_))
  expect_equal(pc$reciprocal_rank, c(1, 1 / 3, 0, 0))
  expect_equal(pc$found, c(TRUE, TRUE, FALSE, FALSE))
  expect_equal(pc$passed, c(TRUE, TRUE, FALSE, TRUE))

  expect_equal(m$recall_at_1, 1 / 3)
  expect_equal(m$recall_at_3, 2 / 3)
  expect_equal(m$recall_at_5, 2 / 3)
  expect_equal(m$mrr, 4 / 9)
  expect_equal(m$negative_correct, 1)
  expect_equal(m$n_cases, 4L)
  expect_equal(m$n_positive, 3L)
  expect_equal(m$n_negative, 1L)
  expect_equal(m$n_errors, 0L)
})

test_that("metrics carries every required name", {
  res <- retrieval_eval_run(fixture_cases(), search_fn = fixture_search_fn)
  required <- c("recall_at_1", "recall_at_3", "recall_at_5", "mrr",
                "negative_correct", "n_cases", "latency_p50_ms", "latency_p95_ms",
                "confusable_negative_correct", "true_no_code_correct",
                "n_confusable_negative", "n_true_no_code")
  expect_true(all(required %in% names(res$metrics)))
})

# ---------------------------------------------------------------------
# Negative taxonomy (pre-staging convergence phase)
# ---------------------------------------------------------------------
#
# "negative_no_authoritative_code" used to mean two different things: no
# canonical code exists at all, versus a real code exists elsewhere and
# must specifically not be returned here. The two are now distinguished by
# query_type, and negative correctness is reported separately for each so
# a regression in one cannot hide behind the other.

test_that("confusable_negative is an allowed query_type", {
  expect_true("confusable_negative" %in% RETRIEVAL_EVAL_QUERY_TYPES)
})

test_that("confusable-negative and true-no-code correctness are computed independently", {
  cases <- data.frame(
    case_id        = c("T-1", "T-2", "T-3", "T-4"),
    system         = rep("psoc", 4),
    version        = rep("2022", 4),
    query          = c("confusable-leaks", "confusable-abstains",
                       "true-no-code-leaks", "true-no-code-abstains"),
    expected_code  = c("C1", "C2", "", ""),
    expected_level = rep("unit_group", 4),
    query_type     = c("confusable_negative", "confusable_negative",
                       "negative_no_authoritative_code", "negative_no_authoritative_code"),
    language       = rep("en", 4),
    must_find      = rep(FALSE, 4),
    notes          = rep("", 4),
    provenance     = rep("fixture", 4),
    stringsAsFactors = FALSE
  )

  # A "confusable_negative" is scored by whether ITS OWN named
  # expected_code comes back -- that is a real, checkable failure.
  #
  # A "negative_no_authoritative_code" row has NO expected_code, so it
  # cannot be scored by "did the expected code appear" -- there is nothing
  # to look for. Correctness instead means the engine returned no
  # authoritative classification result at all: `Z9` is a fabricated
  # authoritative-looking answer to a query with no real code, and must
  # score as WRONG even though there was never an expected_code for it to
  # match against.
  stub_fn <- function(system, version, query, limit) {
    data.frame(code = switch(query,
      "confusable-leaks" = "C1",
      "confusable-abstains" = character(0),
      "true-no-code-leaks" = "Z9",
      "true-no-code-abstains" = character(0)
    ), stringsAsFactors = FALSE)
  }

  res <- retrieval_eval_run(cases, search_fn = stub_fn, k = c(1L, 3L, 5L))
  m <- res$metrics

  expect_equal(m$n_confusable_negative, 2L)
  expect_equal(m$n_true_no_code, 2L)
  # Confusable: exactly the case whose own expected_code was returned
  # fails, the one whose wasn't passes -- 1 of 2 correct, a REAL check.
  expect_equal(m$confusable_negative_correct, 0.5)
  # True-no-code: the one that returned "Z9" (an unrelated official-looking
  # code) is now WRONG; the one that returned nothing is correct -- 1 of 2,
  # a real check, not vacuously 100%.
  expect_equal(m$true_no_code_correct, 0.5)

  pc <- res$per_case
  expect_false(pc$passed[pc$case_id == "T-3"])
  expect_true(pc$passed[pc$case_id == "T-4"])
})

test_that("a taxonomy split can diverge from the blended negative_correct", {
  # All confusables leak, all true-no-code cases correctly abstain. The
  # blend (negative_correct) reports 50%, which would read as "the system
  # is unsafe" without knowing WHICH half -- the split makes it unambiguous
  # that the failure is entirely in the confusable-negative bucket.
  cases <- data.frame(
    case_id        = c("T-1", "T-2", "T-3", "T-4"),
    system         = rep("psoc", 4),
    version        = rep("2022", 4),
    query          = c("confusable-a", "confusable-b", "no-code-a", "no-code-b"),
    expected_code  = c("C1", "C2", "", ""),
    expected_level = rep("unit_group", 4),
    query_type     = c("confusable_negative", "confusable_negative",
                       "negative_no_authoritative_code", "negative_no_authoritative_code"),
    language       = rep("en", 4),
    must_find      = rep(FALSE, 4),
    notes          = rep("", 4),
    provenance     = rep("fixture", 4),
    stringsAsFactors = FALSE
  )

  stub_fn <- function(system, version, query, limit) {
    data.frame(code = switch(query,
      "confusable-a" = "C1", "confusable-b" = "C2",
      "no-code-a" = character(0), "no-code-b" = character(0)
    ), stringsAsFactors = FALSE)
  }

  res <- retrieval_eval_run(cases, search_fn = stub_fn, k = c(1L, 3L, 5L))
  m <- res$metrics

  expect_equal(m$negative_correct, 0.5)
  expect_equal(m$confusable_negative_correct, 0)
  expect_equal(m$true_no_code_correct, 1)
})

test_that("the real corpora carry both negative taxonomy values, correctly split", {
  for (path in c(
    testthat::test_path("..", "..", "data-raw", "retrieval_eval_cases.csv"),
    testthat::test_path("..", "..", "data-raw", "retrieval_eval_holdout_cases.csv")
  )) {
    skip_if_not(file.exists(path))
    cases <- retrieval_eval_load_cases(path)
    neg <- cases[tolower(trimws(cases$must_find)) %in% c("false", "f", "0", "no"), ]

    is_confusable <- neg$query_type == "confusable_negative"
    is_true_no_code <- neg$query_type == "negative_no_authoritative_code"

    # Every negative row must land in exactly one of the two buckets --
    # relabelling must not have missed or double-counted a row.
    expect_true(all(is_confusable | is_true_no_code), info = path)
    expect_false(any(is_confusable & is_true_no_code), info = path)

    # A confusable negative names a real code; a true-no-code negative
    # does not. This is the actual distinguishing rule, checked directly
    # rather than trusted from the label alone.
    expect_true(all(nzchar(trimws(neg$expected_code[is_confusable]))), info = path)
    expect_true(all(!nzchar(trimws(neg$expected_code[is_true_no_code]))), info = path)

    # Both buckets are actually populated in both corpora.
    expect_gt(sum(is_confusable), 0L, label = paste(path, "confusable_negative count"))
    expect_gt(sum(is_true_no_code), 0L, label = paste(path, "true_no_code count"))
  }
})

test_that("latency is recorded per case and summarized as p50/p95", {
  res <- retrieval_eval_run(fixture_cases(), search_fn = fixture_search_fn)

  expect_true(all(is.finite(res$per_case$latency_ms)))
  expect_true(all(res$per_case$latency_ms >= 0))
  expect_true(is.finite(res$metrics$latency_p50_ms))
  expect_true(is.finite(res$metrics$latency_p95_ms))
  expect_gte(res$metrics$latency_p95_ms, res$metrics$latency_p50_ms)
})

test_that("a confusable_negative case whose forbidden code IS returned scores as a failure", {
  # FIX-4 is a true no-code row by default (blank expected_code); a
  # confusable_negative row names a REAL forbidden code instead, so it is
  # relabelled locally rather than reusing FIX-4's default semantics.
  cases <- fixture_cases()
  cases$query_type[4] <- "confusable_negative"
  cases$expected_code[4] <- "D4"
  leaky <- function(system, version, query, limit = 50L) {
    if (identical(query, "q4")) return(c("X", "D4", "Y"))
    fixture_search_fn(system, version, query, limit)
  }

  res <- retrieval_eval_run(cases, search_fn = leaky)
  neg <- res$per_case[res$per_case$case_id == "FIX-4", ]

  expect_equal(neg$rank, 2L)
  expect_true(neg$found)
  expect_false(neg$passed)
  expect_equal(res$metrics$negative_correct, 0)
})

test_that("a confusable_negative case whose forbidden code is absent scores as a pass", {
  cases <- fixture_cases()
  cases$query_type[4] <- "confusable_negative"
  cases$expected_code[4] <- "D4"

  res <- retrieval_eval_run(cases, search_fn = fixture_search_fn)
  neg <- res$per_case[res$per_case$case_id == "FIX-4", ]

  expect_true(is.na(neg$rank))
  expect_false(neg$found)
  expect_true(neg$passed)
  expect_equal(res$metrics$negative_correct, 1)
})

test_that("a blank-expected-code negative with no expected code is never counted as FOUND, but an unrelated result still FAILS it", {
  # This is the corrected true-no-code contract (final micro-gate): rank
  # stays NA -- there is genuinely nothing to match against -- but that must
  # not be conflated with "correct". Returning ANY authoritative-looking
  # result to a query with no real classification is itself the defect.
  cases <- fixture_cases()
  stopifnot(identical(cases$query_type[4], "negative_no_authoritative_code"))
  stopifnot(identical(cases$expected_code[4], ""))

  everything <- function(system, version, query, limit = 50L) c("X", "Y", "Z")
  res <- retrieval_eval_run(cases, search_fn = everything)
  neg <- res$per_case[res$per_case$case_id == "FIX-4", ]

  expect_true(is.na(neg$rank))
  expect_false(neg$found)
  expect_false(neg$passed)
  expect_equal(res$metrics$true_no_code_correct, 0)
})

test_that("a true no-code case that correctly returns nothing passes", {
  cases <- fixture_cases()
  res <- retrieval_eval_run(cases, search_fn = fixture_search_fn)
  neg <- res$per_case[res$per_case$case_id == "FIX-4", ]

  expect_true(is.na(neg$rank))
  expect_true(neg$passed)
  expect_equal(res$metrics$true_no_code_correct, 1)
})

test_that("a search_fn that throws is scored as not-found, not an abort", {
  boom <- function(system, version, query, limit = 50L) {
    stop("provider exploded")
  }

  res <- expect_no_error(retrieval_eval_run(fixture_cases(), search_fn = boom))
  pc <- res$per_case

  expect_equal(nrow(pc), 4L)
  expect_true(all(is.na(pc$rank)))
  expect_true(all(grepl("provider exploded", pc$error)))
  expect_equal(res$metrics$recall_at_1, 0)
  expect_equal(res$metrics$mrr, 0)
  # The negative case is still "correct" -- nothing was returned.
  expect_equal(res$metrics$negative_correct, 1)
  expect_equal(res$metrics$n_errors, 4L)
})

test_that("one throwing case does not stop the remaining cases from scoring", {
  flaky <- function(system, version, query, limit = 50L) {
    if (identical(query, "q2")) stop("transient failure")
    fixture_search_fn(system, version, query, limit)
  }

  res <- retrieval_eval_run(fixture_cases(), search_fn = flaky)
  pc <- res$per_case

  expect_equal(pc$rank, c(1L, NA_integer_, NA_integer_, NA_integer_))
  expect_equal(res$metrics$n_errors, 1L)
  expect_equal(res$metrics$recall_at_1, 1 / 3)
})

test_that("recall is monotonically non-decreasing in k", {
  res <- retrieval_eval_run(fixture_cases(), search_fn = fixture_search_fn,
                            k = c(1L, 3L, 5L))
  m <- res$metrics

  expect_lte(m$recall_at_1, m$recall_at_3)
  expect_lte(m$recall_at_3, m$recall_at_5)
})

test_that("a search_fn returning a result object or a tibble is understood", {
  as_df <- function(system, version, query, limit = 50L) {
    data.frame(code = fixture_search_fn(system, version, query),
               stringsAsFactors = FALSE)
  }
  as_result <- function(system, version, query, limit = 50L) {
    list(data = data.frame(code = fixture_search_fn(system, version, query),
                           stringsAsFactors = FALSE))
  }

  expect_equal(
    retrieval_eval_run(fixture_cases(), search_fn = as_df)$per_case$rank,
    c(1L, 3L, NA_integer_, NA_integer_)
  )
  expect_equal(
    retrieval_eval_run(fixture_cases(), search_fn = as_result)$per_case$rank,
    c(1L, 3L, NA_integer_, NA_integer_)
  )
})

test_that("metrics are NA rather than NaN when a class of case is absent", {
  cases <- fixture_cases()[1:3, , drop = FALSE]   # positives only
  res <- retrieval_eval_run(cases, search_fn = fixture_search_fn)

  expect_true(is.na(res$metrics$negative_correct))
  expect_false(is.nan(res$metrics$negative_correct))

  neg_only <- fixture_cases()[4, , drop = FALSE]
  res2 <- retrieval_eval_run(neg_only, search_fn = fixture_search_fn)
  expect_true(is.na(res2$metrics$recall_at_1))
  expect_true(is.na(res2$metrics$mrr))
})

test_that("the breakdown groups cases without changing the maths", {
  tab <- retrieval_eval_breakdown(
    retrieval_eval_run(fixture_cases(), search_fn = fixture_search_fn)$per_case,
    by = "query_type"
  )

  expect_equal(sum(tab$n), 4L)
  expect_true("negative_no_authoritative_code" %in% tab$group)
  exact <- tab[tab$group == "exact_code", ]
  expect_equal(exact$recall_at_1, 1)
  expect_equal(exact$mrr, 1)
})

test_that("codes with leading zeros and punctuation survive loading", {
  cases <- retrieval_eval_load_cases()
  pscc <- cases[cases$system == "pscc", , drop = FALSE]

  expect_gt(nrow(pscc), 0L)
  expect_true(any(grepl("^0", pscc$expected_code)))
  expect_true(any(grepl("[.]", pscc$expected_code)))
  expect_type(cases$expected_code, "character")
})

test_that("the corpus path resolves from tests/testthat and from an explicit path", {
  from_default <- retrieval_eval_load_cases()
  explicit <- file.path("..", "..", "data-raw", "retrieval_eval_cases.csv")

  expect_true(file.exists(explicit))
  expect_equal(nrow(retrieval_eval_load_cases(explicit)), nrow(from_default))
  expect_error(retrieval_eval_load_cases("does/not/exist.csv"), "not found")
})

# The PSCC cross-reference fallback wired into the Search panel
# (UI-POST-07 section 9.11).
#
# app.R falls back to pscc_crossref_search() ONLY when the ordinary ranked
# search found nothing. That rule rests on two facts which these tests pin,
# because if either drifts the fallback either stops firing or starts
# reordering results that the ranked search had already found:
#
#   1. the ordinary search does NOT look at the cross-reference columns, so
#      a cross-reference-only query genuinely returns zero matches;
#   2. the cross-reference search DOES find that record, and says so.
#
# Ranking for every other query is therefore untouched by construction.

CROSSREF_ONLY_QUERY <- "0101.29.00-01"   # a published 2019 PSCC code
CROSSREF_TARGET_CODE <- "0101.29.00-001" # the 2022 commodity it maps to

test_that("the ordinary ranked search does not match cross-reference columns", {
  res <- search_classification_result("pscc", "2022", CROSSREF_ONLY_QUERY, limit = 200)

  # Precondition 1. If this ever becomes non-zero the fallback stops firing,
  # and a cross-reference match would silently lose its explanatory label.
  expect_equal(res$total_matches, 0L)
  expect_equal(nrow(res$data), 0L)
})

test_that("the cross-reference search finds the record the ranked search missed", {
  hits <- pscc_crossref_search(CROSSREF_ONLY_QUERY, limit = 200)

  expect_equal(nrow(hits), 1L)
  expect_identical(hits$code[[1L]], CROSSREF_TARGET_CODE)
  expect_identical(hits$match_field[[1L]], "pscc_2019")
  expect_identical(hits$matched_value[[1L]], CROSSREF_ONLY_QUERY)
})

test_that("the match reason names the edition the match came from", {
  hits <- pscc_crossref_search(CROSSREF_ONLY_QUERY, limit = 200)
  reason <- hits$match_reason[[1L]]

  expect_match(reason, "2019 PSCC cross-reference", fixed = TRUE)
  expect_match(reason, CROSSREF_ONLY_QUERY, fixed = TRUE)
  # The reason must not claim this is the 2022 code.
  expect_false(grepl("Matched 2022", reason, fixed = TRUE))
})

test_that("a cross-reference is never written into the record's own code", {
  hits <- pscc_crossref_search(CROSSREF_ONLY_QUERY, limit = 200)

  expect_false(identical(hits$code[[1L]], CROSSREF_ONLY_QUERY))
  expect_false(identical(hits$pscc_2022_code[[1L]], CROSSREF_ONLY_QUERY))
  # The surfaced 2022 code is the real one from column B.
  expect_identical(hits$pscc_2022_code[[1L]], CROSSREF_TARGET_CODE)
  # ...and the cross-reference itself is still carried, unmodified.
  expect_identical(hits$pscc_2019_code[[1L]], CROSSREF_ONLY_QUERY)
})

test_that("an exact 2022 code is reported as a 2022 match, not a cross-reference", {
  hits <- pscc_crossref_search("0101.21.00-000", limit = 5)

  expect_gte(nrow(hits), 1L)
  expect_identical(hits$match_field[[1L]], "pscc_2022")
  expect_match(hits$match_reason[[1L]], "Matched 2022 PSCC code", fixed = TRUE)
})

test_that("an AHTN value is labelled as an AHTN cross-reference", {
  hits <- pscc_crossref_search("0101.30.10", limit = 5)

  expect_gte(nrow(hits), 1L)
  expect_identical(hits$match_field[[1L]], "ahtn_2022")
  expect_match(hits$match_reason[[1L]], "AHTN 2022 cross-reference", fixed = TRUE)
})

test_that("the fallback never fires for a query the ranked search can answer", {
  # A plain description query must be answered by the ranked search, so the
  # fallback condition (total_matches == 0) is never reached and ranking is
  # provably unaffected.
  res <- search_classification_result("pscc", "2022", "Race horses", limit = 200)

  expect_gt(res$total_matches, 0L)
})

test_that("the match-reason renderer is NULL-safe", {
  # app.R passes r$match_reason unconditionally; it is NULL for every
  # non-cross-reference result, including every non-PSCC system.
  expect_null(pscc_match_reason_ui(NULL))
  expect_null(pscc_match_reason_ui(NA_character_))
  expect_false(is.null(pscc_match_reason_ui("Matched AHTN 2022 cross-reference: 0101.30.10")))
})

test_that("cross-reference results stay bounded", {
  # Spec 9.16: search performance remains bounded even through the fallback.
  hits <- pscc_crossref_search("01", limit = 25)
  expect_lte(nrow(hits), 25L)
})

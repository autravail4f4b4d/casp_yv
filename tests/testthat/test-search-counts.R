# Tests for count-aware search (spec section 14.2).
#
# The bug being locked out: the Search UI rendered `nrow(results())` where
# `results()` had already been capped at `limit = 200`, so almost every system
# reported exactly "200 results" no matter how many rows actually matched.
#
# Boundary matrix required by the spec: total match counts of 0, 1, 199, 200,
# 201 and clearly >200, for BOTH a filtered query and a blank browse query.
# Real classification data does not conveniently contain exactly 199/200/201
# matches for any query, so the boundaries are built synthetically with
# new_classification_tibble(); real large systems (pscc, psgc) are exercised
# separately to prove the plumbing survives contact with actual adapters.

MIDDOT <- "·"

# Rows 1..n_match have level "class" and labels beginning "Widgetology unit",
# so query "widgetology" matches exactly n_match rows (tier 4, label prefix).
# The noise rows have level "division" and share no substring with the query,
# so they are counted only by a blank browse query or by a "division" filter.
make_counts_fixture <- function(n_match, n_noise = 25L) {
  n_match <- as.integer(n_match)
  n_noise <- as.integer(n_noise)
  codes <- c(
    if (n_match > 0L) sprintf("M%05d", seq_len(n_match)),
    if (n_noise > 0L) sprintf("N%05d", seq_len(n_noise))
  )
  labels <- c(
    if (n_match > 0L) sprintf("Widgetology unit %d", seq_len(n_match)),
    if (n_noise > 0L) sprintf("Unrelated entry %d", seq_len(n_noise))
  )
  new_classification_tibble(
    system      = "psic",
    version     = "2026",
    level       = c(rep("class", n_match), rep("division", n_noise)),
    code        = codes,
    label       = labels,
    description = NA_character_,
    parent_code = NA_character_,
    status      = "current",
    source      = "Philippine Statistics Authority",
    source_url  = "https://psa.gov.ph/"
  )
}

# ---------------------------------------------------------------------------
# format_result_count() -- the exact required strings
# ---------------------------------------------------------------------------

test_that("format_result_count() produces the required string for every boundary", {
  # 87 matches, all returned
  expect_identical(format_result_count(87L, 87L, FALSE), "87 results")
  # exactly 1 -> singular
  expect_identical(format_result_count(1L, 1L, FALSE), "1 result")
  # zero
  expect_identical(format_result_count(0L, 0L, FALSE), "No results")
  # truncated
  expect_identical(
    format_result_count(3487L, 200L, TRUE, limit = 200L),
    paste0("3,487 results ", MIDDOT, " showing first 200")
  )
  # total genuinely unknowable
  expect_identical(
    format_result_count(NA_integer_, 200L, TRUE, limit = 200L, total_is_exact = FALSE),
    "200+ results"
  )
  # browse suffix
  expect_identical(
    format_result_count(87L, 87L, FALSE, is_browsing = TRUE),
    paste0("87 results ", MIDDOT, " browsing")
  )
  expect_identical(
    format_result_count(0L, 0L, FALSE, is_browsing = TRUE),
    paste0("No results ", MIDDOT, " browsing")
  )
})

test_that("format_result_count() uses thousands separators and never scientific notation", {
  expect_identical(format_result_count(21742L, 21742L, FALSE), "21,742 results")
  expect_identical(format_result_count(1000000L, 1000000L, FALSE), "1,000,000 results")
  expect_identical(
    format_result_count(21742L, 1500L, TRUE),
    paste0("21,742 results ", MIDDOT, " showing first 1,500")
  )
})

test_that("format_result_count() never reports the cap as the total", {
  # THE regression. 201 matches, limit 200.
  s <- format_result_count(201L, 200L, TRUE, limit = 200L)
  expect_false(identical(s, "200 results"))
  expect_identical(s, paste0("201 results ", MIDDOT, " showing first 200"))

  # Exactly 200 matches with limit 200 IS legitimately "200 results".
  expect_identical(format_result_count(200L, 200L, FALSE, limit = 200L), "200 results")
})

test_that("format_result_count() is a pure string function with no Shiny dependency", {
  out <- format_result_count(5L, 5L, FALSE)
  expect_type(out, "character")
  expect_length(out, 1L)
  expect_false(inherits(out, "shiny.tag"))
})

# ---------------------------------------------------------------------------
# search_classification_data_result() -- boundary matrix, filtered query
# ---------------------------------------------------------------------------

test_that("filtered query: total_matches counts pre-limit matches at every boundary", {
  for (n in c(0L, 1L, 199L, 200L, 201L, 3487L)) {
    fx <- make_counts_fixture(n)
    res <- search_classification_data_result(fx, "widgetology", limit = 200L)

    expect_identical(res$total_matches, n, info = paste("n =", n))
    expect_identical(res$returned_count, min(n, 200L), info = paste("n =", n))
    expect_identical(res$returned_count, nrow(res$data), info = paste("n =", n))
    expect_identical(res$limit, 200L, info = paste("n =", n))
    expect_identical(res$is_truncated, n > 200L, info = paste("n =", n))
  }
})

test_that("blank browse query: total_matches counts pre-limit rows at every boundary", {
  for (n in c(0L, 1L, 199L, 200L, 201L, 3487L)) {
    # Level-filtered browse so the browse total is exactly n (noise rows are
    # level "division"); this also proves the level filter is applied before
    # the count, not after.
    fx <- make_counts_fixture(n)
    res <- search_classification_data_result(fx, "", level = "class", limit = 200L)

    expect_identical(res$total_matches, n, info = paste("browse n =", n))
    expect_identical(res$returned_count, min(n, 200L), info = paste("browse n =", n))
    expect_identical(res$returned_count, nrow(res$data), info = paste("browse n =", n))
    expect_identical(res$is_truncated, n > 200L, info = paste("browse n =", n))
  }
})

test_that("is_truncated is FALSE at exactly the limit and TRUE one past it", {
  at_limit <- search_classification_data_result(
    make_counts_fixture(200L), "widgetology", limit = 200L
  )
  expect_identical(at_limit$total_matches, 200L)
  expect_false(at_limit$is_truncated)
  expect_identical(
    format_result_count(at_limit$total_matches, at_limit$returned_count,
                        at_limit$is_truncated, limit = at_limit$limit),
    "200 results"
  )

  over_limit <- search_classification_data_result(
    make_counts_fixture(201L), "widgetology", limit = 200L
  )
  expect_identical(over_limit$total_matches, 201L)
  expect_true(over_limit$is_truncated)
  ui_string <- format_result_count(
    over_limit$total_matches, over_limit$returned_count,
    over_limit$is_truncated, limit = over_limit$limit
  )
  # The whole point of this workstream.
  expect_false(identical(ui_string, "200 results"))
  expect_identical(ui_string, paste0("201 results ", MIDDOT, " showing first 200"))
})

test_that("blank browse at 201 rows with limit 200 also refuses to say '200 results'", {
  res <- search_classification_data_result(
    make_counts_fixture(201L), NULL, level = "class", limit = 200L
  )
  ui_string <- format_result_count(res$total_matches, res$returned_count,
                                   res$is_truncated, limit = res$limit,
                                   is_browsing = TRUE)
  expect_false(identical(ui_string, "200 results"))
  expect_false(identical(ui_string, paste0("200 results ", MIDDOT, " browsing")))
  expect_identical(
    ui_string,
    paste0("201 results ", MIDDOT, " showing first 200 ", MIDDOT, " browsing")
  )
})

test_that("level filter is applied BEFORE counting", {
  fx <- make_counts_fixture(50L, n_noise = 300L)

  # Level "class" holds only the 50 matching rows.
  res <- search_classification_data_result(fx, "widgetology", level = "class", limit = 200L)
  expect_identical(res$total_matches, 50L)
  expect_false(res$is_truncated)

  # Level "division" holds only the 300 noise rows -- none match the query.
  none <- search_classification_data_result(fx, "widgetology", level = "division", limit = 200L)
  expect_identical(none$total_matches, 0L)
  expect_identical(none$returned_count, 0L)
  expect_false(none$is_truncated)

  # Blank browse of the noise level: 300 rows, truncated at 200.
  browse <- search_classification_data_result(fx, "", level = "division", limit = 200L)
  expect_identical(browse$total_matches, 300L)
  expect_identical(browse$returned_count, 200L)
  expect_true(browse$is_truncated)

  # An unknown level yields zero, not an error.
  unknown <- search_classification_data_result(fx, "", level = "no-such-level", limit = 200L)
  expect_identical(unknown$total_matches, 0L)
})

test_that("returned_count always equals nrow(data), including when limit exceeds matches", {
  for (limit in c(1L, 5L, 200L, 10000L)) {
    res <- search_classification_data_result(make_counts_fixture(199L), "widgetology", limit = limit)
    expect_identical(res$returned_count, nrow(res$data))
    expect_identical(res$returned_count, min(199L, limit))
    expect_identical(res$total_matches, 199L)
  }
})

# ---------------------------------------------------------------------------
# Ranking / filtering unchanged, and performed exactly once
# ---------------------------------------------------------------------------

# Purpose-built six-tier fixture: one row per ranking tier, deliberately
# shuffled in source order so an accidental loss of ranking shows up as a
# different code order rather than an identical one.
make_tier_fixture <- function() {
  new_classification_tibble(
    system  = "psic",
    version = "2026",
    level   = "class",
    code    = c("T6", "6201", "T3", "620199", "T5", "T4"),
    label   = c(
      "Tier six carrier",                 # T6: description-only match
      "Exact code row",                   # tier 1
      "6201",                             # tier 3: label exact
      "Prefix code row",                  # tier 2
      "Contains 6201 inside the label",   # tier 5: label substring
      "6201 leading label"                # tier 4: label prefix
    ),
    description = c(
      "mentions 6201 only in the description",
      NA_character_, NA_character_, NA_character_, NA_character_, NA_character_
    ),
    parent_code = NA_character_,
    status      = "current",
    source      = "Philippine Statistics Authority",
    source_url  = "https://psa.gov.ph/"
  )
}

test_that("ranking order and tier semantics are unchanged", {
  fx <- make_tier_fixture()
  res <- search_classification_data_result(fx, "6201", limit = 100L)

  expect_identical(res$total_matches, 6L)
  expect_identical(
    res$data$code,
    c("6201", "620199", "T3", "T4", "T5", "T6")
  )
  # The thin wrapper returns byte-for-byte the same tibble.
  expect_identical(search_classification_data(fx, "6201", limit = 100L), res$data)
})

test_that("the wrapper returns exactly $data for filtered, browse, level and no-match cases", {
  fx <- make_counts_fixture(210L, n_noise = 40L)
  cases <- list(
    list(q = "widgetology", level = NULL,       limit = 200L),
    list(q = "widgetology", level = "class",    limit = 7L),
    list(q = "",            level = NULL,       limit = 200L),
    list(q = NULL,          level = "division", limit = 5L),
    list(q = "zzzznomatch", level = NULL,       limit = 200L),
    list(q = "widgetology", level = "division", limit = 200L)
  )
  for (cs in cases) {
    wrapped <- search_classification_data(fx, cs$q, level = cs$level, limit = cs$limit)
    counted <- search_classification_data_result(fx, cs$q, level = cs$level, limit = cs$limit)
    expect_identical(wrapped, counted$data)
  }
})

test_that("extra adapter columns still pass through unchanged", {
  fx <- make_counts_fixture(5L, n_noise = 2L)
  fx$component <- "tourism_industry"
  fx$source_code <- sprintf("SRC%02d", seq_len(nrow(fx)))

  res <- search_classification_data_result(fx, "widgetology", limit = 100L)
  expect_identical(
    names(res$data),
    c(CLASSIFICATION_SCHEMA_COLUMNS, "component", "source_code")
  )
  expect_identical(res$total_matches, 5L)
  expect_false(any(c(".rank_tier", ".orig_order") %in% names(res$data)))

  # Browse mode preserves the tibble's own column order, as it always did.
  browse <- search_classification_data_result(fx, "", limit = 100L)
  expect_identical(names(browse$data), names(fx))
})

test_that("filtering and ranking are performed exactly once per call", {
  fx <- make_counts_fixture(500L)
  orig <- normalize_whitespace
  calls <- 0L
  assign("normalize_whitespace", function(x) {
    calls <<- calls + 1L
    orig(x)
  }, envir = globalenv())
  on.exit(assign("normalize_whitespace", orig, envir = globalenv()), add = TRUE)

  # One ranking pass normalizes exactly three things: the query, the labels
  # and the descriptions. Six calls would mean the pass ran twice.
  calls <- 0L
  invisible(search_classification_data_result(fx, "widgetology", limit = 200L))
  expect_identical(calls, 3L)

  calls <- 0L
  invisible(search_classification_data(fx, "widgetology", limit = 200L))
  expect_identical(calls, 3L)
})

# ---------------------------------------------------------------------------
# search_classification_result() -- repository layer
# ---------------------------------------------------------------------------

test_that("search_classification_result() returns the full count-aware shape", {
  res <- search_classification_result("psic", "2026", "01111", limit = 200L)
  expect_named(
    res,
    c("data", "total_matches", "returned_count", "limit", "is_truncated"),
    ignore.order = FALSE
  )
  expect_s3_class(res$data, "tbl_df")
  expect_type(res$total_matches, "integer")
  expect_type(res$returned_count, "integer")
  expect_type(res$limit, "integer")
  expect_type(res$is_truncated, "logical")
  expect_identical(res$returned_count, nrow(res$data))
})

test_that("search_classification() is unchanged and equals search_classification_result()$data", {
  cases <- list(
    list("psic", "2026", "01111", NULL, 100L),
    list("psic", "2026", "", "section", 5L),
    list("psic", "2026", "zzzzznomatch", NULL, 100L),
    list("psoc", "2022", "2121", NULL, 100L),
    list("psoc", "2012", "legislators", NULL, 100L),
    list("pscc", "2022", "fresh", NULL, 200L)
  )
  for (cs in cases) {
    old <- search_classification(cs[[1]], cs[[2]], cs[[3]], level = cs[[4]], limit = cs[[5]])
    new <- search_classification_result(cs[[1]], cs[[2]], cs[[3]], level = cs[[4]], limit = cs[[5]])
    expect_s3_class(old, "tbl_df")
    expect_identical(old, new$data)
    expect_identical(nrow(old), new$returned_count)
  }
})

test_that("search_classification_result() validates exactly like search_classification()", {
  expect_error(search_classification_result("psic", "1999", "x"), "Unsupported version")
  expect_error(search_classification_result("psic", "2026", "x", level = "nope"), "Unsupported level")
  expect_error(search_classification_result("nope", "2026", "x"), "Unsupported classification system")
})

test_that("component filter is applied BEFORE counting", {
  industry <- search_classification_result("ptscs", "2025-v2.1", "a",
                                           limit = 5L, component = "tourism_industry")
  product <- search_classification_result("ptscs", "2025-v2.1", "a",
                                          limit = 5L, component = "tourism_product")
  both <- search_classification_result("ptscs", "2025-v2.1", "a", limit = 5L)

  expect_true(industry$total_matches > 0L)
  expect_true(product$total_matches > 0L)
  expect_identical(industry$total_matches + product$total_matches, both$total_matches)
  expect_true(industry$total_matches < both$total_matches)

  # Every returned row really is from the requested component.
  expect_true(all(industry$data$component == "tourism_industry"))
  expect_identical(industry$returned_count, nrow(industry$data))
})

# ---------------------------------------------------------------------------
# Real large classification system (spec: "at least one")
# ---------------------------------------------------------------------------

test_that("pscc 2022 (large system) reports the true total, not the 200 cap", {
  all_rows <- get_classification("pscc", "2022")
  skip_if(nrow(all_rows) <= 200L, "pscc is unexpectedly small")

  # Blank browse: total is the whole table.
  browse <- search_classification_result("pscc", "2022", "", limit = 200L)
  expect_identical(browse$total_matches, nrow(all_rows))
  expect_identical(browse$returned_count, 200L)
  expect_true(browse$is_truncated)
  browse_string <- format_result_count(browse$total_matches, browse$returned_count,
                                       browse$is_truncated, limit = browse$limit,
                                       is_browsing = TRUE)
  expect_false(identical(browse_string, "200 results"))
  expect_false(identical(browse_string, paste0("200 results ", MIDDOT, " browsing")))
  expect_true(grepl("showing first 200", browse_string, fixed = TRUE))

  # Filtered query with far more than 200 matches.
  filtered <- search_classification_result("pscc", "2022", "fresh", limit = 200L)
  expect_true(filtered$total_matches > 200L)
  expect_identical(filtered$returned_count, 200L)
  expect_true(filtered$is_truncated)
  # Cross-check the total against an uncapped run of the same query.
  uncapped <- search_classification("pscc", "2022", "fresh", limit = nrow(all_rows))
  expect_identical(filtered$total_matches, nrow(uncapped))
  expect_identical(filtered$data, head(uncapped, 200L))
  expect_false(identical(
    format_result_count(filtered$total_matches, filtered$returned_count,
                        filtered$is_truncated, limit = filtered$limit),
    "200 results"
  ))
})

test_that("psgc (large system) blank browse reports the true total", {
  release <- psgc::latest_release()
  all_rows <- get_classification("psgc", release)
  skip_if(nrow(all_rows) <= 200L, "psgc is unexpectedly small")

  res <- search_classification_result("psgc", release, "", limit = 200L)
  expect_identical(res$total_matches, nrow(all_rows))
  expect_identical(res$returned_count, 200L)
  expect_true(res$is_truncated)
  expect_false(identical(
    format_result_count(res$total_matches, res$returned_count, res$is_truncated,
                        limit = res$limit, is_browsing = TRUE),
    paste0("200 results ", MIDDOT, " browsing")
  ))
})

test_that("a small real system reports its exact total with no truncation", {
  sections <- search_classification_result("psic", "2026", "", level = "section", limit = 200L)
  expect_false(sections$is_truncated)
  expect_identical(sections$total_matches, sections$returned_count)
  expect_identical(
    format_result_count(sections$total_matches, sections$returned_count,
                        sections$is_truncated, limit = sections$limit,
                        is_browsing = TRUE),
    paste0(format(sections$total_matches, big.mark = ","), " results ", MIDDOT, " browsing")
  )
})

# ---------------------------------------------------------------------------
# Parallel search counts
# ---------------------------------------------------------------------------

test_that("parallel search carries per-system counts without changing results/errors", {
  out <- search_parallel_classifications("manager", limit_per_system = 5L)

  # Pre-existing structure untouched.
  expect_named(out$results, c("psoc", "psic"))
  expect_s3_class(out$results$psoc, "tbl_df")
  expect_s3_class(out$results$psic, "tbl_df")
  expect_null(out$errors)

  # Additive counts, parallel to $results.
  expect_named(out$counts, c("psoc", "psic"))
  for (sys in c("psoc", "psic")) {
    cnt <- out$counts[[sys]]
    expect_named(cnt, c("total_matches", "returned_count", "limit", "is_truncated"))
    expect_identical(cnt$returned_count, nrow(out$results[[sys]]))
    expect_identical(cnt$limit, 5L)
    expect_true(cnt$total_matches >= cnt$returned_count)
    expect_identical(cnt$is_truncated, cnt$total_matches > cnt$returned_count)

    # The count matches an uncapped run of the same per-system search.
    version <- if (sys == "psoc") "2022" else "2026"
    uncapped <- search_classification(sys, version, "manager", limit = 1e6)
    expect_identical(cnt$total_matches, nrow(uncapped))
  }

  # And at least one pane must be truncated, i.e. the count is load-bearing.
  expect_true(any(vapply(out$counts, function(c) isTRUE(c$is_truncated), logical(1))))
})

test_that("parallel search counts survive a failing system without breaking the rest", {
  out <- search_parallel_classifications(
    "manager",
    systems = c("psoc", "psic"),
    versions = c(psoc = "1899", psic = "2026"),
    limit_per_system = 5L
  )
  expect_true("psoc" %in% names(out$errors))
  expect_null(out$results$psoc)
  expect_null(out$counts$psoc)
  expect_s3_class(out$results$psic, "tbl_df")
  expect_identical(out$counts$psic$returned_count, nrow(out$results$psic))
})

test_that("parallel blank browse counts the whole level, not the per-system limit", {
  out <- search_parallel_classifications(
    "",
    levels = list(psic = "section"),
    limit_per_system = 3L
  )
  psic_sections <- get_classification("psic", "2026", level = "section")
  expect_identical(out$counts$psic$total_matches, nrow(psic_sections))
  expect_identical(out$counts$psic$returned_count, 3L)
  expect_true(out$counts$psic$is_truncated)
  expect_false(identical(
    format_result_count(out$counts$psic$total_matches, out$counts$psic$returned_count,
                        out$counts$psic$is_truncated, limit = 3L),
    "3 results"
  ))
})

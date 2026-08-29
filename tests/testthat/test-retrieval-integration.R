# Convergence-level regression tests for the hybrid retrieval engine.
#
# These pin the behaviour the milestone contract names explicitly, at the
# level users and RM actually consume -- through
# `search_classification_result()`, not through an individual tier. A tier
# can be replaced or retuned; these assertions must survive it.
#
# The reported defect: PSOC 2022 "heavy truck driver" returned ZERO results
# while "Heavy Truck and Lorry Drivers" and "8332" both worked. Root cause
# was that the only approximate tier was a whole-query LITERAL substring
# test, and "and lorry" sits between "truck" and "drivers" in the official
# title. Every query token was present; none of them were adjacent.

TRUCK_CODE <- "8332"
TRUCK_LABEL <- "HEAVY TRUCK AND LORRY DRIVERS"

# Rank of a code in a result, or NA.
.rank_of <- function(res, code) {
  if (nrow(res$data) == 0L) return(NA_integer_)
  hit <- which(res$data$code == code)
  if (length(hit)) as.integer(hit[[1L]]) else NA_integer_
}

.psoc <- function(query, limit = 50L, ...) {
  search_classification_result("psoc", "2022", query, limit = limit, ...)
}


# ---------------------------------------------------------------------
# Exact matches stay dominant (contract 1 and 2)
# ---------------------------------------------------------------------

test_that("an exact code is still the first result", {
  res <- .psoc(TRUCK_CODE)
  expect_gt(nrow(res$data), 0L)
  expect_identical(res$data$code[[1L]], TRUCK_CODE)
  expect_identical(.rank_of(res, TRUCK_CODE), 1L)
})

test_that("an exact official title is still the first result", {
  res <- .psoc("Heavy Truck and Lorry Drivers")
  expect_identical(res$data$code[[1L]], TRUCK_CODE)
  expect_identical(res$data$label[[1L]], TRUCK_LABEL)
})

test_that("approximate retrieval can never outrank an exact code", {
  # The whole tier model rests on this. Tiers 7 and 8 are numerically below
  # tiers 1-6, so an exact code cannot be displaced by any similarity score.
  for (code in c("8332", "8331", "5211", "2221")) {
    res <- .psoc(code)
    skip_if(nrow(res$data) == 0L, paste("no rows for", code))
    expect_identical(res$data$code[[1L]], code, info = code)
  }
})

test_that("hybrid tiers do not reorder what the deterministic tiers found", {
  # For a query the old engine could already answer, hybrid and non-hybrid
  # must agree on the leading results -- the new tiers append, never
  # reshuffle.
  for (q in c("8332", "Heavy Truck and Lorry Drivers", "NURSING PROFESSIONALS")) {
    a <- .psoc(q, hybrid = FALSE)
    b <- .psoc(q, hybrid = TRUE)
    skip_if(nrow(a$data) == 0L, paste("no baseline rows for", q))
    n <- nrow(a$data)
    expect_identical(b$data$code[seq_len(n)], a$data$code, info = q)
  }
})


# ---------------------------------------------------------------------
# The reported defect and its mandated variants (contract section 13)
# ---------------------------------------------------------------------

test_that("the reported defect is fixed: 'heavy truck driver' finds 8332", {
  res <- .psoc("heavy truck driver")
  expect_gt(res$total_matches, 0L)
  expect_false(is.na(.rank_of(res, TRUCK_CODE)))
})

test_that("every mandated query variant retrieves 8332 within the top 5", {
  variants <- c(
    "heavy truck driver",
    "heavy truck drivers",
    "hevy truck driver",
    "trcuk driver"
  )
  for (q in variants) {
    res <- .psoc(q)
    rank <- .rank_of(res, TRUCK_CODE)
    expect_false(is.na(rank), info = paste(q, "-> 8332 not retrieved at all"))
    # expect_lte() takes no `info`, so make the query visible by naming it
    # in the compared value instead.
    expect_true(rank <= 5L, info = paste(q, "-> 8332 at rank", rank))
  }
})

test_that("the fix is not a hard-coded special case", {
  # The same class of query on a different occupation must work, or the
  # engine has been tuned to one example rather than fixed.
  res <- search_classification_result("psoc", "2022", "market salesperson", limit = 50L)
  expect_false(is.na(.rank_of(res, "5211")))

  res2 <- search_classification_result("psoc", "2022", "bus driver", limit = 50L)
  expect_gt(res2$total_matches, 0L)
  expect_false(is.na(.rank_of(res2, "8331")))
})

test_that("no result is invented: every code resolves in the repository", {
  # Similarity methods generate candidates; they never mint codes. Each one
  # must map back to a real (system, version, code) entry.
  for (q in c("heavy truck driver", "hevy truck driver", "trcuk driver")) {
    res <- .psoc(q, limit = 20L)
    for (code in res$data$code) {
      expect_equal(nrow(get_classification_entry("psoc", "2022", code)), 1L,
                   info = paste(q, "->", code))
    }
  }
})


# ---------------------------------------------------------------------
# Negative safety (contract: prevent broad false positives)
# ---------------------------------------------------------------------

test_that("confusable queries do not surface the truck driver code", {
  # These share a word or a character run with the official title but mean
  # something entirely different. Admitting them would be worse than a
  # miss: a plausible wrong code may simply get used.
  for (q in c("screwdriver", "heavy metal drummer")) {
    res <- .psoc(q, limit = 50L)
    expect_true(is.na(.rank_of(res, TRUCK_CODE)),
                info = paste(q, "leaked 8332"))
  }
})

test_that("'nursery' does not surface a nursing occupation", {
  res <- .psoc("nursery", limit = 50L)
  expect_true(is.na(.rank_of(res, "2221")))
})

test_that("an occupation with no authoritative code returns no false match", {
  # There is no PSOC code for this. The engine must not manufacture a
  # plausible neighbour by falling back to a generic category match (final
  # micro-gate: this used to return 2146 MINING ENGINEERS, METALLURGISTS
  # AND RELATED PROFESSIONALS on the strength of "professional"/"engineer"
  # alone, leaving "ai"/"prompt" -- the only content that actually
  # distinguishes the query -- completely unsupported).
  res <- .psoc("professional AI prompt engineer", limit = 20L)
  expect_identical(res$total_matches, 0L)
  # Whatever comes back must at least be real records, and must not claim
  # to be an exact match.
  for (code in res$data$code) {
    expect_equal(nrow(get_classification_entry("psoc", "2022", code)), 1L)
  }
})

test_that("a fabricated commodity does not surface an unrelated commodity code", {
  # "moon rock trading" (final micro-gate, found via the corrected
  # true-no-code metric on the independent holdout2 corpus): "moon" found
  # no support; "rock" and "trading" registered as "supported" purely from
  # a coincidental one-edit overlap with unrelated tokens in unrelated
  # commodity entries ("rock"~"lock", "trading"~"threading"/"heading").
  res <- search_classification_result("pscc", "2022", "moon rock trading", limit = 20L)
  expect_identical(res$total_matches, 0L)
})


# ---------------------------------------------------------------------
# Contracts that must not regress
# ---------------------------------------------------------------------

test_that("blank-query browse is unaffected by the hybrid tiers", {
  a <- .psoc("", limit = 25L, hybrid = FALSE)
  b <- .psoc("", limit = 25L, hybrid = TRUE)
  expect_identical(a$data$code, b$data$code)
  expect_identical(a$total_matches, b$total_matches)
})

test_that("the true-total contract still holds with hybrid tiers", {
  res <- .psoc("driver", limit = 5L)
  expect_equal(res$returned_count, nrow(res$data))
  expect_lte(res$returned_count, 5L)
  expect_gte(res$total_matches, res$returned_count)
  expect_equal(res$is_truncated, res$total_matches > res$returned_count)
})

test_that("level and component filters still bound the candidate pool", {
  res <- search_classification_result("psoc", "2022", "heavy truck driver",
                                      level = "minor_group", limit = 50L)
  expect_true(all(res$data$level == "minor_group"))
  # 8332 is a unit group, so the level filter must exclude it even though
  # the hybrid tier would otherwise retrieve it.
  expect_true(is.na(.rank_of(res, TRUCK_CODE)))
})

test_that("the engine degrades rather than fails when indexes are absent", {
  # An archived edition has no prebuilt index. Retrieval must still work.
  res <- search_classification_result("psoc", "2012", "heavy truck driver", limit = 20L)
  expect_false(is.null(res$data))
  expect_gte(res$total_matches, 0L)
})

test_that("the same engine serves every registered system", {
  reg <- classification_registry()
  for (i in seq_len(nrow(reg))) {
    res <- search_classification_result(reg$id[[i]], reg$current_version[[i]],
                                        "a", limit = 5L)
    expect_false(is.null(res$data), info = reg$id[[i]])
    expect_true(all(c("data", "total_matches", "returned_count",
                      "limit", "is_truncated") %in% names(res)),
                info = reg$id[[i]])
  }
})


# ---------------------------------------------------------------------
# Stale-index rejection at the runtime boundary (not just the unit-level
# fingerprint check)
# ---------------------------------------------------------------------
#
# retrieval_ngram_index_is_valid() is unit-tested directly in
# test-retrieval-ngram.R against edited/recoded/reordered/added corpora.
# What is NOT covered there is the actual RUNTIME BOUNDARY: does
# retrieval_index_for() -- the function search_classification_result()
# actually calls -- really refuse a stale artifact loaded from disk, and
# does the whole search still complete safely rather than silently
# resolving a candidate's `idx` against the wrong row?
#
# A throwaway, non-colliding system/version id is used ("__h4_stale_test__")
# so this can write and delete its own artifact under data/ without ever
# touching a real system's index -- the H4 audit for this milestone found
# that overwriting a real artifact mid-test, even temporarily, is exactly
# the kind of mistake this synthetic id is designed to make impossible.

test_that("a stale on-disk n-gram index is rejected at the runtime boundary", {
  fake_system <- "__h4_stale_test__"
  fake_version <- "v1"
  path <- sprintf("../../data/retrieval_ngram_%s_%s.rds", fake_system, fake_version)
  on.exit({
    if (file.exists(path)) file.remove(path)
    if (exists(".retrieval_index_reset_cache")) .retrieval_index_reset_cache()
  }, add = TRUE)

  old_data <- new_classification_tibble(
    system = fake_system, version = fake_version, level = "unit",
    code = c("A1", "A2", "A3"),
    label = c("Alpha Widget Maker", "Beta Widget Tester", "Gamma Widget Packer"),
    status = "current", source = "test fixture", source_url = "https://example.invalid"
  )
  new_data <- new_classification_tibble(
    system = fake_system, version = fake_version, level = "unit",
    code = c("B1", "B2"),
    label = c("Entirely Different Occupation", "Another Unrelated Role"),
    status = "current", source = "test fixture", source_url = "https://example.invalid"
  )

  old_corpus <- retrieval_corpus(old_data)
  stale_index <- retrieval_ngram_build(old_corpus, system = fake_system, version = fake_version)
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(stale_index, path)

  if (exists(".retrieval_index_reset_cache")) .retrieval_index_reset_cache()

  new_corpus <- retrieval_corpus(new_data)
  resolved <- retrieval_index_for("ngram", fake_system, fake_version, new_corpus)

  expect_null(resolved)
})

test_that("search still completes safely when its n-gram index is stale", {
  fake_system <- "__h4_stale_test2__"
  fake_version <- "v1"
  path <- sprintf("../../data/retrieval_ngram_%s_%s.rds", fake_system, fake_version)
  on.exit({
    if (file.exists(path)) file.remove(path)
    if (exists(".retrieval_index_reset_cache")) .retrieval_index_reset_cache()
  }, add = TRUE)

  old_data <- new_classification_tibble(
    system = fake_system, version = fake_version, level = "unit",
    code = "Z1", label = "Something Else Entirely",
    status = "current", source = "test fixture", source_url = "https://example.invalid"
  )
  stale_index <- retrieval_ngram_build(retrieval_corpus(old_data),
                                       system = fake_system, version = fake_version)
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(stale_index, path)
  if (exists(".retrieval_index_reset_cache")) .retrieval_index_reset_cache()

  # This system isn't in the registry, so drive the ranking function
  # directly rather than through search_classification_result() (which
  # validates against the registry first).
  real_data <- new_classification_tibble(
    system = fake_system, version = fake_version, level = "unit",
    code = c("A1", "A2"),
    label = c("Heavy Truck And Lorry Drivers", "Bus And Tram Drivers"),
    status = "current", source = "test fixture", source_url = "https://example.invalid"
  )
  loaded_stale <- retrieval_index_get("ngram", fake_system, fake_version)
  real_corpus <- retrieval_corpus(real_data)
  # The exact validation retrieval_index_for() performs, called directly so
  # the test does not depend on registry membership.
  valid <- retrieval_ngram_index_is_valid(loaded_stale, real_corpus)
  expect_false(valid)

  # And the ranking function itself never errors and never trusts a
  # rejected index -- passing it through explicitly would be a caller bug,
  # so the real safety net is that retrieval_index_for() (exercised above
  # and wired into search_classification_result()) would have supplied NULL
  # instead of `loaded_stale` here.
  result <- tryCatch(
    search_classification_data_result(real_data, "heavy truck driver", limit = 20L,
                                      hybrid = TRUE, ngram_index = NULL),
    error = function(e) e
  )
  expect_false(inherits(result, "error"))
  expect_true("A1" %in% result$data$code)
})


# ---------------------------------------------------------------------
# Cache isolation (corpus and index caches introduced by this milestone)
# ---------------------------------------------------------------------
#
# retrieval_corpus_get() and retrieval_index_for() cache by a composite key
# of system/version/component/level. A Shiny deployment runs ONE R process
# per worker serving MANY sessions across MANY systems, so a key collision
# would leak one system's candidate rows into another's results -- silently,
# since both are legitimate-looking classification rows.

test_that("querying five different systems in sequence never cross-contaminates", {
  results <- list(
    psoc  = search_classification_result("psoc", "2022", "heavy truck driver", limit = 20L),
    psic  = search_classification_result("psic", "2026", "bakery", limit = 20L),
    pscc  = search_classification_result("pscc", "2022", "race horse", limit = 20L),
    psgc  = search_classification_result("psgc", "Q2_2026", "quezon city", limit = 20L),
    ptscs = search_classification_result("ptscs", "2025-v2.1", "hotel", limit = 20L)
  )

  for (nm in names(results)) {
    r <- results[[nm]]
    if (nrow(r$data) > 0L) {
      expect_true(all(r$data$system == nm), info = nm)
    }
  }
})

test_that("a system's result is unaffected by queries against other systems in between", {
  first <- search_classification_result("psoc", "2022", "heavy truck driver", limit = 20L)

  # Deliberately interleave other systems, including composite ones, between
  # the two PSOC calls.
  invisible(search_classification_result("psic", "2026", "bakery", limit = 20L))
  invisible(search_classification_result("pscc", "2022", "race horse", limit = 20L))
  invisible(search_classification_result("pscrcs", "2025", "design", limit = 20L))

  second <- search_classification_result("psoc", "2022", "heavy truck driver", limit = 20L)

  expect_identical(first$data$code, second$data$code)
  expect_identical(first$total_matches, second$total_matches)
})

test_that("level filters on the same system never bleed into each other", {
  section_only <- search_classification_result("psic", "2026", "a",
                                                level = "section", limit = 50L)
  class_only <- search_classification_result("psic", "2026", "a",
                                              level = "class", limit = 50L)

  expect_true(all(section_only$data$level == "section"))
  expect_true(all(class_only$data$level == "class"))
  expect_length(intersect(section_only$data$code, class_only$data$code), 0L)
})

test_that("component filters on a composite system never bleed into each other", {
  comps <- classification_components("ptscs")
  skip_if(length(comps) < 2L, "PTSCS does not carry at least two components")

  a <- search_classification_result("ptscs", "2025-v2.1", "a",
                                    component = comps[[1L]], limit = 200L)
  b <- search_classification_result("ptscs", "2025-v2.1", "a",
                                    component = comps[[2L]], limit = 200L)

  expect_length(intersect(a$data$code, b$data$code), 0L)
})

test_that("the corpus cache holds one distinct entry per system/version/level/component", {
  # Populate a known set of cache keys, then confirm each is genuinely
  # distinct -- exercises the cache KEY CONSTRUCTION directly rather than
  # only its externally observable effect.
  invisible(search_classification_result("psoc", "2022", "a", limit = 1L))
  invisible(search_classification_result("psic", "2026", "a", level = "section", limit = 1L))
  invisible(search_classification_result("psic", "2026", "a", level = "class", limit = 1L))
  invisible(search_classification_result("ptscs", "2025-v2.1", "a",
                                         component = "tourism_industry", limit = 1L))
  invisible(search_classification_result("ptscs", "2025-v2.1", "a",
                                         component = "tourism_product", limit = 1L))

  corpus_keys <- grep("^corpus::", ls(.retrieval_index_cache), value = TRUE)
  expect_false(anyDuplicated(corpus_keys) > 0L)

  # The two psic level entries and the two ptscs component entries must be
  # genuinely different keys, not the same key overwritten.
  expect_true(any(grepl("^corpus::psic::2026::_all_::section::", corpus_keys)))
  expect_true(any(grepl("^corpus::psic::2026::_all_::class::", corpus_keys)))
  expect_true(any(grepl("^corpus::ptscs::2025-v2[.]1::tourism_industry::", corpus_keys)))
  expect_true(any(grepl("^corpus::ptscs::2025-v2[.]1::tourism_product::", corpus_keys)))
})


# ---------------------------------------------------------------------
# Result-count / materialization contract under hybrid retrieval
# ---------------------------------------------------------------------
#
# `tests/testthat/test-search-counts.R` established this contract for the
# pre-hybrid engine and does not exercise the tier 7/8 recall paths at all.
# These tests confirm the same contract -- true total vs. bounded, capped
# materialization -- holds when hybrid-tier rows are what fills the count.

test_that("total_matches counts hybrid-tier rows, not just the deterministic tiers", {
  # "heavy truck driver" only matches PSOC through tiers 7/8 (token-AND and
  # fused fuzzy/n-gram) -- there is no exact/prefix/substring hit at all.
  res <- search_classification_result("psoc", "2022", "heavy truck driver", limit = 200L)

  expect_gt(res$total_matches, 0L)
  expect_equal(res$returned_count, nrow(res$data))
  expect_equal(res$total_matches, res$returned_count)
  expect_false(res$is_truncated)
})

test_that("a hybrid-filled page still reports truncation honestly", {
  # A broad token-AND query on a small system: force `limit` well below the
  # true match count so tier 7/8 rows are what get truncated.
  res <- search_classification_result("psoc", "2022", "driver", limit = 3L)

  expect_equal(nrow(res$data), 3L)
  expect_gt(res$total_matches, 3L)
  expect_true(res$is_truncated)
  expect_equal(res$is_truncated, res$total_matches > res$returned_count)
})

test_that("a genuine zero-match query reports zero, not a false hybrid hit", {
  res <- search_classification_result("psoc", "2022", "qqqxzzvwk", limit = 200L)

  expect_equal(res$total_matches, 0L)
  expect_equal(nrow(res$data), 0L)
  expect_false(res$is_truncated)
})

test_that("blank-query browse totals are identical with hybrid on or off", {
  # Browse mode returns before the hybrid tiers are ever reached, so the
  # hybrid flag must have no effect on it whatsoever.
  on <- search_classification_result("psoc", "2022", "", limit = 200L, hybrid = TRUE)
  off <- search_classification_result("psoc", "2022", "", limit = 200L, hybrid = FALSE)

  expect_identical(on$total_matches, off$total_matches)
  expect_identical(on$data$code, off$data$code)
})

test_that("the 200-row materialization cap still bounds a large hybrid result", {
  # PSCC (24,180 docs) with a broad query that hybrid tiers expand well
  # past the default page size.
  res <- search_classification_result("pscc", "2022", "animal", limit = 200L)

  expect_lte(nrow(res$data), 200L)
  expect_equal(res$returned_count, nrow(res$data))
  expect_equal(res$is_truncated, res$total_matches > res$returned_count)
})


# ---------------------------------------------------------------------
# Server-computed rank must survive to the displayed table
# (pre-commit retrieval hardening audit, H12)
# ---------------------------------------------------------------------
#
# LIVE BROWSER FINDING: for an exact-title query ("Heavy Truck and Lorry
# Drivers"), search_classification_result() correctly ranks 8332 (tier 3,
# exact normalized label) ahead of 833 (tier 8, a hybrid-tier match on the
# sibling "HEAVY TRUCK AND BUS DRIVERS"). Before hybrid retrieval, an exact-
# title query always returned exactly ONE row, so this was never visible.
# Adding hybrid tiers can now add a second, lower-relevance row underneath
# an exact match -- and DataTables' own default behaviour is an initial
# ascending sort on column 0 as a STRING, so "833" (a lexicographic prefix
# of "8332") displayed ABOVE "8332" despite the server ranking it second.
# The server's own `data` was correct throughout; only the widget's default
# re-sort was wrong. Fixed in app.R by adding `order = list()` to the
# DT::datatable() options for both `classification_results` and the dual-
# search results tables, which disables DataTables' initial sort while
# leaving column-header click-to-sort available.
#
# These tests can't drive an actual DT widget without a running Shiny
# session, so they pin the two structural properties that make the fix
# correct: (1) the server's `data` frame itself is in rank order -- which
# every other test in this file already establishes -- and (2) app.R's own
# source literally disables DT's default sort on exactly the two tables fed
# by the hybrid engine, so the fix cannot silently regress if that code is
# touched again without re-reading this comment.

test_that("app.R disables DT's default sort on both hybrid-fed result tables", {
  path <- testthat::test_path("..", "..", "app.R")
  skip_if_not(file.exists(path))
  src <- readLines(path, warn = FALSE)

  # Every DT::datatable() options block that sets dom = "tip" (the pattern
  # used by both the Search and dual-search results tables) must also set
  # order = list() -- i.e. no options block may combine dom = "tip" without
  # order = list() anywhere near it. Compare-Editions' correspondence table
  # uses the same dom = "tip" pattern but is NOT fed by the hybrid engine
  # (it is PSIC correspondence data) and is intentionally left alone; this
  # test only requires that at least two such blocks exist with the fix,
  # matching the Search and dual-search tables.
  fixed_blocks <- sum(grepl('dom = "tip", order = list\\(\\)', src))
  expect_gte(fixed_blocks, 2L)
})

test_that("an exact-title query's server-side rank puts the exact match first", {
  # This is the property the DT fix relies on: if the SERVER ever stopped
  # ranking the exact match first, no widget-side fix could compensate.
  res <- .psoc("Heavy Truck and Lorry Drivers", limit = 50L)
  expect_gte(nrow(res$data), 1L)
  expect_identical(res$data$code[[1L]], TRUCK_CODE)

  # And through the dual-search wrapper specifically, since that is the
  # second table the fix applies to.
  if (exists("dual_search_side_result")) {
    dual <- dual_search_side_result("psoc", "2022", "Heavy Truck and Lorry Drivers", limit = 50L)
    expect_identical(dual$data$code[[1L]], TRUCK_CODE)
  }
})


# ---------------------------------------------------------------------
# Evidence-sufficiency: the failure SHAPE, not the five diagnosed phrases
# ---------------------------------------------------------------------
#
# The convergence-phase fix (R/retrieval/retrieval_evidence.R) targets a
# general shape -- a single strongly-matched token carrying an otherwise
# unsupported multi-token query over threshold -- not the five specific
# audit phrases (electrician's tape / carpenter ant / security blanket /
# welder's mask / tailor-made suit). These cases are freshly constructed,
# not present in the audit, the dev corpus, or either holdout set, to prove
# the rule generalizes rather than having been tuned to the named examples.

test_that("a fresh single strong-title-token + unrelated word abstains", {
  # Each shares exactly one meaningful token with a real PSOC title but
  # names an unrelated object, not the occupation.
  for (q in c("cook's apron", "farmer's almanac", "driver's seat cover",
              "plumber's crack", "mechanic's overalls", "fisherman's wharf",
              "miner's lamp", "waiter's tray")) {
    res <- .psoc(q, limit = 50L)
    expect_identical(res$total_matches, 0L, info = q)
  }
})

test_that("a fresh multi-token query with multiple supported concepts still resolves", {
  res <- .psoc("truck and lorry driver", limit = 20L)
  expect_false(is.na(.rank_of(res, TRUCK_CODE)))

  res2 <- .psoc("bus and coach driver", limit = 20L)
  expect_gt(res2$total_matches, 0L)
  expect_false(is.na(.rank_of(res2, "8331")))
})

test_that("a fresh double-typo multi-token query still resolves via fuzzy sub-matching", {
  res <- .psoc("hevy truk driver", limit = 20L)
  expect_false(is.na(.rank_of(res, TRUCK_CODE)))
})

test_that("a fresh single-token typo on a single-meaningful-token query still resolves", {
  res <- .psoc("wielder", limit = 20L)
  expect_gt(res$total_matches, 0L)

  res2 <- .psoc("carpentar", limit = 20L)
  expect_false(is.na(.rank_of(res2, "7115")))
})

test_that("code-shaped queries stay excluded from approximate retrieval and never leak", {
  for (q in c("12345678", "0000")) {
    res <- .psoc(q, limit = 20L)
    expect_identical(res$total_matches, 0L, info = q)
  }
})

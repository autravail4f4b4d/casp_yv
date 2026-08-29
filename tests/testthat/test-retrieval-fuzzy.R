# Fuzzy retrieval tier: token-level approximate matching.
#
# The corpus here is synthetic and tiny on purpose. The point of this tier
# is a scoring/bounding contract, not the content of PSOC 2022, and loading
# the real 24k-row artifacts would make the suite slow without testing
# anything the synthetic corpus does not.

fz_corpus <- function(labels, codes = NULL) {
  if (is.null(codes)) codes <- sprintf("%04d", seq_along(labels))
  retrieval_corpus(data.frame(
    code = codes, label = labels, stringsAsFactors = FALSE
  ))
}

FZ_LABELS <- c(
  "HEAVY TRUCK AND LORRY DRIVERS",
  "BUS AND TRAM DRIVERS",
  "CAR, TAXI AND VAN DRIVERS",
  "STALL AND MARKET SALESPERSONS",
  "NURSING PROFESSIONALS"
)
FZ_TRUCK <- 1L
FZ_BUS <- 2L
FZ_CAR <- 3L
FZ_NURSE <- 5L

fz_rank_of <- function(res, i) {
  hit <- res$rank[res$idx == i]
  if (length(hit) == 0L) NA_integer_ else hit[1]
}

# --- the defect this tier exists to fix -----------------------------------

test_that("word-order and interposed-word queries reach the heavy truck entry", {
  corpus <- fz_corpus(FZ_LABELS)

  # "HEAVY TRUCK AND LORRY DRIVERS" is not a superstring of any of these,
  # which is precisely why the literal-containment engine missed them.
  for (q in c("heavy truck driver", "heavy truck drivers",
              "hevy truck driver", "trcuk driver")) {
    res <- retrieval_fuzzy_candidates(q, corpus)
    expect_true(FZ_TRUCK %in% res$idx, info = q)
    expect_equal(fz_rank_of(res, FZ_TRUCK), 1L, info = q)
  }
})

test_that("the heavy truck entry outranks the other driver entries", {
  corpus <- fz_corpus(FZ_LABELS)

  for (q in c("heavy truck driver", "heavy truck drivers",
              "hevy truck driver", "trcuk driver")) {
    res <- retrieval_fuzzy_candidates(q, corpus)
    truck_score <- res$score[res$idx == FZ_TRUCK]

    for (other in c(FZ_BUS, FZ_CAR)) {
      other_score <- res$score[res$idx == other]
      if (length(other_score) == 0L) next
      expect_gt(truck_score, other_score)
    }
  }
})

test_that("a typo'd token still matches through the edit budget", {
  corpus <- fz_corpus(FZ_LABELS)

  # "hevy" -> "heavy" is one deletion; "trcuk" -> "truck" is one ADJACENT
  # TRANSPOSITION, which plain Levenshtein charges 2 and OSA charges 1.
  expect_equal(.retrieval_osa("hevy", "heavy"), 1L)
  expect_equal(.retrieval_osa("trcuk", "truck"), 1L)
  expect_equal(.retrieval_osa("truck", "truck"), 0L)

  clean <- retrieval_fuzzy_candidates("heavy truck driver", corpus)
  typo <- retrieval_fuzzy_candidates("hevy truck driver", corpus)

  # A typo must cost something, but must not cost the match.
  expect_equal(fz_rank_of(typo, FZ_TRUCK), 1L)
  expect_lt(typo$score[typo$idx == FZ_TRUCK], clean$score[clean$idx == FZ_TRUCK])
})

test_that("coverage weighting favours documents matching more query tokens", {
  corpus <- fz_corpus(FZ_LABELS)
  res <- retrieval_fuzzy_candidates("heavy truck driver", corpus)

  # Truck doc matches all three tokens; bus/car match only "driver".
  expect_equal(res$score[res$idx == FZ_TRUCK], 1)
  bus <- res$score[res$idx == FZ_BUS]
  expect_true(length(bus) == 1L && bus < 0.5)
})

# --- discrimination -------------------------------------------------------

test_that("an unrelated query does not surface the truck entry above the match", {
  corpus <- fz_corpus(FZ_LABELS)
  res <- retrieval_fuzzy_candidates("nursing", corpus)

  expect_equal(fz_rank_of(res, FZ_NURSE), 1L)

  truck_rank <- fz_rank_of(res, FZ_TRUCK)
  expect_true(is.na(truck_rank) || truck_rank > fz_rank_of(res, FZ_NURSE))
})

test_that("gibberish does not return the whole corpus", {
  corpus <- fz_corpus(FZ_LABELS)
  res <- retrieval_fuzzy_candidates("zzzqqqxx", corpus)

  expect_lt(nrow(res), corpus$n)
  expect_equal(nrow(res), 0L)
})

test_that("gibberish stays bounded on a larger corpus too", {
  labels <- c(FZ_LABELS, paste("GENERAL OFFICE CLERK GRADE", 1:200))
  corpus <- fz_corpus(labels)
  res <- retrieval_fuzzy_candidates("zzzqqqxx wwwvvvuu", corpus)

  expect_lt(nrow(res), corpus$n / 2)
})

# --- degenerate input -----------------------------------------------------

test_that("blank, NA and empty-corpus inputs return an empty candidate frame", {
  corpus <- fz_corpus(FZ_LABELS)
  empty <- retrieval_corpus(data.frame(
    code = character(0), label = character(0), stringsAsFactors = FALSE
  ))

  cases <- list(
    retrieval_fuzzy_candidates("", corpus),
    retrieval_fuzzy_candidates("   ", corpus),
    retrieval_fuzzy_candidates(NA, corpus),
    retrieval_fuzzy_candidates(NA_character_, corpus),
    retrieval_fuzzy_candidates(character(0), corpus),
    retrieval_fuzzy_candidates("!!! ---", corpus),
    retrieval_fuzzy_candidates("heavy truck driver", empty),
    retrieval_fuzzy_candidates("heavy truck driver", NULL)
  )

  for (res in cases) {
    expect_s3_class(res, "data.frame")
    expect_equal(nrow(res), 0L)
    expect_named(res, c("idx", "score", "rank"))
  }
})

# --- output contract ------------------------------------------------------

test_that("the candidate frame obeys the shared contract", {
  corpus <- fz_corpus(FZ_LABELS)
  res <- retrieval_fuzzy_candidates("heavy truck driver", corpus)

  expect_named(res, c("idx", "score", "rank"))
  expect_type(res$idx, "integer")
  expect_type(res$score, "double")
  expect_gt(nrow(res), 0L)

  expect_equal(res$rank, seq_len(nrow(res)))
  expect_equal(res$rank[1], 1L)
  expect_false(is.unsorted(rev(res$score)))

  expect_false(any(is.na(res$score)))
  expect_true(all(res$score >= 0))
  expect_true(all(res$score <= 1))
})

test_that("top_k is respected", {
  labels <- c(FZ_LABELS, paste("DELIVERY TRUCK DRIVER GRADE", 1:60))
  corpus <- fz_corpus(labels)

  full <- retrieval_fuzzy_candidates("truck driver", corpus, top_k = 50L)
  small <- retrieval_fuzzy_candidates("truck driver", corpus, top_k = 3L)

  expect_lte(nrow(full), 50L)
  expect_equal(nrow(small), 3L)
  expect_equal(small$rank, 1:3)
  expect_equal(small$idx, full$idx[1:3])
})

test_that("results are deterministic across identical calls", {
  labels <- c(FZ_LABELS, paste("HEAVY TRUCK DRIVER VARIANT", 1:40))
  corpus <- fz_corpus(labels)

  a <- retrieval_fuzzy_candidates("hevy truck driver", corpus)
  b <- retrieval_fuzzy_candidates("hevy truck driver", corpus)
  expect_identical(a, b)
})

test_that("an explicit max_distance overrides the length-derived budget", {
  corpus <- fz_corpus(FZ_LABELS)

  strict <- retrieval_fuzzy_candidates("hevy truck driver", corpus, max_distance = 0L)
  loose <- retrieval_fuzzy_candidates("hevy truck driver", corpus)

  # With no edit budget, "hevy" contributes nothing, so the score drops.
  expect_lt(
    strict$score[strict$idx == FZ_TRUCK],
    loose$score[loose$idx == FZ_TRUCK]
  )
})

test_that("very short tokens are matched exactly, never approximately", {
  corpus <- fz_corpus(c("VAN DRIVERS", "BUS DRIVERS"))

  # "van" (3 chars) may take one edit; "vn" (2 chars) may take none, so it
  # must not drag in every two-letter neighbour.
  expect_equal(.retrieval_fuzzy_budget(c(2L, 3L, 4L, 5L, 8L, 9L, 14L)),
               c(0L, 1L, 1L, 2L, 2L, 3L, 3L))
})

test_that("a code-like query is matched against the code key", {
  corpus <- fz_corpus(FZ_LABELS, codes = c("8332", "8331", "8322", "5211", "2221"))

  res <- retrieval_fuzzy_candidates("8332", corpus)
  expect_equal(fz_rank_of(res, FZ_TRUCK), 1L)
  expect_equal(res$score[res$idx == FZ_TRUCK], 1)
})

# --- bounded work ---------------------------------------------------------

test_that("a query over a 5,000-row corpus completes well inside the budget", {
  set.seed(42)
  head_words <- c("HEAVY", "LIGHT", "GENERAL", "SENIOR", "JUNIOR", "ASSISTANT",
                  "CHIEF", "SPECIALIST", "TECHNICAL", "ADMINISTRATIVE")
  mid_words <- c("TRUCK", "MARKET", "NURSING", "FINANCE", "PRODUCTION",
                 "MAINTENANCE", "TRANSPORT", "RETAIL", "AGRICULTURAL", "MINING")
  tail_words <- c("DRIVERS", "OPERATORS", "CLERKS", "SUPERVISORS", "LABOURERS",
                  "PROFESSIONALS", "TECHNICIANS", "SALESPERSONS", "MANAGERS",
                  "WORKERS")

  labels <- paste(
    sample(head_words, 5000, replace = TRUE),
    sample(mid_words, 5000, replace = TRUE),
    "AND", sample(mid_words, 5000, replace = TRUE),
    sample(tail_words, 5000, replace = TRUE),
    "N.E.C."
  )
  labels[1] <- "HEAVY TRUCK AND LORRY DRIVERS"
  corpus <- fz_corpus(labels)

  # Warm any lazily-resolved namespaces first so the measurement is of the
  # retrieval work, not of R's first-call overhead.
  invisible(retrieval_fuzzy_candidates("warm up query", corpus))

  elapsed <- system.time({
    res <- retrieval_fuzzy_candidates("hevy trcuk driver", corpus)
  })[["elapsed"]]

  expect_lt(elapsed, 2)
  expect_true(1L %in% res$idx)
  expect_lte(nrow(res), 50L)
})

# Character n-gram TF-IDF cosine tier.
#
# Everything here runs on small synthetic corpora. The real PSCC corpus is
# 24,180 rows and building an index over it takes seconds; a unit test that
# loads it would be measuring the artifact loader, not this tier. The one
# scale claim that does need evidence -- that the index is sparse and not
# an accidental dense matrix -- is made against a generated 5,000-row
# corpus at the bottom of the file.

# The driver family is the whole reason this tier exists: "heavy truck
# driver" has to reach "HEAVY TRUCK AND LORRY DRIVERS" across the
# interposed "and lorry", and it has to beat two sibling titles that share
# the word "drivers" with it.
ngram_fixture <- function() {
  data.frame(
    code = c("8332", "8331", "8322", "2221", "5211"),
    label = c(
      "HEAVY TRUCK AND LORRY DRIVERS",
      "BUS AND TRAM DRIVERS",
      "CAR, TAXI AND VAN DRIVERS",
      "NURSING PROFESSIONALS",
      "STALL AND MARKET SALESPERSONS"
    ),
    stringsAsFactors = FALSE
  )
}

HEAVY_TRUCK_ROW <- 1L

ngram_fixture_index <- function(...) {
  retrieval_ngram_build(retrieval_corpus(ngram_fixture()), ...)
}

test_that("the index reports a coherent shape for its corpus", {
  corpus <- retrieval_corpus(ngram_fixture())
  index <- retrieval_ngram_build(corpus)

  expect_s3_class(index, "retrieval_ngram_index")
  expect_identical(index$n_docs, 5L)
  expect_identical(index$n_min, 3L)
  expect_identical(index$n_max, 5L)
  expect_gt(index$n_grams, 0L)
  # CSR offsets: one per gram plus the terminating offset, and the last
  # offset must land exactly one past the final posting.
  expect_identical(length(index$gram_start), index$n_grams + 1L)
  expect_identical(index$gram_start[[index$n_grams + 1L]],
                   as.integer(index$n_postings + 1L))
  expect_identical(length(index$post_doc), index$n_postings)
  expect_identical(length(index$post_w), index$n_postings)
  expect_identical(length(index$doc_norm), 5L)
  expect_true(all(index$doc_norm > 0))
})

test_that("'heavy truck driver' ranks the heavy-truck title first", {
  index <- ngram_fixture_index()
  cand <- retrieval_ngram_candidates("heavy truck driver", index)

  expect_gt(nrow(cand), 0L)
  expect_identical(cand$idx[[1L]], HEAVY_TRUCK_ROW)
})

test_that("the plural query form ranks it first too", {
  index <- ngram_fixture_index()
  cand <- retrieval_ngram_candidates("heavy truck drivers", index)

  expect_gt(nrow(cand), 0L)
  expect_identical(cand$idx[[1L]], HEAVY_TRUCK_ROW)
})

test_that("singular and plural queries agree exactly", {
  # retrieval_normalize_tokens() folds the plural before the grams are
  # cut, so these must not merely rank the same -- they must be the same
  # query.
  index <- ngram_fixture_index()
  expect_equal(
    retrieval_ngram_candidates("heavy truck driver", index),
    retrieval_ngram_candidates("heavy truck drivers", index)
  )
})

test_that("partial wording still retrieves the title", {
  index <- ngram_fixture_index()
  cand <- retrieval_ngram_candidates("lorry drivers", index)

  expect_gt(nrow(cand), 0L)
  expect_identical(cand$idx[[1L]], HEAVY_TRUCK_ROW)
})

test_that("an unrelated query does not surface the heavy-truck title first", {
  index <- ngram_fixture_index()

  nursing <- retrieval_ngram_candidates("nurse", index)
  expect_gt(nrow(nursing), 0L)
  expect_identical(nursing$idx[[1L]], 4L)
  expect_false(identical(nursing$idx[[1L]], HEAVY_TRUCK_ROW))

  market <- retrieval_ngram_candidates("market stall salesperson", index)
  expect_gt(nrow(market), 0L)
  expect_identical(market$idx[[1L]], 5L)
})

test_that("the exact official title scores at or near the ceiling", {
  index <- ngram_fixture_index()
  cand <- retrieval_ngram_candidates("HEAVY TRUCK AND LORRY DRIVERS", index)

  expect_identical(cand$idx[[1L]], HEAVY_TRUCK_ROW)
  expect_gt(cand$score[[1L]], 0.99)
  expect_lte(cand$score[[1L]], 1)
})

test_that("the candidate frame obeys the shared contract", {
  index <- ngram_fixture_index()
  cand <- retrieval_ngram_candidates("driver", index)

  expect_named(cand, c("idx", "score", "rank"))
  expect_type(cand$idx, "integer")
  expect_type(cand$score, "double")
  expect_gt(nrow(cand), 1L)

  # Scores are cosines: bounded, and non-increasing down the list.
  expect_true(all(cand$score >= 0 & cand$score <= 1))
  expect_false(is.unsorted(rev(cand$score)))

  # Dense ranks from 1.
  expect_identical(cand$rank, seq_len(nrow(cand)))
})

test_that("top_k truncates and min_score filters", {
  index <- ngram_fixture_index()

  all_hits <- retrieval_ngram_candidates("driver", index, top_k = 50L)
  expect_gte(nrow(all_hits), 3L)

  capped <- retrieval_ngram_candidates("driver", index, top_k = 2L)
  expect_identical(nrow(capped), 2L)
  expect_identical(capped$idx, all_hits$idx[1:2])
  expect_identical(capped$rank, 1:2)

  # A threshold set just under the leader must keep the leader alone.
  threshold <- all_hits$score[[1L]] - 1e-9
  filtered <- retrieval_ngram_candidates("driver", index, min_score = threshold)
  expect_identical(nrow(filtered), 1L)
  expect_identical(filtered$idx[[1L]], all_hits$idx[[1L]])

  # An unreachable threshold empties the set without erroring.
  none <- retrieval_ngram_candidates("driver", index, min_score = 1.5)
  expect_identical(nrow(none), 0L)
  expect_named(none, c("idx", "score", "rank"))
})

test_that("degenerate queries return an empty candidate set, never an error", {
  index <- ngram_fixture_index()

  for (q in list("", "   ", NA_character_, NA, character(0), NULL, "...", "!!")) {
    cand <- retrieval_ngram_candidates(q, index)
    expect_s3_class(cand, "data.frame")
    expect_identical(nrow(cand), 0L)
    expect_named(cand, c("idx", "score", "rank"))
  }
})

test_that("a query with no shared gram returns an empty set", {
  index <- ngram_fixture_index()
  cand <- retrieval_ngram_candidates("zzqx wvkj", index)
  expect_identical(nrow(cand), 0L)
})

test_that("an empty corpus builds and queries cleanly", {
  empty <- retrieval_corpus(NULL)
  index <- retrieval_ngram_build(empty)

  expect_s3_class(index, "retrieval_ngram_index")
  expect_identical(index$n_docs, 0L)
  expect_identical(index$n_grams, 0L)

  cand <- retrieval_ngram_candidates("heavy truck driver", index)
  expect_identical(nrow(cand), 0L)
  expect_named(cand, c("idx", "score", "rank"))

  # A zero-row data.frame is the other way an empty corpus arrives.
  zero <- retrieval_corpus(data.frame(code = character(0), label = character(0)))
  expect_identical(retrieval_ngram_build(zero)$n_docs, 0L)
})

test_that("a corpus of blank labels keeps its documents but retrieves nothing", {
  blank <- retrieval_corpus(
    data.frame(code = c("a", "b"), label = c("", NA_character_),
               stringsAsFactors = FALSE)
  )
  index <- retrieval_ngram_build(blank)

  expect_identical(index$n_docs, 2L)
  expect_identical(nrow(retrieval_ngram_candidates("driver", index)), 0L)
})

test_that("a non-index argument is handled rather than thrown", {
  expect_identical(nrow(retrieval_ngram_candidates("driver", NULL)), 0L)
  expect_identical(nrow(retrieval_ngram_candidates("driver", list())), 0L)
})

test_that("results are deterministic across calls and across rebuilds", {
  index_a <- ngram_fixture_index()
  index_b <- ngram_fixture_index()

  first <- retrieval_ngram_candidates("heavy truck driver", index_a)
  second <- retrieval_ngram_candidates("heavy truck driver", index_a)
  expect_identical(first, second)

  # Same corpus, independently built index -> identical output.
  expect_identical(first, retrieval_ngram_candidates("heavy truck driver", index_b))
  expect_identical(index_a$vocab, index_b$vocab)
  expect_equal(index_a$post_w, index_b$post_w)
})

test_that("ties break on corpus order, so ordering is reproducible", {
  # Two identical labels can only be separated by the deterministic
  # tie-break in retrieval_candidates(), which is ascending idx.
  twins <- retrieval_corpus(
    data.frame(code = c("x1", "x2"), label = c("DELIVERY DRIVERS", "DELIVERY DRIVERS"),
               stringsAsFactors = FALSE)
  )
  index <- retrieval_ngram_build(twins)
  cand <- retrieval_ngram_candidates("delivery driver", index)

  expect_identical(cand$idx, c(1L, 2L))
  expect_equal(cand$score[[1L]], cand$score[[2L]])
})

test_that("the n range is configurable and recorded", {
  index <- ngram_fixture_index(n_min = 4L, n_max = 4L)

  expect_identical(index$n_min, 4L)
  expect_identical(index$n_max, 4L)
  expect_identical(index$meta$n_min, 4L)
  expect_true(all(nchar(index$vocab) == 4L))
  expect_identical(
    retrieval_ngram_candidates("heavy truck driver", index)$idx[[1L]],
    HEAVY_TRUCK_ROW
  )

  expect_error(ngram_fixture_index(n_min = 5L, n_max = 3L))
  expect_error(ngram_fixture_index(n_min = 0L))
})

test_that("the index records the system and version it was built for", {
  index <- ngram_fixture_index(system = "psoc", version = "2022")

  expect_identical(index$meta$system, "psoc")
  expect_identical(index$meta$version, "2022")
  expect_identical(index$meta$n_docs, 5L)
  expect_type(index$meta$fingerprint, "character")
})

test_that("the index records a supported schema version", {
  index <- ngram_fixture_index(system = "psoc", version = "2022")

  expect_identical(index$meta$index_schema_version, RETRIEVAL_NGRAM_SCHEMA_VERSION)
  expect_true(index$meta$index_schema_version %in% RETRIEVAL_NGRAM_SUPPORTED_SCHEMA_VERSIONS)
})

test_that("index validity rejects a missing or unsupported schema version", {
  corpus <- retrieval_corpus(ngram_fixture())
  index <- retrieval_ngram_build(corpus)
  expect_true(retrieval_ngram_index_is_valid(index, corpus))

  missing_schema <- index
  missing_schema$meta$index_schema_version <- NULL
  expect_false(retrieval_ngram_index_is_valid(missing_schema, corpus))

  future_schema <- index
  future_schema$meta$index_schema_version <- max(RETRIEVAL_NGRAM_SUPPORTED_SCHEMA_VERSIONS) + 1L
  expect_false(retrieval_ngram_index_is_valid(future_schema, corpus))

  zero_schema <- index
  zero_schema$meta$index_schema_version <- 0L
  expect_false(retrieval_ngram_index_is_valid(zero_schema, corpus))
})

test_that("index validity tracks the corpus it was built from", {
  corpus <- retrieval_corpus(ngram_fixture())
  index <- retrieval_ngram_build(corpus)

  expect_true(retrieval_ngram_index_is_valid(index, corpus))
  expect_true(retrieval_ngram_index_is_valid(index, retrieval_corpus(ngram_fixture())))

  # A changed label.
  edited <- ngram_fixture()
  edited$label[[2L]] <- "BUS AND COACH DRIVERS"
  expect_false(retrieval_ngram_index_is_valid(index, retrieval_corpus(edited)))

  # A changed code, labels untouched: idx would now resolve to a
  # different record, so the index is stale even though the text matches.
  recoded <- ngram_fixture()
  recoded$code[[3L]] <- "8399"
  expect_false(retrieval_ngram_index_is_valid(index, retrieval_corpus(recoded)))

  # Reordered rows, same content.
  reordered <- ngram_fixture()[c(2L, 1L, 3L, 4L, 5L), , drop = FALSE]
  expect_false(retrieval_ngram_index_is_valid(index, retrieval_corpus(reordered)))

  # An added row, and a removed one.
  added <- rbind(ngram_fixture(),
                 data.frame(code = "9999", label = "NEW ENTRY",
                            stringsAsFactors = FALSE))
  expect_false(retrieval_ngram_index_is_valid(index, retrieval_corpus(added)))
  expect_false(retrieval_ngram_index_is_valid(index,
                                              retrieval_corpus(ngram_fixture()[-1L, ])))

  # Malformed inputs are FALSE, not an error.
  expect_false(retrieval_ngram_index_is_valid(NULL, corpus))
  expect_false(retrieval_ngram_index_is_valid(list(), corpus))
  expect_false(retrieval_ngram_index_is_valid(index, NULL))
  expect_false(retrieval_ngram_index_is_valid(index, list()))
})

test_that("a saved and reloaded index still queries identically", {
  # The gram -> id lookup is an environment; if it did not survive
  # serialization the build script's artifacts would be useless.
  index <- ngram_fixture_index(system = "psoc", version = "2022")
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(index, path)
  restored <- readRDS(path)

  expect_identical(
    retrieval_ngram_candidates("heavy truck driver", index),
    retrieval_ngram_candidates("heavy truck driver", restored)
  )
  expect_true(retrieval_ngram_index_is_valid(restored, retrieval_corpus(ngram_fixture())))
})

test_that("a 5,000-row corpus builds and queries in well under 5 seconds", {
  # The guard against an accidental dense n_docs x n_grams matrix: at this
  # size that would be roughly 5,000 x 25,000 doubles (~1 GB) and would
  # blow the budget long before the assertion.
  n <- 5000L
  heads <- c("HEAVY", "LIGHT", "BUS", "TRAM", "CAR", "TAXI", "VAN", "SHIP",
             "TRAIN", "CRANE")
  mids <- c("TRUCK", "LORRY", "TRAILER", "FREIGHT", "CARGO", "PASSENGER",
            "DELIVERY", "HAULAGE", "TRANSPORT", "LOGISTICS")
  tails <- c("DRIVERS", "OPERATORS", "ATTENDANTS", "HANDLERS", "SUPERVISORS",
             "MECHANICS", "INSPECTORS", "CLERKS", "LOADERS", "DISPATCHERS")

  i <- seq_len(n)
  synthetic <- data.frame(
    code = sprintf("%05d", i),
    label = paste(
      heads[(i - 1L) %% length(heads) + 1L],
      mids[((i - 1L) %/% 10L) %% length(mids) + 1L],
      tails[((i - 1L) %/% 100L) %% length(tails) + 1L],
      sprintf("GROUP %d", i)
    ),
    stringsAsFactors = FALSE
  )

  started <- Sys.time()
  corpus <- retrieval_corpus(synthetic)
  index <- retrieval_ngram_build(corpus, system = "synthetic", version = "test")
  cand <- retrieval_ngram_candidates("heavy truck driver", index, top_k = 50L)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))

  expect_identical(index$n_docs, n)
  expect_identical(nrow(cand), 50L)
  expect_true(all(cand$score > 0 & cand$score <= 1))
  expect_lt(elapsed, 5)

  # Sparsity, stated as a fact rather than inferred from the clock: the
  # postings must be a small fraction of the dense cell count.
  expect_lt(index$n_postings, 0.05 * as.numeric(index$n_docs) * index$n_grams)
})

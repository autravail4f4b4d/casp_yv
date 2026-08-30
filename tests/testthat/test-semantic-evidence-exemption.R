# W6 -- admitting a semantic candidate past the LEXICAL evidence gate.
#
# The gate (retrieval_evidence.R) asks whether a candidate's label carries
# most of the query's own words. A semantic candidate is lexically
# disjoint by definition, so before this exemption existed the semantic
# tier was structurally inert: measured with a PERFECT encoder, Recall@10
# was identical with semantic off, mocked and oracle, because every
# semantically-retrieved row was dropped at the gate.
#
# The exemption is deliberately narrow and OFF unless a caller opts in.

test_that("nothing is exempt by default -- the gate is unchanged", {
  corpus <- retrieval_corpus(data.frame(
    code  = c("1", "2"),
    label = c("RUBBER PRODUCTS MACHINE OPERATORS", "BAKERS AND PASTRY COOKS"),
    stringsAsFactors = FALSE
  ))
  cands <- data.frame(idx = c(1L, 2L), score = c(0.9, 0.8), rank = 1:2)
  out <- retrieval_evidence_filter(cands, retrieval_tokens("vulcanizer")[[1L]], corpus)
  expect_equal(nrow(out), 0L)
})

test_that("an exempt idx bypasses the gate while every other row is still judged", {
  corpus <- retrieval_corpus(data.frame(
    code  = c("1", "2"),
    label = c("RUBBER PRODUCTS MACHINE OPERATORS", "BAKERS AND PASTRY COOKS"),
    stringsAsFactors = FALSE
  ))
  cands <- data.frame(idx = c(1L, 2L), score = c(0.9, 0.8), rank = 1:2)
  out <- retrieval_evidence_filter(cands, retrieval_tokens("vulcanizer")[[1L]],
                                   corpus, exempt = 1L)
  expect_equal(nrow(out), 1L)
  expect_equal(out$idx, 1L)
  # Densely re-ranked from 1, same as the unexempted path.
  expect_equal(out$rank, 1L)
})

test_that("the exemption threshold admits only high-confidence semantic rows", {
  strong <- data.frame(idx = c(3L, 7L), score = c(0.97, 0.55), rank = 1:2)
  expect_identical(.retrieval_semantic_exempt(strong), 3L)

  weak <- data.frame(idx = c(4L), score = c(0.10), rank = 1L)
  expect_identical(.retrieval_semantic_exempt(weak), integer(0))
})

test_that("no semantic tier means no exemption at all", {
  expect_identical(.retrieval_semantic_exempt(NULL), integer(0))
  expect_identical(.retrieval_semantic_exempt(data.frame()), integer(0))
  # A malformed tier must not error and must not exempt anything.
  expect_identical(.retrieval_semantic_exempt(data.frame(a = 1)), integer(0))
  expect_identical(
    .retrieval_semantic_exempt(data.frame(idx = 1L, score = NA_real_)),
    integer(0)
  )
})

test_that("the threshold is conservative enough to require near-exact semantic agreement", {
  # Guards against a future edit quietly loosening the value that is
  # currently protecting the negative-safety corpus.
  expect_gte(RETRIEVAL_MIN_SEMANTIC_EXEMPT, 0.85)
})

test_that("with semantic retrieval disabled, hybrid retrieval is byte-identical", {
  # The default path passes no embedding index, so the exemption computes
  # to integer(0) and nothing about existing behaviour changes.
  skip_if_not(exists("retrieval_hybrid_candidates", mode = "function"))
  corpus <- retrieval_corpus(data.frame(
    code  = c("1", "2", "3"),
    label = c("HEAVY TRUCK AND LORRY DRIVERS", "BUS AND TRAM DRIVERS",
              "BAKERS AND PASTRY COOKS"),
    stringsAsFactors = FALSE
  ))
  a <- retrieval_hybrid_candidates("truck driver", corpus)
  b <- retrieval_hybrid_candidates("truck driver", corpus, embedding_index = NULL)
  expect_identical(a, b)
})

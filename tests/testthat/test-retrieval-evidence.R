# Unit-level tests for the approximate-match evidence-sufficiency gate
# (R/retrieval/retrieval_evidence.R), isolated from the fuzzy/ngram/RRF
# machinery it sits downstream of. See test-retrieval-integration.R for the
# end-to-end contract through search_classification_result().

test_that("meaningful tokens drop short tokens and the closed stopword set", {
  toks <- c("a", "the", "electrician", "s", "tape", "of", "carpenter")
  out <- retrieval_meaningful_tokens(toks)
  expect_identical(out, c("electrician", "tape", "carpenter"))
})

test_that("an empty or entirely-stopword query is trivially sufficient", {
  expect_true(retrieval_evidence_sufficient(character(0), c("driver")))
  expect_true(retrieval_evidence_sufficient(c("the", "a"), c("driver")))
})

test_that("a single meaningful query token needs only itself supported", {
  expect_true(retrieval_evidence_sufficient(c("carpentar"), c("carpenters", "and", "joiners")))
  expect_false(retrieval_evidence_sufficient(c("zzzzz"), c("carpenters", "and", "joiners")))
})

test_that("a two-token query needs both tokens supported, not just one", {
  # Mirrors the diagnosed "electrician's tape" leak: "electrician" matches
  # the title, "tape" matches nothing in it.
  expect_false(retrieval_evidence_sufficient(
    c("electrician", "tape"),
    c("building", "and", "related", "electricians")
  ))
  expect_true(retrieval_evidence_sufficient(
    c("heavy", "truck", "driver"),
    c("heavy", "truck", "and", "lorry", "drivers")
  ))
})

test_that("stopword-caliber tokens are excluded from candidate-side support too", {
  # "ant" is edit-distance-1 from the connector "and". If "and" were left in
  # the candidate's meaningful vocabulary, "ant" would spuriously count as
  # supported against ANY title containing "and".
  expect_false(retrieval_evidence_sufficient(
    c("carpenter", "ant"),
    c("carpenters", "and", "joiners")
  ))
})

test_that("typo'd tokens are still recognised via the real fuzzy primitive", {
  # The gate must reuse .retrieval_fuzzy_token_similarity(), not a naive
  # exact-match check, or single-character transpositions like this one
  # would be wrongly treated as unsupported.
  expect_true(retrieval_evidence_sufficient(
    c("trcuk", "driver"),
    c("heavy", "truck", "and", "lorry", "drivers")
  ))
})

test_that("a longer query needs a strict majority of its meaningful tokens supported", {
  # required = n %/% 2 + 1 for n > 1 -- more than half, not merely half.
  expect_true(retrieval_evidence_sufficient(
    c("heavy", "truck", "driver", "zzzzz"),
    c("heavy", "truck", "and", "lorry", "drivers")
  ))
  expect_false(retrieval_evidence_sufficient(
    c("heavy", "zzzzz", "yyyyy", "xxxxx"),
    c("heavy", "truck", "and", "lorry", "drivers")
  ))
})

test_that("exactly half support is no longer sufficient at n=4 (final micro-gate fix)", {
  # "professional AI prompt engineer": 2 of 4 meaningful tokens ("ai",
  # "prompt") are corpus-wide unsupported; the other 2 ("professional",
  # "engineer") are common category nouns that happen to match unrelated
  # titles. The old max(2, ceiling(n*0.5)) formula required only 2 of 4 and
  # let this through; a strict majority requires 3.
  expect_false(retrieval_evidence_sufficient(
    c("professional", "ai", "prompt", "engineer"),
    c("mining", "engineers", "metallurgists", "and", "related", "professionals")
  ))
})

test_that("a coincidental short-word overlap is not enough support (final micro-gate fix)", {
  # "moon rock trading": a fabricated commodity. "moon" correctly finds no
  # support anywhere. "rock" and "trading" previously registered as
  # "supported" purely because SOME unrelated candidate token happened to
  # sit within one edit of them ("rock"~"lock", "trading"~"threading"/
  # "heading") -- a coincidence, not a real lexical relationship. A minimum
  # per-token similarity floor (0.8) rejects these while still admitting
  # every genuine typo pair already required by the mandated positives.
  expect_false(retrieval_evidence_sufficient(
    c("moon", "rock", "trading"),
    c("interchangeable", "tool", "hand", "rock", "drilling", "boring")
  ))
  expect_false(retrieval_evidence_sufficient(
    c("moon", "rock", "trading"),
    c("structure", "lock", "gate", "tower", "heading")
  ))

  # Genuine typo/singular-plural support must survive the same floor.
  expect_true(retrieval_evidence_sufficient(c("trcuk"), c("truck", "driver")))
  expect_true(retrieval_evidence_sufficient(c("hevy"), c("heavy", "truck")))
})

test_that("retrieval_evidence_filter drops insufficiently-supported rows and keeps the rest", {
  corpus <- list(tokens = list(
    c("building", "and", "related", "electricians"),
    c("heavy", "truck", "and", "lorry", "drivers")
  ))
  candidates <- data.frame(
    idx = c(1L, 2L),
    rank = c(1L, 2L),
    code = c("7411", "8332"),
    stringsAsFactors = FALSE
  )
  attr(candidates, "tiers") <- c("ngram", "ngram")

  out <- retrieval_evidence_filter(candidates, c("electrician", "tape"), corpus)
  expect_false("7411" %in% out$code)

  out2 <- retrieval_evidence_filter(candidates, c("heavy", "truck", "driver"), corpus)
  expect_true("8332" %in% out2$code)
})

test_that("retrieval_evidence_filter is a no-op for an empty query or empty candidates", {
  corpus <- list(tokens = list(c("a", "b")))
  empty_candidates <- retrieval_no_candidates()

  expect_identical(retrieval_evidence_filter(empty_candidates, c("x"), corpus), empty_candidates)

  candidates <- data.frame(idx = 1L, rank = 1L, code = "X", stringsAsFactors = FALSE)
  expect_identical(retrieval_evidence_filter(candidates, character(0), corpus), candidates)
})

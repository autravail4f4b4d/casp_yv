# Semantic search behaviour: interface, system isolation, exact-match
# dominance, provider-failure fallback, and query caching.
#
# Covers sections 8.1, 9, 41, 51 and 52 of
# SEMANTIC_RETRIEVAL_AND_CONTEXT_CONSISTENCY_HARDENING.md.
#
# NO NETWORK, NO CREDENTIALS, NO SKIPS (section 55).
#
# Two of these tests inject a stand-in encoder AT THE PROVIDER BOUNDARY
# rather than through the `embed_fn` argument. That is deliberate:
# `retrieval_hybrid_candidates()` calls the semantic tier without an
# `embed_fn`, so the tier reaches `retrieval_embed_texts()` exactly as it
# would with a real endpoint. A test that only injected through `embed_fn`
# would never exercise the path the application actually takes, and would
# pass just as happily against an engine that ignored the semantic tier
# altogether.

# ------------------------------------------------------------- helpers

# The candidate generator, reached WITHOUT the v10 semantic mode gate.
# The gate lives on `retrieval_embeddings_candidates()` and is what makes
# shadow mode non-authoritative; it is proved in
# test-semantic-non-authority.R. These tests are about the generator's own
# behaviour, so they opt out of the gate with the documented `mode = NULL`.
sem_candidates <- function(...) retrieval_embeddings_candidates(..., mode = NULL)

# Replace the provider entry point for the duration of `code`, then put the
# original back. This is what a real embedding endpoint would occupy.
with_stub_provider <- function(fn, code) {
  had <- exists("retrieval_embed_texts", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("retrieval_embed_texts", envir = globalenv()) else NULL

  assign("retrieval_embed_texts",
         function(texts, config = NULL) fn(texts),
         envir = globalenv())
  retrieval_embedding_cache_reset()

  on.exit({
    if (had) {
      assign("retrieval_embed_texts", old, envir = globalenv())
    } else {
      rm("retrieval_embed_texts", envir = globalenv())
    }
    retrieval_embedding_cache_reset()
  }, add = TRUE)

  force(code)
}

# Deterministic near-orthogonal unit vector for row i. No RNG.
sr_row_vector <- function(i, dim = 32L) {
  j <- seq_len(dim)
  v <- sin(as.numeric(i) * 7919 + j * 104729) + cos(as.numeric(i) * 15485863 + j * 31)
  v / sqrt(sum(v * v))
}

# An encoder that maps each document to its own row vector and each named
# query straight onto a chosen row -- a perfect, fully controlled encoder,
# so a test can dictate exactly what the semantic tier will propose.
sr_directed_embedder <- function(doc_texts, query_targets, dim = 32L) {
  doc_row <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_along(doc_texts)) assign(doc_texts[i], i, envir = doc_row)

  q_row <- new.env(hash = TRUE, parent = emptyenv())
  for (nm in names(query_targets)) {
    assign(retrieval_normalize(nm), query_targets[[nm]], envir = q_row)
  }

  function(texts) {
    texts <- as.character(texts)
    texts[is.na(texts)] <- ""
    m <- matrix(0, nrow = length(texts), ncol = dim)
    for (i in seq_along(texts)) {
      r <- doc_row[[texts[i]]]
      if (is.null(r)) r <- q_row[[texts[i]]]
      if (!is.null(r)) m[i, ] <- sr_row_vector(r, dim)
    }
    m
  }
}

# Fixtures carry the FULL canonical schema, because
# `search_classification_data_result()` projects onto it -- a fixture with
# fewer columns would fail for a reason unrelated to anything under test.
sr_table <- function(system, version, level, code, label, parent_code = NA_character_) {
  data.frame(
    system = system, version = version, level = level, code = code, label = label,
    description = NA_character_, parent_code = parent_code,
    status = "current", source = "Philippine Statistics Authority",
    source_url = paste0("https://psa.gov.ph/classification/", system),
    stringsAsFactors = FALSE
  )
}

sr_psoc <- function() {
  sr_table("psoc", "2022",
           level = c("unit_group", "unit_group", "unit_group"),
           code = c("8332", "6111", "2330"),
           label = c("HEAVY TRUCK AND LORRY DRIVERS", "RICE FARMERS",
                     "SECONDARY EDUCATION TEACHERS"))
}

sr_psic <- function() {
  sr_table("psic", "2026",
           level = c("class", "class"),
           code = c("0112", "0113"),
           label = c("Growing of rice", "Growing of corn"))
}

sr_build <- function(data, system, version, query_targets = list(), dim = 32L) {
  corpus <- retrieval_corpus(data)
  docs <- retrieval_embedding_documents(data, system = system, version = version)
  embed <- sr_directed_embedder(docs$text, query_targets, dim = dim)
  index <- retrieval_embeddings_build(
    corpus, config = list(model = paste0("directed-", dim)), embed_fn = embed,
    data = data, system = system, version = version, documents = docs
  )
  list(data = data, corpus = corpus, docs = docs, embed = embed, index = index)
}

# ------------------------------------------- section 8.1: the interface

test_that("retrieval_semantic_search() returns the documented shape", {
  b <- sr_build(sr_psoc(), "psoc", "2022",
                query_targets = list("tsuper ng trak" = 1L))

  res <- retrieval_semantic_search("tsuper ng trak", b$index, top_k = 3L,
                                   system = "psoc", version = "2022",
                                   embed_fn = b$embed)

  expect_true(is.data.frame(res))
  expect_true(all(c("row_index", "code", "semantic_score", "semantic_rank",
                    "source", "semantic_document_sources") %in% names(res)))
  expect_gt(nrow(res), 0L)

  # Canonical row identity is preserved: row_index indexes the corpus, and
  # code is the unmodified canonical code at that row.
  expect_identical(res$row_index[1], 1L)
  expect_identical(res$code[1], "8332")
  expect_identical(res$source[1], "semantic")
  expect_identical(res$semantic_rank, seq_len(nrow(res)))
  expect_equal(res$semantic_score[1], 1, tolerance = 1e-9)
  # Section 11: a candidate carries enough metadata to explain itself.
  expect_true(nzchar(res$semantic_document_sources[1]))
})

test_that("top_k bounds the result and scores descend", {
  b <- sr_build(sr_psoc(), "psoc", "2022",
                query_targets = list("tsuper ng trak" = 1L))
  res <- retrieval_semantic_search("tsuper ng trak", b$index, top_k = 2L,
                                   min_score = NULL, embed_fn = b$embed)
  expect_lte(nrow(res), 2L)
  if (nrow(res) > 1L) expect_true(all(diff(res$semantic_score) <= 1e-12))
})

test_that("a broken index or query yields zero rows, never a condition", {
  b <- sr_build(sr_psoc(), "psoc", "2022")
  empty_ok <- function(x) {
    expect_true(is.data.frame(x))
    expect_identical(nrow(x), 0L)
  }
  empty_ok(retrieval_semantic_search("anything", NULL, embed_fn = b$embed))
  empty_ok(retrieval_semantic_search("anything", list(nonsense = TRUE), embed_fn = b$embed))
  empty_ok(retrieval_semantic_search(NA_character_, b$index, embed_fn = b$embed))
  empty_ok(retrieval_semantic_search("", b$index, embed_fn = b$embed))
  empty_ok(retrieval_semantic_search(c("two", "queries"), b$index, embed_fn = b$embed))
  empty_ok(retrieval_semantic_search("anything", b$index,
                                     embed_fn = function(x) stop("provider down")))
})

# ------------------------------------- section 9: system/index isolation

test_that("a PSOC query cannot retrieve PSIC rows through a semantic index", {
  psoc <- sr_build(sr_psoc(), "psoc", "2022")
  psic <- sr_build(sr_psic(), "psic", "2026",
                   query_targets = list("palay farmer" = 1L))

  # The PSIC index answers for PSIC.
  hit <- retrieval_semantic_search("palay farmer", psic$index, system = "psic",
                                   version = "2026", embed_fn = psic$embed)
  expect_gt(nrow(hit), 0L)
  expect_identical(hit$code[1], "0112")

  # Asked as PSOC, the same index returns nothing at all -- not a
  # best-effort PSIC answer wearing a PSOC label.
  crossed <- retrieval_semantic_search("palay farmer", psic$index, system = "psoc",
                                       version = "2022", embed_fn = psic$embed)
  expect_identical(nrow(crossed), 0L)

  # And every code an index can ever return belongs to its own system, by
  # construction: the codes were written in from that system's rows.
  expect_true(all(psic$index$codes %in% sr_psic()$code))
  expect_true(all(psoc$index$codes %in% sr_psoc()$code))
  expect_false(any(psic$index$codes %in% sr_psoc()$code))
})

test_that("the validation gate refuses a cross-system index", {
  psoc <- sr_build(sr_psoc(), "psoc", "2022")
  psic <- sr_build(sr_psic(), "psic", "2026")

  # This is the exact call retrieval_index_for() makes before an index is
  # allowed anywhere near the engine.
  expect_false(retrieval_embeddings_index_is_valid(psic$index, psoc$corpus))
  expect_false(retrieval_embeddings_index_is_valid(psoc$index, psic$corpus))
  expect_true(retrieval_embeddings_index_is_valid(psoc$index, psoc$corpus))
  expect_true(retrieval_embeddings_index_is_valid(psic$index, psic$corpus))
})

test_that("indexes are separate artifacts per system and edition", {
  # Path separation is the first line of defence: retrieval_index_get()
  # composes data/retrieval_embeddings_<system>_<version>.rds, so a PSOC
  # index is never even read for a PSIC lookup.
  psoc_path <- sprintf("data/retrieval_%s_%s_%s.rds", "embeddings", "psoc", "2022")
  psic_path <- sprintf("data/retrieval_%s_%s_%s.rds", "embeddings", "psic", "2026")
  expect_false(identical(psoc_path, psic_path))

  psoc <- sr_build(sr_psoc(), "psoc", "2022")
  psic <- sr_build(sr_psic(), "psic", "2026")
  expect_identical(psoc$index$system, "psoc")
  expect_identical(psic$index$system, "psic")
  expect_false(identical(psoc$index$corpus_fingerprint, psic$index$corpus_fingerprint))
})

# ------------------------------- exact-match dominance (section 41 / CLAUDE.md)

test_that("an exact label match is not displaced by an adversarial semantic rank", {
  data <- sr_psoc()
  # The encoder is rigged: the exact-label query for row 1 is pointed at
  # row 3 with cosine 1.000, so the semantic tier proposes the WRONG record
  # as its single best candidate.
  b <- sr_build(data, "psoc", "2022",
                query_targets = list("heavy truck and lorry drivers" = 3L))

  sem <- retrieval_semantic_search("HEAVY TRUCK AND LORRY DRIVERS", b$index,
                                   embed_fn = b$embed)
  expect_identical(sem$code[1], "2330")  # the tier really is proposing the wrong row

  with_stub_provider(b$embed, {
    res <- search_classification_data_result(
      data, "HEAVY TRUCK AND LORRY DRIVERS", limit = 10L, hybrid = TRUE,
      embedding_index = b$index, corpus = b$corpus
    )
    # Tier 3 (exact normalized label) sits above the fused tier, so the
    # verified exact match stays first no matter what the encoder thinks.
    expect_identical(as.character(res$data$code)[1], "8332")
  })
})

test_that("an exact code match is not displaced either", {
  data <- sr_psoc()
  b <- sr_build(data, "psoc", "2022", query_targets = list("8332" = 2L))

  with_stub_provider(b$embed, {
    res <- search_classification_data_result(
      data, "8332", limit = 10L, hybrid = TRUE,
      embedding_index = b$index, corpus = b$corpus
    )
    expect_identical(as.character(res$data$code)[1], "8332")
  })
})

# ------------------------------ section 52: provider failure is fail-soft

test_that("a failing embedding provider leaves the other tiers working", {
  data <- sr_psoc()
  b <- sr_build(data, "psoc", "2022")

  failures <- list(
    thrower = function(texts) stop("connection refused"),
    nuller  = function(texts) NULL,
    ragged  = function(texts) matrix(1, nrow = 1L, ncol = 3L),   # wrong dim
    garbage = function(texts) "not a matrix"
  )

  for (nm in names(failures)) {
    with_stub_provider(failures[[nm]], {
      res <- expect_no_error(search_classification_data_result(
        data, "heavy truck driver", limit = 10L, hybrid = TRUE,
        embedding_index = b$index, corpus = b$corpus
      ))
      # The deterministic tiers are untouched: the record is still found.
      expect_true("8332" %in% as.character(res$data$code),
                  info = paste("provider failure mode:", nm))
    })
  }
})

test_that("a failing provider degrades the tier to nothing, not to noise", {
  b <- sr_build(sr_psoc(), "psoc", "2022")
  with_stub_provider(function(texts) stop("timeout"), {
    cand <- sem_candidates("rice farmer", b$index)
    expect_true(is.data.frame(cand))
    expect_identical(nrow(cand), 0L)
    expect_identical(names(cand), c("idx", "score", "rank"))
  })
})

test_that("hybrid fusion survives a semantic tier that throws", {
  b <- sr_build(sr_psoc(), "psoc", "2022")
  with_stub_provider(function(texts) stop("provider exploded"), {
    fused <- expect_no_error(retrieval_hybrid_candidates(
      "rice farmer", b$corpus, ngram_index = NULL, embedding_index = b$index
    ))
    expect_true(is.data.frame(fused))
    # Fuzzy still ran and still found the record.
    expect_true(2L %in% fused$idx)
  })
})

# ------------------------------------- section 12: disabled is the default

test_that("with nothing configured the tier is inert and the app is unaffected", {
  # No RETRIEVAL_EMBEDDING_* variable is set in a normal test session, and
  # the default for the enable flag is FALSE.
  cfg <- retrieval_embedding_config()
  expect_false(retrieval_embedding_available(cfg))

  b <- sr_build(sr_psoc(), "psoc", "2022")
  # Real provider path, genuinely unconfigured: no stub, no network.
  retrieval_embedding_cache_reset()
  cand <- sem_candidates("rice farmer", b$index)
  expect_identical(nrow(cand), 0L)

  res <- search_classification_data_result(
    sr_psoc(), "rice farmer", limit = 10L, hybrid = TRUE,
    embedding_index = b$index, corpus = b$corpus
  )
  expect_true("6111" %in% as.character(res$data$code))
})

# ----------------------------------------- section 51: query-vector cache

test_that("the query cache spares a repeated provider call", {
  b <- sr_build(sr_psoc(), "psoc", "2022",
                query_targets = list("tsuper ng trak" = 1L))
  calls <- 0L
  counting <- function(texts) { calls <<- calls + 1L; b$embed(texts) }

  with_stub_provider(counting, {
    first <- sem_candidates("tsuper ng trak", b$index)
    expect_identical(calls, 1L)
    second <- sem_candidates("tsuper ng trak", b$index)
    expect_identical(calls, 1L)          # served from cache
    expect_identical(first$idx, second$idx)
    expect_equal(first$score, second$score)

    # A different query is a different key.
    sem_candidates("rice farmer", b$index)
    expect_identical(calls, 2L)

    retrieval_embedding_cache_reset()
    sem_candidates("tsuper ng trak", b$index)
    expect_identical(calls, 3L)
  })
})

test_that("the cache never crosses two incompatible indexes", {
  psoc <- sr_build(sr_psoc(), "psoc", "2022",
                   query_targets = list("palay farmer" = 2L))
  psic <- sr_build(sr_psic(), "psic", "2026",
                   query_targets = list("palay farmer" = 1L))

  # Same query text, two different indexes. If the cache keyed on the query
  # alone, the second lookup would reuse the first index's vector.
  seen <- character(0)
  dispatch <- function(texts) {
    # Documents were embedded at build time; only queries arrive here.
    if (identical(retrieval_normalize(texts[1]), "palay farmer")) {
      seen <<- c(seen, "q")
    }
    # Return whichever encoder matches the index currently being queried;
    # both map "palay farmer" to their own row 1/2.
    if (length(seen) <= 1L) psoc$embed(texts) else psic$embed(texts)
  }

  with_stub_provider(dispatch, {
    a <- retrieval_semantic_search("palay farmer", psoc$index, system = "psoc",
                                   version = "2022")
    b2 <- retrieval_semantic_search("palay farmer", psic$index, system = "psic",
                                    version = "2026")
    expect_identical(length(seen), 2L)   # both indexes paid for their own call
    expect_identical(a$code[1], "6111")
    expect_identical(b2$code[1], "0112")
  })
})

test_that("an injected embed_fn is never cached", {
  b <- sr_build(sr_psoc(), "psoc", "2022",
                query_targets = list("tsuper ng trak" = 1L))
  calls <- 0L
  counting <- function(texts) { calls <<- calls + 1L; b$embed(texts) }

  retrieval_embedding_cache_reset()
  sem_candidates("tsuper ng trak", b$index, embed_fn = counting)
  sem_candidates("tsuper ng trak", b$index, embed_fn = counting)
  # Caching a caller-supplied closure would be unsound -- its behaviour is
  # not part of the cache key -- so it is deliberately not cached.
  expect_identical(calls, 2L)
})

# ---------------------------------- candidate generation, never authority

test_that("the semantic tier proposes rows that already exist and nothing else", {
  data <- sr_psoc()
  b <- sr_build(data, "psoc", "2022",
                query_targets = list("something unrelated entirely" = 2L))

  res <- retrieval_semantic_search("something unrelated entirely", b$index,
                                   top_k = 10L, embed_fn = b$embed)
  # Every proposed code is a real canonical code at a real row, and the
  # row index resolves to that same code in the source table.
  expect_true(all(res$code %in% data$code))
  expect_identical(data$code[res$row_index], res$code)
  # A cosine is not a confidence. It is only ever an ordering.
  expect_true(all(res$semantic_score <= 1 + 1e-9))
})

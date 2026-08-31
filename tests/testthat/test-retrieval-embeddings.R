# Tests for the OPTIONAL semantic retrieval tier.
#
# These tests run with NO NETWORK and NO SKIPS. The provider is exercised
# either through a deterministic in-test stub or through its
# already-disabled configuration, never by calling a real endpoint.
#
# The property under test throughout is FAIL-OPEN: every malfunction of
# the semantic tier must produce an empty candidate set, never a
# condition, so that classification search keeps working when the
# embedding backend is absent, misconfigured or broken.

# ---------------------------------------------------------------- helpers

# From v10, `retrieval_embeddings_candidates()` carries the semantic MODE
# GATE: at the repository default (`RETRIEVAL_SEMANTIC_MODE=off`) it
# returns nothing by design, and at `shadow` it measures and then returns
# nothing. That gate is the subject of test-semantic-non-authority.R.
#
# The tests in THIS file are about the candidate generator underneath it
# -- cosine ranking, top-k, fail-open on every provider malfunction -- so
# they call it ungated. `mode = NULL` is the documented way for a caller
# that owns its own authority decision to reach the generator.
sem_candidates <- function(...) retrieval_embeddings_candidates(..., mode = NULL)

# `withr` is not guaranteed to be part of this project's locked
# dependencies, so environment variables are saved and restored by hand.
with_env_vars <- function(vars, code) {
  # Call sites build `c(clear_embedding_env(), list(...))`, so a name can
  # appear twice; the later (explicit) value wins.
  vars <- vars[!duplicated(names(vars), fromLast = TRUE)]
  nms <- names(vars)
  old <- Sys.getenv(nms, unset = NA_character_, names = TRUE)

  on.exit({
    for (nm in nms) {
      if (is.na(old[[nm]])) {
        Sys.unsetenv(nm)
      } else {
        do.call(Sys.setenv, stats::setNames(list(old[[nm]]), nm))
      }
    }
  }, add = TRUE)

  for (nm in nms) {
    if (is.na(vars[[nm]])) {
      Sys.unsetenv(nm)
    } else {
      do.call(Sys.setenv, stats::setNames(list(as.character(vars[[nm]])), nm))
    }
  }

  force(code)
}

RETRIEVAL_EMB_ENV_NAMES <- c(
  "RETRIEVAL_EMBEDDING_ENABLED", "RETRIEVAL_EMBEDDING_URL",
  "RETRIEVAL_EMBEDDING_MODEL", "RETRIEVAL_EMBEDDING_API_KEY",
  "RETRIEVAL_EMBEDDING_TIMEOUT"
)

clear_embedding_env <- function() {
  stats::setNames(as.list(rep(NA_character_, length(RETRIEVAL_EMB_ENV_NAMES))),
                  RETRIEVAL_EMB_ENV_NAMES)
}

# A deterministic, offline, hashing bag-of-tokens vectoriser. It is NOT a
# semantic model -- it only needs to be a stable function of the text so
# that ranking, determinism and dimensionality can be asserted without a
# provider.
stub_embedder <- function(dim = 64L) {
  force(dim)
  function(texts) {
    texts <- as.character(texts)
    m <- matrix(0, nrow = length(texts), ncol = dim)
    for (i in seq_along(texts)) {
      toks <- strsplit(texts[i], " ", fixed = TRUE)[[1]]
      toks <- toks[nzchar(toks)]
      if (length(toks) == 0L) {
        m[i, 1L] <- 1
        next
      }
      for (tok in toks) {
        cps <- utf8ToInt(tok)
        bucket <- (sum(cps * seq_along(cps)) %% dim) + 1L
        m[i, bucket] <- m[i, bucket] + 1
      }
    }
    m
  }
}

sample_corpus <- function(labels = NULL) {
  if (is.null(labels)) {
    labels <- c(
      "heavy truck driver",
      "light truck driver",
      "rice farmer",
      "software developer",
      "fish vendor"
    )
  }
  retrieval_corpus(data.frame(
    code = sprintf("%04d", seq_along(labels)),
    label = labels,
    stringsAsFactors = FALSE
  ))
}

expect_empty_candidates <- function(x) {
  expect_true(is.data.frame(x))
  expect_identical(nrow(x), 0L)
  expect_identical(names(x), c("idx", "score", "rank"))
}

# ------------------------------------------------------- provider config

test_that("the semantic tier is unavailable when nothing is configured", {
  with_env_vars(clear_embedding_env(), {
    cfg <- retrieval_embedding_config()

    expect_false(cfg$enabled)
    expect_identical(cfg$url, "")
    expect_identical(cfg$model, "")
    expect_false(cfg$has_key)
    expect_identical(cfg$timeout, RETRIEVAL_EMBEDDING_DEFAULT_TIMEOUT)

    expect_false(retrieval_embedding_available())
    expect_false(retrieval_embedding_available(cfg))
  })
})

test_that("enabling alone is not enough; url and model are both required", {
  with_env_vars(c(clear_embedding_env(),
                  list(RETRIEVAL_EMBEDDING_ENABLED = "true")), {
    expect_true(retrieval_embedding_config()$enabled)
    expect_false(retrieval_embedding_available())
  })

  with_env_vars(c(clear_embedding_env(), list(
    RETRIEVAL_EMBEDDING_ENABLED = "true",
    RETRIEVAL_EMBEDDING_URL = "http://127.0.0.1:1/v1/embeddings"
  )), {
    expect_false(retrieval_embedding_available())
  })

  with_env_vars(c(clear_embedding_env(), list(
    RETRIEVAL_EMBEDDING_ENABLED = "true",
    RETRIEVAL_EMBEDDING_URL = "http://127.0.0.1:1/v1/embeddings",
    RETRIEVAL_EMBEDDING_MODEL = "paraphrase-multilingual-MiniLM-L12-v2"
  )), {
    expect_true(retrieval_embedding_available())
  })
})

test_that("retrieval_embedding_available() makes no network call", {
  # A refused/unroutable endpoint must still answer instantly and TRUE,
  # proving the check is pure configuration.
  with_env_vars(c(clear_embedding_env(), list(
    RETRIEVAL_EMBEDDING_ENABLED = "true",
    RETRIEVAL_EMBEDDING_URL = "http://127.0.0.1:1/v1/embeddings",
    RETRIEVAL_EMBEDDING_MODEL = "stub-model"
  )), {
    elapsed <- system.time(res <- retrieval_embedding_available())[["elapsed"]]
    expect_true(res)
    expect_lt(elapsed, 2)
  })
})

test_that("the API key never appears anywhere in the public config", {
  sentinel <- "SECRET-DO-NOT-LEAK"

  with_env_vars(c(clear_embedding_env(), list(
    RETRIEVAL_EMBEDDING_ENABLED = "true",
    RETRIEVAL_EMBEDDING_URL = "http://127.0.0.1:1/v1/embeddings",
    RETRIEVAL_EMBEDDING_MODEL = "stub-model",
    RETRIEVAL_EMBEDDING_API_KEY = sentinel
  )), {
    cfg <- retrieval_embedding_config()

    expect_true(cfg$has_key)
    expect_false(sentinel %in% names(cfg))

    flat <- paste(vapply(cfg, function(v) paste(as.character(v), collapse = " "),
                         character(1)), collapse = " ")
    expect_false(grepl(sentinel, flat, fixed = TRUE))

    dumped <- paste(utils::capture.output(utils::str(cfg)), collapse = " ")
    expect_false(grepl(sentinel, dumped, fixed = TRUE))

    printed <- paste(utils::capture.output(print(cfg)), collapse = " ")
    expect_false(grepl(sentinel, printed, fixed = TRUE))

    dput_out <- paste(utils::capture.output(dput(cfg)), collapse = " ")
    expect_false(grepl(sentinel, dput_out, fixed = TRUE))
  })
})

test_that("the provider identifier stamped on an index carries no credential", {
  sentinel <- "SECRET-DO-NOT-LEAK"

  # The nastiest realistic case: the credential is embedded in the URL's
  # userinfo, so a naive "record the endpoint" would write it straight into
  # a committed-adjacent artifact and print it from the build script.
  with_env_vars(c(clear_embedding_env(), list(
    RETRIEVAL_EMBEDDING_ENABLED = "true",
    RETRIEVAL_EMBEDDING_URL = paste0("https://user:", sentinel,
                                     "@embeddings.example.org:8443/v1/embeddings?key=",
                                     sentinel),
    RETRIEVAL_EMBEDDING_MODEL = "multilingual-e5-base",
    RETRIEVAL_EMBEDDING_API_KEY = sentinel
  )), {
    id <- retrieval_embedding_provider_id()

    expect_false(grepl(sentinel, id, fixed = TRUE))
    expect_false(grepl("user:", id, fixed = TRUE))
    expect_false(grepl("@", id, fixed = TRUE))
    expect_false(grepl("?", id, fixed = TRUE))
    # It is still a useful identifier: host, port, path and model survive,
    # which is what makes "was this index built by a different encoder?"
    # answerable.
    expect_true(grepl("embeddings.example.org:8443/v1/embeddings", id, fixed = TRUE))
    expect_true(grepl("multilingual-e5-base", id, fixed = TRUE))

    # And it must survive the round trip onto an index artifact.
    corpus <- sample_corpus()
    index <- retrieval_embeddings_build(corpus, embed_fn = stub_embedder())
    expect_false(grepl(sentinel, index$provider, fixed = TRUE))
    expect_false(grepl(sentinel,
                       paste(utils::capture.output(utils::str(index)), collapse = " "),
                       fixed = TRUE))
  })
})

test_that("the provider identifier is empty rather than misleading when unset", {
  with_env_vars(clear_embedding_env(), {
    expect_identical(retrieval_embedding_provider_id(), "")
  })
})

test_that("the scrubber removes the credential from provider messages", {
  sentinel <- "SECRET-DO-NOT-LEAK"
  with_env_vars(c(clear_embedding_env(),
                  list(RETRIEVAL_EMBEDDING_API_KEY = sentinel)), {
    scrubbed <- .retrieval_embedding_scrub(
      paste0("Authorization: Bearer ", sentinel, " failed")
    )
    expect_false(grepl(sentinel, scrubbed, fixed = TRUE))
    expect_true(grepl("<redacted>", scrubbed, fixed = TRUE))
  })
})

# --------------------------------------------------- provider fail-open

test_that("retrieval_embed_texts() returns NULL, silently, when disabled", {
  with_env_vars(clear_embedding_env(), {
    expect_silent(res <- retrieval_embed_texts(c("truck driver", "rice farmer")))
    expect_null(res)
  })
})

test_that("retrieval_embed_texts() returns NULL for empty or absent input", {
  with_env_vars(clear_embedding_env(), {
    expect_null(retrieval_embed_texts(character(0)))
    expect_null(retrieval_embed_texts(NULL))
  })
})

test_that("retrieval_embed_texts() never propagates a transport failure", {
  # Port 1 on loopback: refused immediately, no external network involved.
  with_env_vars(c(clear_embedding_env(), list(
    RETRIEVAL_EMBEDDING_ENABLED = "true",
    RETRIEVAL_EMBEDDING_URL = "http://127.0.0.1:1/v1/embeddings",
    RETRIEVAL_EMBEDDING_MODEL = "stub-model",
    RETRIEVAL_EMBEDDING_API_KEY = "SECRET-DO-NOT-LEAK",
    RETRIEVAL_EMBEDDING_TIMEOUT = "1"
  )), {
    warned <- character(0)
    res <- withCallingHandlers(
      retrieval_embed_texts("truck driver"),
      warning = function(w) {
        warned <<- c(warned, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    expect_null(res)
    # Whatever the transport said, the credential is not in it.
    expect_false(any(grepl("SECRET-DO-NOT-LEAK", warned, fixed = TRUE)))
  })
})

test_that("the response parser rejects every malformed payload shape", {
  ok <- jsonlite::fromJSON(
    '{"data":[{"embedding":[1,2,3]},{"embedding":[4,5,6]}]}',
    simplifyVector = FALSE
  )
  m <- .retrieval_embedding_parse(ok, n_expected = 2L)
  expect_true(is.matrix(m))
  expect_identical(dim(m), c(2L, 3L))
  expect_equal(m[2, ], c(4, 5, 6))

  # Alternative self-hosted shapes are accepted.
  tei <- jsonlite::fromJSON('{"embeddings":[[1,0],[0,1]]}', simplifyVector = FALSE)
  expect_identical(dim(.retrieval_embedding_parse(tei, 2L)), c(2L, 2L))

  bare <- jsonlite::fromJSON('[[1,0],[0,1]]', simplifyVector = FALSE)
  expect_identical(dim(.retrieval_embedding_parse(bare, 2L)), c(2L, 2L))

  # Malformed shapes yield NULL rather than a guess.
  expect_null(.retrieval_embedding_parse(
    jsonlite::fromJSON('{"error":"bad request"}', simplifyVector = FALSE), 1L))
  expect_null(.retrieval_embedding_parse(
    jsonlite::fromJSON('{"data":[]}', simplifyVector = FALSE), 1L))
  # Ragged vectors.
  expect_null(.retrieval_embedding_parse(
    jsonlite::fromJSON('{"data":[{"embedding":[1,2]},{"embedding":[1,2,3]}]}',
                       simplifyVector = FALSE), 2L))
  # Wrong number of rows for the request.
  expect_null(.retrieval_embedding_parse(
    jsonlite::fromJSON('{"data":[{"embedding":[1,2]}]}', simplifyVector = FALSE), 2L))
  expect_null(.retrieval_embedding_parse(NULL, 1L))
})

# --------------------------------------------------------- index building

test_that("an index builds from a stubbed embedder and carries its metadata", {
  corpus <- sample_corpus()
  index <- retrieval_embeddings_build(
    corpus,
    config = list(enabled = TRUE, url = "stub", model = "stub-model",
                  timeout = 5, has_key = FALSE),
    embed_fn = stub_embedder(64L),
    batch_size = 2L  # forces the multi-batch path
  )

  expect_false(is.null(index))
  expect_s3_class(index, "retrieval_embedding_index")
  expect_identical(index$n_docs, 5L)
  expect_identical(index$dim, 64L)
  expect_identical(index$model, "stub-model")
  expect_true(nzchar(index$built_at))
  # Two independent checksums: one over canonical row identity (what the
  # runtime validator can recompute from a corpus) and one over the text
  # that was actually embedded (build-time audit).
  expect_true(nzchar(index$corpus_fingerprint))
  expect_true(nzchar(index$doc_fingerprint))
  expect_identical(index$index_version, RETRIEVAL_EMBEDDING_INDEX_VERSION)
  expect_identical(index$doc_recipe_version, RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION)

  # Stored vectors are unit length, so cosine is one matrix-vector product.
  expect_equal(sqrt(rowSums(index$vectors^2)), rep(1, 5), tolerance = 1e-9)
})

test_that("building over an empty corpus yields NULL, not an error", {
  empty <- retrieval_corpus(NULL)
  expect_null(retrieval_embeddings_build(empty, embed_fn = stub_embedder()))
})

test_that("a failing embedder abandons the build rather than half-indexing", {
  corpus <- sample_corpus()

  thrower <- function(texts) stop("provider exploded")
  expect_null(retrieval_embeddings_build(corpus, embed_fn = thrower))

  nuller <- function(texts) NULL
  expect_null(retrieval_embeddings_build(corpus, embed_fn = nuller))

  # Right shape, wrong row count for the batch.
  short <- function(texts) matrix(1, nrow = 1L, ncol = 8L)
  expect_null(retrieval_embeddings_build(corpus, embed_fn = short, batch_size = 5L))
})

test_that("retrieval_embeddings_load() returns NULL for a missing file", {
  expect_null(retrieval_embeddings_load(
    file.path(tempdir(), "definitely-not-here-retrieval.rds")))
  expect_null(retrieval_embeddings_load(NULL))
  expect_null(retrieval_embeddings_load(NA_character_))
  expect_null(retrieval_embeddings_load(""))
})

test_that("retrieval_embeddings_load() round-trips a real index and rejects junk", {
  corpus <- sample_corpus()
  index <- retrieval_embeddings_build(corpus, embed_fn = stub_embedder())

  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(index, path)
  expect_false(is.null(retrieval_embeddings_load(path)))

  junk <- tempfile(fileext = ".rds")
  on.exit(unlink(junk), add = TRUE)
  saveRDS(list(hello = "world"), junk)
  expect_null(retrieval_embeddings_load(junk))
})

# ------------------------------------------------------- index validation

test_that("index validity tracks the corpus it was built from", {
  corpus <- sample_corpus()
  index <- retrieval_embeddings_build(corpus, embed_fn = stub_embedder())

  expect_true(retrieval_embeddings_index_is_valid(index, corpus))

  # A relabelled entry: same row count, different content.
  changed <- sample_corpus(c(
    "heavy truck driver", "light truck driver", "corn farmer",
    "software developer", "fish vendor"
  ))
  expect_false(retrieval_embeddings_index_is_valid(index, changed))

  # A different row count.
  shorter <- sample_corpus(c("heavy truck driver", "rice farmer"))
  expect_false(retrieval_embeddings_index_is_valid(index, shorter))

  # Reordering is a change too -- row i of the index must mean row i of
  # the corpus, so a permutation must invalidate.
  reordered <- sample_corpus(c(
    "light truck driver", "heavy truck driver", "rice farmer",
    "software developer", "fish vendor"
  ))
  expect_false(retrieval_embeddings_index_is_valid(index, reordered))

  expect_false(retrieval_embeddings_index_is_valid(NULL, corpus))
  expect_false(retrieval_embeddings_index_is_valid(index, NULL))
  expect_false(retrieval_embeddings_index_is_valid(index, retrieval_corpus(NULL)))
})

# ------------------------------------------------------------- querying

test_that("querying a stub-built index returns sensible ranked candidates", {
  corpus <- sample_corpus()
  embed <- stub_embedder(64L)
  index <- retrieval_embeddings_build(corpus, embed_fn = embed)

  cand <- sem_candidates("truck driver", index,
                                          top_k = 50L, embed_fn = embed)

  expect_true(is.data.frame(cand))
  expect_gt(nrow(cand), 0L)
  expect_identical(names(cand), c("idx", "score", "rank"))

  # Cosine of unit vectors: bounded in [-1, 1], NOT clamped or rescaled.
  expect_true(all(cand$score >= -1 - 1e-9 & cand$score <= 1 + 1e-9))

  # Dense ranks from 1, descending score.
  expect_identical(cand$rank, seq_len(nrow(cand)))
  expect_false(is.unsorted(rev(cand$score)))

  # The two truck-driver rows must outrank the unrelated ones.
  expect_true(all(cand$idx[1:2] %in% c(1L, 2L)))

  # The default min_score of 0 discards rows orthogonal to the query --
  # "software developer" shares no token with "truck driver", so it is
  # dropped rather than ranked. Re-query with the filter off to confirm it
  # is genuinely below the truck-driver rows and not merely missing.
  all_cand <- sem_candidates("truck driver", index,
                                              top_k = 50L, min_score = NULL,
                                              embed_fn = embed)
  expect_identical(nrow(all_cand), 5L)
  score_of <- stats::setNames(all_cand$score, as.character(all_cand$idx))
  expect_gt(score_of[["1"]], score_of[["4"]])
  expect_gt(score_of[["2"]], score_of[["3"]])
  expect_equal(unname(score_of[["4"]]), 0)
})

test_that("top_k is respected", {
  corpus <- sample_corpus()
  embed <- stub_embedder(64L)
  index <- retrieval_embeddings_build(corpus, embed_fn = embed)

  cand <- sem_candidates("truck driver", index,
                                          top_k = 2L, embed_fn = embed)
  expect_lte(nrow(cand), 2L)
  expect_identical(cand$rank, seq_len(nrow(cand)))
})

test_that("querying is deterministic across identical calls", {
  corpus <- sample_corpus()
  embed <- stub_embedder(64L)
  index <- retrieval_embeddings_build(corpus, embed_fn = embed)

  a <- sem_candidates("truck driver", index, embed_fn = embed)
  b <- sem_candidates("truck driver", index, embed_fn = embed)
  expect_identical(a, b)

  # And the index itself is reproducible bar its timestamp.
  index2 <- retrieval_embeddings_build(corpus, embed_fn = embed)
  expect_equal(index$vectors, index2$vectors)
  expect_identical(index$fingerprint, index2$fingerprint)
})

# ------------------------------------------------- FAIL-OPEN at query time

test_that("a NULL, empty or invalid index yields an empty candidate set", {
  embed <- stub_embedder()

  expect_empty_candidates(
    sem_candidates("truck driver", NULL, embed_fn = embed))

  expect_empty_candidates(
    sem_candidates("truck driver",
                                    retrieval_embeddings_build(retrieval_corpus(NULL),
                                                               embed_fn = embed),
                                    embed_fn = embed))

  expect_empty_candidates(
    sem_candidates("truck driver", list(), embed_fn = embed))

  expect_empty_candidates(
    sem_candidates(
      "truck driver",
      list(index_version = 1L, vectors = matrix(numeric(0), nrow = 0, ncol = 0),
           n_docs = 0L, dim = 0L),
      embed_fn = embed))

  # A stale artifact from an earlier layout version is refused.
  stale <- retrieval_embeddings_build(sample_corpus(), embed_fn = embed)
  stale$index_version <- 0L
  expect_empty_candidates(
    sem_candidates("truck driver", stale, embed_fn = embed))
})

test_that("a blank, NA or malformed query yields an empty candidate set", {
  embed <- stub_embedder()
  index <- retrieval_embeddings_build(sample_corpus(), embed_fn = embed)

  for (q in list("", "   ", NA_character_, NULL, character(0),
                 c("a", "b"), "!!! ???")) {
    expect_empty_candidates(
      sem_candidates(q, index, embed_fn = embed))
  }
})

test_that("an induced provider failure never propagates out of the tier", {
  embed <- stub_embedder(64L)
  index <- retrieval_embeddings_build(sample_corpus(), embed_fn = embed)

  thrower <- function(texts) stop("embedding endpoint is on fire")
  expect_empty_candidates(
    sem_candidates("truck driver", index, embed_fn = thrower))

  nuller <- function(texts) NULL
  expect_empty_candidates(
    sem_candidates("truck driver", index, embed_fn = nuller))

  # Malformed provider output: a JSON body the parser could not turn into
  # a matrix reaches this layer as a non-matrix value.
  garbage <- function(texts) list(error = "rate limited")
  expect_empty_candidates(
    sem_candidates("truck driver", index, embed_fn = garbage))

  textual <- function(texts) "<html>502 Bad Gateway</html>"
  expect_empty_candidates(
    sem_candidates("truck driver", index, embed_fn = textual))

  # Right type, wrong dimensionality: the model was swapped under a stale
  # index. Mixing dimensions must not be attempted.
  wrong_dim <- function(texts) matrix(1, nrow = length(texts), ncol = 7L)
  expect_empty_candidates(
    sem_candidates("truck driver", index, embed_fn = wrong_dim))

  # Non-finite output.
  nasty <- function(texts) matrix(NaN, nrow = length(texts), ncol = 64L)
  res <- sem_candidates("truck driver", index, embed_fn = nasty)
  expect_true(is.data.frame(res))
  expect_identical(nrow(res), 0L)
})

test_that("with no backend configured the tier is inert but harmless", {
  # The realistic default state of this deployment: enabled=false, so the
  # real provider is used, returns NULL, and Search sees an empty set.
  with_env_vars(clear_embedding_env(), {
    embed <- stub_embedder()
    index <- retrieval_embeddings_build(sample_corpus(), embed_fn = embed)

    expect_empty_candidates(
      sem_candidates("truck driver", index))
  })
})

test_that("an empty semantic set does not disturb rank fusion", {
  # The integration property the other tiers depend on: RRF over
  # (lexical, semantic-empty) must equal RRF over (lexical) alone.
  lexical <- retrieval_candidates(idx = c(3L, 1L, 5L), score = c(0.9, 0.5, 0.2))
  semantic <- retrieval_no_candidates()

  fused <- retrieval_rrf(list(lexical = lexical, semantic = semantic))
  lexical_only <- retrieval_rrf(list(lexical = lexical))

  expect_identical(fused$idx, lexical_only$idx)
  expect_equal(fused$score, lexical_only$score)
})

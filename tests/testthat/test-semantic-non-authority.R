# PROOF OF NON-AUTHORITY.
#
# Spec 24, 29, 33 and 40: for pre-staging-v10 the semantic tier may be
# measured and may not decide anything. This file is the evidence for
# that claim, and it is the single most important file in the semantic
# workstream.
#
# THE METHOD: AN ADVERSARIAL ENCODER
# -----------------------------------------------------------------
# A benign encoder proves nothing -- if the semantic tier agrees with the
# deterministic engine, an equality assertion passes whether or not the
# tier has any influence. So every test here uses an encoder that is
# deliberately, maximally WRONG: it maps every query exactly onto the
# vector of a code the correct answer is not, producing cosine 1.000 at
# semantic rank 1 for a code that must never be chosen.
#
# The tests then assert two things TOGETHER, and both halves are
# required:
#
#   1. the deterministic outcome under `shadow` is IDENTICAL to the
#      outcome under `off`; and
#   2. the shadow ring actually recorded the adversarial code at rank 1
#      with cosine ~1.
#
# Without (2), a semantic tier that silently failed to run would satisfy
# (1) and the file would be worthless. (2) is what proves the tier really
# executed and really was ignored.
#
# NO NETWORK, NO CREDENTIALS, NO SKIPS. The encoder is injected at the
# provider boundary -- `retrieval_embed_texts()` -- which is exactly
# where a real endpoint would sit, so the engine's own call path is
# exercised unchanged.

# ------------------------------------------------------------- helpers

# Save/restore RETRIEVAL_SEMANTIC_MODE by hand; `withr` is not a locked
# dependency of this project.
with_semantic_mode <- function(mode, code) {
  had <- Sys.getenv("RETRIEVAL_SEMANTIC_MODE", unset = NA_character_)
  if (is.null(mode)) Sys.unsetenv("RETRIEVAL_SEMANTIC_MODE") else Sys.setenv(RETRIEVAL_SEMANTIC_MODE = mode)
  on.exit({
    if (is.na(had)) Sys.unsetenv("RETRIEVAL_SEMANTIC_MODE") else Sys.setenv(RETRIEVAL_SEMANTIC_MODE = had)
  }, add = TRUE)
  force(code)
}

with_stub_provider <- function(fn, code) {
  had <- exists("retrieval_embed_texts", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("retrieval_embed_texts", envir = globalenv()) else NULL
  assign("retrieval_embed_texts", function(texts, config = NULL) fn(texts),
         envir = globalenv())
  retrieval_embedding_cache_reset()
  on.exit({
    if (had) assign("retrieval_embed_texts", old, envir = globalenv())
    else rm("retrieval_embed_texts", envir = globalenv())
    retrieval_embedding_cache_reset()
  }, add = TRUE)
  force(code)
}

na_row_vector <- function(i, dim = 32L) {
  j <- seq_len(dim)
  v <- sin(as.numeric(i) * 7919 + j * 104729) + cos(as.numeric(i) * 15485863 + j * 31)
  v / sqrt(sum(v * v))
}

# Documents keep their own vectors; EVERY query is placed exactly on the
# vector of `wrong_row`. Cosine against that row is 1.000 and every other
# row is near-orthogonal, so the semantic tier proposes the wrong code
# with maximal possible confidence.
na_adversarial_embedder <- function(doc_texts, wrong_row, dim = 32L) {
  doc_row <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_along(doc_texts)) assign(doc_texts[i], i, envir = doc_row)
  function(texts) {
    texts <- as.character(texts)
    texts[is.na(texts)] <- ""
    m <- matrix(0, nrow = length(texts), ncol = dim)
    for (i in seq_along(texts)) {
      r <- doc_row[[texts[i]]]
      if (is.null(r)) r <- wrong_row
      m[i, ] <- na_row_vector(r, dim)
    }
    m
  }
}

na_table <- function() {
  data.frame(
    system = "psoc", version = "2022",
    level = c("unit_group", "unit_group", "unit_group"),
    code = c("8332", "6111", "2330"),
    label = c("HEAVY TRUCK AND LORRY DRIVERS", "RICE FARMERS",
              "SECONDARY EDUCATION TEACHERS"),
    description = NA_character_, parent_code = NA_character_,
    status = "current", source = "Philippine Statistics Authority",
    source_url = "https://psa.gov.ph/classification/psoc",
    stringsAsFactors = FALSE
  )
}

# Fixture whose semantic tier always proposes SECONDARY EDUCATION
# TEACHERS (row 3) no matter what is asked.
na_fixture <- function(wrong_row = 3L, dim = 32L) {
  data <- na_table()
  corpus <- retrieval_corpus(data)
  docs <- retrieval_embedding_documents(data, system = "psoc", version = "2022")
  embed <- na_adversarial_embedder(docs$text, wrong_row, dim = dim)
  index <- retrieval_embeddings_build(
    corpus, config = list(model = paste0("adversarial-", dim)),
    embed_fn = embed, data = data, system = "psoc", version = "2022",
    documents = docs
  )
  list(data = data, corpus = corpus, docs = docs, embed = embed, index = index)
}

# ------------------------------------------------- the engine-level proof

test_that("shadow mode returns byte-identical retrieval results to off", {
  b <- na_fixture()
  queries <- c("heavy truck driver", "rice farmer", "tsuper ng trak",
               "palay", "vulcanizer")

  for (q in queries) {
    off <- with_semantic_mode("off", with_stub_provider(b$embed, {
      retrieval_embedding_cache_reset()
      search_classification_data_result(b$data, q, limit = 10L, hybrid = TRUE,
                                        embedding_index = b$index, corpus = b$corpus)
    }))

    retrieval_shadow_reset()
    shadow <- with_semantic_mode("shadow", with_stub_provider(b$embed, {
      retrieval_embedding_cache_reset()
      search_classification_data_result(b$data, q, limit = 10L, hybrid = TRUE,
                                        embedding_index = b$index, corpus = b$corpus)
    }))

    # No index at all: the third point of comparison, which rules out the
    # possibility that BOTH arms were perturbed equally.
    none <- with_semantic_mode("off", {
      search_classification_data_result(b$data, q, limit = 10L, hybrid = TRUE,
                                        embedding_index = NULL, corpus = b$corpus)
    })

    expect_identical(shadow, off, info = paste("query:", q))
    expect_identical(shadow, none, info = paste("query:", q))

    # ...AND the tier really ran, and really proposed the wrong answer.
    expect_gt(retrieval_shadow_count(), 0L)
    rec <- retrieval_shadow_last()
    expect_identical(rec$semantic_top1_code, "2330")
    expect_gt(rec$semantic_top1_score, 0.999)
    expect_false(rec$semantic_authority_applied)
  }
  retrieval_shadow_reset()
})

test_that("the adversarial code never enters the returned result set", {
  b <- na_fixture()
  retrieval_shadow_reset()
  res <- with_semantic_mode("shadow", with_stub_provider(b$embed, {
    search_classification_data_result(b$data, "heavy truck driver", limit = 10L,
                                      hybrid = TRUE, embedding_index = b$index,
                                      corpus = b$corpus)
  }))
  codes <- as.character(res$data$code)
  expect_true("8332" %in% codes)
  # The tier shouted 2330 at cosine 1.000 and was not listened to.
  expect_identical(retrieval_shadow_last()$semantic_top1_code, "2330")
  expect_false("2330" %in% codes)
  retrieval_shadow_reset()
})

test_that("off mode never calls the provider at all", {
  b <- na_fixture()
  calls <- 0L
  counting <- function(texts) { calls <<- calls + 1L; b$embed(texts) }

  with_semantic_mode("off", with_stub_provider(counting, {
    retrieval_embedding_cache_reset()
    search_classification_data_result(b$data, "heavy truck driver", limit = 10L,
                                      hybrid = TRUE, embedding_index = b$index,
                                      corpus = b$corpus)
  }))
  expect_identical(calls, 0L)
  expect_identical(retrieval_shadow_count(), 0L)

  with_semantic_mode("shadow", with_stub_provider(counting, {
    retrieval_embedding_cache_reset()
    retrieval_shadow_reset()
    search_classification_data_result(b$data, "heavy truck driver", limit = 10L,
                                      hybrid = TRUE, embedding_index = b$index,
                                      corpus = b$corpus)
  }))
  expect_gt(calls, 0L)
  retrieval_shadow_reset()
})

# ------------------------------------------------- provider failure (32)

test_that("a provider failure in shadow mode changes nothing and raises nothing", {
  b <- na_fixture()
  failures <- list(
    thrower   = function(texts) stop("connection refused"),
    nuller    = function(texts) NULL,
    wrong_dim = function(texts) matrix(1, nrow = length(texts), ncol = 3L),
    garbage   = function(texts) "not a matrix"
  )

  baseline <- with_semantic_mode("off", {
    search_classification_data_result(b$data, "heavy truck driver", limit = 10L,
                                      hybrid = TRUE, embedding_index = NULL,
                                      corpus = b$corpus)
  })

  for (nm in names(failures)) {
    retrieval_shadow_reset()
    res <- with_semantic_mode("shadow", with_stub_provider(failures[[nm]], {
      expect_no_error(search_classification_data_result(
        b$data, "heavy truck driver", limit = 10L, hybrid = TRUE,
        embedding_index = b$index, corpus = b$corpus))
    }))
    expect_identical(res, baseline, info = paste("failure mode:", nm))
    expect_true("8332" %in% as.character(res$data$code), info = nm)

    # Telemetry degrades to "unavailable" rather than disappearing: the
    # observation that the provider failed is itself worth recording.
    rec <- retrieval_shadow_last()
    expect_false(is.null(rec), info = nm)
    expect_identical(rec$provider_status, "provider_unavailable", info = nm)
    expect_identical(length(rec$semantic_codes), 0L, info = nm)
    expect_false(rec$semantic_authority_applied, info = nm)
  }
  retrieval_shadow_reset()
})

# ----------------------------------- the assistant coding packet (spec 24)

test_that("shadow mode leaves selected_code, allowed_codes and clarification identical", {
  # The engine-level proof above uses a three-row fixture. This one runs
  # the REAL coding service over the REAL PSOC 2022 table, with the
  # adversarial index injected into the process index cache so that the
  # repository hands it to the engine exactly as it would a shipped
  # artifact. Nothing is written to disk.
  data <- get_classification("psoc", "2022", level = NULL)
  corpus <- retrieval_corpus_get(data, "psoc", "2022")
  docs <- retrieval_embedding_documents(data, system = "psoc", version = "2022")

  wrong_row <- match("2330", as.character(data$code))
  expect_false(is.na(wrong_row))

  embed <- na_adversarial_embedder(docs$text, wrong_row, dim = 32L)
  index <- retrieval_embeddings_build(
    corpus, config = list(model = "adversarial-32"), embed_fn = embed,
    data = data, system = "psoc", version = "2022", documents = docs
  )
  expect_true(retrieval_embeddings_index_is_valid(index, corpus,
                                                  system = "psoc", version = "2022"))

  key <- paste("validated", "embeddings", "psoc", "2022",
               "_all_", "_all_", corpus$n, sep = "::")
  assign(key, index, envir = .retrieval_index_cache)
  # MUST be removed: a leaked index would silently give every later test
  # file in the suite a semantic tier.
  on.exit(suppressWarnings(rm(list = key, envir = .retrieval_index_cache)), add = TRUE)

  probes <- list(
    list(occupation = "truck driver", systems = "psoc"),
    list(occupation = "rice farmer", systems = "psoc"),
    list(occupation = "carpenter", systems = "psoc")
  )

  for (p in probes) {
    off <- with_semantic_mode("off", with_stub_provider(embed, {
      retrieval_shadow_reset()
      assistant_coding_service(occupation = p$occupation,
                               requested_systems = p$systems)
    }))
    expect_identical(retrieval_shadow_count(), 0L)

    shadow <- with_semantic_mode("shadow", with_stub_provider(embed, {
      retrieval_shadow_reset()
      assistant_coding_service(occupation = p$occupation,
                               requested_systems = p$systems)
    }))

    # The tier ran, inside the real service, and proposed the wrong code
    # at the highest cosine the metric allows.
    expect_gt(retrieval_shadow_count(), 0L, label = p$occupation)
    tops <- vapply(retrieval_shadow_records(),
                   function(r) r$semantic_top1_code %||% NA_character_,
                   character(1))
    expect_true(all(tops[!is.na(tops)] == "2330"), label = p$occupation)

    # ...and the packet is unchanged in every field the spec names.
    expect_identical(shadow$occupation$selected_code,
                     off$occupation$selected_code, label = p$occupation)
    expect_identical(assistant_allowed_codes(shadow),
                     assistant_allowed_codes(off), label = p$occupation)
    expect_identical(shadow$clarification, off$clarification, label = p$occupation)
    expect_identical(shadow$status, off$status, label = p$occupation)
    expect_identical(shadow$current_edition_enforced,
                     off$current_edition_enforced, label = p$occupation)
    # Whole-packet equality, which subsumes the four above and catches
    # anything the spec did not think to name.
    expect_identical(shadow, off, label = p$occupation)
  }
  retrieval_shadow_reset()
})

# ------------------------------------------------- the release rule (40)

test_that("active is a named state and is not reachable", {
  expect_true("active" %in% RETRIEVAL_SEMANTIC_MODES)
  expect_false(RETRIEVAL_SEMANTIC_ACTIVE_PERMITTED)

  # Requested explicitly...
  expect_identical(retrieval_semantic_mode("active"), "shadow")
  # ...and through the environment.
  with_semantic_mode("active", {
    expect_identical(retrieval_semantic_mode(), "shadow")
    # The operator's intent is still legible, so a diagnostic can say
    # "recognised, deliberately held".
    expect_identical(retrieval_semantic_mode_requested(), "active")
  })

  # Nothing reachable is authoritative.
  for (m in c("off", "shadow", "active")) {
    expect_false(retrieval_semantic_is_authoritative(retrieval_semantic_mode(m)))
  }
})

test_that("the threshold-gated evidence exemption stays inactive", {
  # Spec 28: measure, do not activate. The exemption exists in
  # retrieval_engine.R and must remain unreachable at its current
  # threshold, which no cosine below 0.90 can clear.
  expect_identical(RETRIEVAL_MIN_SEMANTIC_EXEMPT, 0.90)
  below <- data.frame(idx = c(1L, 2L), score = c(0.89, 0.5), rank = 1:2)
  expect_identical(.retrieval_semantic_exempt(below), integer(0))
  # And in shadow mode the engine never sees a semantic candidate set at
  # all, so the exemption has nothing to act on regardless of threshold.
  b <- na_fixture()
  cand <- with_semantic_mode("shadow", with_stub_provider(b$embed, {
    retrieval_embeddings_candidates("heavy truck driver", b$index)
  }))
  expect_identical(nrow(cand), 0L)
  retrieval_shadow_reset()
})

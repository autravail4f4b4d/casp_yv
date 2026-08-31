# Semantic mode resolution and shadow telemetry.
#
# Spec 24 (three explicit modes) and spec 26 (what one observation must
# capture). The proof that shadow mode cannot change an answer lives in
# test-semantic-non-authority.R; this file covers the mechanism itself --
# mode parsing, the record's contents, the memory bound, the reset, the
# no-op path, and the requirement that none of it is ever rendered.
#
# NO NETWORK, NO CREDENTIALS, NO SKIPS.

with_semantic_mode <- function(mode, code) {
  had <- Sys.getenv("RETRIEVAL_SEMANTIC_MODE", unset = NA_character_)
  if (is.null(mode)) Sys.unsetenv("RETRIEVAL_SEMANTIC_MODE") else Sys.setenv(RETRIEVAL_SEMANTIC_MODE = mode)
  on.exit({
    if (is.na(had)) Sys.unsetenv("RETRIEVAL_SEMANTIC_MODE") else Sys.setenv(RETRIEVAL_SEMANTIC_MODE = had)
  }, add = TRUE)
  force(code)
}

sh_row_vector <- function(i, dim = 32L) {
  j <- seq_len(dim)
  v <- sin(as.numeric(i) * 7919 + j * 104729) + cos(as.numeric(i) * 15485863 + j * 31)
  v / sqrt(sum(v * v))
}

sh_fixture <- function(dim = 32L) {
  data <- data.frame(
    system = "psoc", version = "2022",
    level = "unit_group",
    code = c("8332", "6111", "2330"),
    label = c("HEAVY TRUCK AND LORRY DRIVERS", "RICE FARMERS",
              "SECONDARY EDUCATION TEACHERS"),
    description = NA_character_, parent_code = NA_character_,
    status = "current", source = "Philippine Statistics Authority",
    source_url = "https://psa.gov.ph/classification/psoc",
    stringsAsFactors = FALSE
  )
  corpus <- retrieval_corpus(data)
  docs <- retrieval_embedding_documents(data, system = "psoc", version = "2022")
  doc_row <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_along(docs$text)) assign(docs$text[i], i, envir = doc_row)
  embed <- function(texts) {
    texts <- as.character(texts); texts[is.na(texts)] <- ""
    m <- matrix(0, nrow = length(texts), ncol = dim)
    for (i in seq_along(texts)) {
      r <- doc_row[[texts[i]]]
      if (is.null(r)) r <- 1L
      m[i, ] <- sh_row_vector(r, dim)
    }
    m
  }
  index <- retrieval_embeddings_build(
    corpus, config = list(model = paste0("shadow-", dim)), embed_fn = embed,
    data = data, system = "psoc", version = "2022", documents = docs
  )
  list(data = data, corpus = corpus, docs = docs, embed = embed, index = index)
}

# --------------------------------------------------- mode resolution (24)

test_that("the mode vocabulary is exactly off / shadow / active", {
  expect_identical(RETRIEVAL_SEMANTIC_MODES, c("off", "shadow", "active"))
  expect_identical(RETRIEVAL_SEMANTIC_DEFAULT_MODE, "off")
})

test_that("the repository default is off", {
  with_semantic_mode(NULL, {
    expect_identical(retrieval_semantic_mode(), "off")
    expect_false(retrieval_shadow_enabled())
    expect_false(retrieval_semantic_is_authoritative())
  })
})

test_that("mode parsing is tolerant of case and whitespace", {
  for (v in c("shadow", "SHADOW", "  Shadow  ")) {
    with_semantic_mode(v, expect_identical(retrieval_semantic_mode(), "shadow"))
  }
  with_semantic_mode("OFF", expect_identical(retrieval_semantic_mode(), "off"))
})

test_that("an unrecognised mode fails closed rather than erroring", {
  # A typo in a deployment variable must not take the app down, and must
  # not accidentally turn something on.
  for (v in c("on", "true", "1", "sahdow", "")) {
    with_semantic_mode(v, expect_identical(retrieval_semantic_mode(), "off"))
  }
  expect_identical(retrieval_semantic_mode(NA), "off")
  expect_identical(retrieval_semantic_mode(character(0)), "off")
  expect_identical(retrieval_semantic_mode(c("shadow", "off")), "off")
})

test_that("mode is independent of the embedding provider's own switch", {
  # Transport and authority are separate questions: shadow must be
  # measurable with an injected encoder and no endpoint, which is the
  # only reason this test suite can exist at all.
  with_semantic_mode("shadow", {
    expect_identical(retrieval_semantic_mode(), "shadow")
    expect_false(retrieval_embedding_available())
  })
})

# ----------------------------------------------------- the record (26)

test_that("a shadow record captures every field section 26 names", {
  retrieval_shadow_reset()
  id <- retrieval_shadow_record(
    query = "  Tsuper NG Trak ", system = "psoc", version = "2022",
    codes = c("8332", "9331"), scores = c(0.91, 0.44), ranks = c(1L, 2L),
    deterministic_code = "9331", context_compatible = "compatible",
    provider_status = "ok", origin = "probe", mode = "shadow"
  )
  expect_false(is.null(id))

  r <- retrieval_shadow_last()
  expect_identical(r$normalized_query, retrieval_normalize("Tsuper NG Trak"))
  expect_identical(r$system, "psoc")
  expect_identical(r$version, "2022")
  expect_identical(r$deterministic_code, "9331")
  expect_identical(r$semantic_codes, c("8332", "9331"))
  expect_identical(r$semantic_scores, c(0.91, 0.44))
  expect_identical(r$semantic_ranks, c(1L, 2L))
  # The rank of the DETERMINISTIC answer inside the semantic shortlist --
  # the number the activation decision actually turns on.
  expect_identical(r$deterministic_rank, 2L)
  expect_identical(r$context_compatible, "compatible")
  expect_identical(r$provider_status, "ok")
  expect_false(r$semantic_authority_applied)
  retrieval_shadow_reset()
})

test_that("a deterministic answer absent from the shortlist ranks NA", {
  retrieval_shadow_reset()
  retrieval_shadow_record(query = "x", codes = c("1", "2"),
                          deterministic_code = "9999", mode = "shadow")
  expect_true(is.na(retrieval_shadow_last()$deterministic_rank))
  retrieval_shadow_reset()
})

test_that("the deterministic half can be attached after the fact", {
  retrieval_shadow_reset()
  id <- retrieval_shadow_record(query = "palay", codes = c("0112", "6111"),
                                scores = c(0.8, 0.7), mode = "shadow")
  expect_true(is.na(retrieval_shadow_last()$deterministic_code))

  expect_true(retrieval_shadow_annotate("6111", context_compatible = "incompatible"))
  r <- retrieval_shadow_last()
  expect_identical(r$deterministic_code, "6111")
  expect_identical(r$deterministic_rank, 2L)
  expect_identical(r$context_compatible, "incompatible")
  expect_false(r$semantic_authority_applied)

  # Addressable by id, so a concurrent probe cannot annotate the wrong row.
  expect_true(retrieval_shadow_annotate("0112", id = id))
  expect_identical(retrieval_shadow_last()$deterministic_rank, 1L)

  expect_false(retrieval_shadow_annotate("0112", id = 99999L))
  retrieval_shadow_reset()
})

test_that("an unknown context verdict is normalised, not invented", {
  retrieval_shadow_reset()
  retrieval_shadow_record(query = "x", context_compatible = "probably fine",
                          mode = "shadow")
  expect_identical(retrieval_shadow_last()$context_compatible, "unknown")
  retrieval_shadow_reset()
})

test_that("semantic_authority_applied is FALSE and has no setter", {
  retrieval_shadow_reset()
  for (i in 1:5) {
    retrieval_shadow_record(query = paste("q", i), codes = "1",
                            deterministic_code = "1", mode = "shadow")
  }
  # No argument of the recorder can raise it, and annotation re-asserts it.
  retrieval_shadow_annotate("1")
  expect_true(retrieval_shadow_invariants_hold())
  expect_false(any(retrieval_shadow_summary()$semantic_authority_applied))
  expect_false("semantic_authority_applied" %in%
                 names(formals(retrieval_shadow_record)))
  retrieval_shadow_reset()
})

# ---------------------------------------------------- the no-op path

test_that("recording is a no-op with the mode off", {
  retrieval_shadow_reset()
  expect_null(retrieval_shadow_record(query = "x", codes = "1", mode = "off"))
  with_semantic_mode("off", {
    expect_null(retrieval_shadow_record(query = "x", codes = "1"))
    expect_null(retrieval_shadow_observe("x", NULL))
  })
  expect_identical(retrieval_shadow_count(), 0L)
  expect_identical(nrow(retrieval_shadow_summary()), 0L)
  expect_true(retrieval_shadow_invariants_hold())
})

test_that("an empty ring reports cleanly rather than erroring", {
  retrieval_shadow_reset()
  expect_null(retrieval_shadow_last())
  expect_false(retrieval_shadow_annotate("1"))
  s <- retrieval_shadow_summary()
  expect_s3_class(s, "data.frame")
  expect_identical(nrow(s), 0L)
})

# ---------------------------------------------------- the memory bound

test_that("the ring is bounded and drops oldest first", {
  retrieval_shadow_reset()
  n <- RETRIEVAL_SHADOW_MAX_RECORDS + 25L
  for (i in seq_len(n)) {
    retrieval_shadow_record(query = paste0("query ", i), codes = "1",
                            mode = "shadow")
  }
  expect_identical(retrieval_shadow_count(), RETRIEVAL_SHADOW_MAX_RECORDS)
  expect_identical(retrieval_shadow_dropped(), 25L)
  # Oldest evicted, newest retained.
  ids <- vapply(retrieval_shadow_records(), function(r) r$id, integer(1))
  expect_identical(min(ids), 26L)
  expect_identical(max(ids), n)
  retrieval_shadow_reset()
})

test_that("reset clears records, sequence and drop count", {
  retrieval_shadow_record(query = "x", mode = "shadow")
  retrieval_shadow_reset()
  expect_identical(retrieval_shadow_count(), 0L)
  expect_identical(retrieval_shadow_dropped(), 0L)
  expect_null(retrieval_shadow_last())
})

# --------------------------------------------------- the observe path

test_that("observe measures a real semantic search without returning candidates", {
  b <- sh_fixture()
  retrieval_shadow_reset()

  id <- retrieval_shadow_observe(
    "tsuper ng trak", b$index,
    deterministic_codes = c("8332", "6111"),
    system = "psoc", version = "2022",
    embed_fn = b$embed, mode = "shadow"
  )
  expect_false(is.null(id))

  r <- retrieval_shadow_last()
  expect_identical(r$origin, "probe")
  expect_identical(r$provider_status, "ok")
  expect_gt(length(r$semantic_codes), 0L)
  expect_identical(r$semantic_top1_code, "8332")
  expect_gt(r$semantic_top1_score, 0.999)
  expect_identical(r$deterministic_code, "8332")
  expect_identical(r$deterministic_rank, 1L)
  expect_false(r$semantic_authority_applied)

  # A record id is the ONLY thing the caller gets back. There is no
  # candidate set here for anyone to accidentally consume.
  expect_true(is.numeric(id) || is.integer(id))
  retrieval_shadow_reset()
})

test_that("observe records the failure rather than the exception", {
  b <- sh_fixture()
  retrieval_shadow_reset()
  retrieval_shadow_observe("tsuper ng trak", b$index, system = "psoc",
                           version = "2022",
                           embed_fn = function(texts) stop("endpoint down"),
                           mode = "shadow")
  r <- retrieval_shadow_last()
  expect_identical(r$provider_status, "provider_unavailable_or_empty")
  expect_identical(length(r$semantic_codes), 0L)

  retrieval_shadow_reset()
  retrieval_shadow_observe("tsuper ng trak", NULL, mode = "shadow")
  expect_identical(retrieval_shadow_last()$provider_status, "no_index")
  retrieval_shadow_reset()
})

test_that("a system mismatch measures nothing, exactly as the search does", {
  b <- sh_fixture()
  retrieval_shadow_reset()
  retrieval_shadow_observe("tsuper ng trak", b$index, system = "psic",
                           version = "2026", embed_fn = b$embed, mode = "shadow")
  expect_identical(length(retrieval_shadow_last()$semantic_codes), 0L)
  retrieval_shadow_reset()
})

# ------------------------------------------------ telemetry stays internal

test_that("no UI or assistant source consumes shadow telemetry", {
  # Spec 26: never exposed to the user, never in model prose, never in a
  # shipped artifact. The cheapest durable guard is a source scan --
  # anything that renders must not be able to reach these functions.
  root <- normalizePath(file.path(getwd(), "..", ".."))
  dirs <- c(file.path(root, "R", "ui"), file.path(root, "R", "assistant"))
  files <- unlist(lapply(dirs, function(d) {
    if (!dir.exists(d)) character(0)
    else list.files(d, pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  }))
  app <- file.path(root, "app.R")
  if (file.exists(app)) files <- c(files, app)
  expect_gt(length(files), 0L)

  pattern <- "retrieval_shadow_|\\.retrieval_shadow_state"
  offenders <- Filter(function(f) {
    any(grepl(pattern, readLines(f, warn = FALSE)))
  }, files)
  expect_identical(offenders, character(0))
})

test_that("no shadow telemetry is persisted to a shipped artifact", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  expect_identical(
    list.files(file.path(root, "data"), pattern = "shadow", ignore.case = TRUE),
    character(0)
  )
  # And nothing in the module writes.
  src <- readLines(file.path(root, "R", "retrieval", "retrieval_shadow.R"),
                   warn = FALSE)
  expect_false(any(grepl("saveRDS|writeLines|write\\.csv|file\\.create|cat\\(", src)))
})

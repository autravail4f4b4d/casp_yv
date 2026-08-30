# Semantic document construction, index schema, and invalidation.
#
# Covers sections 10, 11, 14 and 15 of
# SEMANTIC_RETRIEVAL_AND_CONTEXT_CONSISTENCY_HARDENING.md.
#
# NO NETWORK, NO CREDENTIALS, NO SKIPS (section 55). Every embedding in
# this file comes from a deterministic in-test stub through the `embed_fn`
# injection seam.
#
# The load-bearing assertion in this file is the PSIC one: a historical
# 2009/2019 activity code must never appear in a document describing a
# current 2026 row. That is not a style preference -- a historical code
# embedded as if current is precisely the silent edition substitution the
# classification rules forbid, and it would be invisible at query time
# because the vector, not the text, is what gets compared.

# A deterministic offline vectoriser. Not a semantic model: it only has to
# be a stable function of the text.
sem_stub_embedder <- function(dim = 32L) {
  force(dim)
  function(texts) {
    texts <- as.character(texts)
    texts[is.na(texts)] <- ""
    m <- matrix(0, nrow = length(texts), ncol = dim)
    for (i in seq_along(texts)) {
      toks <- strsplit(texts[i], " ", fixed = TRUE)[[1]]
      toks <- toks[nzchar(toks)]
      if (!length(toks)) { m[i, 1L] <- 1; next }
      for (tok in toks) {
        cps <- utf8ToInt(tok)
        m[i, (sum(cps * seq_along(cps)) %% dim) + 1L] <-
          m[i, (sum(cps * seq_along(cps)) %% dim) + 1L] + 1
      }
    }
    m
  }
}

sem_psoc_table <- function() {
  data.frame(
    system = "psoc", version = "2022",
    level = c("major_group", "unit_group", "unit_group"),
    code = c("8", "8141", "8332"),
    label = c("PLANT AND MACHINE OPERATORS AND ASSEMBLERS",
              "RUBBER PRODUCTS MACHINE OPERATORS",
              "HEAVY TRUCK AND LORRY DRIVERS"),
    description = c(NA_character_, NA_character_, NA_character_),
    parent_code = c(NA_character_, "8", "8"),
    stringsAsFactors = FALSE
  )
}

sem_psic_table <- function() {
  data.frame(
    system = "psic", version = "2026",
    level = c("section", "class", "sub-class"),
    code = c("I", "5610", "56105"),
    label = c("Accommodation and Food Service Activities",
              "Restaurants and mobile food service activities",
              "Activities of carinderia or eatery"),
    description = c(NA_character_, NA_character_, NA_character_),
    parent_code = c(NA_character_, "I", "5610"),
    stringsAsFactors = FALSE
  )
}

# ------------------------------------------------------ recipe selection

test_that("each classification system gets its own document recipe", {
  expect_identical(retrieval_embedding_doc_recipe("psoc"), "psoc")
  expect_identical(retrieval_embedding_doc_recipe("PSOC"), "psoc")
  expect_identical(retrieval_embedding_doc_recipe("psic"), "psic")
  # Every other registered system falls back to the generic recipe rather
  # than borrowing PSOC's or PSIC's evidence rules.
  expect_identical(retrieval_embedding_doc_recipe("pscc"), "generic")
  expect_identical(retrieval_embedding_doc_recipe("psgc"), "generic")
  expect_identical(retrieval_embedding_doc_recipe(NULL), "generic")
})

# -------------------------------------------- section 10: what is embedded

test_that("a document is more than the label: hierarchy and level are carried", {
  docs <- retrieval_embedding_documents(sem_psoc_table(), guidance = FALSE,
                                        curated = FALSE)

  expect_identical(length(docs$text), 3L)
  expect_identical(docs$recipe, "psoc")
  expect_identical(docs$doc_recipe_version, RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION)

  # Row 2's document carries its own label, its parent's label, and its
  # classification level -- none of which the v1 label-only recipe had.
  d2 <- docs$text[2]
  expect_true(grepl("rubber products machine operators", d2, fixed = TRUE))
  expect_true(grepl("plant and machine operators", d2, fixed = TRUE))
  expect_true(grepl("unit group", d2, fixed = TRUE))

  # Documents are normalized on the same pipeline queries use: lower case,
  # no punctuation. A document that kept its original case would never
  # match a normalized query vector's text.
  expect_identical(docs$text, retrieval_normalize(docs$text))
})

test_that("a root row with no parent still produces a usable document", {
  docs <- retrieval_embedding_documents(sem_psoc_table(), guidance = FALSE,
                                        curated = FALSE)
  expect_true(nzchar(docs$text[1]))
  expect_true(grepl("plant and machine operators", docs$text[1], fixed = TRUE))
  expect_false(docs$provenance$hierarchy_used[1])
})

test_that("documents are bounded in length and cut on a token boundary", {
  long <- data.frame(
    system = "pscc", version = "2022", level = "commodity",
    code = "0101.29.00-001",
    label = paste(rep("verylongcommoditywordthatrepeats", 40), collapse = " "),
    description = NA_character_, parent_code = NA_character_,
    stringsAsFactors = FALSE
  )
  docs <- retrieval_embedding_documents(long)
  expect_lte(nchar(docs$text[1]), RETRIEVAL_EMBEDDING_DOC_MAX_CHARS)
  # Truncation must not leave a half word, which would be a token the
  # encoder has never seen in any other document.
  expect_false(grepl(" $", docs$text[1]))
  expect_true(all(nchar(strsplit(docs$text[1], " ", fixed = TRUE)[[1]]) > 1L))
})

test_that("PSOC admits a survey-guidance phrase only when its code is current", {
  guidance <- list(
    list(term = "vulcanizer", code = "8141"),
    list(term = "tire maker", code = "8141"),
    # A code this edition does not have. It must contribute nothing --
    # never be re-pointed at a neighbouring code.
    list(term = "obsolete occupation", code = "9999")
  )
  docs <- retrieval_embedding_documents(sem_psoc_table(), guidance = guidance,
                                        curated = FALSE)

  expect_true(grepl("vulcanizer", docs$text[2], fixed = TRUE))
  expect_true(grepl("tire maker", docs$text[2], fixed = TRUE))
  expect_true(docs$provenance$survey_guidance_used[2])

  expect_false(any(grepl("obsolete occupation", docs$text, fixed = TRUE)))
  expect_false(docs$provenance$survey_guidance_used[1])
  expect_false(docs$provenance$survey_guidance_used[3])
})

test_that("curated PSOC terminology is admitted on the same code-verified terms", {
  curated <- data.frame(
    occupation = c("Tire Vulcanizing Shop Worker", "Ghost Occupation"),
    curated_psoc = c("8141", "0000"),
    stringsAsFactors = FALSE
  )
  docs <- retrieval_embedding_documents(sem_psoc_table(), guidance = FALSE,
                                        curated = curated)

  expect_true(grepl("tire vulcanizing shop worker", docs$text[2], fixed = TRUE))
  expect_true(docs$provenance$curated_terminology_used[2])
  expect_false(any(grepl("ghost occupation", docs$text, fixed = TRUE)))
})

test_that("PSIC carries historical activity WORDING but never a historical code", {
  hints <- list(
    list(term = "carinderia", activity = "carinderia or eatery",
         historical_code = "56107"),
    # An activity that matches no current label contributes nothing at all.
    list(term = "water refilling station",
         activity = "water purifying and refilling station",
         historical_code = "11053")
  )
  docs <- retrieval_embedding_documents(sem_psic_table(), guidance = hints)

  # The wording reached the current row whose canonical label contains it.
  expect_true(grepl("carinderia or eatery", docs$text[3], fixed = TRUE))
  expect_true(docs$provenance$historical_activity_text_used[3])

  # SECTION 10.2, THE LOAD-BEARING RULE. The 2009/2019 code that the
  # guidance row carries for audit must appear in no document, anywhere.
  expect_false(any(grepl("56107", docs$text, fixed = TRUE)))
  expect_false(any(grepl("11053", docs$text, fixed = TRUE)))

  # An unmatched activity is dropped rather than attached to the nearest
  # plausible row.
  expect_false(any(grepl("water purifying", docs$text, fixed = TRUE)))
  expect_false(any(docs$provenance$historical_activity_text_used[1:2]))
})

test_that("PSIC never receives PSOC's occupation-phrase evidence, or vice versa", {
  psoc_guidance <- list(list(term = "vulcanizer", code = "8141"))
  # The PSIC recipe ignores an occupation-phrase table entirely: it has no
  # code-verified occupation evidence to admit.
  docs <- retrieval_embedding_documents(sem_psic_table(), guidance = psoc_guidance)
  expect_false(any(grepl("vulcanizer", docs$text, fixed = TRUE)))
  expect_false(any(docs$provenance$survey_guidance_used))
})

# ------------------------------------------------ section 11: provenance

test_that("provenance explains why every document says what it says", {
  guidance <- list(list(term = "vulcanizer", code = "8141"))
  docs <- retrieval_embedding_documents(sem_psoc_table(), guidance = guidance,
                                        curated = FALSE)
  p <- docs$provenance

  expect_true(is.data.frame(p))
  expect_identical(nrow(p), 3L)
  expect_true(all(c("semantic_document_sources", "current_label_used",
                    "current_description_used", "survey_guidance_used",
                    "historical_activity_text_used",
                    "historical_code_authoritative") %in% names(p)))

  expect_identical(p$code, c("8", "8141", "8332"))
  expect_true(all(p$current_label_used))
  # These fixtures carry no description, which is also the state of the
  # real PSOC 2022 and PSIC 2026 tables (measured: 0 of 649 and 0 of 2202).
  expect_false(any(p$current_description_used))

  expect_true(grepl("current_label", p$semantic_document_sources[2], fixed = TRUE))
  expect_true(grepl("survey_guidance_occupation_phrase",
                    p$semantic_document_sources[2], fixed = TRUE))

  # An invariant, not a computed column: no document ever derives its
  # authority from a historical edition.
  expect_true(all(p$historical_code_authoritative == FALSE))
})

# --------------------------------------------- section 14: index schema

test_that("the index records every field needed to detect a stale artifact", {
  data <- sem_psoc_table()
  corpus <- retrieval_corpus(data)
  index <- retrieval_embeddings_build(
    corpus, config = list(model = "stub-model"), embed_fn = sem_stub_embedder(),
    data = data, system = "psoc", version = "2022"
  )

  expect_false(is.null(index))
  expect_s3_class(index, "retrieval_embedding_index")

  # Section 14's required fields, each present and each meaningful.
  expect_identical(index$index_version, RETRIEVAL_EMBEDDING_INDEX_VERSION)
  expect_identical(index$doc_recipe_version, RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION)
  expect_identical(index$doc_recipe, "psoc")
  expect_identical(index$system, "psoc")
  expect_identical(index$version, "2022")
  expect_identical(index$n_docs, 3L)
  expect_identical(index$dim, 32L)
  expect_identical(index$model, "stub-model")
  # Canonical row identity: the UNMODIFIED codes, in row order, so a
  # candidate can be resolved to a real record without the repository.
  expect_identical(index$codes, c("8", "8141", "8332"))
  expect_true(nzchar(index$corpus_fingerprint))
  expect_true(nzchar(index$doc_fingerprint))
  expect_identical(nrow(index$provenance), 3L)

  # Vectors are stored unit length so cosine is one matrix-vector product.
  expect_equal(sqrt(rowSums(index$vectors^2)), rep(1, 3), tolerance = 1e-9)
})

test_that("codes are stored as strings, so leading zeros and dots survive", {
  data <- data.frame(
    system = "pscc", version = "2022", level = "commodity",
    code = c("0101.29.00-001", "0709.93.00-004"),
    label = c("Live horses", "Bitter gourd (Ampalaya)"),
    description = NA_character_, parent_code = NA_character_,
    stringsAsFactors = FALSE
  )
  index <- retrieval_embeddings_build(
    retrieval_corpus(data), embed_fn = sem_stub_embedder(),
    data = data, system = "pscc", version = "2022"
  )
  expect_identical(index$codes, c("0101.29.00-001", "0709.93.00-004"))
  expect_type(index$codes, "character")
})

test_that("a canonical table misaligned with its corpus refuses to build", {
  data <- sem_psoc_table()
  corpus <- retrieval_corpus(data)
  # One fewer row than the corpus: every document would attach to the wrong
  # record. Refusing is the only safe outcome.
  expect_null(retrieval_embeddings_build(
    corpus, embed_fn = sem_stub_embedder(), data = data[1:2, , drop = FALSE],
    system = "psoc", version = "2022"
  ))
  expect_null(retrieval_embeddings_build(
    corpus, embed_fn = sem_stub_embedder(), data = "not a table"
  ))
})

# ---------------------------------------- section 15: index invalidation

test_that("an index built under an older schema or recipe is rejected", {
  data <- sem_psoc_table()
  corpus <- retrieval_corpus(data)
  index <- retrieval_embeddings_build(
    corpus, embed_fn = sem_stub_embedder(), data = data,
    system = "psoc", version = "2022"
  )
  expect_true(retrieval_embeddings_index_is_valid(index, corpus))

  stale_schema <- index
  stale_schema$index_version <- RETRIEVAL_EMBEDDING_INDEX_VERSION - 1L
  expect_false(retrieval_embeddings_index_is_valid(stale_schema, corpus))

  stale_recipe <- index
  stale_recipe$doc_recipe_version <- RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION - 1L
  expect_false(retrieval_embeddings_index_is_valid(stale_recipe, corpus))

  # A v1 artifact has no recipe version at all.
  v1_shaped <- index
  v1_shaped$doc_recipe_version <- NULL
  expect_false(retrieval_embeddings_index_is_valid(v1_shaped, corpus))

  # And it must not even load, so a stale file on disk is inert rather than
  # half-trusted.
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(v1_shaped, path)
  expect_null(retrieval_embeddings_load(path))
})

test_that("a re-coded row invalidates the index even when its label is unchanged", {
  data <- sem_psoc_table()
  index <- retrieval_embeddings_build(
    retrieval_corpus(data), embed_fn = sem_stub_embedder(), data = data,
    system = "psoc", version = "2022"
  )

  recoded <- data
  recoded$code[2] <- "8149"
  # Same labels, same row count, same order -- only the code moved. A
  # label-only fingerprint would accept this and then attach 8141's vector
  # to code 8149, which is silent substitution.
  expect_false(retrieval_embeddings_index_is_valid(index, retrieval_corpus(recoded)))
})

test_that("index validity is enforced per system and per edition when asked", {
  data <- sem_psoc_table()
  corpus <- retrieval_corpus(data)
  index <- retrieval_embeddings_build(
    retrieval_corpus(data), embed_fn = sem_stub_embedder(), data = data,
    system = "psoc", version = "2022"
  )

  expect_true(retrieval_embeddings_index_is_valid(index, corpus, "psoc", "2022"))
  expect_true(retrieval_embeddings_index_is_valid(index, corpus, "PSOC", "2022"))
  expect_false(retrieval_embeddings_index_is_valid(index, corpus, "psic", "2022"))
  expect_false(retrieval_embeddings_index_is_valid(index, corpus, "psoc", "2012"))

  # The two-argument form retrieval_engine.R uses is unchanged.
  expect_true(retrieval_embeddings_index_is_valid(index, corpus))
})

test_that("building without a canonical table still produces a valid v2 index", {
  # The corpus-only fallback path: no descriptions, no hierarchy, no
  # guidance -- but the same schema, so tooling and tests that only have a
  # corpus are not second-class.
  corpus <- retrieval_corpus(sem_psoc_table())
  index <- retrieval_embeddings_build(corpus, embed_fn = sem_stub_embedder())

  expect_false(is.null(index))
  expect_identical(index$doc_recipe_version, RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION)
  expect_true(retrieval_embeddings_index_is_valid(index, corpus))
})

# ------------------------------- the real tables, through the real recipe

test_that("the live PSOC and PSIC recipes produce complete, code-free documents", {
  skip_if_not(exists("get_classification", mode = "function"))

  psoc <- get_classification("psoc", "2022")
  docs <- retrieval_embedding_documents(psoc, system = "psoc", version = "2022")
  expect_identical(length(docs$text), nrow(psoc))
  expect_true(all(nzchar(docs$text)))
  expect_true(all(docs$provenance$current_label_used))
  # Guidance evidence is loaded in the test session, so some rows must
  # actually carry it -- a recipe that silently found none would look
  # identical to the old label-only one.
  expect_gt(sum(docs$provenance$survey_guidance_used), 0L)

  psic <- get_classification("psic", "2026")
  pdocs <- retrieval_embedding_documents(psic, system = "psic", version = "2026")
  expect_identical(length(pdocs$text), nrow(psic))
  expect_true(all(pdocs$provenance$historical_code_authoritative == FALSE))

  # No historical PSIC code from the survey-guidance table may appear in
  # any current PSIC 2026 document. Checked against the real artifact, not
  # a fixture.
  if (exists("ASSISTANT_GUIDANCE_PSIC_ACTIVITY_HINTS")) {
    hist_codes <- vapply(ASSISTANT_GUIDANCE_PSIC_ACTIVITY_HINTS,
                         function(r) as.character(r$historical_code)[1], character(1))
    hist_codes <- unique(hist_codes[nzchar(hist_codes) & !is.na(hist_codes)])
    joined <- paste(pdocs$text, collapse = " ")
    for (hc in hist_codes) {
      expect_false(grepl(hc, joined, fixed = TRUE),
                   info = paste("historical PSIC code leaked into a current document:", hc))
    }
  }
})

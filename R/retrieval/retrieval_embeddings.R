# The OPTIONAL semantic candidate generator.
#
# Contract with the rest of the hybrid retriever: this file exposes one
# candidate generator with the same signature shape as the fuzzy and
# n-gram tiers, and it FAILS OPEN. When no embedding backend is
# configured -- the default -- `retrieval_embeddings_candidates()` returns
# `retrieval_no_candidates()`, `retrieval_rrf()` drops the empty set, and
# Search / Dual Search / RM behave exactly as they do today. Nothing in
# this file may ever be able to break classification retrieval.
#
# COST MODEL
# -----------------------------------------------------------------
# Document vectors are computed ONCE, offline, by
# scripts/build_retrieval_embeddings.R and stored as an .rds. At runtime
# only the user's query is embedded: one short HTTP call, then one
# matrix-vector product. Embedding the corpus per request would be
# unaffordable and is never done.
#
# WHAT A COSINE SCORE IS AND IS NOT
# -----------------------------------------------------------------
# The score returned here is the cosine of the angle between a query
# vector and a label vector in an embedding space. IT IS NOT A
# PROBABILITY THAT A CLASSIFICATION IS CORRECT, and it must never be
# presented to a user, or to the model, as a confidence that a code is the
# right answer. It orders candidates for a downstream verification step
# against the canonical repository; that verification, not this number,
# decides what may be shown. This is the same rule as CLAUDE.md's
# "no retrieved code = no classification code presented as the answer":
# a high cosine is not retrieval, it is a suggestion of where to look.
#
# Consistent with the evidence hierarchy in CLAUDE.md, semantic
# similarity sits at the BOTTOM of the ordering. It may surface a
# candidate; it may never outrank an exact code or exact label match.

# Bumped when the on-disk index layout changes, so a stale artifact built
# by an earlier version is rejected rather than silently misread.
RETRIEVAL_EMBEDDING_INDEX_VERSION <- 1L

# A cheap, dependency-free, deterministic fingerprint of the corpus text.
#
# Purpose is narrow: detect that an index was built against DIFFERENT
# classification data than the corpus it is now being used with. It is not
# a cryptographic digest and is not used for any security decision, which
# is why base arithmetic is preferred over adding a hashing dependency.
.retrieval_embedding_fingerprint <- function(texts) {
  texts <- as.character(texts)
  texts[is.na(texts)] <- ""
  n <- length(texts)
  if (n == 0L) return("v1-0-0-0-0")

  s <- paste(texts, collapse = "")
  v <- utf8ToInt(s)
  if (length(v) == 0L) return(paste0("v1-", n, "-0-0-0"))

  # Position-weighted sum: sensitive to reordering as well as to content.
  # Values are reduced before multiplication so the running totals stay
  # well inside a double's exact-integer range for any realistic corpus.
  cv <- as.numeric(v %% 65536L)
  w <- as.numeric((seq_along(v) %% 8191L) + 1L)
  a <- sum(cv * w) %% 2147483647
  b <- sum((cv %% 251) * (cv %% 251)) %% 2147483647

  paste0("v1-", n, "-", nchar(s), "-",
         format(a, scientific = FALSE), "-", format(b, scientific = FALSE))
}

# Deliberately local rather than a shared `%||%`: this file must not
# install an infix operator into the global environment that Shiny, rlang
# or another workstream's file might also define.
.retrieval_first_chr <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  x <- as.character(x)[1L]
  if (is.na(x)) "" else x
}

# The text actually handed to the embedding model.
#
# Deliberately the SHARED normalized label key from retrieval_corpus(), not
# a private variant: query and document must traverse an identical text
# pipeline or the two vectors are not comparable. Singularization is
# skipped here (unlike the lexical tier) because a multilingual encoder
# handles morphology itself, and folding plurals would discard signal it
# can use. Falls back to the token key when a label normalizes to empty.
.retrieval_embedding_doc_texts <- function(corpus) {
  if (is.null(corpus) || is.null(corpus$n) || corpus$n == 0L) return(character(0))
  txt <- as.character(corpus$label_key)
  fallback <- as.character(corpus$text_key)
  blank <- is.na(txt) | !nzchar(txt)
  if (any(blank) && length(fallback) == length(txt)) txt[blank] <- fallback[blank]
  txt[is.na(txt)] <- ""
  txt
}

# The query goes through the same normalization the documents did.
.retrieval_embedding_query_text <- function(query) {
  if (is.null(query) || length(query) != 1L) return(NA_character_)
  if (is.na(query)) return(NA_character_)
  q <- retrieval_normalize(as.character(query))
  if (length(q) != 1L || is.na(q) || !nzchar(q)) return(NA_character_)
  q
}

#' Build a semantic index over a retrieval corpus. BUILD TIME ONLY.
#'
#' Embeds every document label once and stores L2-normalized vectors
#' alongside the metadata needed to detect a stale artifact later. This is
#' called by scripts/build_retrieval_embeddings.R, never from a running
#' Shiny session.
#'
#' @param corpus A corpus from `retrieval_corpus()`.
#' @param config Optional pre-read provider config.
#' @param embed_fn Optional embedding function taking a character vector
#'   and returning an (n x d) numeric matrix or NULL. Defaults to the HTTP
#'   provider. Exists so the build script can batch, and so tests can
#'   exercise this code with no network.
#' @param batch_size integer(1) texts per provider call.
#'
#' @return An index list of class "retrieval_embedding_index", or NULL if
#'   the corpus is empty or embedding failed. Never throws.
retrieval_embeddings_build <- function(corpus, config = NULL, embed_fn = NULL,
                                       batch_size = 64L) {
  cfg <- if (is.null(config)) retrieval_embedding_config() else config
  fn <- if (is.null(embed_fn)) function(x) retrieval_embed_texts(x, cfg) else embed_fn

  texts <- .retrieval_embedding_doc_texts(corpus)
  if (length(texts) == 0L) return(NULL)

  batch_size <- suppressWarnings(as.integer(batch_size))
  if (length(batch_size) != 1L || is.na(batch_size) || batch_size < 1L) batch_size <- 64L

  starts <- seq(1L, length(texts), by = batch_size)
  mats <- vector("list", length(starts))

  for (i in seq_along(starts)) {
    lo <- starts[i]
    hi <- min(lo + batch_size - 1L, length(texts))
    m <- tryCatch(fn(texts[lo:hi]), error = function(e) NULL)
    # A partial index is worse than none: a corpus half-covered would rank
    # the covered half systematically above the rest for no semantic
    # reason. Any failed batch abandons the whole build.
    if (is.null(m) || !is.numeric(m) || is.null(dim(m)) || nrow(m) != (hi - lo + 1L)) {
      return(NULL)
    }
    mats[[i]] <- m
  }

  dims <- vapply(mats, ncol, integer(1))
  if (length(unique(dims)) != 1L) return(NULL)

  vectors <- do.call(rbind, mats)
  vectors <- retrieval_embedding_l2_normalize(vectors)
  if (is.null(vectors) || nrow(vectors) != length(texts)) return(NULL)

  structure(
    list(
      index_version = RETRIEVAL_EMBEDDING_INDEX_VERSION,
      vectors       = vectors,
      n_docs        = nrow(vectors),
      dim           = ncol(vectors),
      model         = .retrieval_first_chr(cfg$model),
      fingerprint   = .retrieval_embedding_fingerprint(texts),
      built_at      = as.character(Sys.time())
    ),
    class = "retrieval_embedding_index"
  )
}

#' Load a semantic index from disk.
#'
#' A missing, unreadable or structurally wrong file is NOT an error: it
#' means the optional tier is unavailable. Returns NULL and never throws.
#'
#' @param path Path to an .rds written by
#'   scripts/build_retrieval_embeddings.R.
#'
#' @return An index, or NULL.
retrieval_embeddings_load <- function(path) {
  if (is.null(path) || length(path) != 1L || is.na(path) || !nzchar(path)) return(NULL)
  if (!file.exists(path)) return(NULL)

  idx <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!.retrieval_embedding_index_ok(idx)) return(NULL)
  idx
}

# Structural validation, shared by load and query. Kept separate from
# `retrieval_embeddings_index_is_valid()` because that one additionally
# asks "does this index match THIS corpus".
.retrieval_embedding_index_ok <- function(index) {
  if (is.null(index) || !is.list(index)) return(FALSE)
  if (!identical(index$index_version, RETRIEVAL_EMBEDDING_INDEX_VERSION)) return(FALSE)
  v <- index$vectors
  if (is.null(v) || !is.numeric(v) || is.null(dim(v))) return(FALSE)
  if (nrow(v) == 0L || ncol(v) == 0L) return(FALSE)
  if (!identical(as.integer(index$n_docs), nrow(v))) return(FALSE)
  if (!identical(as.integer(index$dim), ncol(v))) return(FALSE)
  if (any(!is.finite(v))) return(FALSE)
  TRUE
}

#' Does this index correspond to this corpus?
#'
#' Guards the case that matters most: classification data was rebuilt but
#' the embedding artifact was not, so row 412 of the index no longer means
#' row 412 of the corpus. A mismatch would attach real codes to the wrong
#' vectors -- the exact class of silent substitution the classification
#' rules forbid -- so a mismatched index is refused outright.
#'
#' @param index An index, possibly NULL.
#' @param corpus A corpus from `retrieval_corpus()`, possibly NULL.
#'
#' @return logical(1).
retrieval_embeddings_index_is_valid <- function(index, corpus) {
  if (!.retrieval_embedding_index_ok(index)) return(FALSE)
  if (is.null(corpus) || is.null(corpus$n)) return(FALSE)
  if (!identical(as.integer(corpus$n), as.integer(index$n_docs))) return(FALSE)

  texts <- .retrieval_embedding_doc_texts(corpus)
  identical(as.character(index$fingerprint),
            .retrieval_embedding_fingerprint(texts))
}

#' Semantic candidates for a query.
#'
#' FAIL-OPEN GUARANTEE. This returns `retrieval_no_candidates()` -- never
#' NULL, never a condition -- for every one of: NULL index, structurally
#' invalid index, empty index, NULL/NA/blank/multi-element query, provider
#' disabled, provider unreachable, provider timeout, non-2xx response,
#' malformed response, dimension mismatch between query and index, and an
#' `embed_fn` that throws. The deterministic tiers therefore keep working
#' unchanged whatever the backend does.
#'
#' @param query character(1) user query.
#' @param index An index from `retrieval_embeddings_load()`.
#' @param top_k integer(1) maximum candidates.
#' @param min_score numeric(1) or NULL. Cosine is in [-1, 1] and is NOT
#'   clamped or rescaled; the default of 0 discards candidates pointing
#'   away from the query, which are never useful.
#' @param config Optional pre-read provider config.
#' @param embed_fn Optional embedding function, for build tooling and
#'   tests. Defaults to the HTTP provider.
#'
#' @return A candidate data.frame (idx, score, rank).
retrieval_embeddings_candidates <- function(query, index, top_k = 50L,
                                            min_score = 0, config = NULL,
                                            embed_fn = NULL) {
  # Everything is wrapped: no failure inside the semantic tier may ever
  # reach the caller as a condition.
  out <- tryCatch({
    if (!.retrieval_embedding_index_ok(index)) return(retrieval_no_candidates())

    q <- .retrieval_embedding_query_text(query)
    if (is.na(q)) return(retrieval_no_candidates())

    cfg <- if (is.null(config)) retrieval_embedding_config() else config
    fn <- if (is.null(embed_fn)) function(x) retrieval_embed_texts(x, cfg) else embed_fn

    qm <- tryCatch(fn(q), error = function(e) NULL)
    if (is.null(qm) || !is.numeric(qm)) return(retrieval_no_candidates())
    if (is.null(dim(qm))) qm <- matrix(qm, nrow = 1L)
    if (nrow(qm) < 1L || ncol(qm) != ncol(index$vectors)) {
      return(retrieval_no_candidates())
    }

    qv <- retrieval_embedding_l2_normalize(qm[1L, , drop = FALSE])
    if (is.null(qv)) return(retrieval_no_candidates())

    # Both sides are unit-length, so this product IS the cosine.
    score <- as.numeric(index$vectors %*% as.numeric(qv[1L, ]))
    if (length(score) != nrow(index$vectors) || all(!is.finite(score))) {
      return(retrieval_no_candidates())
    }
    score[!is.finite(score)] <- NA_real_

    retrieval_candidates(
      idx = seq_len(nrow(index$vectors)),
      score = score,
      top_k = top_k,
      min_score = min_score
    )
  }, error = function(e) retrieval_no_candidates())

  if (is.null(out) || !is.data.frame(out)) return(retrieval_no_candidates())
  out
}

# Character n-gram TF-IDF cosine retrieval.
#
# WHAT THIS TIER IS FOR
# ---------------------------------------------------------------------
# The lexical tier requires whole tokens to line up. It therefore fails on
# the single most common shape of a real classification query: the user
# writes a shorter, plainer phrase than the official title, and the
# official title has extra words wedged into the middle of it.
#
#   query : "heavy truck driver"
#   title : "HEAVY TRUCK AND LORRY DRIVERS"
#
# No token is missing, but "and lorry" sits between the two halves of the
# phrase the user typed, and a fuzzy whole-string edit distance is
# punished hard by those nine interposed characters. Character n-grams do
# not care where the shared material sits: " heavy truck " contributes the
# same evidence whether or not something follows it. That is why this tier
# exists alongside the lexical and fuzzy ones rather than replacing them.
#
# THE INDEX IS AN INVERTED INDEX, NOT A MATRIX
# ---------------------------------------------------------------------
# The obvious implementation -- an n_docs x n_grams TF-IDF matrix -- is
# not available here: `Matrix` is not a declared dependency of this
# application, and a dense 24,180 x 82,013 double matrix is ~15 GB. So the
# index is a hand-rolled CSR-style posting list in base R:
#
#   vocab       sorted unique grams                       (n_grams)
#   gram_id     environment, gram -> integer vocab id     (hashed lookup)
#   gram_start  offset of each gram's postings            (n_grams + 1)
#   post_doc    document index of each posting            (n_postings)
#   post_w      raw TF-IDF weight of each posting         (n_postings)
#   doc_norm    L2 norm of each document's weight vector  (n_docs)
#
# Scoring a query then touches only the documents that actually share a
# gram with it, and the cosine denominator is a precomputed division
# rather than a second pass over the corpus.
#
# The `gram_id` environment is what keeps querying cheap. `match()`
# against an 82,013-element character vocabulary rebuilds a hash table on
# every call (~26 ms measured on the PSCC index); a hashed environment
# lookup of the same query is ~0.7 ms. The environment is built once, at
# build time, and is treated as immutable thereafter.
#
# BUILD TIME VS QUERY TIME
# ---------------------------------------------------------------------
# `retrieval_ngram_build()` is a build-time operation.
# `retrieval_ngram_candidates()` never rebuilds, never touches disk and
# never touches the network. That separation is the reason a saved index
# has to be able to say what corpus it was built from -- see
# `retrieval_ngram_index_is_valid()`.

RETRIEVAL_NGRAM_CLASS <- "retrieval_ngram_index"

# Defaults. 3 is the shortest gram that still carries a morpheme rather
# than noise; 5 is long enough to span a short word plus its boundaries
# (" bus ", "truck") without exploding the vocabulary.
RETRIEVAL_NGRAM_N_MIN <- 3L
RETRIEVAL_NGRAM_N_MAX <- 5L

# Explicit field-layout version (pre-staging convergence phase).
#
# The corpus fingerprint already rejects a STALE index (built from
# different content). It says nothing about a SUPERSEDED index -- one
# whose internal field layout no longer matches what the current code
# expects, because a future revision renamed or restructured a field. Such
# an index would still pass the fingerprint check (the fingerprint is
# computed from corpus content, not from the index's own structure) and
# would then fail with a raw NULL-field or missing-name error the first
# time a query touched the changed field -- an unhelpful crash rather than
# a clean "this index can't be used" rejection.
#
# Bump this whenever a field is added, renamed, or reinterpreted in a way
# that an older `retrieval_ngram_index` object would not satisfy.
# RETRIEVAL_NGRAM_SUPPORTED_SCHEMA_VERSIONS lists every version the CURRENT
# code can still read; an index outside that set is rejected exactly like a
# stale one -- safe abstention, not a hard failure -- so a deployment
# rolling out new code with an old index degrades to lexical fallback
# rather than crashing the whole search path.
RETRIEVAL_NGRAM_SCHEMA_VERSION <- 1L
RETRIEVAL_NGRAM_SUPPORTED_SCHEMA_VERSIONS <- 1L

# ---------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------

# Pads with a single leading and trailing space so word boundaries become
# part of the gram alphabet: " bus" only matches a word starting with
# "bus", never the middle of "business".
.retrieval_ngram_pad <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  paste0(" ", x, " ")
}

# All character n-grams of `padded` for n in n_min:n_max, returned as a
# flat gram vector plus a parallel document-index vector.
#
# Vectorised across the whole corpus rather than looped per document:
# `sequence()` produces the concatenated 1..count offsets and one
# `substring()` call cuts every gram of a given width at once. On the
# 24,180-row PSCC corpus this produces 2.3 M gram instances in ~0.27 s.
.retrieval_ngram_extract <- function(padded, n_min, n_max) {
  n_docs <- length(padded)
  if (n_docs == 0L) return(list(gram = character(0), doc = integer(0)))

  widths <- nchar(padded, type = "chars")
  grams <- vector("list", n_max - n_min + 1L)
  docs <- vector("list", n_max - n_min + 1L)

  for (k in seq_along(grams)) {
    nn <- n_min + k - 1L
    cnt <- pmax(widths - nn + 1L, 0L)
    if (sum(cnt) == 0L) {
      grams[[k]] <- character(0)
      docs[[k]] <- integer(0)
      next
    }
    di <- rep.int(seq_len(n_docs), cnt)
    st <- sequence(cnt)
    grams[[k]] <- substring(padded[di], st, st + nn - 1L)
    docs[[k]] <- di
  }

  list(
    gram = unlist(grams, use.names = FALSE),
    doc = unlist(docs, use.names = FALSE)
  )
}

# A cheap deterministic checksum over a character vector.
#
# Deliberately NOT a cryptographic digest: adding a hashing package for
# this would be a new dependency, and the job here is staleness detection,
# not tamper resistance. Three independent accumulators are combined so
# that the common ways a corpus changes are all caught:
#
#   a  sum of character codes      -- any character substitution
#   b  position-weighted sum       -- any reordering of rows
#   c  sum of string lengths       -- any insertion or deletion
#
# All three stay well inside the exact-integer range of a double for
# corpora far larger than any PSA classification (the position-weighted
# term is ~3e12 at 24k rows against a 2^53 ceiling), and `b` is reduced
# mod 2^40 so it stays exact for absurd inputs too.
.retrieval_text_checksum <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  n <- length(x)
  if (n == 0L) return("n0")

  codes <- vapply(
    x,
    function(s) if (nchar(s, type = "chars") > 0L) sum(utf8ToInt(s)) else 0,
    numeric(1), USE.NAMES = FALSE
  )
  lens <- as.numeric(nchar(x, type = "chars"))

  sprintf(
    "n%d.a%.0f.b%.0f.c%.0f",
    n, sum(codes), sum(codes * seq_len(n)) %% 2^40, sum(lens)
  )
}

# The corpus fingerprint recorded in the index. Both the text used to
# build the postings AND the codes are covered: a corpus whose labels are
# unchanged but whose codes moved is a different corpus, because `idx`
# resolves to a different record.
.retrieval_ngram_fingerprint <- function(corpus) {
  paste0(
    .retrieval_text_checksum(corpus$text_key),
    "|",
    .retrieval_text_checksum(corpus$code_key)
  )
}

.retrieval_ngram_empty_index <- function(n_min, n_max, system, version) {
  structure(
    list(
      n_docs = 0L,
      n_grams = 0L,
      n_postings = 0L,
      n_min = n_min,
      n_max = n_max,
      vocab = character(0),
      gram_id = new.env(parent = emptyenv(), hash = TRUE),
      gram_start = 1L,
      post_doc = integer(0),
      post_w = numeric(0),
      idf = numeric(0),
      doc_norm = numeric(0),
      meta = list(
        index_schema_version = RETRIEVAL_NGRAM_SCHEMA_VERSION,
        system = system,
        version = version,
        n_docs = 0L,
        n_min = n_min,
        n_max = n_max,
        fingerprint = .retrieval_ngram_fingerprint(
          list(text_key = character(0), code_key = character(0))
        ),
        built_at = NA_character_
      )
    ),
    class = RETRIEVAL_NGRAM_CLASS
  )
}

# ---------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------

#' Build a character n-gram TF-IDF index over a retrieval corpus.
#'
#' Documents are `corpus$text_key` -- the shared singularized token key
#' from `retrieval_normalize_tokens()`, so this tier folds plurals exactly
#' the way the lexical tier does and the two can never disagree about
#' whether "drivers" and "driver" are the same word.
#'
#' Weighting is sublinear TF with smoothed IDF, L2-normalized:
#'
#'   tf(g, d)  = 1 + log(count of g in d)
#'   idf(g)    = log((1 + N) / (1 + df(g))) + 1
#'   w(g, d)   = tf(g, d) * idf(g)
#'   score     = <q_hat, d_hat>   where x_hat = x / ||x||_2
#'
#' Sublinear TF stops a gram that repeats inside one long title from
#' dominating it. The +1 smoothing on both sides of the IDF ratio keeps
#' every weight strictly positive, so a gram that occurs in every single
#' document still contributes a little rather than being silently deleted
#' from the vocabulary.
#'
#' @param corpus A corpus from `retrieval_corpus()`.
#' @param n_min,n_max integer(1) inclusive gram width range.
#' @param system,version character(1) recorded in the index metadata so a
#'   saved index can identify what it indexes. Optional.
#'
#' @return An object of class "retrieval_ngram_index". A zero-document
#'   corpus yields a well-formed empty index, never NULL and never an
#'   error.
retrieval_ngram_build <- function(corpus,
                                  n_min = RETRIEVAL_NGRAM_N_MIN,
                                  n_max = RETRIEVAL_NGRAM_N_MAX,
                                  system = NA_character_,
                                  version = NA_character_) {
  n_min <- as.integer(n_min)
  n_max <- as.integer(n_max)
  if (is.na(n_min) || is.na(n_max) || n_min < 1L || n_max < n_min) {
    stop("retrieval_ngram_build(): require 1 <= n_min <= n_max.", call. = FALSE)
  }
  system <- as.character(system)[1]
  version <- as.character(version)[1]

  if (is.null(corpus) || is.null(corpus$text_key) ||
      length(corpus$text_key) == 0L) {
    return(.retrieval_ngram_empty_index(n_min, n_max, system, version))
  }

  n_docs <- length(corpus$text_key)
  padded <- .retrieval_ngram_pad(corpus$text_key)
  pairs <- .retrieval_ngram_extract(padded, n_min, n_max)

  if (length(pairs$gram) == 0L) {
    idx <- .retrieval_ngram_empty_index(n_min, n_max, system, version)
    # A corpus of blank labels still has documents; only the postings are
    # empty. Record the real document count so validity checks and the
    # build report do not misreport it as an empty corpus.
    idx$n_docs <- n_docs
    idx$doc_norm <- numeric(n_docs)
    idx$meta$n_docs <- n_docs
    idx$meta$fingerprint <- .retrieval_ngram_fingerprint(corpus)
    idx$meta$built_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    return(idx)
  }

  # Radix sort is C-locale and therefore locale-independent: the same
  # corpus produces the same vocabulary ordering on every machine, which
  # is what makes a saved index reproducible.
  vocab <- sort(unique(pairs$gram), method = "radix")
  n_grams <- length(vocab)
  gid <- match(pairs$gram, vocab)

  # Collapse to unique (gram, document) postings, carrying the raw term
  # count. Sorting by (gram, doc) also lays the postings out contiguously
  # per gram, which is what `gram_start` indexes into.
  ord <- order(gid, pairs$doc, method = "radix")
  gs <- gid[ord]
  ds <- pairs$doc[ord]
  len <- length(gs)
  is_new <- if (len == 1L) {
    TRUE
  } else {
    c(TRUE, gs[-1L] != gs[-len] | ds[-1L] != ds[-len])
  }
  start <- which(is_new)
  tf <- diff(c(start, len + 1L))
  post_gram <- gs[start]
  post_doc <- ds[start]

  df <- tabulate(post_gram, nbins = n_grams)
  idf <- log((1 + n_docs) / (1 + df)) + 1
  post_w <- (1 + log(tf)) * idf[post_gram]

  # Per-document L2 norm, precomputed so the cosine denominator is one
  # division at query time. `rowsum` is a single C-level grouped sum.
  doc_norm <- numeric(n_docs)
  sq <- rowsum(post_w^2, group = post_doc, reorder = TRUE)
  doc_norm[as.integer(rownames(sq))] <- sqrt(as.numeric(sq))

  gram_id <- new.env(parent = emptyenv(), hash = TRUE, size = n_grams)
  list2env(stats::setNames(as.list(seq_len(n_grams)), vocab), envir = gram_id)

  structure(
    list(
      n_docs = n_docs,
      n_grams = n_grams,
      n_postings = length(post_doc),
      n_min = n_min,
      n_max = n_max,
      vocab = vocab,
      gram_id = gram_id,
      # CSR offsets: postings for gram g are gram_start[g] ..
      # gram_start[g + 1] - 1. Every vocabulary gram occurs at least once,
      # so no run is empty.
      gram_start = c(1L, cumsum(df) + 1L),
      post_doc = as.integer(post_doc),
      post_w = as.numeric(post_w),
      idf = as.numeric(idf),
      doc_norm = doc_norm,
      meta = list(
        index_schema_version = RETRIEVAL_NGRAM_SCHEMA_VERSION,
        system = system,
        version = version,
        n_docs = n_docs,
        n_min = n_min,
        n_max = n_max,
        fingerprint = .retrieval_ngram_fingerprint(corpus),
        built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
      )
    ),
    class = RETRIEVAL_NGRAM_CLASS
  )
}

# ---------------------------------------------------------------------
# Validity
# ---------------------------------------------------------------------

#' Was this index built from this corpus?
#'
#' A saved index and the repository it indexes drift independently: the
#' classification artifacts can be rebuilt without anyone remembering to
#' rebuild the index, and a stale index silently returns candidates whose
#' `idx` now points at a different record. That is a wrong-code failure,
#' not a performance failure, so the check is cheap enough to run on load.
#'
#' @param index A "retrieval_ngram_index".
#' @param corpus A corpus from `retrieval_corpus()`.
#'
#' @return logical(1). FALSE -- never an error -- for a malformed index or
#'   corpus, so a caller can treat "unusable" and "stale" identically.
retrieval_ngram_index_is_valid <- function(index, corpus) {
  if (!inherits(index, RETRIEVAL_NGRAM_CLASS)) return(FALSE)
  if (is.null(index$meta) || is.null(index$meta$fingerprint)) return(FALSE)
  schema_version <- index$meta$index_schema_version
  if (is.null(schema_version) || !(schema_version %in% RETRIEVAL_NGRAM_SUPPORTED_SCHEMA_VERSIONS)) {
    return(FALSE)
  }
  if (is.null(corpus) || is.null(corpus$text_key) || is.null(corpus$code_key)) {
    return(FALSE)
  }
  if (!identical(as.integer(index$meta$n_docs), as.integer(length(corpus$text_key)))) {
    return(FALSE)
  }
  identical(index$meta$fingerprint, .retrieval_ngram_fingerprint(corpus))
}

#' @export
print.retrieval_ngram_index <- function(x, ...) {
  cat("<retrieval_ngram_index>\n")
  cat("  system/version : ", x$meta$system, " / ", x$meta$version, "\n", sep = "")
  cat("  documents      : ", x$n_docs, "\n", sep = "")
  cat("  grams (", x$n_min, "-", x$n_max, ")   : ", x$n_grams, "\n", sep = "")
  cat("  postings       : ", x$n_postings, "\n", sep = "")
  invisible(x)
}

# ---------------------------------------------------------------------
# Query
# ---------------------------------------------------------------------

#' Retrieve candidates by character n-gram TF-IDF cosine.
#'
#' Pure computation over a prebuilt index: no rebuild, no disk, no
#' network, no mutation of the index.
#'
#' @param query character(1) free-text query.
#' @param index A "retrieval_ngram_index".
#' @param top_k integer(1) maximum candidates.
#' @param min_score numeric(1) or NULL. Candidates scoring at or below
#'   this are dropped. Defaults to 0, which discards documents sharing no
#'   gram with the query.
#'
#' @return A candidate data.frame (idx, score, rank) from
#'   `retrieval_candidates()`; `score` is the cosine similarity in [0, 1].
#'   An empty, NA or blank query, an unusable index, or an out-of-
#'   vocabulary query all return `retrieval_no_candidates()`.
retrieval_ngram_candidates <- function(query, index, top_k = 50L,
                                       min_score = 0) {
  if (!inherits(index, RETRIEVAL_NGRAM_CLASS)) return(retrieval_no_candidates())
  if (index$n_docs == 0L || index$n_grams == 0L) return(retrieval_no_candidates())

  if (is.null(query) || length(query) == 0L) return(retrieval_no_candidates())
  q <- as.character(query)[1]
  if (is.na(q)) return(retrieval_no_candidates())

  q <- retrieval_normalize_tokens(q)
  if (length(q) != 1L || is.na(q) || !nzchar(q)) return(retrieval_no_candidates())

  qg <- .retrieval_ngram_extract(.retrieval_ngram_pad(q), index$n_min, index$n_max)$gram
  if (length(qg) == 0L) return(retrieval_no_candidates())

  q_unique <- unique(qg)
  q_tf <- tabulate(match(qg, q_unique), nbins = length(q_unique))

  q_id <- unlist(
    mget(q_unique, envir = index$gram_id, ifnotfound = list(NA_integer_)),
    use.names = FALSE
  )
  keep <- !is.na(q_id)
  # Nothing the user typed appears anywhere in this classification. That
  # is a legitimate empty result, not an error.
  if (!any(keep)) return(retrieval_no_candidates())

  q_id <- as.integer(q_id[keep])
  q_w <- (1 + log(q_tf[keep])) * index$idf[q_id]
  q_len <- sqrt(sum(q_w^2))
  if (!is.finite(q_len) || q_len <= 0) return(retrieval_no_candidates())
  q_w <- q_w / q_len

  # Accumulate the numerator over only the documents that share a gram.
  # `scores` is one numeric of length n_docs (190 KB at PSCC scale), which
  # is cheaper than assembling and sorting a posting-key table.
  scores <- numeric(index$n_docs)
  starts <- index$gram_start
  for (j in seq_along(q_id)) {
    g <- q_id[j]
    lo <- starts[g]
    hi <- starts[g + 1L] - 1L
    if (hi < lo) next
    rng <- lo:hi
    d <- index$post_doc[rng]
    scores[d] <- scores[d] + q_w[j] * index$post_w[rng]
  }

  hits <- which(scores > 0)
  if (length(hits) == 0L) return(retrieval_no_candidates())

  # The query side is already unit length, so dividing by the document
  # norm completes the cosine. Clamped only to absorb floating-point
  # overshoot past 1 on an exact match.
  sim <- scores[hits] / index$doc_norm[hits]
  sim <- pmin(pmax(sim, 0), 1)

  retrieval_candidates(hits, sim, top_k = top_k, min_score = min_score)
}

# The shared hybrid retrieval engine.
#
# One engine serves Search, PSOC + PSIC and RM. There is deliberately no
# second, LLM-only semantic path: if RM could reach candidates that Search
# cannot, the two would disagree about what the application knows, and the
# grounding rule ("no retrieved/verified code = no authoritative code")
# would be enforced against a different corpus than the one users search.
#
# TIER MODEL
# ----------
# Tiers 1-6 are the pre-existing deterministic ranking in R/search.R and are
# NOT touched by this file. The hybrid tiers are strictly BELOW them:
#
#   1  exact code                     )
#   2  code prefix                    )  unchanged, and always dominant
#   3  exact normalized label         )
#   4  label prefix                   )
#   5  label substring                )
#   6  description substring          )
#   ---------------------------------------------------------------
#   7  all query tokens present in the label, in any order
#   8  fused approximate candidates (fuzzy + n-gram + semantic via RRF)
#
# Because the new tiers carry higher tier numbers, every result the old
# engine returned keeps its exact previous position. The hybrid tiers can
# only ADD candidates below them. That is what makes "existing deterministic
# ranking must not regress" true by construction rather than by testing.
#
# Tier 7 is where the reported defect is actually fixed. "heavy truck
# driver" fails tier 5 because the substring test is whole-query and
# literal, and "and lorry" sits in the middle of "HEAVY TRUCK AND LORRY
# DRIVERS". Every query token is nonetheless present, so an order-
# independent token-AND test resolves it exactly, with no fuzzy scoring and
# no threshold to tune.
#
# Tier 8 exists for what tier 7 cannot reach: typos ("hevy", "trcuk"),
# where a token is not present at all and only edit distance or shared
# character n-grams can recover it.
#
# APPROXIMATE RETRIEVAL IS CANDIDATE GENERATION ONLY. Nothing here mints,
# renames or authorises a code; every candidate is an index into rows that
# already exist in the canonical repository.

# Cost control. The hybrid tiers are skipped entirely when the deterministic
# tiers already filled the requested page: if a query has plenty of exact
# and substring hits there is nothing for approximate retrieval to add, and
# a Shiny reactive on every keystroke should not pay for it.
RETRIEVAL_HYBRID_CANDIDATES <- 50L

# RRF weights. Lexical evidence is trusted above character-shape evidence,
# and semantic evidence -- which is the only tier that can match with no
# lexical overlap at all -- is trusted least. These are ORDERING weights
# inside the fused tier, not probabilities.
RETRIEVAL_RRF_WEIGHTS <- c(fuzzy = 1.0, ngram = 0.9, semantic = 0.7)

# Corpus size above which the edit-distance tier is skipped when the n-gram
# tier already produced enough candidates. Measured: fuzzy costs ~45ms on
# PSOC (649 docs) and ~700ms on PSCC (24,180), while n-gram is 2-3ms on
# both. 5,000 keeps every occupation and industry classification on the
# full-fat path and only sheds the tier where it actually hurts.
RETRIEVAL_FUZZY_MAX_DOCS <- 5000L

# Admission thresholds for the approximate tiers.
#
# Without these, the fused tier admits ANY candidate the generators rank,
# and both generators always rank something. Measured on the 147-case
# evaluation corpus, that took negative-case correctness from 100% to 36%:
# "screwdriver" surfaced HEAVY TRUCK AND LORRY DRIVERS (shared "driver"
# grams), "nursery" surfaced NURSING PROFESSIONALS, "heavy metal drummer"
# surfaced the truck driver on the shared word "heavy". Broad false
# positives on a statistical classification are worse than a miss: a user
# shown a plausible wrong code may simply use it.
#
# RETRIEVAL_MIN_FUZZY is a coverage statement, not a magic number. The fuzzy
# score is 0.75*mean-best-token-similarity + 0.25*coverage, so 0.5 means
# roughly "at least half the query actually matched". The leaked negatives
# scored 0.333 -- one token of three -- while every true positive scored
# >= 0.925.
#
# RETRIEVAL_MIN_NGRAM is empirical: true positives ran 0.345-0.722 and
# leaked negatives 0.213-0.421, so these two distributions genuinely
# OVERLAP and no cosine threshold separates them perfectly. 0.45 clears
# every measured leak; the one true positive below it ("trcuk driver",
# 0.345) is recovered by the fuzzy tier, which is exactly why the tiers are
# fused rather than used alone. This is the most tuned constant in the
# engine and the first thing to re-evaluate when the corpus grows.
RETRIEVAL_MIN_FUZZY <- 0.5
RETRIEVAL_MIN_NGRAM <- 0.45

#' Is a candidate generator available in this process?
#'
#' The tiers are optional by design. A missing n-gram index or an
#' unconfigured embedding backend must degrade retrieval, never break it.
.retrieval_has <- function(fn) exists(fn, mode = "function")

#' Rows whose label contains every query token, in any order.
#'
#' Tier 7. Pure set containment over the singularized token key, so
#' "drivers" matches "driver" and word order is irrelevant. Single-token
#' queries are excluded: for those, tier 5's substring test already covers
#' the same ground, and admitting them here would flood the tier with every
#' record containing a common word.
#'
#' @param query_tokens character vector of singularized query tokens.
#' @param corpus a `retrieval_corpus()` list.
#'
#' @return integer vector of corpus indices, possibly empty.
retrieval_token_all_match <- function(query_tokens, corpus) {
  if (length(query_tokens) < 2L || corpus$n == 0L) return(integer(0))
  query_tokens <- unique(query_tokens)

  postings <- corpus$token_postings
  if (is.null(postings)) {
    # Corpus built before postings existed (or by a caller that constructed
    # the list by hand): fall back to the scan so behaviour is identical.
    hit <- vapply(
      corpus$tokens,
      function(doc_tokens) all(query_tokens %in% doc_tokens),
      logical(1)
    )
    return(corpus$idx[hit])
  }

  # Intersect posting lists, rarest first: if any query token appears in no
  # document, the intersection is empty and we stop immediately.
  lists <- vector("list", length(query_tokens))
  for (i in seq_along(query_tokens)) {
    docs <- postings[[query_tokens[i]]]
    if (is.null(docs)) return(integer(0))
    lists[[i]] <- docs
  }
  lists <- lists[order(lengths(lists))]

  acc <- lists[[1L]]
  for (i in seq_along(lists)[-1L]) {
    acc <- acc[acc %in% lists[[i]]]
    if (length(acc) == 0L) return(integer(0))
  }
  sort(acc)
}

#' Generate fused approximate candidates for a query.
#'
#' Runs whichever candidate generators are available and combines them with
#' Reciprocal Rank Fusion. Each generator is wrapped so that a failure in
#' one tier cannot take down retrieval as a whole -- this is the fail-open
#' requirement, and it applies to the local tiers too, not only to the
#' networked semantic one.
#'
#' @param query character(1) raw user query.
#' @param corpus a `retrieval_corpus()` list.
#' @param ngram_index optional prebuilt n-gram index, or NULL.
#' @param embedding_index optional prebuilt embedding index, or NULL.
#' @param top_k integer(1).
#'
#' @return A candidate data.frame (idx, score, rank), possibly zero-row.
#'   Never NULL, never an error.
retrieval_hybrid_candidates <- function(query, corpus,
                                        ngram_index = NULL,
                                        embedding_index = NULL,
                                        top_k = RETRIEVAL_HYBRID_CANDIDATES) {
  if (corpus$n == 0L) return(retrieval_no_candidates())
  q <- retrieval_normalize(query)
  if (is.na(q) || !nzchar(q)) return(retrieval_no_candidates())

  safely <- function(expr) {
    tryCatch(
      {
        out <- force(expr)
        if (is.null(out) || !is.data.frame(out)) NULL else out
      },
      error = function(e) NULL,
      warning = function(w) {
        # A tier is allowed to warn (the embedding provider does so on a
        # backend failure). Re-evaluate without the handler so a warning is
        # not mistaken for a failure.
        tryCatch(suppressWarnings(force(expr)), error = function(e) NULL)
      }
    )
  }

  sets <- list()

  # n-gram first: it is the cheapest tier by two orders of magnitude
  # (measured 2-3ms even on the 24,180-row PSCC index, versus ~150ms+ for
  # edit distance) and it covers most morphology and partial wording.
  if (!is.null(ngram_index) && .retrieval_has("retrieval_ngram_candidates")) {
    sets$ngram <- safely(retrieval_ngram_candidates(
      query, ngram_index, top_k = top_k, min_score = RETRIEVAL_MIN_NGRAM
    ))
  }

  # Edit distance is the expensive tier, and its unique contribution is
  # TYPOS -- characters that are simply wrong, which n-grams also degrade
  # on. On a large corpus it dominates query time (measured ~700ms on PSCC,
  # against a 250ms UI debounce), so it is skipped when the corpus is large
  # AND the n-gram tier already produced a healthy candidate set. When no
  # n-gram index exists, fuzzy runs regardless of size: recall correctness
  # outranks latency, and a missing index is a build problem to fix, not a
  # reason to silently retrieve less.
  ngram_sufficient <- !is.null(sets$ngram) && nrow(sets$ngram) >= min(top_k, 20L)
  run_fuzzy <- .retrieval_has("retrieval_fuzzy_candidates") &&
    (corpus$n <= RETRIEVAL_FUZZY_MAX_DOCS || !ngram_sufficient)

  if (run_fuzzy) {
    fz <- safely(retrieval_fuzzy_candidates(query, corpus, top_k = top_k))
    if (!is.null(fz) && nrow(fz) > 0L) {
      fz <- fz[fz$score >= RETRIEVAL_MIN_FUZZY, , drop = FALSE]
      if (nrow(fz) > 0L) fz$rank <- seq_len(nrow(fz))
    }
    sets$fuzzy <- fz
  }
  if (!is.null(embedding_index) && .retrieval_has("retrieval_embeddings_candidates")) {
    sets$semantic <- safely(retrieval_embeddings_candidates(query, embedding_index, top_k = top_k))
  }

  if (length(sets) == 0L) return(retrieval_no_candidates())

  fused <- retrieval_rrf(sets, weights = RETRIEVAL_RRF_WEIGHTS, top_k = top_k)

  # Evidence-sufficiency gate (pre-staging convergence phase). A weighted-
  # average score can admit a candidate on the strength of ONE matched
  # token even when every other query concept is unsupported -- see
  # R/retrieval/retrieval_evidence.R for the measured leaks this closes
  # ("electrician's tape" -> BUILDING AND RELATED ELECTRICIANS) and the
  # required positives it was verified NOT to break ("trcuk driver" -> 8332,
  # via the same per-token fuzzy match this gate reuses). Applied once,
  # here, so it covers every candidate generator uniformly -- including a
  # future semantic tier -- with no separate wiring per tier.
  if (.retrieval_has("retrieval_evidence_filter")) {
    query_tokens <- retrieval_tokens(q)[[1]]
    fused <- retrieval_evidence_filter(fused, query_tokens, corpus)
  }

  fused
}

# ---------------------------------------------------------------------
# Index cache
# ---------------------------------------------------------------------
#
# Indexes are immutable read-mostly artifacts. They are loaded once per R
# process and shared across Shiny sessions -- never rebuilt per query and
# never per session. A missing artifact caches its own absence so a
# deployment without prebuilt indexes costs one stat() per process rather
# than one per keystroke.

.retrieval_index_cache <- new.env(parent = emptyenv())

.retrieval_index_reset_cache <- function() {
  rm(list = ls(.retrieval_index_cache), envir = .retrieval_index_cache)
  invisible(NULL)
}

.retrieval_resolve_path <- function(rel) {
  for (p in c(rel, file.path("..", "..", rel))) {
    if (file.exists(p)) return(p)
  }
  rel
}

#' Corpus for one system+version+component+level, cached per R process.
#'
#' Building a corpus means NFKC-normalizing and tokenizing every label. On
#' PSCC that is 24,180 documents and measured ~4.1 seconds -- utterly
#' unaffordable on a Shiny reactive that fires per keystroke, and pure waste
#' besides, because the canonical data is immutable for the lifetime of the
#' process. Built once, reused by every query and every session.
#'
#' The cache key includes level and component because the corpus indices
#' must line up row-for-row with the filtered data the caller ranks.
#'
#' @param data the already-filtered canonical tibble.
#' @param system,version,component,level cache key parts.
#'
#' @return a `retrieval_corpus()` list.
retrieval_corpus_get <- function(data, system, version, component = NULL, level = NULL) {
  key <- paste("corpus", system, version,
               component %||% "_all_", level %||% "_all_",
               nrow(data), sep = "::")

  if (exists(key, envir = .retrieval_index_cache, inherits = FALSE)) {
    cached <- get(key, envir = .retrieval_index_cache, inherits = FALSE)
    # Row count is in the key, but guard identity anyway: a corpus whose
    # indices no longer line up with `data` would mis-resolve candidates to
    # the wrong records, which is far worse than rebuilding.
    if (cached$n == nrow(data)) return(cached)
  }

  corpus <- retrieval_corpus(data)
  assign(key, corpus, envir = .retrieval_index_cache)
  corpus
}

# Local null-coalescing helper; R/search.R and app.R define their own but
# this file must stand alone when sourced individually by tests.
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Load an index and validate it against the corpus ONCE per process.
#'
#' Validity is a correctness gate -- an index is a map of row offsets into
#' the canonical table, so a stale one resolves candidates to the wrong
#' records with full confidence. But the check walks the whole corpus to
#' recompute its fingerprint, measured at 158ms on PSCC, which is
#' unaffordable per query and pointless besides: both the index and the
#' corpus are immutable for the lifetime of the process, so the verdict
#' cannot change between queries.
#'
#' A rejected index is cached as NULL, so a stale artifact costs one check
#' rather than one per keystroke.
#'
#' @param kind "ngram" or "embeddings".
#' @param system,version,component,level identify the corpus.
#' @param corpus the corpus the index must line up with.
#'
#' @return The index if valid, otherwise NULL.
retrieval_index_for <- function(kind, system, version, corpus,
                                component = NULL, level = NULL) {
  key <- paste("validated", kind, system, version,
               component %||% "_all_", level %||% "_all_",
               corpus$n, sep = "::")

  if (exists(key, envir = .retrieval_index_cache, inherits = FALSE)) {
    return(get(key, envir = .retrieval_index_cache, inherits = FALSE))
  }

  index <- retrieval_index_get(kind, system, version)

  validator <- switch(
    kind,
    ngram = "retrieval_ngram_index_is_valid",
    embeddings = "retrieval_embeddings_index_is_valid",
    NULL
  )
  if (!is.null(index) && !is.null(validator) && .retrieval_has(validator)) {
    ok <- tryCatch(
      isTRUE(get(validator, mode = "function")(index, corpus)),
      error = function(e) FALSE
    )
    if (!ok) index <- NULL
  }

  assign(key, index, envir = .retrieval_index_cache)
  index
}

#' Load a prebuilt retrieval index, or NULL when unavailable.
#'
#' @param kind "ngram" or "embeddings".
#' @param system,version character(1).
#'
#' @return The index object, or NULL. Never errors.
retrieval_index_get <- function(kind, system, version) {
  key <- paste(kind, system, version, sep = "::")
  if (exists(key, envir = .retrieval_index_cache, inherits = FALSE)) {
    return(get(key, envir = .retrieval_index_cache, inherits = FALSE))
  }

  rel <- sprintf("data/retrieval_%s_%s_%s.rds", kind, system, version)
  path <- .retrieval_resolve_path(rel)

  obj <- if (file.exists(path)) {
    tryCatch(readRDS(path), error = function(e) NULL)
  } else {
    NULL
  }

  assign(key, obj, envir = .retrieval_index_cache)
  obj
}

# The shared retrieval corpus and the candidate-set contract.
#
# Every candidate generator (fuzzy, n-gram, semantic) consumes a corpus
# produced here and returns a candidate set in the shape defined here, so
# the fusion step can combine them without knowing which tier produced
# what. This is what makes Search, PSOC + PSIC and RM share one engine
# rather than three lookalike code paths.

#' Build the retrieval corpus for one system+version.
#'
#' The corpus is a projection of the canonical repository -- it never adds,
#' renames or invents a record. `idx` is the row index back into `data`, and
#' that index is how every candidate is resolved to a real entry during
#' verification.
#'
#' @param data A canonical classification tibble (as returned by
#'   `get_classification()`), already filtered to the requested
#'   system/version/component by the caller.
#'
#' @return A list with:
#'   \describe{
#'     \item{n}{integer, number of documents}
#'     \item{idx}{integer vector, 1..n}
#'     \item{code_key}{normalized code, for exact-code comparison}
#'     \item{label_key}{normalized label, for exact-label comparison}
#'     \item{text_key}{singularized token key of the label, used by the
#'       approximate tiers}
#'     \item{tokens}{list of singularized token vectors}
#'   }
#'   A zero-row input yields a well-formed empty corpus, never NULL.
retrieval_corpus <- function(data) {
  if (is.null(data) || nrow(data) == 0L) {
    return(list(
      n = 0L, idx = integer(0),
      code_key = character(0), label_key = character(0),
      text_key = character(0), tokens = list()
    ))
  }

  label <- as.character(data$label)
  tokens <- retrieval_tokens(label)

  out <- list(
    n = nrow(data),
    idx = seq_len(nrow(data)),
    code_key = retrieval_normalize_code(data$code),
    label_key = retrieval_normalize(label),
    text_key = retrieval_normalize_tokens(label),
    tokens = tokens
  )
  out$token_postings <- .retrieval_token_postings(tokens)
  out
}

# Inverted token -> document postings.
#
# Tier 7 asks "which documents contain ALL of these tokens". Answering that
# by scanning every document's token vector is O(n_docs) per query and
# measured ~500ms on the 24,180-row PSCC table -- unaffordable on a keystroke
# path. Intersecting posting lists instead touches only documents that
# contain the RAREST query token, which is typically a handful.
#
# Held in a hashed environment: `match()` against a large character vector
# rebuilds its hash on every call, whereas an environment lookup is O(1) and
# built once.
.retrieval_token_postings <- function(tokens) {
  lens <- lengths(tokens)
  if (sum(lens) == 0L) return(new.env(parent = emptyenv()))

  flat_token <- unlist(tokens, use.names = FALSE)
  flat_doc <- rep.int(seq_along(tokens), lens)

  # Group document ids by token in one pass.
  ord <- order(flat_token, flat_doc, method = "radix")
  flat_token <- flat_token[ord]
  flat_doc <- flat_doc[ord]

  starts <- c(TRUE, flat_token[-1L] != flat_token[-length(flat_token)])
  group_id <- cumsum(starts)
  uniq <- flat_token[starts]

  env <- new.env(hash = TRUE, parent = emptyenv(), size = length(uniq) * 2L)
  split_docs <- split(flat_doc, group_id)
  for (i in seq_along(uniq)) {
    assign(uniq[i], unique(split_docs[[i]]), envir = env)
  }
  env
}

#' An empty candidate set in the canonical shape.
#'
#' @return A zero-row data.frame with columns idx (integer), score
#'   (numeric), rank (integer).
retrieval_no_candidates <- function() {
  data.frame(
    idx = integer(0), score = numeric(0), rank = integer(0),
    stringsAsFactors = FALSE
  )
}

#' Assemble a candidate set from scores.
#'
#' Sorts by descending score, truncates to `top_k`, and assigns dense ranks
#' starting at 1. Ties break by ascending `idx`, which keeps the corpus's
#' own (source) order as the deterministic tie-breaker -- two runs over the
#' same data always produce the same ordering.
#'
#' @param idx integer vector of corpus indices.
#' @param score numeric vector of generator-local scores (higher is better).
#' @param top_k integer(1) maximum candidates to keep.
#' @param min_score numeric(1) or NULL. Candidates at or below this are
#'   dropped before ranking.
#'
#' @return A candidate data.frame (idx, score, rank).
retrieval_candidates <- function(idx, score, top_k = 50L, min_score = NULL) {
  if (length(idx) == 0L) return(retrieval_no_candidates())

  keep <- !is.na(score)
  if (!is.null(min_score)) keep <- keep & score > min_score
  idx <- idx[keep]
  score <- score[keep]
  if (length(idx) == 0L) return(retrieval_no_candidates())

  ord <- order(-score, idx)
  idx <- idx[ord]
  score <- score[ord]

  if (length(idx) > top_k) {
    idx <- idx[seq_len(top_k)]
    score <- score[seq_len(top_k)]
  }

  data.frame(
    idx = as.integer(idx), score = as.numeric(score),
    rank = seq_along(idx), stringsAsFactors = FALSE
  )
}

#' Reciprocal Rank Fusion over several candidate sets.
#'
#' RRF is used because edit distance, TF-IDF cosine and embedding cosine
#' are not calibrated to a common scale -- combining their raw scores would
#' let whichever tier happens to have the widest numeric range dominate.
#' RRF only reads each tier's ORDERING, which is the part that is
#' meaningfully comparable.
#'
#'   RRF(d) = sum_i weight_i / (k + rank_i(d))
#'
#' @param candidate_sets A named list of candidate data.frames. NULL or
#'   empty members are skipped, which is what lets the semantic tier fail
#'   open without changing the call site.
#' @param k numeric(1). The RRF damping constant; 60 is the value from the
#'   original formulation and stops rank-1 from being overwhelmingly
#'   dominant.
#' @param weights named numeric vector of per-tier weights, or NULL for
#'   equal weighting.
#' @param top_k integer(1).
#'
#' @return A candidate data.frame (idx, score, rank) where score is the RRF
#'   score. Contributing tier membership is preserved in the `tiers`
#'   attribute for explainability.
retrieval_rrf <- function(candidate_sets, k = 60, weights = NULL, top_k = 50L) {
  sets <- Filter(function(s) !is.null(s) && is.data.frame(s) && nrow(s) > 0L, candidate_sets)
  if (length(sets) == 0L) return(retrieval_no_candidates())

  acc <- new.env(parent = emptyenv())
  tiers <- new.env(parent = emptyenv())

  for (nm in names(sets)) {
    s <- sets[[nm]]
    w <- if (!is.null(weights) && !is.na(weights[nm])) weights[[nm]] else 1
    for (i in seq_len(nrow(s))) {
      key <- as.character(s$idx[i])
      contrib <- w / (k + s$rank[i])
      acc[[key]] <- (if (is.null(acc[[key]])) 0 else acc[[key]]) + contrib
      tiers[[key]] <- c(tiers[[key]], nm)
    }
  }

  keys <- ls(acc)
  out <- retrieval_candidates(
    idx = as.integer(keys),
    score = vapply(keys, function(kk) acc[[kk]], numeric(1)),
    top_k = top_k
  )
  attr(out, "tiers") <- lapply(as.character(out$idx), function(kk) unique(tiers[[kk]]))
  out
}

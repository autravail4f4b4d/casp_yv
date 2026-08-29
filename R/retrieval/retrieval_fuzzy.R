# Fuzzy (approximate-match) candidate generation for hybrid retrieval.
#
# This tier exists to fix one concrete defect: the deterministic engine only
# performs a whole-query literal containment test, so "heavy truck driver"
# does not reach "HEAVY TRUCK AND LORRY DRIVERS" (the interposed "AND
# LORRY" breaks the substring), and "hevy truck driver" reaches nothing at
# all. Matching therefore happens PER TOKEN here, not per whole string:
# every query token independently finds its best-matching document token,
# and those per-token similarities are combined into one document score.
#
# ---------------------------------------------------------------------------
# Distance algorithm: OSA (optimal string alignment), i.e. restricted
# Damerau-Levenshtein.
#
# Plain Levenshtein is not sufficient. The required case "trcuk" -> "truck"
# is an adjacent transposition, which Levenshtein charges 2 (two
# substitutions) and OSA charges 1. With a per-token budget of 2 for a
# 5-character token, Levenshtein technically still admits it, but it also
# admits every unrelated 5-character token two substitutions away, which is
# a far noisier candidate set than "one keyboard slip away".
#
# `stringdist` is not installed and adding it would mean editing renv.lock,
# which this workstream does not own, so OSA is implemented here directly.
# It is a small DP: the Levenshtein recurrence plus one extra branch that
# reads the row from two steps back.
#
# ---------------------------------------------------------------------------
# Work bound. The PSCC corpus is ~24,000 documents; this runs on a Shiny
# reactive path, so a full DP against every document token for every query
# token is not affordable. Three bounds are applied, cheapest first:
#
#   1. VOCABULARY, not documents. Distance is computed against the set of
#      DISTINCT document tokens, then scattered back to the documents that
#      contain them. ~24k PSCC labels collapse to roughly an order of
#      magnitude fewer distinct tokens, and repeated words ("services",
#      "other", "n e c") are scored once instead of thousands of times.
#
#   2. LENGTH BOUND. |nchar(a) - nchar(b)| > d implies OSA(a, b) > d, since
#      every edit changes the length by at most one. Tokens outside the
#      budget's length window are discarded with an integer comparison.
#
#   3. LEVENSHTEIN PREFILTER via utils::adist(), which is vectorised and
#      implemented in C. Every OSA operation can be simulated by at most two
#      Levenshtein operations (a transposition = two substitutions), so
#      Lev <= 2 * OSA, and therefore Lev > 2*d implies OSA > d. adist() is
#      thus an admissible prefilter -- it can never discard a true match --
#      and the hand-written R DP only ever runs on the handful of survivors.
#
# A hard cap (.RETRIEVAL_FUZZY_MAX_DP) additionally limits how many
# survivors reach the R-level DP, so a pathological query cannot stall the
# session. Survivors are ordered by Levenshtein distance then vocabulary
# position before the cap is applied, so the cap is deterministic and drops
# the least promising entries first.
#
# The functions here are pure: no global state, no disk I/O, no network.

# Maximum number of prefilter survivors that reach the R-level OSA DP, per
# query token. Reaching this cap means the token is a near-miss for hundreds
# of distinct vocabulary entries, which is noise, not signal.
.RETRIEVAL_FUZZY_MAX_DP <- 500L

# Weighting of mean per-token similarity against query coverage in the
# document score. Both terms live in [0, 1] and the weights sum to 1, so the
# score does too. Coverage is broken out as its own term (rather than left
# implicit in the mean) so that a document matching all three tokens of
# "heavy truck driver" is rewarded for BREADTH of match, not only for the
# quality of the tokens it happened to match.
.RETRIEVAL_FUZZY_W_MEAN <- 0.75
.RETRIEVAL_FUZZY_W_COVERAGE <- 0.25

#' Default edit budget for one token, derived from its length.
#'
#' A single global constant is wrong in both directions: it is far too
#' permissive for short tokens (at distance 2, "van" reaches "man", "can",
#' "bag", "car" -- almost every three-letter word) and far too strict for
#' long ones ("adminstrative" is two edits from "administrative"). The
#' budget therefore scales with length.
#'
#' Tokens of two characters or fewer get a budget of zero -- exact match
#' only. There is no such thing as a "close" two-character token; at
#' distance 1 every such token matches most of the alphabet.
#'
#' @param n integer vector of token lengths.
#'
#' @return integer vector of per-token maximum edit distances.
.retrieval_fuzzy_budget <- function(n) {
  out <- integer(length(n))
  out[n <= 2L] <- 0L
  out[n > 2L & n <= 4L] <- 1L
  out[n > 4L & n <= 8L] <- 2L
  out[n > 8L] <- 3L
  out
}

#' OSA distance between two already-split character vectors.
#'
#' Restricted Damerau-Levenshtein: insertion, deletion, substitution, and
#' transposition of two ADJACENT characters. "Restricted" means no substring
#' is edited more than once, which is what keeps the recurrence to three
#' rows and makes it cheap enough to run in R on a small survivor set.
#'
#' @param ac character vector of single characters (the query token).
#' @param bc character vector of single characters (the candidate token).
#'
#' @return integer(1) distance.
.retrieval_osa_chars <- function(ac, bc) {
  la <- length(ac)
  lb <- length(bc)
  if (la == 0L) return(lb)
  if (lb == 0L) return(la)

  # prev2 = row i-2, prev1 = row i-1, cur = row i. Only three rows are ever
  # live, because the transposition branch reaches back exactly two rows.
  prev2 <- integer(lb + 1L)
  prev1 <- 0:lb
  cur <- integer(lb + 1L)

  for (i in seq_len(la)) {
    cur[1L] <- i
    ai <- ac[i]
    for (j in seq_len(lb)) {
      cost <- if (ai == bc[j]) 0L else 1L
      v <- min(
        cur[j] + 1L,          # deletion from b / insertion into a
        prev1[j + 1L] + 1L,   # insertion into b / deletion from a
        prev1[j] + cost       # match or substitution
      )
      # The Damerau branch: the previous character of each string is the
      # current character of the other, so one swap explains both.
      if (i > 1L && j > 1L && ai == bc[j - 1L] && ac[i - 1L] == bc[j]) {
        v <- min(v, prev2[j - 1L] + 1L)
      }
      cur[j + 1L] <- v
    }
    prev2 <- prev1
    prev1 <- cur
  }

  prev1[lb + 1L]
}

#' OSA distance from one string to each of several strings.
#'
#' @param a character(1).
#' @param b character vector.
#'
#' @return integer vector of the same length as `b`.
.retrieval_osa <- function(a, b) {
  if (length(b) == 0L) return(integer(0))
  ac <- strsplit(a, "", fixed = TRUE)[[1]]
  bs <- strsplit(b, "", fixed = TRUE)
  vapply(bs, function(bc) .retrieval_osa_chars(ac, bc), integer(1))
}

#' Similarity of every vocabulary entry to one query token.
#'
#' Similarity is `1 - distance / max(nchar)`, so it is exactly 1 for an
#' identical token and degrades with the size of the edit RELATIVE to the
#' token, not absolutely: one slip in a four-letter word is a bigger deal
#' than one slip in a twelve-letter word.
#'
#' @param token character(1), an already-normalized query token.
#' @param vocab character vector of distinct normalized document tokens.
#' @param vocab_nchar integer vector, `nchar(vocab)` precomputed.
#' @param max_distance integer(1) or NULL for the length-derived default.
#'
#' @return numeric vector, length `length(vocab)`, in [0, 1]. Zero means
#'   "no match within budget", never a near miss.
.retrieval_fuzzy_token_similarity <- function(token, vocab, vocab_nchar,
                                              max_distance = NULL) {
  sim <- numeric(length(vocab))
  if (length(vocab) == 0L) return(sim)

  qn <- nchar(token)
  budget <- if (is.null(max_distance)) {
    .retrieval_fuzzy_budget(qn)
  } else {
    as.integer(max_distance)
  }
  if (is.na(budget) || budget < 0L) budget <- 0L

  # Bound 0: exact match, resolved by hash lookup, never by DP.
  hit <- match(token, vocab)
  if (!is.na(hit)) sim[hit] <- 1

  if (budget == 0L) return(sim)

  # Bound 2: length window. |len(a) - len(b)| <= d is necessary for
  # OSA(a, b) <= d.
  cand <- which(abs(vocab_nchar - qn) <= budget)
  if (!is.na(hit)) cand <- cand[cand != hit]
  if (length(cand) == 0L) return(sim)

  # Bound 3: vectorised C Levenshtein as an admissible prefilter, since
  # Lev <= 2 * OSA.
  lev <- as.integer(utils::adist(token, vocab[cand]))
  keep <- which(lev <= 2L * budget)
  if (length(keep) == 0L) return(sim)

  if (length(keep) > .RETRIEVAL_FUZZY_MAX_DP) {
    keep <- keep[order(lev[keep], cand[keep])][seq_len(.RETRIEVAL_FUZZY_MAX_DP)]
  }
  surv <- cand[keep]

  d <- .retrieval_osa(token, vocab[surv])
  ok <- d <= budget
  if (!any(ok)) return(sim)

  surv <- surv[ok]
  d <- d[ok]
  s <- 1 - d / pmax(qn, vocab_nchar[surv])
  s[s < 0] <- 0

  sim[surv] <- pmax(sim[surv], s)
  sim
}

#' Flatten a corpus's token lists into a vocabulary + posting arrays.
#'
#' Exposed so a caller on a hot path may compute it once and hand it back as
#' `corpus$fuzzy_index`; `retrieval_fuzzy_candidates()` builds it on demand
#' otherwise. It is derived purely from the corpus, so reusing it can never
#' change a result.
#'
#' @param corpus A corpus from `retrieval_corpus()`.
#'
#' @return A list with `vocab` (sorted distinct tokens), `vocab_nchar`,
#'   `tok_doc` (document index per token occurrence) and `tok_vid`
#'   (vocabulary index per token occurrence).
retrieval_fuzzy_index <- function(corpus) {
  empty <- list(
    vocab = character(0), vocab_nchar = integer(0),
    tok_doc = integer(0), tok_vid = integer(0)
  )
  if (is.null(corpus) || is.null(corpus$tokens) || length(corpus$tokens) == 0L) {
    return(empty)
  }

  lens <- lengths(corpus$tokens)
  flat <- unlist(corpus$tokens, use.names = FALSE)
  if (length(flat) == 0L) return(empty)

  # factor() gives a sorted level set and the position vector in one pass,
  # and sorted levels make the vocabulary order deterministic.
  f <- factor(flat)
  list(
    vocab = levels(f),
    vocab_nchar = nchar(levels(f)),
    tok_doc = rep.int(corpus$idx, lens),
    tok_vid = as.integer(f)
  )
}

# Best per-document similarity, given a per-vocabulary similarity vector.
#
# The scatter uses "sort ascending, then assign" rather than tapply/split:
# duplicate subscripts in R's assignment resolve last-write-wins, so writing
# the occurrences in ascending similarity order leaves each document holding
# its maximum. This touches only the occurrences that actually matched.
.retrieval_fuzzy_scatter_max <- function(sim_vocab, index, n) {
  best <- numeric(n)
  s <- sim_vocab[index$tok_vid]
  hit <- which(s > 0)
  if (length(hit) == 0L) return(best)
  o <- order(s[hit])
  best[index$tok_doc[hit][o]] <- s[hit][o]
  best
}

# Code-like queries ("8332", "0101.29.00-001") are matched against the
# normalized CODE key, not against label tokens. A digit string tokenizes to
# a single token that no label word will ever be near, so without this the
# tier would silently return nothing for the most precise query a user can
# type. Codes are compared whole -- they have no token structure -- and code
# punctuation is preserved by retrieval_normalize_code(), so this cannot
# collapse two distinct codes onto one key.
.retrieval_fuzzy_code_candidates <- function(query, corpus, top_k, max_distance) {
  qk <- retrieval_normalize_code(query)
  ck <- corpus$code_key
  if (is.na(qk) || !nzchar(qk) || length(ck) == 0L) return(retrieval_no_candidates())

  ck[is.na(ck)] <- ""
  uniq <- unique(ck)
  sim_uniq <- .retrieval_fuzzy_token_similarity(
    qk, uniq, nchar(uniq), max_distance = max_distance
  )
  score <- sim_uniq[match(ck, uniq)]
  score[is.na(score)] <- 0

  retrieval_candidates(corpus$idx, score, top_k = top_k, min_score = 0)
}

#' Fuzzy candidate retrieval over a classification corpus.
#'
#' Scores every document by how well the query's tokens are covered by the
#' document's tokens, allowing for typos. See the file header for the
#' distance algorithm and the work bounds.
#'
#' Scoring, for a query of `q` tokens:
#'
#'   best[i]  = highest similarity of query token i to ANY document token
#'   mean     = sum(best) / q
#'   coverage = count(best > 0) / q
#'   score    = 0.75 * mean + 0.25 * coverage
#'
#' Both terms are in [0, 1] and the weights sum to 1, so the score is in
#' [0, 1] and is exactly 1 only when every query token matches some document
#' token exactly. Unmatched query tokens contribute zero to both terms,
#' which is what makes a document matching all three tokens of "heavy truck
#' driver" outrank one matching only "driver".
#'
#' @param query character(1). Free text, or a classification code.
#' @param corpus A corpus from `retrieval_corpus()`. May optionally carry a
#'   precomputed `fuzzy_index` from `retrieval_fuzzy_index()`.
#' @param top_k integer(1) maximum candidates returned.
#' @param max_distance integer(1) to force one edit budget for every token,
#'   or NULL (default) to derive it from each token's length.
#'
#' @return A candidate data.frame (idx, score, rank) as defined by
#'   `retrieval_candidates()`. An empty, NA or blank query, an empty corpus,
#'   or a query that matches nothing all return `retrieval_no_candidates()`.
#'   Never NULL, never an error, never a negative or NA score.
retrieval_fuzzy_candidates <- function(query, corpus, top_k = 50L,
                                       max_distance = NULL) {
  if (is.null(corpus) || is.null(corpus$n) || corpus$n == 0L) {
    return(retrieval_no_candidates())
  }
  if (length(query) != 1L || is.na(query)) return(retrieval_no_candidates())
  query <- as.character(query)
  if (!nzchar(retrieval_normalize(query))) return(retrieval_no_candidates())

  top_k <- as.integer(top_k)
  if (is.na(top_k) || top_k < 1L) return(retrieval_no_candidates())

  if (retrieval_is_code_like(query)) {
    return(.retrieval_fuzzy_code_candidates(query, corpus, top_k, max_distance))
  }

  qtokens <- retrieval_tokens(query)[[1]]
  if (length(qtokens) == 0L) return(retrieval_no_candidates())
  # Repeated query words must not count twice toward coverage.
  qtokens <- unique(qtokens)

  index <- corpus$fuzzy_index
  if (is.null(index) || is.null(index$vocab)) index <- retrieval_fuzzy_index(corpus)
  if (length(index$vocab) == 0L) return(retrieval_no_candidates())

  n <- corpus$n
  sum_best <- numeric(n)
  matched <- numeric(n)

  for (qt in qtokens) {
    sim_vocab <- .retrieval_fuzzy_token_similarity(
      qt, index$vocab, index$vocab_nchar, max_distance = max_distance
    )
    if (!any(sim_vocab > 0)) next
    best <- .retrieval_fuzzy_scatter_max(sim_vocab, index, n)
    sum_best <- sum_best + best
    matched <- matched + (best > 0)
  }

  nq <- length(qtokens)
  score <- .RETRIEVAL_FUZZY_W_MEAN * (sum_best / nq) +
    .RETRIEVAL_FUZZY_W_COVERAGE * (matched / nq)
  score[is.na(score)] <- 0
  score[score < 0] <- 0
  score[score > 1] <- 1

  retrieval_candidates(corpus$idx, score, top_k = top_k, min_score = 0)
}

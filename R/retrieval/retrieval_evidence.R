# Approximate-match evidence sufficiency.
#
# ROOT CAUSE this file exists to fix (pre-staging convergence phase,
# diagnosed with instrumented evidence, not guessed):
#
# retrieval_fuzzy_candidates() and retrieval_ngram_candidates() both score a
# document as a WEIGHTED AVERAGE over query tokens (fuzzy: 0.75*mean-best-
# similarity + 0.25*coverage; ngram: whole-string character-shingle cosine).
# Averaging means a single strongly-matched token can carry a multi-token
# query over the admission threshold even when every OTHER query token found
# no support at all. Measured directly:
#
#   "electrician's tape" -> 7411 BUILDING AND RELATED ELECTRICIANS
#     ngram score 0.491 (threshold 0.45) -- PASSES on "electrician" alone;
#     "tape" matches nothing in the candidate's tokens.
#   "carpenter ant" -> 7115 CARPENTERS AND JOINERS
#     fuzzy score 0.875, ngram 0.676 -- PASSES on "carpenter" alone;
#     "ant" is edit-distance 1 from the candidate's own connector word "and"
#     (a-n-t / a-n-d), which very nearly let it slip through even a naive
#     coverage check -- see the stopword exclusion below.
#   "security blanket" -> 5414 SECURITY GUARDS
#     ngram score 0.609, fuzzy 0.500 -- PASSES on "security" alone;
#     "blanket" matches nothing.
#
# Contrast with the required legitimate positives, where EVERY meaningful
# query token finds support in the same winning candidate:
#
#   "heavy truck driver"  -> 8332: heavy/truck/driver all match (3/3).
#   "hevy truck driver"   -> 8332: truck/driver exact, "hevy" fuzzy-matches
#                             "heavy" at OSA distance 1 (2/3, "hevy" itself
#                             also supported once fuzzy sub-matching is
#                             applied -- see below).
#   "trcuk driver"        -> 8332/833: "driver" exact, "trcuk" is OSA
#                             distance 1 from "truck" (an adjacent
#                             transposition) -- BOTH of its 2 meaningful
#                             tokens are supported.
#
# The fix is therefore not "raise the threshold" (P1 explicitly rules this
# out, and raising it uniformly would also kill "trcuk driver", whose raw
# scores are IN THE SAME RANGE as the leaking negatives -- there is no
# single cosine/edit-similarity cutoff that separates them). The fix is a
# SEPARATE, GENERAL evidence-sufficiency gate: how many of the query's
# meaningful concepts does this specific candidate actually support.
#
# Two things make this safe rather than merely threshold-in-disguise:
#
#   1. It is measured PER (query, candidate) PAIR, using the same
#      already-tested per-token similarity primitive the fuzzy tier uses --
#      so a typo'd token ("trcuk", "hevy") still counts as supported. This
#      is NOT stemming (no morphological rule is applied) and NOT a second
#      distance metric; it reuses .retrieval_fuzzy_token_similarity()
#      verbatim.
#   2. STOPWORD-CALIBER connector tokens are excluded from BOTH sides before
#      counting. Without this, "ant" (the insect) would count as "supported"
#      by CARPENTERS AND JOINERS purely because "ant" happens to be
#      edit-distance 1 from the label's own connector word "and" -- a
#      coincidence with zero bearing on classification relevance. The list
#      below is a short, closed set of English function words plus the
#      single-letter fragments an apostrophe split or "n.e.c." produces
#      ("electrician's" -> "electrician", "s"); it carries no semantic
#      content and this is a stopword filter, not stemming.
#
# The gate is applied ONCE, generically, at the fusion boundary
# (retrieval_hybrid_candidates() in retrieval_engine.R) -- not inside the
# fuzzy or n-gram scoring functions themselves, which are untouched and
# keep every existing test passing unchanged. This also means any future
# candidate generator (the dormant semantic tier included) is covered by
# the same gate automatically, with no separate wiring.

# Closed set. English function words that carry no discriminating power in
# a classification title, plus token fragments an apostrophe split or an
# "n.e.c."-style abbreviation produces. Deliberately short and
# uncontroversial -- this is stopword filtering for one narrow purpose
# (evidence counting), never applied to normalization, display, or the
# scoring formulas themselves.
RETRIEVAL_EVIDENCE_STOPWORDS <- c(
  "a", "an", "the",
  "and", "or", "nor", "but",
  "of", "in", "on", "at", "to", "for", "with", "by", "as", "from",
  "is", "are", "was", "were", "be", "been",
  "who", "which", "that", "this",
  "s", "n", "e", "c"
)

#' Tokens that carry discriminating power for evidence counting.
#'
#' Drops single-character fragments (nchar 1) and the closed stopword set
#' above. This is NOT the tokenizer used for scoring or display -- it is a
#' narrower view used only to decide how many DISTINCT CONCEPTS a query
#' actually expresses, so evidence can be required per concept rather than
#' per raw token.
#'
#' @param tokens character vector of already-normalized/singularized
#'   tokens (as produced by `retrieval_tokens()`).
#'
#' @return character vector, a subset of `tokens`. Possibly empty.
retrieval_meaningful_tokens <- function(tokens) {
  tokens <- tokens[!is.na(tokens) & nzchar(tokens)]
  tokens[nchar(tokens) >= 2L & !(tokens %in% RETRIEVAL_EVIDENCE_STOPWORDS)]
}

# Minimum meaningful-token support required, as a function of how many
# meaningful concepts the query expresses.
#
#   0 or 1 meaningful token  -> that one token (if any) must itself be
#                               supported. A single-concept query is not
#                               this gate's problem -- if the sole concept
#                               matched at all, the existing score threshold
#                               already decided whether the match is strong
#                               enough.
#   2+ meaningful tokens     -> a STRICT majority (more than half), i.e.
#                               n %/% 2 + 1. "heavy truck driver" (3
#                               concepts) requires 2; "trcuk driver" (2
#                               concepts) requires both; a 4-concept query
#                               requires 3, not 2.
#
# Final micro-gate finding: an "at least half" rule (the original formula
# here was max(2, ceiling(n * 0.5))) lets a 4-token query pass on EXACTLY
# its two most generic, corpus-ubiquitous tokens while its two most
# specific tokens go completely unsupported. Diagnosed on
# "professional AI prompt engineer" (4 meaningful tokens, all distinct
# concepts): "professional" and "engineer" are both singular-normalized
# forms that recur across dozens of unrelated PSOC titles (~11% and ~2% of
# all unit-group labels respectively, e.g. "MINING ENGINEERS,
# METALLURGISTS AND RELATED PROFESSIONALS"), while "ai" and "prompt" -- the
# only tokens that actually distinguish this query -- appear in zero
# corpus documents and were left unsupported by design of the OLD 50%
# floor. A strict majority closes exactly this gap: at even n it now
# requires one more supported token than before; at odd n (where ceiling
# already rounds past half) it is unchanged, so "heavy truck driver" (n=3,
# requires 2) and "trcuk driver" (n=2, requires 2) are unaffected.
#
# This is a coverage RATIO, not a fixed count or an enumerated word list, so
# it does not privilege any specific query length, occupation, or code -- it
# generalizes by construction rather than by enumeration.
.retrieval_evidence_required <- function(n_meaningful) {
  if (n_meaningful <= 1L) return(n_meaningful)
  n_meaningful %/% 2L + 1L
}

# Minimum per-token similarity for a query token to count as "supported" by
# a candidate token. Final micro-gate finding: "supported" previously meant
# `any(sim > 0)` -- no floor at all -- which let two SHORT, unrelated,
# common words with a coincidental one-edit overlap count as real evidence.
# Diagnosed on "moon rock trading" (a fabricated commodity with no PSCC
# code): "rock" ~ "lock" (sim 0.750, an unrelated word in an unrelated iron/
# steel structures entry) and "trading" ~ "threading"/"heading" (sim 0.778/
# 0.714, unrelated words in unrelated tool and mineral-wool entries) both
# registered as "supported", meeting the 2-of-3 requirement on pure
# coincidence -- "moon" itself correctly found no support anywhere.
#
# Surveyed against every already-verified typo pair in the corpora to place
# the floor without re-tuning per query:
#
#   genuine typo/singular-plural pairs (must stay supported), lowest first:
#     trcuk~truck 0.800, hevy~heavy 0.800, tabel~table 0.800,
#     electrision~electrician 0.818, wielder~welder 0.857, ... up to 0.923
#   coincidental short-word overlaps (must NOT be supported), highest first:
#     trading~threading 0.778, rock~lock 0.750, trading~heading 0.714,
#     ant~and 0.667
#
# The two clusters do not overlap: every genuine pair scores >= 0.800, every
# coincidental one scores <= 0.778. The floor sits at the natural gap
# between them, not fitted to any single query.
RETRIEVAL_EVIDENCE_MIN_TOKEN_SIMILARITY <- 0.8

#' Is there sufficient lexical evidence for a (query, candidate) pair?
#'
#' Reuses the fuzzy tier's own per-token similarity so a typo'd query token
#' ("trcuk", "hevy") still counts as supported -- this is deliberately the
#' SAME notion of "matched" the fuzzy tier already uses internally, not a
#' new or stricter distance metric.
#'
#' @param query_tokens character vector, already-normalized/singularized
#'   query tokens (as from `retrieval_tokens(query_norm)[[1]]`).
#' @param candidate_tokens character vector, the candidate document's own
#'   tokens (as from `corpus$tokens[[idx]]`).
#' @param max_distance passed through to the per-token similarity function;
#'   NULL (default) derives a budget from each token's length, identical to
#'   the fuzzy tier's own default.
#'
#' @return logical(1). TRUE when there is no evidence to evaluate (a query
#'   with zero meaningful tokens is not this gate's concern) or when enough
#'   meaningful query tokens found support; FALSE otherwise. Never NA,
#'   never an error.
retrieval_evidence_sufficient <- function(query_tokens, candidate_tokens,
                                          max_distance = NULL) {
  q_meaningful <- retrieval_meaningful_tokens(query_tokens)
  if (length(q_meaningful) == 0L) return(TRUE)

  c_meaningful <- retrieval_meaningful_tokens(candidate_tokens)
  if (length(c_meaningful) == 0L) return(FALSE)

  c_vocab <- unique(c_meaningful)
  c_nchar <- nchar(c_vocab)

  supported <- vapply(q_meaningful, function(qt) {
    sim <- .retrieval_fuzzy_token_similarity(qt, c_vocab, c_nchar, max_distance = max_distance)
    any(sim >= RETRIEVAL_EVIDENCE_MIN_TOKEN_SIMILARITY)
  }, logical(1))

  sum(supported) >= .retrieval_evidence_required(length(q_meaningful))
}

#' Filter a fused candidate set down to those with sufficient evidence.
#'
#' Applied once, at the fusion boundary, so every approximate-retrieval
#' consumer (Search, PSOC + PSIC, RM, and any future candidate generator)
#' gets the same abstention behaviour with no separate wiring.
#'
#' @param candidates a candidate data.frame (idx, score, rank), as returned
#'   by `retrieval_rrf()` -- may carry a `tiers` attribute, which is
#'   preserved for the surviving rows.
#' @param query_tokens character vector, the query's own meaningful-eligible
#'   tokens (pre-filtering is not required; `retrieval_evidence_sufficient()`
#'   does its own filtering).
#' @param corpus a `retrieval_corpus()` list, supplying `tokens` by index.
#' @param exempt integer vector of `idx` values that bypass the gate.
#'
#'   THIS GATE IS LEXICAL BY CONSTRUCTION: it asks whether the candidate's
#'   own label contains most of the query's words. A SEMANTIC candidate is
#'   lexically disjoint by definition -- that is the entire reason it was
#'   retrieved -- so it can never satisfy this test. Measured, with a
#'   PERFECT (oracle) encoder:
#'
#'     "maize farmer"        -> 6112 CORN FARMERS            cosine 1.000, dropped (1 of 2 tokens supported)
#'     "high school teacher" -> 2330 SECONDARY EDUCATION ... cosine 1.000, dropped (1 of 3)
#'     "vulcanizer"          -> 8141 RUBBER PRODUCTS ...     cosine 1.000, dropped (0 of 1)
#'
#'   so Recall@10 was IDENTICAL with semantic retrieval off, mocked, and
#'   oracle-perfect: the tier was structurally inert, not merely weak.
#'
#'   `exempt` is how a caller admits a candidate that earned its place on
#'   non-lexical evidence. It is deliberately a caller decision: this
#'   function must not know what a "semantic tier" is, and the gate keeps
#'   its full strength for every candidate not named here. Nothing is
#'   exempt by default, so existing behaviour -- including the negative
#'   safety this gate provides -- is byte-identical unless a caller opts in.
#'
#' @return A candidate data.frame in the same shape, re-ranked densely from
#'   1 after dropping insufficient rows. Never NULL, never an error. An
#'   empty or NULL input returns `retrieval_no_candidates()`.
retrieval_evidence_filter <- function(candidates, query_tokens, corpus,
                                      exempt = integer(0)) {
  if (is.null(candidates) || nrow(candidates) == 0L) return(retrieval_no_candidates())
  if (length(query_tokens) == 0L) return(candidates)

  tiers_attr <- attr(candidates, "tiers")
  exempt <- if (length(exempt) == 0L) integer(0) else as.integer(exempt)

  keep <- vapply(candidates$idx, function(idx) {
    if (length(exempt) > 0L && idx %in% exempt) return(TRUE)
    cand_tokens <- corpus$tokens[[idx]]
    retrieval_evidence_sufficient(query_tokens, cand_tokens)
  }, logical(1))

  out <- candidates[keep, , drop = FALSE]
  if (nrow(out) == 0L) return(retrieval_no_candidates())

  out$rank <- seq_len(nrow(out))
  if (!is.null(tiers_attr)) attr(out, "tiers") <- tiers_attr[keep]
  out
}

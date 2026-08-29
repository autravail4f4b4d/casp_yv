# Spec 13 -- post-retrieval context-consistency gate.
#
# THE FAILURE THIS PREVENTS (measured, not hypothetical):
#
#   occupation slot "nurse"
#     -> PSOC search returns exactly ONE candidate:
#        6118 GARDENERS, HORTICULTURAL AND NURSERY GROWERS
#     -> 2221 NURSING PROFESSIONALS is not returned at all
#
# Why: "nurse" is a literal SUBSTRING of "nursery", so the deterministic
# substring tier (tier 5) admits 6118 -- and tiers 1-7 are not subject to
# the approximate-tier evidence gate, so nothing downstream questioned it.
# Meanwhile sim("nurse","nursing") = 0.000, so the correct record was
# lexically unreachable from the user's own wording.
#
# 6118 is perfectly canonical. It is simply not a plausible answer to
# "nurse". Per spec 12.3/13 such a candidate must be REJECTED rather than
# surfaced with a disclaimer.
#
# THE RULE: a candidate survives only if at least one meaningful token of
# the (expansion-aware) slot query finds WHOLE-TOKEN support in the
# candidate's own label, at the same 0.8 similarity floor already
# established and justified for the retrieval evidence gate
# (RETRIEVAL_EVIDENCE_MIN_TOKEN_SIMILARITY, see
# R/retrieval/retrieval_evidence.R). Whole-token, not substring -- that is
# precisely the distinction the tier-5 substring match blurs.
#
# Worked through on the real records:
#   "nurse" (expanded {nurse, nursing}) vs 6118 tokens
#       {gardener, horticultural, and, nursery, grower}
#       sim(nurse,   nursery) = 0.714  < 0.8
#       sim(nursing, nursery) = 0.571  < 0.8      -> REJECTED
#   "nurse" (expanded {nurse, nursing}) vs 2221 tokens
#       {nursing, professional}
#       sim(nursing, nursing) = 1.000 >= 0.8      -> KEPT
#
# This reuses the retrieval layer's own similarity primitive rather than
# inventing a second notion of "matches", and it is a pure function of
# verified candidate text -- no LLM confidence is consulted, as spec 13
# requires ("Do not use LLM free-form confidence as the final gate").

#' Is one verified candidate contextually plausible for a slot query?
#'
#' @param query_texts character vector -- the slot phrase plus any
#'   controlled expansions (`assistant_expand_query()`).
#' @param label character(1) the candidate's official label.
#' @param description character(1) or NA. Consulted only as a fallback when
#'   the label alone gives no support, since official descriptions
#'   legitimately name the occupation in prose the title omits.
#'
#' @return logical(1). TRUE when support is found (or when there is nothing
#'   to judge). Never NA, never an error.
assistant_context_plausible <- function(query_texts, label, description = NA_character_) {
  if (length(query_texts) == 0L) return(TRUE)

  q_tokens <- unique(unlist(
    lapply(query_texts, function(x) retrieval_tokens(retrieval_normalize(x))[[1L]]),
    use.names = FALSE
  ))
  q_meaningful <- retrieval_meaningful_tokens(q_tokens)
  if (length(q_meaningful) == 0L) return(TRUE)

  supported_in <- function(text) {
    if (is.na(text) || !nzchar(text)) return(FALSE)
    c_tokens <- retrieval_tokens(retrieval_normalize(text))[[1L]]
    c_vocab <- unique(retrieval_meaningful_tokens(c_tokens))
    if (length(c_vocab) == 0L) return(FALSE)
    c_nchar <- nchar(c_vocab)
    any(vapply(q_meaningful, function(qt) {
      sim <- .retrieval_fuzzy_token_similarity(qt, c_vocab, c_nchar)
      any(sim >= RETRIEVAL_EVIDENCE_MIN_TOKEN_SIMILARITY)
    }, logical(1)))
  }

  if (supported_in(as.character(label))) return(TRUE)
  supported_in(as.character(description))
}

#' Drop contextually implausible rows from a candidate set.
#'
#' @param rows data.frame with `label` (and optionally `description`).
#' @param query_texts character vector of slot phrase + expansions.
#'
#' @return `rows` filtered. A zero-row result is a legitimate outcome and
#'   means "abstain", per spec 13.
assistant_context_filter <- function(rows, query_texts) {
  if (is.null(rows) || nrow(rows) == 0L) return(rows)
  if (length(query_texts) == 0L) return(rows)

  desc <- if ("description" %in% names(rows)) {
    as.character(rows$description)
  } else {
    rep(NA_character_, nrow(rows))
  }

  keep <- vapply(seq_len(nrow(rows)), function(i) {
    assistant_context_plausible(query_texts, rows$label[[i]], desc[[i]])
  }, logical(1))

  rows[keep, , drop = FALSE]
}

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

# Residual / negated category markers.
#
# Classifications end many families with a catch-all ("... n.e.c.",
# "Other ...") or with an explicit negation ("NON-residential",
# "except rice and corn"). Those categories are defined by what they are
# NOT, so when the user's own wording does not contain the marker they
# should rank BELOW the affirmative sibling that names the thing directly.
#
# Measured need: "residential construction" matched BOTH
# 41001 Construction of residential buildings AND
# 41002 Construction of NON-residential buildings equally, because
# "non-residential" tokenizes to {non, residential} and so contains the
# query token. The pair then looked like a genuine sibling ambiguity and
# the service asked a question the user had already answered.
# Markers valid ANYWHERE in a label: these always designate a residual or
# negated category ("... n.e.c.", "NON-residential", "except rice").
ASSISTANT_RESIDUAL_MARKERS <- c(
  "non", "nec", "elsewhere", "except", "unspecified", "miscellaneous"
)

# "other" only counts when the label STARTS with it. Measured reason:
# 78200 "Temporary employment agency activities and OTHER human resource
# provisions" is a compound title, not a catch-all, and penalising it
# pushed the correct detailed sub-class below its own aggregate. By
# contrast "Other amusement and recreation activities" genuinely is the
# residual sibling of its family.
.ASSISTANT_RESIDUAL_LEADING <- "other"

#' Does a candidate label carry a residual/negated marker the query lacks?
#'
#' @return logical(1). TRUE means the candidate is a catch-all or negated
#'   category that the user did not ask for.
assistant_is_residual_match <- function(query_texts, label) {
  raw_lbl <- tolower(as.character(label))
  if (length(raw_lbl) != 1L || is.na(raw_lbl) || !nzchar(raw_lbl)) return(FALSE)
  # Collapse the dotted abbreviation FIRST: normalization splits "n.e.c."
  # into the three single letters n / e / c, which no marker can match.
  raw_lbl <- gsub("n\\.?\\s?e\\.?\\s?c\\.?", " nec ", raw_lbl)
  lbl <- .assistant_norm_text(raw_lbl)
  if (!nzchar(lbl)) return(FALSE)
  lbl_tokens <- strsplit(lbl, " ", fixed = TRUE)[[1L]]
  lbl_markers <- intersect(lbl_tokens, ASSISTANT_RESIDUAL_MARKERS)
  if (length(lbl_tokens) > 0L &&
      identical(lbl_tokens[[1L]], .ASSISTANT_RESIDUAL_LEADING)) {
    lbl_markers <- c(lbl_markers, .ASSISTANT_RESIDUAL_LEADING)
  }
  if (length(lbl_markers) == 0L) return(FALSE)

  raw_q <- tolower(paste(as.character(query_texts), collapse = " "))
  raw_q <- gsub("n\\.?\\s?e\\.?\\s?c\\.?", " nec ", raw_q)
  q <- .assistant_norm_text(raw_q)
  q_tokens <- strsplit(q, " ", fixed = TRUE)[[1L]]
  # Only penalise markers the user did NOT use: someone asking for
  # "other retail" genuinely wants the residual category.
  length(setdiff(lbl_markers, q_tokens)) > 0L
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

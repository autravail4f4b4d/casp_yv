# Deterministic, dependency-light scoring for the PSIC 2019<->2026
# correspondence build (scripts/build_psic_correspondence.R).
#
# Everything here is plain string/set arithmetic -- no generative LLM, no
# statistical calibration, no external fuzzy-matching package. `stringdist`
# was checked and is not installed; per CLAUDE.md's "prefer the smallest
# dependency surface" rule, similarity is a hand-rolled Jaccard-over-
# normalized-word-tokens function rather than a new dependency.
#
# SCORING MODEL
# -------------
# `score_correspondence()` sums independent signals into a single ordinal
# score, then buckets that score into "high"/"moderate"/"low" confidence.
# These are NOT calibrated probabilities -- section 17 of the spec is
# explicit that its own illustrative weights ("same exact code +40",
# "authoritative ISIC bridge +30", "near-identical title +15", "compatible
# hierarchy +10", "description similarity +5") are a starting framework
# only, to be made "explicit, centralized, and testable", not copied
# verbatim. This build keeps the same four signal *names* the spec lists,
# but grades "compatible hierarchy" by how tight the match is (same class >
# same group > same division) instead of one flat compatible/incompatible
# boolean, because a same-4-digit-class match is materially stronger
# location evidence than a same-2-digit-division match and collapsing both
# into "+10" would understate that difference. This is a documented
# deviation from the spec's flat illustrative number, not from its intent.
#
# WEIGHTS (points)
#   exact_code            40   the 2019 code exists verbatim in 2026
#   hierarchy: same_class  30   same 4-digit class-code family
#   hierarchy: same_group  15   same 3-digit group-code family
#   hierarchy: same_division 7  same 2-digit division-code family
#   hierarchy: none          0
#   isic_bridge_supported  30   authoritative UN ISIC Rev.4<->Rev.5 class
#                                correspondence connects the two positions,
#                                AND both PSIC editions' own labels at that
#                                class position are themselves close to the
#                                ISIC title there (see isic_bridge.R for why
#                                that gate exists: PSIC reassigns some
#                                class-level codes to different national
#                                concepts than ISIC uses at the same number,
#                                so a code-number match against ISIC alone
#                                is not trustworthy without also checking
#                                that PSIC actually followed ISIC's
#                                assignment at that position)
#   near_identical_title    15   normalized-label Jaccard similarity >= 0.90
#   description_similarity   5   both descriptions present (non-NA) and
#                                normalized-token Jaccard similarity >= 0.60
#
# CONFIDENCE BUCKETS
#   score >= 50            high
#   25 <= score < 50        moderate
#   score < 25              low
#
# These cutoffs are an explicit, documented choice (not calibrated), picked
# so that: (a) exact-code continuity alone with a same-class hierarchy bonus
# already clears "high" even with a completely different title (matches the
# spec's explicit instruction that a "renamed" row -- exact code, different
# label -- must still be confidence "high", since code continuity alone is
# strong deterministic evidence); (b) a same-class-family candidate with no
# strong title match lands at "moderate" (right neighbourhood, real
# uncertainty about which specific target); (c) a pure cross-division
# label-similarity guess with no hierarchy support lands at "low" unless the
# title match is very strong.

CORRESPONDENCE_SCORE_WEIGHTS <- list(
  exact_code = 40,
  hierarchy_same_class = 30,
  hierarchy_same_group = 15,
  hierarchy_same_division = 7,
  hierarchy_none = 0,
  isic_bridge_supported = 30,
  near_identical_title = 15,
  description_similarity = 5
)

CORRESPONDENCE_CONFIDENCE_THRESHOLDS <- list(high = 50, moderate = 25)

# Similarity thresholds used throughout the build (kept here, centralized,
# so a single place documents every magic number in this pipeline).
CORRESPONDENCE_SIMILARITY_THRESHOLDS <- list(
  near_identical_title = 0.90,   # jaccard >= this counts as "near-identical"
  description_similarity = 0.60, # jaccard >= this counts as "similar" description
  candidate_minimum = 0.34,      # jaccard >= this is even considered a fallback candidate
  isic_conformance = 0.50        # jaccard >= this means a PSIC label "follows" its ISIC title
)

#' Normalize a label for comparison: lowercase, strip punctuation, collapse
#' whitespace. Never mutates the original label used for display.
normalize_label <- function(x) {
  x <- ifelse(is.na(x), "", x)
  x <- tolower(x)
  x <- gsub("[^a-z0-9 ]+", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

#' Tokenize a normalized label into a unique word set.
label_tokens <- function(x) {
  norm <- normalize_label(x)
  if (identical(norm, "")) return(character(0))
  unique(strsplit(norm, " ", fixed = TRUE)[[1]])
}

#' Jaccard similarity between the word-token sets of two labels.
#' Returns 0 if either side has no tokens (rather than NaN/NA), so callers
#' never have to special-case empty/NA labels.
jaccard_token_similarity <- function(a, b) {
  ta <- label_tokens(a)
  tb <- label_tokens(b)
  if (length(ta) == 0L || length(tb) == 0L) return(0)
  inter <- length(intersect(ta, tb))
  uni <- length(union(ta, tb))
  if (uni == 0L) return(0)
  inter / uni
}

#' Is label `a` "near-identical" to label `b`?
#' Exact normalized-string equality always counts; otherwise falls back to
#' the token-Jaccard threshold (handles reordered/lightly-reworded titles).
is_near_identical_title <- function(a, b) {
  na_norm <- normalize_label(a)
  nb_norm <- normalize_label(b)
  if (identical(na_norm, nb_norm) && !identical(na_norm, "")) return(TRUE)
  jaccard_token_similarity(a, b) >= CORRESPONDENCE_SIMILARITY_THRESHOLDS$near_identical_title
}

#' Classify the code-prefix hierarchy relationship between two PSIC codes.
#' Only defined for the numeric portion below section level (division/
#' group/class/sub-class codes are strictly left-prefix nested; section is
#' not, per the adapters' own documented convention -- this function is
#' never asked to compare across section).
#'
#' @return one of "same_class", "same_group", "same_division", "none".
hierarchy_relation <- function(code_a, code_b) {
  if (is.na(code_a) || is.na(code_b)) return("none")
  if (nchar(code_a) >= 4 && nchar(code_b) >= 4 && substr(code_a, 1, 4) == substr(code_b, 1, 4)) {
    return("same_class")
  }
  if (nchar(code_a) >= 3 && nchar(code_b) >= 3 && substr(code_a, 1, 3) == substr(code_b, 1, 3)) {
    return("same_group")
  }
  if (nchar(code_a) >= 2 && nchar(code_b) >= 2 && substr(code_a, 1, 2) == substr(code_b, 1, 2)) {
    return("same_division")
  }
  "none"
}

.hierarchy_weight <- function(relation) {
  switch(relation,
    same_class = CORRESPONDENCE_SCORE_WEIGHTS$hierarchy_same_class,
    same_group = CORRESPONDENCE_SCORE_WEIGHTS$hierarchy_same_group,
    same_division = CORRESPONDENCE_SCORE_WEIGHTS$hierarchy_same_division,
    CORRESPONDENCE_SCORE_WEIGHTS$hierarchy_none
  )
}

#' Bucket a numeric score into "high"/"moderate"/"low".
bucket_confidence <- function(score) {
  if (score >= CORRESPONDENCE_CONFIDENCE_THRESHOLDS$high) return("high")
  if (score >= CORRESPONDENCE_CONFIDENCE_THRESHOLDS$moderate) return("moderate")
  "low"
}

#' Compute the full centralized score for one candidate source/target pair.
#'
#' @param exact_code logical(1). Source code == target code verbatim.
#' @param source_label,target_label character(1) each. Used for the
#'   near-identical-title signal.
#' @param source_code,target_code character(1) each. Used for the hierarchy
#'   signal (ignored if `exact_code` is TRUE, since hierarchy is then
#'   trivially "same_class").
#' @param source_description,target_description character(1) each,
#'   possibly NA. Used for the description-similarity signal.
#' @param isic_bridge_supported logical(1). Precomputed by the caller via
#'   `isic_bridge_supported()` in isic_bridge.R.
#'
#' @return a list(score = double, confidence = character, hierarchy = character)
score_correspondence <- function(exact_code,
                                  source_code, target_code,
                                  source_label, target_label,
                                  source_description = NA_character_,
                                  target_description = NA_character_,
                                  isic_bridge_supported = FALSE) {
  score <- 0
  hierarchy <- if (isTRUE(exact_code)) "same_class" else hierarchy_relation(source_code, target_code)

  if (isTRUE(exact_code)) score <- score + CORRESPONDENCE_SCORE_WEIGHTS$exact_code
  score <- score + .hierarchy_weight(hierarchy)
  if (isTRUE(isic_bridge_supported)) score <- score + CORRESPONDENCE_SCORE_WEIGHTS$isic_bridge_supported

  near_identical <- is_near_identical_title(source_label, target_label)
  if (near_identical) score <- score + CORRESPONDENCE_SCORE_WEIGHTS$near_identical_title

  desc_similar <- FALSE
  if (!is.na(source_description) && !is.na(target_description) &&
      nchar(trimws(source_description)) > 0 && nchar(trimws(target_description)) > 0) {
    desc_similar <- jaccard_token_similarity(source_description, target_description) >=
      CORRESPONDENCE_SIMILARITY_THRESHOLDS$description_similarity
  }
  if (desc_similar) score <- score + CORRESPONDENCE_SCORE_WEIGHTS$description_similarity

  list(
    score = score,
    confidence = bucket_confidence(score),
    hierarchy = hierarchy,
    near_identical_title = near_identical,
    description_similar = desc_similar
  )
}

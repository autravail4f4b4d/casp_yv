# Shared deterministic normalization for hybrid classification retrieval.
#
# This is THE normalization contract. Every retrieval tier -- lexical,
# fuzzy, n-gram, semantic -- and the evaluation harness must call these
# functions rather than rolling their own casefold/trim, because a
# candidate generator that normalizes differently from the one that ranks
# it will silently disagree about what matched.
#
# Two hard rules:
#
#   1. NOTHING HERE TOUCHES CANONICAL DATA. These functions produce a
#      transient comparison key. Official codes and labels are never
#      rewritten, and the value returned to the UI always comes from the
#      repository, never from a normalized string.
#
#   2. CODE PUNCTUATION IS INFORMATION. "0101.29.00-001" and
#      "0101.29.00001" are different codes. Text normalization strips
#      punctuation; code normalization must not. The two paths are
#      therefore separate functions, and the caller picks deliberately.
#
# Stemming is deliberately NOT implemented. Aggressive stemming collapses
# distinct official terms ("operating"/"operator", "processing"/"processor")
# that this classification genuinely distinguishes. Only a controlled
# plural rule is applied -- see .retrieval_singularize().

# U+00A0 NBSP and the other separators that appear in PSA source workbooks.
# R's [[:space:]] does not match U+00A0, which is exactly the defect that
# made 1,647 PSCC hierarchy rows read as depth 0 in an earlier milestone.
RETRIEVAL_SPACE_CHARS <- "  -   　  "

#' Normalize free text into a comparison key.
#'
#' Deterministic and idempotent: `f(f(x)) == f(x)`.
#'
#' Steps, in order: Unicode NFKC composition; unify exotic spaces to plain
#' spaces; case-fold; map typographic quotes/dashes to ASCII; drop
#' punctuation to spaces; collapse whitespace; trim.
#'
#' @param x character vector.
#'
#' @return character vector of the same length. NA in, NA out.
retrieval_normalize <- function(x) {
  x <- as.character(x)
  if (length(x) == 0L) return(character(0))

  out <- stringi::stri_trans_nfkc(x)
  out <- stringi::stri_replace_all_regex(out, paste0("[", RETRIEVAL_SPACE_CHARS, "]"), " ")
  out <- stringi::stri_trans_tolower(out)

  # Typographic characters -> ASCII, so a curly apostrophe and a straight
  # one produce the same key.
  out <- stringi::stri_replace_all_fixed(
    out,
    c("‘", "’", "“", "”", "–", "—", "‐", "‑"),
    c("'", "'", "\"", "\"", "-", "-", "-", "-"),
    vectorize_all = FALSE
  )

  # Everything that is not a letter, digit or space becomes a space. This
  # is where hyphens and apostrophes go: "n.e.c." -> "n e c", "workers'" ->
  # "workers". Splitting rather than deleting is deliberate -- deleting
  # would weld "truck-driver" into "truckdriver" and lose a token boundary.
  out <- stringi::stri_replace_all_regex(out, "[^\\p{L}\\p{N} ]+", " ")

  out <- stringi::stri_replace_all_regex(out, "\\s+", " ")
  out <- stringi::stri_trim_both(out)

  out[is.na(x)] <- NA_character_
  out
}

#' Normalize a classification code for comparison.
#'
#' Case and surrounding whitespace are noise; separators are not. A code
#' key keeps every dot, hyphen and leading zero exactly as published, so
#' this can never collapse two distinct codes onto one key.
#'
#' @param x character vector.
#'
#' @return character vector of the same length. NA in, NA out.
retrieval_normalize_code <- function(x) {
  x <- as.character(x)
  if (length(x) == 0L) return(character(0))

  out <- stringi::stri_trans_nfkc(x)
  out <- stringi::stri_replace_all_regex(out, paste0("[", RETRIEVAL_SPACE_CHARS, "]"), " ")
  out <- stringi::stri_trans_tolower(out)
  out <- stringi::stri_trim_both(out)
  out <- stringi::stri_replace_all_regex(out, "\\s+", " ")

  out[is.na(x)] <- NA_character_
  out
}

# Controlled singularization. English plural rules only, applied to whole
# tokens, and only the three regular patterns. This is what lets
# "drivers" match "driver" without a stemmer deciding that "buses" and
# "business" share a root.
#
# Tokens of three characters or fewer are left alone ("gas" must not
# become "ga"), and a short irregular allowlist protects official terms
# whose plural form IS the lemma.
RETRIEVAL_PLURAL_KEEP <- c(
  "gas", "goods", "premises", "series", "species", "works", "news",
  "analysis", "basis", "status", "census", "business", "process",
  "glass", "class", "grass", "press", "dress", "cross", "loss", "gross"
)

.retrieval_singularize <- function(tokens) {
  out <- tokens
  # `done` makes the three rules MUTUALLY EXCLUSIVE. Applying them in
  # sequence to the same token compounds them: "buses" would lose "es" to
  # rule 2 giving "bus", then lose "s" to rule 3 giving "bu". Only the
  # first matching rule may fire per token.
  done <- tokens %in% RETRIEVAL_PLURAL_KEEP | nchar(tokens) <= 3L

  # "...ies" -> "...y"  (lorries -> lorry)
  i <- !done & grepl("[^aeiou]ies$", out)
  out[i] <- sub("ies$", "y", out[i])
  done <- done | i

  # "...ses"/"...xes"/"...zes"/"...ches"/"...shes" -> drop "es"
  # (buses -> bus, boxes -> box, batches -> batch)
  i <- !done & grepl("(s|x|z|ch|sh)es$", out)
  out[i] <- sub("es$", "", out[i])
  done <- done | i

  # plain trailing "s" (drivers -> driver), but never a "ss" ending
  i <- !done & grepl("[^s]s$", out)
  out[i] <- sub("s$", "", out[i])

  out
}

#' Split normalized text into comparison tokens.
#'
#' @param x character vector (raw or already normalized -- normalization is
#'   idempotent, so it is applied again defensively).
#' @param singularize logical(1). Apply the controlled plural rule.
#'
#' @return A list of character vectors, one per input element. An empty or
#'   NA input yields `character(0)`, never NULL.
retrieval_tokens <- function(x, singularize = TRUE) {
  norm <- retrieval_normalize(x)
  lapply(norm, function(s) {
    if (is.na(s) || !nzchar(s)) return(character(0))
    toks <- strsplit(s, " ", fixed = TRUE)[[1]]
    toks <- toks[nzchar(toks)]
    if (singularize && length(toks)) toks <- .retrieval_singularize(toks)
    toks
  })
}

#' A single normalized comparison key with plurals folded.
#'
#' Used as the "does every token appear" key by the lexical tier and as the
#' input string to the n-gram tier, so both agree on morphology.
#'
#' @param x character vector.
#'
#' @return character vector of space-joined singularized tokens.
retrieval_normalize_tokens <- function(x) {
  vapply(retrieval_tokens(x), function(t) paste(t, collapse = " "), character(1))
}

#' Does a query look like a classification code rather than words?
#'
#' Used to decide whether to compare against the code column or the label
#' column. Deliberately conservative: a string is code-like only if it
#' contains a digit and no alphabetic run longer than two characters, so
#' "8332" and "0101.29.00-001" qualify while "heavy truck driver" and
#' "section a" do not.
#'
#' @param x character vector.
#'
#' @return logical vector of the same length.
retrieval_is_code_like <- function(x) {
  x <- as.character(x)
  trimmed <- stringi::stri_trim_both(x)
  has_digit <- grepl("[0-9]", trimmed)
  long_alpha <- grepl("[A-Za-z]{3,}", trimmed)
  out <- has_digit & !long_alpha
  out[is.na(x)] <- FALSE
  out
}

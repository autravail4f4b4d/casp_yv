# C7 -- canonical example-occupation evidence.
#
# WHY THIS EXISTS
# ---------------
# The corrective micro-gate exposed three selection failures that share one
# cause: the resolver ranked candidates on LABEL text alone, and several
# occupations are simply not named in any label.
#
#   "mayor"             -> ranked 1112 SENIOR GOVERNMENT OFFICIALS first
#                          (correct answer is 1111 LEGISLATORS)
#   "statistician"      -> no verified code was asserted at all
#   "call center agent" -> 4222 and 5244 tied, both surfaced as equals
#
# None of those words appear in the labels 1111 LEGISLATORS, 2122
# STATISTICIANS or CONTACT CENTER INFORMATION CLERKS in a way that ranks
# them correctly. But the canonical repository DOES carry the evidence, in
# a structured section of each unit group's official description:
#
#   "... Examples of the occupations classified here: Call center agent,
#    Call center assistant/representative, Customer service representative
#    Some related occupations classified elsewhere: Call center salesperson
#    - 5244, Telemarketing salesperson - 5244 ..."
#
# Measured against 1111: the token "mayor" occurs in exactly ONE PSOC
# description in the whole repository, and it is 1111's example list
# ("... Governor/Vice Governor, Mayor/Vice Mayor, Senator"). So the correct
# answer was always derivable from canonical data; the resolver just was
# not reading it.
#
# THE EDITION PROBLEM, AND WHY BORROWING IS SAFE
# ----------------------------------------------
# Measured: PSOC 2022 carries descriptions for 0 of its 649 records, while
# the archived PSOC 2012 edition carries them for all 638. The examples
# therefore have to come from the archived edition.
#
# That is only sound where the two editions genuinely describe the same
# occupation, so the borrow is gated on BOTH conditions holding:
#   * the code exists in both editions, AND
#   * the two labels are identical after normalization.
# Measured coverage: 611 of 649 current codes have such a twin; 24 codes
# present in both editions have DIFFERENT labels and are deliberately
# excluded -- a changed label is exactly the signal that the concept moved,
# and borrowing there could attach 2012 examples to a 2022 concept that no
# longer matches.
#
# Nothing here can mint a code: example evidence only REORDERS candidates
# that hybrid retrieval already returned and that canonical verification
# will still confirm. The current edition remains the classification of
# record, and no archived label or code is ever presented to the user.
#
# PARSING
# -------
# The "Examples of the occupations classified here" / "Some related
# occupations classified elsewhere" pair is a fixed PSA/ISCO template, not
# free prose: it occurs verbatim in 359 of 638 records (341 of 455 unit
# groups). Splitting on those two literal anchors is therefore a structural
# read, not fragile pattern-guessing. The "classified elsewhere" tail is
# discarded deliberately -- it lists occupations belonging to OTHER codes,
# each with the other code appended ("Call center salesperson - 5244"), so
# treating it as evidence for THIS code would invert the intended meaning.

# Both anchors have measured wording variants in the canonical text, so
# they are matched as bounded case-insensitive patterns rather than one
# fixed string:
#   "here"      -> "Examples of the occupations classified here:"      (288)
#                  "Examples of the occupations classified here are:"  (71)
#                  "Example of the occupations classified here:"       (9)
#   "elsewhere" -> "Some related occupations classified elsewhere"     (206)
#                  "A related occupations classified elsewhere"        (11)
# Missing the singular "Example of ..." form silently dropped 9 records'
# evidence; missing the "A related ..." form let an OTHER code's
# cross-reference ("Statistician - 2120" under 2631 Economists) be read as
# evidence FOR 2631, which is exactly the inversion this parser must avoid.
.ASSISTANT_EXAMPLES_HERE_ANCHOR <-
  "Examples? of the occupations? classified here\\s*(are)?\\s*:?"
.ASSISTANT_EXAMPLES_ELSEWHERE_ANCHOR <-
  "\\w+\\s+related occupations? classified elsewhere"

.assistant_examples_cache <- new.env(parent = emptyenv())

.assistant_examples_cache_reset <- function() {
  rm(list = ls(.assistant_examples_cache), envir = .assistant_examples_cache)
  invisible(NULL)
}

.assistant_norm_text <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("[^a-z0-9]+", " ", x)
  trimws(gsub("\\s+", " ", x))
}

#' Pull the example-occupation list out of one official description.
#'
#' @param description character(1).
#' @return character vector of example occupation phrases (possibly empty).
assistant_parse_example_occupations <- function(description) {
  d <- as.character(description)
  if (length(d) != 1L || is.na(d) || !nzchar(d)) return(character(0))
  if (!grepl(.ASSISTANT_EXAMPLES_HERE_ANCHOR, d, ignore.case = TRUE)) {
    return(character(0))
  }

  tail <- sub(paste0("^.*", .ASSISTANT_EXAMPLES_HERE_ANCHOR), "", d,
              ignore.case = TRUE)
  # Drop the "classified elsewhere" block: those belong to OTHER codes.
  tail <- strsplit(tail, .ASSISTANT_EXAMPLES_ELSEWHERE_ANCHOR,
                   perl = FALSE)[[1L]][1L]
  tail <- sub("^\\s*:?\\s*", "", tail)

  parts <- unlist(strsplit(tail, "[,;]"), use.names = FALSE)
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]
  # An example may pack two forms into one entry ("Mayor/Vice Mayor",
  # "Call center assistant/representative"); keep the whole phrase AND the
  # slash-separated alternatives.
  extra <- unlist(strsplit(parts, "/", fixed = TRUE), use.names = FALSE)
  unique(trimws(c(parts, extra[nzchar(trimws(extra))])))
}

#' Example occupations for one code, borrowing from an archived edition
#' when the current edition carries no description.
#'
#' @return character vector, possibly empty. Never errors.
assistant_example_occupations <- function(system, version = NULL, code) {
  system_chr <- .assistant_scalar_chr(system)
  code_chr <- .assistant_scalar_chr(code)
  if (is.null(system_chr) || is.null(code_chr)) return(character(0))
  version_chr <- tryCatch(.assistant_resolve_version(system_chr, version),
                          error = function(e) NULL)
  if (is.null(version_chr)) return(character(0))

  idx <- .assistant_examples_index(system_chr, version_chr)
  if (is.null(idx)) return(character(0))
  hit <- idx[[code_chr]]
  if (is.null(hit)) character(0) else hit
}

# code -> example vector, for one system+version, built once per process.
.assistant_examples_index <- function(system, version) {
  key <- paste0("ex::", system, "::", version)
  cached <- .assistant_examples_cache[[key]]
  if (!is.null(cached)) return(cached)

  current <- tryCatch(get_classification(system, version, level = NULL),
                      error = function(e) NULL)
  if (is.null(current) || nrow(current) == 0L) return(NULL)

  desc <- as.character(current$description)
  has_own <- !is.na(desc) & nzchar(trimws(desc))

  # Borrow from every OTHER edition of the same system, but only for codes
  # whose label is unchanged.
  if (!all(has_own)) {
    other_versions <- tryCatch(
      setdiff(as.character(classification_versions(system)), version),
      error = function(e) character(0)
    )
    cur_norm_label <- .assistant_norm_text(current$label)
    for (ov in other_versions) {
      archived <- tryCatch(get_classification(system, ov, level = NULL),
                           error = function(e) NULL)
      if (is.null(archived) || nrow(archived) == 0L) next
      a_desc <- as.character(archived$description)
      keep <- !is.na(a_desc) & nzchar(trimws(a_desc))
      if (!any(keep)) next
      archived <- archived[keep, , drop = FALSE]
      a_desc <- a_desc[keep]

      m <- match(current$code, archived$code)
      ok <- !has_own & !is.na(m)
      if (!any(ok)) next
      label_same <- rep(FALSE, length(ok))
      label_same[ok] <- cur_norm_label[ok] ==
        .assistant_norm_text(archived$label[m[ok]])
      take <- ok & label_same
      desc[take] <- a_desc[m[take]]
      has_own <- has_own | take
    }
  }

  out <- new.env(parent = emptyenv())
  for (i in seq_len(nrow(current))) {
    if (!has_own[[i]]) next
    ex <- assistant_parse_example_occupations(desc[[i]])
    if (length(ex)) assign(as.character(current$code[[i]]), ex, envir = out)
  }
  idx <- as.list(out)
  .assistant_examples_cache[[key]] <- idx
  idx
}

# Evidence strength of a slot phrase against one code's example list.
#
#   2  exact match -- the phrase IS one of the canonical examples
#   1  subset match -- every meaningful token of the phrase appears in one
#      example, so the phrase is a less specific form of it
#   0  no example evidence
#
# The two tiers are what separate the call-center pair without naming
# either code: "call center agent" is EXACTLY an example under 4222 (score
# 2) but only a subset of "Call center agent (sales and marketing)" under
# 5244 (score 1), so 4222 wins; "call center sales agent" is a subset of
# the 5244 example only (4222's example has no "sales" token), so 5244 wins.
ASSISTANT_EXAMPLE_SCORE_EXACT <- 2L
ASSISTANT_EXAMPLE_SCORE_SUBSET <- 1L
ASSISTANT_EXAMPLE_SCORE_NONE <- 0L

#' Score a slot phrase against a code's canonical example occupations.
#'
#' @return integer(1): 2 exact, 1 subset, 0 none.
assistant_example_evidence_score <- function(phrase, examples) {
  p <- .assistant_scalar_chr(phrase)
  if (is.null(p) || length(examples) == 0L) return(ASSISTANT_EXAMPLE_SCORE_NONE)

  q <- .assistant_norm_text(p)
  if (!nzchar(q)) return(ASSISTANT_EXAMPLE_SCORE_NONE)
  ex_norm <- .assistant_norm_text(examples)
  ex_norm <- ex_norm[nzchar(ex_norm)]
  if (length(ex_norm) == 0L) return(ASSISTANT_EXAMPLE_SCORE_NONE)

  if (any(ex_norm == q)) return(ASSISTANT_EXAMPLE_SCORE_EXACT)

  q_tokens <- retrieval_meaningful_tokens(strsplit(q, " ", fixed = TRUE)[[1L]])
  if (length(q_tokens) == 0L) return(ASSISTANT_EXAMPLE_SCORE_NONE)
  for (e in ex_norm) {
    e_tokens <- retrieval_meaningful_tokens(strsplit(e, " ", fixed = TRUE)[[1L]])
    if (length(e_tokens) && all(q_tokens %in% e_tokens)) {
      return(ASSISTANT_EXAMPLE_SCORE_SUBSET)
    }
  }
  ASSISTANT_EXAMPLE_SCORE_NONE
}

#' Example-evidence score for one code against the user's OWN phrase.
#'
#' Deliberately scored on the original wording only, never on the
#' controlled expansions. Measured reason: "corn farmer" expands to
#' "farming"/"growing" for retrieval recall, and "farming" is a subset of
#' 2132's example "Farming adviser" -- scoring expansions promoted
#' FARMING, FORESTRY AND FISHERIES ADVISERS above the correct 6112 CORN
#' FARMERS. Expansions exist to widen the candidate POOL; they are far too
#' coarse to serve as evidence about which candidate the user meant.
assistant_code_example_score <- function(system, version, code, phrase) {
  ex <- assistant_example_occupations(system, version, code)
  if (length(ex) == 0L) return(ASSISTANT_EXAMPLE_SCORE_NONE)
  assistant_example_evidence_score(phrase, ex)
}

#' Codes whose canonical example occupations match a phrase.
#'
#' Retrieval indexes labels, not example lists, so an occupation named ONLY
#' in an example ("City administrator" under 1112 SENIOR GOVERNMENT
#' OFFICIALS, "Call center agent (sales and marketing)" under 5244) is
#' unreachable by lexical search and the resolver abstained on it. This
#' scans the example index directly so such codes can enter the candidate
#' pool at all. They still pass canonical verification and the ordinary
#' ranking afterwards -- this widens the pool, it never decides an answer.
#'
#' @return data.frame(code, example_evidence) ordered strongest first,
#'   possibly zero-row. Never errors.
assistant_codes_matching_examples <- function(system, version = NULL, phrase,
                                              min_score = ASSISTANT_EXAMPLE_SCORE_SUBSET) {
  empty <- data.frame(code = character(0), example_evidence = integer(0),
                      stringsAsFactors = FALSE)
  system_chr <- .assistant_scalar_chr(system)
  p <- .assistant_scalar_chr(phrase)
  if (is.null(system_chr) || is.null(p)) return(empty)
  version_chr <- tryCatch(.assistant_resolve_version(system_chr, version),
                          error = function(e) NULL)
  if (is.null(version_chr)) return(empty)

  idx <- .assistant_examples_index(system_chr, version_chr)
  if (is.null(idx) || length(idx) == 0L) return(empty)

  scores <- vapply(idx, function(ex) assistant_example_evidence_score(p, ex), integer(1))
  keep <- scores >= min_score
  if (!any(keep)) return(empty)

  out <- data.frame(
    code = names(idx)[keep],
    example_evidence = unname(scores[keep]),
    stringsAsFactors = FALSE
  )
  out[order(-out$example_evidence, out$code), , drop = FALSE]
}

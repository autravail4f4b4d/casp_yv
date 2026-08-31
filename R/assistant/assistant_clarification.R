# W1 -- bounded clarification resolution.
#
# ============================================================================
# THE ROOT CAUSE THIS FILE EXISTS TO REMOVE
# ============================================================================
#
# v10 made the SERVER choose the route, the slots and the code. It did not
# make the server choose how a REPLY relates to the question it just asked.
# `assistant_turn_apply_reply()` had exactly one rule for a detail slot:
#
#     args$establishment_activity <- txt        # whatever the user typed
#
# and the reply then went through ordinary global PSIC retrieval. Every
# remaining live blocker falls out of that one line:
#
#   teacher -> "latter"
#       "latter" became the establishment activity and was retrieved
#       against the whole of PSIC. It matches "Manufacture of prepared
#       pigments..." (20224) on the fragment "latter"/"lather". The two
#       verified options the application had ALREADY computed -- 85312 and
#       85314 -- were never consulted, because
#       `assistant_turn_set_pending()` stored only `missing_slot` and the
#       question STRING and threw the options (codes included) away.
#
#   teacher -> full option label
#       Same path. It happened to retrieve the right code, but by global
#       search rather than by selecting the option the user named, so the
#       result was luck, not a contract -- and once the ordinal turn above
#       had wrongly RESOLVED the packet, the pending state was gone and
#       the label became a fresh occupation request instead ("no verified
#       PSOC").
#
#   carpenter -> "residential"
#       A single ambiguous word was passed straight into unrestricted PSIC
#       retrieval, which returned 87100 Residential nursing care
#       activities for a carpenter.
#
# The fix is a BOUNDED UNIVERSE. When the application asked a question with
# options, the reply is resolved against those options and nothing else;
# when it asked an open question, a reply that carries no discriminating
# content is refused rather than retrieved.
#
# Nothing here invents a code. Options already carry canonical codes
# produced by the deterministic retrieval that raised the question, and a
# selected option is RE-VERIFIED against the canonical repository (current
# edition only) before it can become an answer.

# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------

# Lower-case, punctuation-to-space, whitespace-collapsed. Deliberately the
# same shape as `.assistant_norm_text()` but kept local so a change to the
# retrieval normaliser can never silently change what "second" means.
.assistant_clar_norm <- function(x) {
  s <- .assistant_scalar_chr(x)
  if (is.null(s)) return("")
  s <- tolower(s)
  s <- gsub("[^a-z0-9]+", " ", s)
  trimws(gsub("\\s+", " ", s))
}

.assistant_clar_tokens <- function(x) {
  t <- strsplit(.assistant_clar_norm(x), " ", fixed = TRUE)[[1L]]
  t[nzchar(t)]
}

# ---------------------------------------------------------------------------
# Ordinal / reference resolver (spec 10)
# ---------------------------------------------------------------------------

# Bare index words. `former`/`latter` are handled separately because they
# are only defined for a two-choice question.
.ASSISTANT_ORDINAL_WORDS <- list(
  "1" = 1L, "2" = 2L, "3" = 3L, "4" = 4L,
  "1st" = 1L, "2nd" = 2L, "3rd" = 3L, "4th" = 4L,
  "first" = 1L, "second" = 2L, "third" = 3L, "fourth" = 4L
)

# Leading words that only introduce the reference ("option 2", "the third",
# "number 1"). Stripped, never matched on their own.
.ASSISTANT_ORDINAL_LEAD <- "^(the|option|options|choice|number|no|item|letter)\\s+"

# Trailing words that only follow the reference ("second one", "first option").
.ASSISTANT_ORDINAL_TRAIL <- "\\s+(one|option|choice|item)$"

#' Resolve an ordinal / positional reference to a 1-based option index.
#'
#' Case-insensitive, punctuation and whitespace tolerant. Returns
#' `NA_integer_` for anything that is not unambiguously a reference, so a
#' caller can fall through to label matching -- this function never
#' guesses.
#'
#' `former` and `latter` resolve ONLY for a two-choice question (spec 10).
#' With three options "the latter" does not identify anything, and picking
#' the last one would be an invention.
#'
#' @param reply character(1) the user's message.
#' @param n_options integer(1) how many options are on offer.
#'
#' @return integer(1) in `1:n_options`, or `NA_integer_`.
assistant_option_reference_index <- function(reply, n_options) {
  n <- suppressWarnings(as.integer(n_options))
  if (is.na(n) || n < 1L) return(NA_integer_)

  s <- .assistant_clar_norm(reply)
  if (!nzchar(s)) return(NA_integer_)

  # Strip introducers/trailers repeatedly: "the option 2", "the second one".
  repeat {
    before <- s
    s <- trimws(sub(.ASSISTANT_ORDINAL_LEAD, "", s, perl = TRUE))
    s <- trimws(sub(.ASSISTANT_ORDINAL_TRAIL, "", s, perl = TRUE))
    if (identical(s, before)) break
  }
  if (!nzchar(s)) return(NA_integer_)

  if (identical(s, "former")) return(if (n == 2L) 1L else NA_integer_)
  if (identical(s, "latter")) return(if (n == 2L) 2L else NA_integer_)

  idx <- .ASSISTANT_ORDINAL_WORDS[[s]]
  if (is.null(idx)) return(NA_integer_)
  if (idx > n) return(NA_integer_)
  as.integer(idx)
}

# ---------------------------------------------------------------------------
# Bounded option matching (spec 11/12)
# ---------------------------------------------------------------------------

#' Match a reply against the CURRENT pending options and nothing else.
#'
#' Resolution order, strongest evidence first:
#'   1. an ordinal/positional reference ("2", "second", "the latter");
#'   2. the option's full label, normalised (case/punctuation tolerant);
#'   3. a token subset that fits exactly ONE option ("upland" against
#'      "Growing of rice in upland"; "with special needs" against
#'      "...with special needs", which "...without special needs" does not
#'      contain because `without` is a different token).
#'
#' A subset that fits more than one option is NOT a match: "special needs"
#' fits both teacher options and must be asked about again rather than
#' resolved arbitrarily.
#'
#' No fuzzy, n-gram, semantic or global retrieval is used or reachable from
#' here (spec 10/30).
#'
#' @param reply character(1).
#' @param options list of `list(code, label)` -- the pending options.
#'
#' @return list(matched = logical(1), index = integer(1) or NA,
#'   option = the matched option or NULL, kind = character(1)).
assistant_match_pending_option <- function(reply, options) {
  none <- list(matched = FALSE, index = NA_integer_, option = NULL,
               kind = NA_character_)
  if (is.null(options) || length(options) == 0L) return(none)

  idx <- assistant_option_reference_index(reply, length(options))
  if (!is.na(idx)) {
    return(list(matched = TRUE, index = idx, option = options[[idx]],
                kind = "reference"))
  }

  norm_reply <- .assistant_clar_norm(reply)
  if (!nzchar(norm_reply)) return(none)

  labels <- vapply(options, function(o) .assistant_clar_norm(o$label), character(1))

  exact <- which(labels == norm_reply)
  if (length(exact) == 1L) {
    return(list(matched = TRUE, index = as.integer(exact[[1L]]),
                option = options[[exact[[1L]]]], kind = "exact_label"))
  }

  reply_tokens <- .assistant_clar_tokens(reply)
  if (length(reply_tokens) == 0L) return(none)

  fits <- vapply(options, function(o) {
    all(reply_tokens %in% .assistant_clar_tokens(o$label))
  }, logical(1))
  if (sum(fits) == 1L) {
    hit <- which(fits)[[1L]]
    return(list(matched = TRUE, index = as.integer(hit), option = options[[hit]],
                kind = "label_subset"))
  }

  none
}

# ---------------------------------------------------------------------------
# Short ambiguous replies (spec 13)
# ---------------------------------------------------------------------------

# Single words that name a SETTING, SECTOR or QUALIFIER rather than an
# activity. Each of these retrieves a confident-looking detailed code that
# has nothing to do with the establishment the user is describing
# ("residential" -> 87100 Residential nursing care activities for a
# carpenter). Multi-word replies are NOT affected: "residential
# construction" says what the establishment does and still resolves.
ASSISTANT_AMBIGUOUS_SHORT_REPLIES <- c(
  "residential", "non-residential", "nonresidential",
  "private", "public", "government", "commercial", "industrial",
  "hospital", "clinic", "school", "farm", "office", "shop", "store",
  "business", "company", "establishment", "enterprise",
  "trading", "contractor", "services", "service", "online", "general"
)

# Filler that may accompany the ambiguous word without adding meaning.
.ASSISTANT_AMBIGUOUS_FILLER <- c(
  "a", "an", "the", "it", "is", "its", "it's", "po", "lang", "yung", "ang",
  "sa", "na", "ko", "siya", "ito", "kay", "sang", "ug", "og"
)

# Slots whose reply is free-text activity wording, and which are therefore
# the ones a bare qualifier can hijack.
.ASSISTANT_ACTIVITY_SLOTS <- c("establishment_activity", "establishment_activity_detail")

#' Is this reply a bare qualifier that cannot identify an activity?
#'
#' TRUE only when EVERY content token is filler except a single term from
#' `ASSISTANT_AMBIGUOUS_SHORT_REPLIES`. Deliberately strict: the moment the
#' user adds a real activity word the reply is treated normally.
assistant_reply_too_ambiguous <- function(reply) {
  tokens <- .assistant_clar_tokens(reply)
  tokens <- tokens[!(tokens %in% .ASSISTANT_AMBIGUOUS_FILLER)]
  if (length(tokens) != 1L) return(FALSE)
  norm_terms <- vapply(ASSISTANT_AMBIGUOUS_SHORT_REPLIES, .assistant_clar_norm,
                       character(1), USE.NAMES = FALSE)
  tokens[[1L]] %in% norm_terms
}

#' A narrower deterministic question for a bare qualifier (spec 13).
#'
#' Built only from the user's own word and the occupation already on file.
#' Names no code and offers no classification the application has not
#' verified -- it asks what the establishment DOES.
assistant_narrow_activity_question <- function(reply, occupation = NULL) {
  term <- .assistant_clar_tokens(reply)
  term <- term[!(term %in% .ASSISTANT_AMBIGUOUS_FILLER)]
  word <- if (length(term) >= 1L) term[[1L]] else "that"
  occ <- .assistant_scalar_chr(occupation)
  who <- if (is.null(occ)) "the establishment" else sprintf("the establishment where the %s works", occ)
  sprintf(
    paste0(
      "\"%s\" on its own does not say what %s actually does. ",
      "What is its main activity - for example %s building construction, ",
      "%s care services, or some other %s activity?"
    ),
    word, who, word, word, word
  )
}

# ---------------------------------------------------------------------------
# Explicit new coding request (spec 14)
# ---------------------------------------------------------------------------

# Tokens that mean "classify this for me" explicitly, as opposed to any
# text that merely happens to arrive while a question is outstanding.
.ASSISTANT_EXPLICIT_CODING_SIGNAL <- paste0(
  "\\b(psoc|psic|psgc|psced|pcoicop|pcpc|pscc|psccs|ptscs|pscrcs)\\b",
  "|\\b(code|codes|classification|classify|coding)\\b"
)

#' Does this turn explicitly start a NEW coding request?
#'
#' Two conditions, both required:
#'   1. an explicit coding signal is present ("psoc", "psic", "code",
#'      "classification", ...);
#'   2. once those signal tokens and the ordinary request scaffolding are
#'      stripped, a SUBSTANTIVE subject remains.
#'
#' Condition 2 is what separates "statistician at PSA psoc psic" (subject
#' "statistician at psa" -> a new request) from a bare "psic" or "what is
#' the code" (nothing left -> still an answer to the outstanding question).
#'
#' Bounded option labels are official PSA titles and never contain these
#' signal tokens, so a valid clarification reply cannot trip this.
assistant_explicit_new_coding_request <- function(text) {
  q <- .assistant_scalar_chr(text)
  if (is.null(q)) return(FALSE)
  q <- tolower(q)
  if (!grepl(.ASSISTANT_EXPLICIT_CODING_SIGNAL, q, perl = TRUE)) return(FALSE)
  residual <- .assistant_clar_tokens(.assistant_slot_strip_noise(q))
  subject <- residual[!(residual %in% .ASSISTANT_REQUEST_SCAFFOLDING)]
  length(subject) >= 1L
}

# Words that only ASK; they carry no subject. "please give me the code"
# leaves nothing but these behind and is therefore still an answer to the
# outstanding question, not a new request.
.ASSISTANT_REQUEST_SCAFFOLDING <- c(
  "a", "an", "the", "this", "that", "it", "is", "are", "was", "of", "for",
  "to", "and", "or", "in", "on", "with", "my", "me", "i", "im", "you",
  "your", "us", "we", "what", "which", "who", "how", "do", "does", "did",
  "can", "could", "would", "should", "please", "kindly", "give", "tell",
  "show", "find", "get", "want", "need", "know", "help", "about", "s",
  "po", "ba", "ang", "ng", "ko", "ako", "ano", "sa", "na", "yung", "unsa",
  "ug", "og", "ni", "nga", "ako'y"
)

# ---------------------------------------------------------------------------
# Explanation requests (spec 21)
# ---------------------------------------------------------------------------

# The model may speak only when the user asks it to. These are the asks.
# Deliberately anchored and short: an explanation request is a SHORT meta
# question about the answer just given, never a new description of work.
.ASSISTANT_EXPLANATION_PATTERNS <- paste(
  "^why\\b", "\\bwhy\\?$",
  "^(please\\s+)?explain\\b", "\\bexplain (this|that|it)\\b",
  "^what does (this|that|it) mean\\b",
  "^what(\\s+is|'s) the difference\\b",
  "^how come\\b",
  "^(pakipaliwanag|paki-paliwanag|paliwanag)\\b",
  "^bakit\\b", "^ngano\\b",
  sep = "|"
)

#' Is the user asking RM to explain the answer it already gave?
#'
#' Bounded to short turns on purpose. "Why is a mayor 1111?" is an
#' explanation request; a fresh paragraph describing a business is not,
#' even if the word "explain" appears inside it.
assistant_explanation_requested <- function(text) {
  q <- .assistant_clar_norm(text)
  if (!nzchar(q)) return(FALSE)
  if (length(.assistant_clar_tokens(q)) > 12L) return(FALSE)
  grepl(.ASSISTANT_EXPLANATION_PATTERNS, q, perl = TRUE)
}

# ---------------------------------------------------------------------------
# Canonical verification of a selected option
# ---------------------------------------------------------------------------

#' Re-verify one option code against the canonical repository.
#'
#' The option's code was produced by deterministic retrieval when the
#' question was raised, but it is re-read here rather than trusted: the
#' label, level, coding role, edition and status all come from the
#' repository at selection time, and an archived or unknown code returns
#' NULL so the caller falls back to asking again (spec: current edition
#' only, and no code without retrieval).
#'
#' @return the `industry`/`occupation` half of a packet, or NULL.
assistant_verified_option_half <- function(system, code) {
  sys <- .assistant_scalar_chr(system)
  cd <- .assistant_scalar_chr(code)
  if (is.null(sys) || is.null(cd)) return(NULL)

  lv <- tryCatch(assistant_coding_level(sys, NULL, cd), error = function(e) NULL)
  if (is.null(lv) || !isTRUE(lv$found)) return(NULL)

  row <- tryCatch(get_classification_entry(sys, lv$version, cd),
                  error = function(e) NULL)
  if (is.null(row) || nrow(row) == 0L) return(NULL)
  status_current <- as.character(row$status[[1L]])
  if (is.na(status_current) || !identical(tolower(status_current), "current")) {
    return(NULL)
  }

  list(
    status = "resolved",
    selected_code = as.character(lv$code),
    selected_label = as.character(lv$label),
    classification_level = as.character(lv$classification_level),
    level_display = as.character(lv$level_display),
    coding_role = as.character(lv$coding_role),
    version = as.character(lv$version),
    status_current = status_current,
    evidence_source = "clarification_option",
    supported_aggregate_code = NA_character_
  )
}

#' Complete a pending packet with the option the user selected.
#'
#' Every fact that is NOT the answered slot is carried over verbatim from
#' the packet that raised the question -- which is what preserves PSOC 2330
#' across a "latter" reply instead of re-deriving it from the word
#' "latter".
#'
#' @param packet the `clarification_required` packet that asked.
#' @param option list(code, label) chosen from that packet's own options.
#' @param system character(1), the system the question was about.
#'
#' @return a `resolved` packet, or NULL if the code cannot be verified.
assistant_packet_with_selected_option <- function(packet, option, system = "psic") {
  if (is.null(packet) || is.null(option)) return(NULL)
  half <- assistant_verified_option_half(system, option$code)
  if (is.null(half)) return(NULL)

  out <- packet
  if (identical(system, "psoc")) {
    out$occupation <- half
    out$allowed_codes$psoc <- half$selected_code
  } else {
    out$industry <- half
    out$allowed_codes$psic <- half$selected_code
  }
  out$clarification <- list(
    missing_slot = NA_character_,
    question = NA_character_,
    options = list()
  )
  out$status <- "resolved"
  out
}

#' Re-ask the SAME bounded question, unchanged.
#'
#' Used when a reply arrives that the bounded universe cannot interpret.
#' Returns the original packet so the rendered question, the options and
#' the stored pending state remain identical -- the application never
#' invents a second, differently-worded question for the same slot
#' (spec 23).
assistant_packet_reask <- function(packet) {
  packet
}

#' Replace an OPEN slot's question with a narrower one (spec 13).
#'
#' Keeps the same `missing_slot`, so the pending state and the reply
#' handling are unchanged; only the wording narrows. No code is added and
#' none is removed.
assistant_packet_narrow_question <- function(packet, question) {
  if (is.null(packet)) return(NULL)
  q <- .assistant_scalar_chr(question)
  if (is.null(q)) return(packet)
  packet$clarification$question <- q
  packet$clarification$options <- list()
  packet
}

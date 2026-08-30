# W3 -- multi-input (batch) request parsing.
#
# ROOT CAUSE THIS EXISTS TO REMOVE (reproduced against the live build, not
# inferred). A single user turn containing six independent coding requests,
# one per line:
#
#   grab taxi driver psoc
#   food panda bicycle driver psoc
#   vulcanizer psoc
#   online seller psoc
#   data scientist psoc
#   esports player psoc
#
# routed as ONE `contextual_coding` request. The router normalises
# whitespace (`gsub("\\s+", " ")`), so the newlines vanished before any
# routing decision was made and the whole paste became a single query
# string. The resolver then produced a single answer -- live, PSOC 3424
# ESPORTS PLAYERS AND COACHES, the LAST line -- and that answer became the
# session's `latest_packet`, contaminating the turns that followed.
#
# The split below happens on the RAW text, before normalisation, and is
# deliberately conservative: it is a false-negative-safe design. Failing to
# detect a batch degrades to exactly today's single-request behaviour;
# falsely detecting one would shred a legitimate sentence into nonsense. So
# every gate here is a reason NOT to split.
#
# NO RECURSION HAZARD: batch detection only runs when the raw text contains
# a line break, and every candidate line has had its line breaks removed by
# the split. `assistant_route_request()` called on a candidate line can
# therefore never re-enter batch detection.

# Bounded so a pasted 500-line spreadsheet column cannot fan out into 500
# resolver calls. Overflow is REPORTED, never silently dropped.
ASSISTANT_BATCH_MAX_ITEMS <- 12L

# Leading list markers a user may paste: "- ", "* ", "1. ", "2) ", bullets.
# Requires trailing whitespace, so a bare code line ("8325") is untouched.
.ASSISTANT_BATCH_MARKER <- "^\\s*(?:[-*•–—]|[0-9]{1,2}\\s*[.)])\\s+"

# A line that OPENS with one of these is a continuation of the line above,
# i.e. hard-wrapped prose, not an independent request.
.ASSISTANT_BATCH_CONTINUATION <- paste0(
  "^(and|or|but|so|then|because|since|which|that|while|whereas|although|",
  "however|therefore|also|plus|pero|tapos|kasi|ug|ang)\\b"
)

# A line that ENDS with one of these is unfinished -- the request continues
# on the next line, so the two lines are one request, not two.
.ASSISTANT_BATCH_DANGLING <- paste0(
  "[,;:]$|",
  "\\b(and|or|but|so|then|because|of|the|a|an|to|in|on|at|for|with|from|",
  "by|as|is|are|was|were|na|ng|sa|ni|si)$"
)

# Longest a single batch line may be. Real coding requests in this corpus
# run 2-11 words ("what is the psic of a janitor deployed through manpower
# agency" is 11); ordinary prose sentences run longer.
.ASSISTANT_BATCH_MAX_WORDS <- 12L

#' Raw, marker-stripped, non-empty lines of a user turn.
#'
#' Returns `character(0)` for anything that is not multi-line, which is the
#' short-circuit that keeps single-request routing byte-identical.
.assistant_batch_raw_lines <- function(text) {
  raw <- .assistant_scalar_chr(text)
  if (is.null(raw)) return(character(0))
  if (!grepl("[\r\n]", raw)) return(character(0))
  parts <- strsplit(raw, "\r\n|\r|\n")[[1L]]
  parts <- sub(.ASSISTANT_BATCH_MARKER, "", parts, perl = TRUE)
  parts <- trimws(gsub("[[:space:]]+", " ", parts))
  parts[nzchar(parts)]
}

#' Does ONE line independently look like a coding request?
#'
#' Every gate is a veto. The decisive one is the EXPLICIT SIGNAL gate: the
#' line must name a classification system or use coding wording on its own.
#' `assistant_route_request()` sends any text of three or more characters to
#' `contextual_coding` as a catch-all, so without this gate the hard-wrapped
#' pair "teacher in a private" / "high school psoc psic" would both qualify
#' and one request would be split into two. Requiring the signal on EVERY
#' line means the fragment "teacher in a private" vetoes the whole split.
.assistant_batch_line_is_request <- function(line) {
  q <- .assistant_router_norm(line)
  if (!nzchar(q) || nchar(q) < 3L) return(FALSE)
  if (!grepl("[a-z]", q)) return(FALSE)

  words <- strsplit(q, " ", fixed = TRUE)[[1L]]
  words <- words[nzchar(words)]
  if (length(words) == 0L || length(words) > .ASSISTANT_BATCH_MAX_WORDS) return(FALSE)

  if (grepl(.ASSISTANT_BATCH_CONTINUATION, q)) return(FALSE)
  if (grepl(.ASSISTANT_BATCH_DANGLING, q)) return(FALSE)

  # EXPLICIT SIGNAL -- named system or coding wording, not the catch-all.
  signalled <- length(assistant_router_requested_systems(q)) > 0L ||
    grepl(.ASSISTANT_CODING_VERBS, q)
  if (!signalled) return(FALSE)

  # And it must still be a CODING request when routed on its own: a bare
  # code lookup, a system question or an edition question is not a batch
  # member, because a batch is a batch of coding requests.
  identical(assistant_route_request(q)$route, "contextual_coding")
}

#' Split a turn into independent coding-request lines.
#'
#' @return character vector of two or more lines, or `character(0)` when the
#'   turn is not a batch. ALL lines must qualify; one non-qualifying line
#'   vetoes the split, so a batch with a trailing prose remark stays whole.
assistant_batch_split <- function(text) {
  lines <- .assistant_batch_raw_lines(text)
  if (length(lines) < 2L) return(character(0))
  ok <- vapply(lines, .assistant_batch_line_is_request, logical(1), USE.NAMES = FALSE)
  if (!all(ok)) return(character(0))
  lines
}

#' Strip the classification-system tokens out of a line.
#'
#' "grab taxi driver psoc" is what the user typed and what gets rendered
#' back; "grab taxi driver" is what the resolver should receive as the
#' occupation. Falls back to the original line if stripping empties it.
.assistant_batch_query <- function(line) {
  q <- .assistant_router_norm(line)
  ids <- tryCatch(.assistant_router_system_ids(), error = function(e) character(0))
  for (id in ids) {
    q <- gsub(paste0("\\b", id, "\\b"), " ", q)
  }
  q <- gsub("\\b(code|codes|classification)\\b", " ", q)
  q <- trimws(gsub("[[:space:]]+", " ", q))
  q <- trimws(gsub("[[:punct:]]+$", "", q))
  if (nzchar(q)) q else .assistant_router_norm(line)
}

.assistant_batch_label <- function(query) {
  if (!nzchar(query)) return(query)
  paste0(toupper(substr(query, 1L, 1L)), substr(query, 2L, nchar(query)))
}

#' Parse a user turn into a deterministic batch representation (spec 26).
#'
#' @return list:
#'   `is_batch`   logical(1)
#'   `items`      list of per-item lists, each
#'                `list(index, text, query, label, requested_systems,
#'                      code_tokens, route)`
#'   `truncated`  logical(1) -- more lines qualified than the cap allows
#'   `dropped`    character vector of the lines beyond the cap
#'
#' Each item is self-contained: nothing in item `i` is derived from item
#' `j`, so slot extraction, retrieval, the coding-service call and the
#' resulting `allowed_codes` are independent per item.
assistant_batch_parse <- function(text) {
  out <- list(is_batch = FALSE, items = list(), truncated = FALSE,
              dropped = character(0))
  lines <- assistant_batch_split(text)
  if (length(lines) < 2L) return(out)

  n_keep <- min(length(lines), ASSISTANT_BATCH_MAX_ITEMS)
  keep <- lines[seq_len(n_keep)]
  out$truncated <- length(lines) > n_keep
  out$dropped <- if (out$truncated) lines[-seq_len(n_keep)] else character(0)

  out$is_batch <- TRUE
  out$items <- lapply(seq_along(keep), function(i) {
    ln <- keep[[i]]
    routed <- assistant_route_request(ln)
    query <- .assistant_batch_query(ln)
    list(
      index = i,
      text = ln,
      query = query,
      label = .assistant_batch_label(query),
      requested_systems = routed$requested_systems,
      code_tokens = routed$code_tokens,
      route = "contextual_coding"
    )
  })
  out
}

#' The argument list for ONE item's independent coding-service call.
#'
#' Built only from that item, never from the turn, the session or a sibling
#' item -- this is the concrete guarantee behind "item 1 state != item 2
#' state" (spec 27).
assistant_batch_item_args <- function(item) {
  if (is.null(item) || !is.list(item)) return(NULL)
  sys <- intersect(tolower(as.character(item$requested_systems)), c("psoc", "psic"))
  if (length(sys) == 0L) sys <- c("psoc", "psic")
  list(
    occupation = item$query,
    establishment_activity = NULL,
    requested_systems = sys,
    wage_payer = NULL
  )
}

#' Union the per-item packets into one guard-compatible packet.
#'
#' The output guard validates a turn's assembled prose against ONE packet's
#' `allowed_codes`. A batch legitimately authorises every code its items
#' retrieved, so the union is the correct authorisation set -- and it is
#' still a closed set of RETRIEVED codes, so the no-code-without-retrieval
#' rule is untouched. `occupation`/`industry` are deliberately NULL: there
#' is no single answer to render from a batch.
assistant_batch_merge_packets <- function(packets) {
  psoc <- character(0)
  psic <- character(0)
  for (p in packets) {
    if (is.null(p) || is.null(p$allowed_codes)) next
    psoc <- c(psoc, as.character(p$allowed_codes$psoc))
    psic <- c(psic, as.character(p$allowed_codes$psic))
  }
  list(
    status = "batch",
    occupation = NULL,
    industry = NULL,
    allowed_codes = list(
      psoc = unique(psoc[!is.na(psoc) & nzchar(psoc)]),
      psic = unique(psic[!is.na(psic) & nzchar(psic)])
    )
  )
}

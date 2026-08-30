# W1-A -- deterministic, server-side intent router.
#
# ROOT CAUSE THIS EXISTS TO REMOVE (traced against the live build, not
# inferred). Eight tools were registered globally and the MODEL chose among
# them, so one coding request had several independent authoritative routes.
# Each observed live failure maps to a different route being taken:
#
#   * assistant_search_classification("psoc", "mayor") returns
#     total_matches = 0 -- raw retrieval has none of the controlled
#     expansions, example evidence or survey guidance that the contextual
#     resolver applies. A session where the model picked raw search
#     therefore reported "no PSOC" for mayor.
#   * assistant_get_classification_entry("psoc", "1112") returns a valid
#     entry. A session where the model GUESSED 1112 and then "verified" it
#     got confirmation, which is why 1112 looked authoritative.
#   * assistant_search_common_pairings("Carpenter") returns
#     psic_rev5_code = 41001 with has_fixed_psic = TRUE, which is how an
#     archived-looking construction PSIC reached prose for carpenter.
#   * every search tool exposes `version` in its schema, so the model could
#     request version = "2019" and receive status = "archived" rows.
#
# There was no router, no coding service, no clarification state and no
# output guard (all four files absent; app.R passed the full tool list and
# contained no route logic).
#
# The router below runs BEFORE any authoritative tool is reachable and is
# pure R -- no model call -- so the same text always produces the same
# route. The router never picks a CODE; it picks which deterministic
# service is allowed to pick one.

ASSISTANT_ROUTES <- c(
  "exact_code_lookup",
  "contextual_coding",
  "batch_contextual_coding",
  "system_information",
  "edition_comparison",
  "general_search",
  "non_classification"
)

# Routes that are coding requests. `batch_contextual_coding` is a coding
# route in every respect -- it is contextual_coding applied N times -- and
# MUST be treated as at least as restrictive as contextual_coding wherever
# a route is checked. See `assistant_turn_set_route()`, which canonicalises
# it so the existing tool-body interlock, the render suppression and the
# validate-then-append output guard all stay engaged for a batch turn.
ASSISTANT_CODING_ROUTES <- c("contextual_coding", "batch_contextual_coding")

#' Is this route a coding route (single or batch)?
assistant_route_is_coding <- function(route) {
  r <- .assistant_scalar_chr(route)
  !is.null(r) && r %in% ASSISTANT_CODING_ROUTES
}

# System tokens the user might name, mapped to registry ids. Derived from
# the registry at call time so a newly registered system routes correctly
# without editing this file.
.assistant_router_system_ids <- function() {
  tryCatch(classification_registry()$id, error = function(e) character(0))
}

# A token that looks like a classification code in ANY supported system:
# 1-5+ digits (PSOC/PSIC), dotted/hyphenated PSCC, 10-digit PSGC, or a
# single section letter. Deliberately shape-based, never a code list.
.ASSISTANT_CODE_SHAPE <- "^[0-9]{1,10}(\\.[0-9]{2}\\.[0-9]{2}-[0-9]{3})?$"

.assistant_router_norm <- function(x) {
  x <- tolower(as.character(x))
  trimws(gsub("\\s+", " ", x))
}

#' Which classification systems did the user name?
#'
#' @return character vector of registry ids, possibly empty.
assistant_router_requested_systems <- function(text) {
  q <- .assistant_router_norm(text)
  if (!nzchar(q)) return(character(0))
  ids <- .assistant_router_system_ids()
  hit <- vapply(ids, function(id) grepl(paste0("\\b", id, "\\b"), q), logical(1))
  ids[hit]
}

# Wording that means "classify this for me" rather than "tell me about".
.ASSISTANT_CODING_VERBS <- paste(
  "\\bcode\\b", "\\bcoding\\b", "\\bclassif", "\\bwhat is the (psoc|psic)",
  "\\bwhich (psoc|psic)", "\\bgive me the", "\\bhow (do|would) (i|you) code",
  sep = "|"
)

# Wording that means "explain the system itself".
# "What is PSCCS?" asks about the SYSTEM. "What is the PSIC of a janitor?"
# asks for a CODE and merely names the system in passing -- the negative
# lookahead on a following "of" is what separates them. Without it the
# janitor query routed to system_information and never reached the
# outsourcing precondition.
.ASSISTANT_SYSTEM_INFO_PATTERNS <- paste(
  "\\bwhat (is|are) (the )?(psgc|psic|psoc|psced|pcoicop|pcpc|psccs|pscc|ptscs|pscrcs)\\b(?!\\s+(of|for|code)\\b)",
  "\\bdifference between\\b",
  "\\bcomponents? of (the )?(psgc|psic|psoc|psced|pcoicop|pcpc|psccs|pscc|ptscs|pscrcs)\\b",
  "\\bwhat does .* stand for\\b",
  "\\bwhich (classification )?system\\b",
  sep = "|"
)

.ASSISTANT_EDITION_PATTERNS <- paste(
  "\\bcompare\\b.*\\bedition", "\\bcorrespondence\\b",
  "\\b2019\\b.*\\b2026\\b", "\\b2026\\b.*\\b2019\\b",
  "\\bmaps? to\\b.*\\brevision\\b", "\\bwhat (replaced|became of)\\b",
  sep = "|"
)

.ASSISTANT_NON_CLASSIFICATION <- paste(
  "^(hi|hello|hey|kumusta|kamusta|good (morning|afternoon|evening))\\b",
  "^(thanks|thank you|salamat)\\b",
  "^(who are you|what can you do|help)\\b",
  sep = "|"
)

#' Route one user message deterministically.
#'
#' @param text character(1) the user's message.
#' @param pending list or NULL -- an outstanding clarification from
#'   `assistant_turn_state`. When present, a short reply is treated as an
#'   answer to that question rather than as a fresh request.
#'
#' @return list(route, requested_systems, code_tokens, is_clarification_reply,
#'   text). Never errors.
#'
#'   On the batch route the result additionally carries `items` (see
#'   `assistant_batch_parse()`), `batch_truncated` and `batch_dropped`.
#'   Those fields are ABSENT -- not NULL-valued -- for every other route, so
#'   single-request results are unchanged field-for-field.
assistant_route_request <- function(text, pending = NULL) {
  raw <- .assistant_scalar_chr(text)
  out <- list(
    route = "non_classification",
    requested_systems = character(0),
    code_tokens = character(0),
    is_clarification_reply = FALSE,
    text = if (is.null(raw)) NA_character_ else raw
  )
  if (is.null(raw)) return(out)

  q <- .assistant_router_norm(raw)
  systems <- assistant_router_requested_systems(q)
  out$requested_systems <- systems

  tokens <- strsplit(q, "[^0-9a-z.\\-]+")[[1L]]
  tokens <- tokens[nzchar(tokens)]
  code_tokens <- tokens[grepl(.ASSISTANT_CODE_SHAPE, tokens)]
  out$code_tokens <- code_tokens

  # A pending clarification wins over re-routing: "residential construction"
  # is an ANSWER, not a new search. Guarded so an explicit new code lookup
  # or system question can still supersede it (spec 13).
  if (!is.null(pending) && isTRUE(pending$active)) {
    supersedes <- (length(code_tokens) > 0L && length(systems) > 0L) ||
      grepl(.ASSISTANT_SYSTEM_INFO_PATTERNS, q, perl = TRUE)
    if (!supersedes) {
      out$route <- "contextual_coding"
      out$is_clarification_reply <- TRUE
      return(out)
    }
  }

  # MULTI-INPUT (W3, spec 25/26). Checked AFTER the pending-clarification
  # guard above, so a clarification reply can never be read as a batch even
  # if the user answers on several lines -- the guard has already returned.
  # Checked BEFORE every single-request branch, because those branches
  # operate on `q`, in which the line breaks have already been collapsed to
  # spaces; that collapse is what made six requests look like one.
  #
  # `assistant_batch_parse()` short-circuits on any turn without a line
  # break, so nothing below this point changes for a one-line request.
  batch <- assistant_batch_parse(raw)
  if (isTRUE(batch$is_batch)) {
    out$route <- "batch_contextual_coding"
    out$items <- batch$items
    out$batch_truncated <- batch$truncated
    out$batch_dropped <- batch$dropped
    # The turn-level requested systems are the union of the items', so the
    # session's system authorisation (H3) is wide enough for every item and
    # no wider.
    out$requested_systems <- unique(unlist(
      lapply(batch$items, function(it) it$requested_systems)
    ))
    if (is.null(out$requested_systems)) out$requested_systems <- character(0)
    return(out)
  }

  if (grepl(.ASSISTANT_NON_CLASSIFICATION, q)) {
    out$route <- "non_classification"
    return(out)
  }
  if (grepl(.ASSISTANT_EDITION_PATTERNS, q)) {
    out$route <- "edition_comparison"
    return(out)
  }
  # An explicit code + a named system is a lookup, never a coding request:
  # "PSOC 833" must return 833, not descend to a Unit Group (spec 22).
  if (length(code_tokens) > 0L && length(systems) > 0L) {
    out$route <- "exact_code_lookup"
    return(out)
  }
  if (grepl(.ASSISTANT_SYSTEM_INFO_PATTERNS, q, perl = TRUE)) {
    out$route <- "system_information"
    return(out)
  }
  # Naming psoc/psic without a code, or using coding wording, is a coding
  # request. So is any occupation/establishment description that reaches
  # here -- coding is the safe default for classification-shaped text,
  # because it is the only route that enforces the deterministic rules.
  if (length(systems) > 0L || grepl(.ASSISTANT_CODING_VERBS, q)) {
    out$route <- "contextual_coding"
    return(out)
  }
  if (nchar(q) >= 3L) {
    out$route <- "contextual_coding"
    return(out)
  }
  out
}

# --- route-specific model-facing tool surface (W1-E) -----------------------
#
# The model gets DIFFERENT tools depending on the route. On the coding
# route the low-level authoritative alternatives are simply absent, so the
# bypass that produced the live failures cannot be expressed.
ASSISTANT_ROUTE_TOOLS <- list(
  contextual_coding = c(
    "assistant_code_occupation_and_activity",
    "assistant_get_psic_rule",
    "assistant_coding_level"
  ),
  # A batch is N coding requests, so it gets EXACTLY the coding surface --
  # never a wider one. Defined explicitly rather than by reference so a
  # future widening of one cannot silently widen the other, and so
  # app.R's `assistant_tools_for_route(routed$route, ...)` resolves the
  # batch route to a real tool set instead of failing closed to none.
  batch_contextual_coding = c(
    "assistant_code_occupation_and_activity",
    "assistant_get_psic_rule",
    "assistant_coding_level"
  ),
  exact_code_lookup = c(
    "assistant_get_classification_entry",
    "assistant_coding_level",
    "assistant_classification_registry"
  ),
  system_information = c(
    "assistant_get_classification_system_info",
    "assistant_classification_registry"
  ),
  edition_comparison = c(
    "assistant_get_classification_system_info",
    "assistant_get_classification_entry",
    "assistant_classification_registry"
  ),
  general_search = c(
    "assistant_search_classification",
    "assistant_get_classification_entry",
    "assistant_coding_level"
  ),
  non_classification = c(
    "assistant_classification_registry",
    "assistant_get_classification_system_info"
  )
)

#' Tool names permitted on a route.
assistant_route_tool_names <- function(route) {
  hit <- ASSISTANT_ROUTE_TOOLS[[route]]
  if (is.null(hit)) character(0) else hit
}

#' The ellmer tool objects permitted on a route.
#'
#' `assistant_search_classification` and `assistant_search_common_pairings`
#' are deliberately absent from `contextual_coding`: they remain available
#' to the coding SERVICE internally, but never as a model-selectable
#' authoritative route for a coding request (spec 21).
assistant_tools_for_route <- function(route, all_tools = NULL) {
  allowed <- assistant_route_tool_names(route)
  if (is.null(all_tools)) all_tools <- rm_assistant_tools()
  nms <- vapply(all_tools, function(t) t@name, character(1))
  all_tools[nms %in% allowed]
}

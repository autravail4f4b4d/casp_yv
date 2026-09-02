# W1-C -- session-scoped clarification state.
#
# WHY: the live build had none, so a clarification reply was a brand-new
# unrelated query. Asking "what is the main activity of the establishment
# where the carpenter works?" and receiving "residential construction"
# produced a fresh search for the phrase "residential construction" with
# the carpenter -- and the already-resolved PSOC 7115 -- forgotten.
#
# ISOLATION: state lives in an environment created PER CALL to
# `assistant_new_turn_state()`, and app.R creates exactly one inside each
# Shiny `server` invocation. Nothing is stored at file scope, so two
# browser sessions cannot observe each other's pending question. This
# mirrors how the ellmer chat client is already created per session.

#' Create an empty per-session clarification store.
#'
#' @return an environment. Callers must keep it inside their own session
#'   scope; never assign one at package/file level.
#'
#' `current_route` defaults to `"contextual_coding"` -- the MOST
#' RESTRICTIVE route -- deliberately (H1). A session whose route has never
#' been successfully determined (e.g. the very first tool call before any
#' routing observer has run, or a routing failure) must default to
#' blocking the low-level authoritative tools, never to allowing them.
#' "Unset" and "unrestricted" must never be the same state.
assistant_new_turn_state <- function() {
  st <- new.env(parent = emptyenv())
  st$pending <- NULL
  st$current_route <- "contextual_coding"
  st$declared_route <- "contextual_coding"
  st$current_requested_systems <- c("psoc", "psic")
  st$latest_packet <- NULL
  st$batch <- NULL
  st$last_batch <- NULL
  # Records the user attached in the UI, as IDENTIFIER-ONLY descriptors,
  # newest last. Never a classification decision and never a snapshot of
  # one: see R/assistant/assistant_attached_context.R.
  st$attached_context <- list()
  st
}


# --- attached context (UI selection bridge) --------------------------------
#
# Per session, like everything else in this environment: one visitor's
# attached record can never be visible to another's turn.

#' Replace the session's attached-context descriptors.
#'
#' @param descriptors a list of descriptors from
#'   `assistant_context_descriptor_entry()` /
#'   `assistant_context_descriptor_correspondence()`, newest LAST. An empty
#'   list clears the context, which is what removing the last chip does.
assistant_turn_set_attached_context <- function(state, descriptors) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  if (is.null(descriptors)) descriptors <- list()
  if (!is.list(descriptors)) descriptors <- list(descriptors)
  # Keep only well-formed descriptors, so a malformed one can never reach
  # the verification step and can never be counted as "context exists".
  keep <- Filter(function(d) {
    is.list(d) && !is.null(d$kind) && d$kind %in% ASSISTANT_CONTEXT_KINDS
  }, descriptors)
  state$attached_context <- keep
  invisible(NULL)
}

#' The session's attached-context descriptors, newest last.
assistant_turn_attached_context <- function(state) {
  if (is.null(state) || !is.environment(state)) return(list())
  d <- state$attached_context
  if (is.null(d)) list() else d
}

#' Drop every attached descriptor.
#'
#' Called by New chat. NOT called by closing the panel: closing hides a
#' panel, it does not discard what the user attached.
assistant_turn_clear_attached_context <- function(state) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  state$attached_context <- list()
  invisible(NULL)
}

#' Record the route determined for the CURRENT turn (H1).
#'
#' Read by the tool-body interlock (assistant_tools.R) and by the
#' content-rendering override (assistant_render.R) -- both close over this
#' SAME environment, so the write here is visible to both without any
#' dependency on Shiny scheduling order.
#'
#' BATCH CANONICALISATION (W3). `batch_contextual_coding` is stored as
#' `contextual_coding` in `current_route`, the field every enforcement site
#' reads. Three independent checks elsewhere are written as
#' `identical(route, "contextual_coding")` and live in files this
#' workstream does not own -- the tool-body interlock
#' (`.assistant_route_interlocked()`), the live-render suppression
#' (assistant_render.R) and the validate-then-append output guard (app.R).
#' Introducing a NEW route string would have silently disengaged all three
#' for exactly the turns that need them most: a batch of coding requests.
#' Canonicalising here means a batch turn is, to every one of those checks,
#' indistinguishable from a coding turn -- fail-closed by construction and
#' with no edit to their files. The declared route is retained separately
#' for callers that legitimately need to know a turn was a batch; it is
#' never consulted to GRANT anything.
assistant_turn_set_route <- function(state, route) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  r <- .assistant_scalar_chr(route)
  # An unrecognised or missing route is treated as the restrictive default,
  # never as "no restriction".
  declared <- if (is.null(r) || !(r %in% ASSISTANT_ROUTES)) {
    "contextual_coding"
  } else {
    r
  }
  state$declared_route <- declared
  state$current_route <- if (assistant_route_is_coding(declared)) {
    "contextual_coding"
  } else {
    declared
  }
  # A new turn starts a new authorisation window for the batch packet
  # accumulator below. `set_route()` is called once per turn, synchronously,
  # before any provider round-trip, so this is the correct reset point.
  state$batch_allowed <- NULL
  # ... and for the deterministic render carrier (see
  # `assistant_turn_set_render()`), for exactly the same reason: one turn's
  # authoritative answer must never be emitted into the next turn's stream.
  state$pending_render <- NULL
  state$render_emitted <- FALSE
  invisible(state$current_route)
}

# --- deterministic render carrier (W3/W4) ----------------------------------
#
# THE DEFECT THIS REMOVES. On a coding turn the model's own text is
# suppressed chunk by chunk (assistant_render.R), and the authoritative
# answer used to be appended as a SEPARATE message once the stream
# finished. shinychat still opens a streaming assistant message for every
# turn and its `chunk_end` reducer commits that message to the transcript
# whether or not anything was ever written into it -- so every coding turn
# deposited an extra, contentless assistant bubble, rendered with
# shinychat's raw `<svg>` placeholder icon, immediately before the real
# answer. Two bubbles per turn, one of them empty.
#
# THE FIX. The deterministic render is handed to the FIRST content chunk of
# the turn, so the streaming message carries the authoritative answer
# itself. One message per turn, containing exactly the text R produced.
# `assistant_turn_render_emitted()` tells app.R whether that happened; if
# the provider produced no chunk at all, app.R appends the same text
# instead, so the answer never depends on the model having spoken.

#' Hand this turn's authoritative rendering to the stream.
assistant_turn_set_render <- function(state, text) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  t <- .assistant_scalar_chr(text)
  state$pending_render <- if (is.null(t) || !nzchar(trimws(t))) NULL else t
  state$render_emitted <- FALSE
  invisible(state$pending_render)
}

#' Take the authoritative rendering exactly once. NULL afterwards.
assistant_turn_take_render <- function(state) {
  if (is.null(state) || !is.environment(state)) return(NULL)
  t <- state$pending_render
  if (is.null(t)) return(NULL)
  state$pending_render <- NULL
  state$render_emitted <- TRUE
  t
}

#' Was this turn's authoritative rendering already emitted into the stream?
assistant_turn_render_emitted <- function(state) {
  if (is.null(state) || !is.environment(state)) return(FALSE)
  isTRUE(state$render_emitted)
}

#' The route the router actually declared for this turn, which is the only
#' way to observe that a turn was a batch. Read-only signal for rendering
#' and orchestration -- never a capability grant.
assistant_turn_declared_route <- function(state) {
  if (is.null(state) || !is.environment(state)) return("contextual_coding")
  r <- state$declared_route
  if (is.null(r) || !(r %in% ASSISTANT_ROUTES)) "contextual_coding" else r
}

#' Was the current turn routed as a batch?
assistant_turn_is_batch <- function(state) {
  identical(assistant_turn_declared_route(state), "batch_contextual_coding")
}

#' The route for the current turn, or the restrictive default if unset.
assistant_turn_current_route <- function(state) {
  if (is.null(state) || !is.environment(state)) return("contextual_coding")
  r <- state$current_route
  if (is.null(r) || !(r %in% ASSISTANT_ROUTES)) "contextual_coding" else r
}

#' Record which systems the CURRENT turn is authorised to answer about
#' (H3), derived deterministically by the router -- never supplied by the
#' model.
assistant_turn_set_requested_systems <- function(state, systems) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  sys <- intersect(tolower(as.character(systems)), c("psoc", "psic"))
  state$current_requested_systems <- if (length(sys) == 0L) c("psoc", "psic") else sys
  invisible(state$current_requested_systems)
}

#' The systems authorised for the current turn, defaulting to both.
assistant_turn_requested_systems <- function(state) {
  if (is.null(state) || !is.environment(state)) return(c("psoc", "psic"))
  sys <- state$current_requested_systems
  if (is.null(sys) || length(sys) == 0L) c("psoc", "psic") else sys
}

#' Record the most recent coding-service packet for this session (H2) --
#' the output guard validates the model's generated prose against THIS
#' packet's `allowed_codes` once the turn's text is fully assembled.
#'
#' BATCH ACCUMULATION (W3). There is one `latest_packet` slot per session
#' and the coding tool overwrites it on every call. On a batch turn the
#' model calls that tool once per item, so the LAST item's packet would be
#' the only authorisation the output guard sees -- and the guard would then
#' strike out the five perfectly well-retrieved codes belonging to items 1-5
#' and replace the whole answer with the last item's. That is the same
#' overwrite defect the batch route exists to remove, one layer down.
#'
#' So on a batch turn -- and ONLY on a batch turn -- `allowed_codes` is
#' UNIONED across the turn's packets rather than replaced. The set still
#' contains nothing but codes the coding service actually retrieved during
#' this turn, so "no retrieved code = no code" is untouched; it is widened
#' to the turn's real answer set, not to anything unverified. The window is
#' one turn: `assistant_turn_set_route()` resets it. Every other route
#' replaces the packet exactly as before.
assistant_turn_set_latest_packet <- function(state, packet) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  if (is.null(packet)) {
    state$latest_packet <- NULL
    state$batch_allowed <- NULL
    return(invisible(NULL))
  }
  if (assistant_turn_is_batch(state)) {
    prev <- state$batch_allowed
    merged <- list(
      psoc = unique(c(as.character(prev$psoc), as.character(packet$allowed_codes$psoc))),
      psic = unique(c(as.character(prev$psic), as.character(packet$allowed_codes$psic)))
    )
    merged$psoc <- merged$psoc[!is.na(merged$psoc) & nzchar(merged$psoc)]
    merged$psic <- merged$psic[!is.na(merged$psic) & nzchar(merged$psic)]
    state$batch_allowed <- merged
    # The rest of the packet stays as the most recent item's, so a guard
    # rejection still has a real packet to re-render from.
    packet$allowed_codes <- merged
  }
  state$latest_packet <- packet
  invisible(NULL)
}

#' The most recent coding-service packet, or NULL.
assistant_turn_latest_packet <- function(state) {
  if (is.null(state) || !is.environment(state)) return(NULL)
  state$latest_packet
}

#' Is there an outstanding question in this session?
assistant_turn_pending <- function(state) {
  if (is.null(state) || !is.environment(state)) return(NULL)
  p <- state$pending
  if (is.null(p)) return(NULL)
  if (!isTRUE(p$active)) return(NULL)
  p
}

#' Record a coding request that is waiting on one missing slot.
#'
#' Stores the minimal deterministic context needed to rerun the same
#' request (spec 12): the slots already known, the systems asked for, and
#' which slot is missing. No prose, no candidate pool, no model output.
#'
#' STRUCTURED OPTIONS (spec 9). When the question offers choices, their
#' CANONICAL IDENTITY is stored, not just the display prose: `options`
#' keeps `list(index, code, label)` per choice and `system`/`parent_code`
#' record what the question is about. Storing only `question` -- the
#' previous behaviour -- is precisely why "latter" could not be resolved:
#' by the time the reply arrived, the two verified codes the application
#' had already chosen between (85312 / 85314) no longer existed anywhere in
#' the session, so the reply had nothing to be matched against and fell
#' through to global retrieval.
#'
#' `packet` itself is retained for the same reason: completing the pending
#' slot must PRESERVE every other verified fact (PSOC 2330) rather than
#' re-derive it from the reply text.
assistant_turn_set_pending <- function(state, packet, occupation = NULL,
                                       establishment_activity = NULL,
                                       requested_systems = c("psoc", "psic"),
                                       wage_payer = NULL) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  if (is.null(packet) || !identical(packet$status, "clarification_required")) {
    return(assistant_turn_clear(state))
  }
  state$pending <- list(
    active = TRUE,
    route = "contextual_coding",
    requested_systems = requested_systems,
    occupation = occupation,
    establishment_activity = establishment_activity,
    wage_payer = wage_payer,
    missing_slot = packet$clarification$missing_slot,
    question = packet$clarification$question,
    system = .assistant_pending_system(packet),
    parent_code = .assistant_pending_parent_code(packet),
    options = .assistant_pending_options(packet),
    packet = packet
  )
  invisible(state$pending)
}

# Which system the outstanding question is about. Only the industry half
# ever raises an option question today; the occupation half is handled for
# symmetry so a future PSOC subtype question needs no change here.
.assistant_pending_system <- function(packet) {
  slot <- packet$clarification$missing_slot
  if (!is.null(slot) && !is.na(slot) && identical(slot, "occupation")) "psoc" else "psic"
}

.assistant_pending_parent_code <- function(packet) {
  ind <- packet$industry
  if (is.null(ind)) return(NA_character_)
  agg <- ind$supported_aggregate_code
  if (is.null(agg) || is.na(agg)) NA_character_ else as.character(agg)
}

# Options as stored: 1-based index plus the canonical code and label the
# coding service verified when it raised the question.
.assistant_pending_options <- function(packet) {
  opts <- packet$clarification$options
  if (is.null(opts) || length(opts) == 0L) return(list())
  out <- vector("list", length(opts))
  for (i in seq_along(opts)) {
    out[[i]] <- list(
      index = i,
      code = as.character(opts[[i]]$code),
      label = as.character(opts[[i]]$label)
    )
  }
  out
}

#' Clear the pending question (resolved, superseded, or topic change).
#'
#' Also drops any batch accumulator and the previous batch's per-item
#' results: a new chat must not inherit one turn's multi-request context.
assistant_turn_clear <- function(state) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  state$pending <- NULL
  state$batch <- NULL
  state$last_batch <- NULL
  state$pending_render <- NULL
  state$render_emitted <- FALSE
  invisible(NULL)
}

# --- batch state isolation (W3, spec 27) -----------------------------------
#
# THE DEFECT THIS PREVENTS. With one `pending` slot per session and six
# requests in one turn, whichever item was processed last owned the
# session: item 6's clarification became item 1's context, and item 6's
# packet became the whole turn's `latest_packet`. Live, the six-line paste
# collapsed to a single answer (PSOC 3424) which then leaked into the
# following independent turns.
#
# THE INVARIANT. While a batch is in flight NOTHING is written to
# `state$pending`. Per-item outcomes accumulate in a separate list, keyed
# by the item's own index, and each entry holds only what that item's own
# resolution produced. There is therefore no shared mutable slot for one
# item to overwrite, which is what makes `item i state != item j state`
# structural rather than a matter of ordering.
#
# THE RESOLUTION RULE, applied once at the end and deterministic:
#   0 unresolved  -> session pending state is EMPTY
#   1 unresolved  -> that one item becomes the active pending clarification
#   2+ unresolved -> NO pending clarification is activated; the unresolved
#                    items are returned with per-item prompts instead
# Auto-activating one of several would silently pick a winner and route the
# user's next reply into it -- the same overwrite bug in a new costume.

#' Open a batch. Drops any leftover pending question so it cannot become
#' the first item's context.
assistant_turn_begin_batch <- function(state, n_items = NA_integer_) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  state$pending <- NULL
  state$batch <- list()
  state$batch_expected <- suppressWarnings(as.integer(n_items))
  invisible(state$batch)
}

.assistant_batch_unresolved <- function(entry) {
  p <- entry$packet
  !is.null(p) && identical(p$status, "clarification_required") &&
    !is.null(p$clarification)
}

#' Record ONE item's independent outcome.
#'
#' @param item a parsed item from `assistant_batch_parse()$items`.
#' @param packet that item's own `assistant_coding_service()` result.
#' @param occupation,establishment_activity,wage_payer the slots THIS item
#'   was resolved with -- the minimal rerun context, exactly as
#'   `assistant_turn_set_pending()` stores for a single request. Defaults
#'   come from the item itself, never from the session or a sibling item.
assistant_turn_record_batch_item <- function(state, item, packet,
                                             occupation = NULL,
                                             establishment_activity = NULL,
                                             wage_payer = NULL) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  if (is.null(state$batch)) state$batch <- list()
  if (is.null(item) || !is.list(item)) return(invisible(state$batch))

  idx <- suppressWarnings(as.integer(item$index))
  if (is.na(idx)) idx <- length(state$batch) + 1L
  sys <- intersect(tolower(as.character(item$requested_systems)), c("psoc", "psic"))
  if (length(sys) == 0L) sys <- c("psoc", "psic")

  entry <- list(
    index = idx,
    text = item$text,
    query = item$query,
    label = item$label,
    requested_systems = sys,
    occupation = occupation %||% item$query,
    establishment_activity = establishment_activity,
    wage_payer = wage_payer,
    packet = packet
  )
  entry$unresolved <- .assistant_batch_unresolved(entry)
  entry$missing_slot <- if (entry$unresolved) packet$clarification$missing_slot else NULL
  entry$question <- if (entry$unresolved) packet$clarification$question else NULL

  # Keyed by the item's own index, so a re-record replaces that item and
  # only that item.
  state$batch[[as.character(idx)]] <- entry
  invisible(entry)
}

#' The items recorded so far in the in-flight batch, in index order.
assistant_turn_batch_items <- function(state) {
  if (is.null(state) || !is.environment(state)) return(list())
  b <- state$batch
  if (is.null(b) || length(b) == 0L) return(list())
  # Unnamed: callers iterate positionally, and the internal index keys are
  # an implementation detail of the "one slot per item" store.
  unname(b[order(vapply(b, function(e) e$index, numeric(1)))])
}

#' The per-item results of the most recently finalised batch.
assistant_turn_last_batch <- function(state) {
  if (is.null(state) || !is.environment(state)) return(list())
  b <- state$last_batch
  if (is.null(b)) list() else b
}

#' Close the batch and apply the resolution rule above.
#'
#' @return list(n_items, n_resolved, n_unresolved, resolved, unresolved,
#'   prompts, pending_activated, pending_index, truncated_note).
#'   `resolved`/`unresolved` are the per-item entries; `prompts` is one
#'   user-facing line per unresolved item.
assistant_turn_finalize_batch <- function(state) {
  empty <- list(n_items = 0L, n_resolved = 0L, n_unresolved = 0L,
                resolved = list(), unresolved = list(), prompts = character(0),
                pending_activated = FALSE, pending_index = NA_integer_)
  if (is.null(state) || !is.environment(state)) return(empty)

  items <- assistant_turn_batch_items(state)
  state$batch <- NULL
  state$batch_expected <- NULL
  if (length(items) == 0L) {
    state$pending <- NULL
    state$last_batch <- list()
    return(empty)
  }

  unresolved <- Filter(function(e) isTRUE(e$unresolved), items)
  resolved <- Filter(function(e) !isTRUE(e$unresolved), items)

  activated <- FALSE
  pending_index <- NA_integer_
  if (length(unresolved) == 1L) {
    e <- unresolved[[1L]]
    assistant_turn_set_pending(
      state, e$packet,
      occupation = e$occupation,
      establishment_activity = e$establishment_activity,
      requested_systems = e$requested_systems,
      wage_payer = e$wage_payer
    )
    activated <- !is.null(assistant_turn_pending(state))
    if (activated) pending_index <- e$index
  } else {
    # 0 unresolved -> spec 27 requires an EMPTY session pending state.
    # 2+ unresolved -> deliberately none activated.
    state$pending <- NULL
  }

  prompts <- vapply(unresolved, function(e) {
    q <- e$question
    if (is.null(q) || is.na(q) || !nzchar(q)) q <- "More detail is needed to code this."
    sprintf("%s. %s -- %s", e$index, e$text, q)
  }, character(1))

  # Written last: `assistant_turn_set_pending()` above may clear state.
  state$last_batch <- items

  list(
    n_items = length(items),
    n_resolved = length(resolved),
    n_unresolved = length(unresolved),
    resolved = resolved,
    unresolved = unresolved,
    prompts = prompts,
    pending_activated = activated,
    pending_index = pending_index
  )
}

# Answers that mean "the establishment pays" vs "the agency pays". Matched
# on the user's own words; anything else leaves the slot unfilled so the
# question is asked again rather than guessed at.
.ASSISTANT_PAYER_ESTABLISHMENT <- "establishment|hospital|school|company|store|factory|office|employer|where (they|he|she) (work|is deployed)|the client"
.ASSISTANT_PAYER_AGENCY <- "agency|manpower|outsourc|contractor|recruit|third.?party"

#' Merge a user's free-text reply into the pending request's missing slot.
#'
#' @return the updated argument list for `assistant_coding_service()`, or
#'   NULL when there is no pending request.
assistant_turn_apply_reply <- function(state, reply) {
  p <- assistant_turn_pending(state)
  if (is.null(p)) return(NULL)
  txt <- .assistant_scalar_chr(reply)
  if (is.null(txt)) return(NULL)

  args <- list(
    occupation = p$occupation,
    establishment_activity = p$establishment_activity,
    requested_systems = p$requested_systems,
    wage_payer = p$wage_payer
  )

  slot <- p$missing_slot
  if (identical(slot, "wage_payer")) {
    low <- tolower(txt)
    # Check agency first: "paid by the agency, not the hospital" names both.
    if (grepl(.ASSISTANT_PAYER_AGENCY, low)) {
      args$wage_payer <- "agency"
      # The agency's OWN activity is what gets classified when it pays.
      # Wording chosen to match the canonical PSIC 2026 family
      # (78 Employment Activities), not invented.
      args$establishment_activity <- "temporary employment agency activities"
    } else if (grepl(.ASSISTANT_PAYER_ESTABLISHMENT, low)) {
      args$wage_payer <- "establishment"
      # Keep the deployment site as the activity, minus the agency wording
      # that previously blocked it.
      cleaned <- as.character(p$establishment_activity %||% "")
      cleaned <- gsub(
        "(through|via|by)?\\s*(a |an |the )?(manpower|recruitment|outsourcing)\\s*agency",
        "", cleaned, ignore.case = TRUE
      )
      # Strip the preposition/article residue the removal leaves behind,
      # so "manpower agency at a hospital" becomes "hospital" rather than
      # "at a hospital" (which retrieves the n.e.c. catch-all first).
      cleaned <- trimws(gsub("^\\s*(at|in|for|with|of)\\s+(a |an |the )?", "",
                             trimws(cleaned), ignore.case = TRUE))
      if (nzchar(cleaned)) args$establishment_activity <- cleaned
    }
  } else if (identical(slot, "occupation")) {
    args$occupation <- txt
  } else {
    # establishment_activity and establishment_activity_detail both take
    # the reply as the new activity wording.
    args$establishment_activity <- txt
  }
  args
}

`%||%` <- function(a, b) if (is.null(a)) b else a

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
  st$current_requested_systems <- c("psoc", "psic")
  st$latest_packet <- NULL
  st
}

#' Record the route determined for the CURRENT turn (H1).
#'
#' Read by the tool-body interlock (assistant_tools.R) and by the
#' content-rendering override (assistant_render.R) -- both close over this
#' SAME environment, so the write here is visible to both without any
#' dependency on Shiny scheduling order.
assistant_turn_set_route <- function(state, route) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  r <- .assistant_scalar_chr(route)
  # An unrecognised or missing route is treated as the restrictive default,
  # never as "no restriction".
  state$current_route <- if (is.null(r) || !(r %in% ASSISTANT_ROUTES)) {
    "contextual_coding"
  } else {
    r
  }
  invisible(state$current_route)
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
assistant_turn_set_latest_packet <- function(state, packet) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
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
#' Stores only the minimal deterministic context needed to rerun the same
#' request (spec 12): the slots already known, the systems asked for, and
#' which slot is missing. No prose, no candidate pool, no model output.
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
    question = packet$clarification$question
  )
  invisible(state$pending)
}

#' Clear the pending question (resolved, superseded, or topic change).
assistant_turn_clear <- function(state) {
  if (is.null(state) || !is.environment(state)) return(invisible(NULL))
  state$pending <- NULL
  invisible(NULL)
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

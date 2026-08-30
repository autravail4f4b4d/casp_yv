# H2 support -- bridges a process-global S7 dispatch to per-session state.
#
# WHY THIS EXISTS: `contents_shinychat()` (see assistant_render.R) is a
# process-global S7 generic -- one method serves every concurrent Shiny
# session. To suppress live text rendering for ONLY the sessions currently
# on the contextual_coding route, the override needs to know WHICH session
# a given content chunk belongs to and look up THAT session's own
# `assistant_turn_state`.
#
# The registry below is the standard pattern for this: a single
# process-global lookup table, keyed by Shiny's own per-session `token`,
# whose VALUES are the already-isolated per-session turn-state
# environments created by `assistant_new_turn_state()`. The registry itself
# holds no user data -- only a pointer to each session's own environment --
# so this does not reintroduce the module-level mutable state the original
# RM design deliberately avoided (spec 10/22 from prior phases). Verified
# by test: two registered sessions never see each other's state through
# this lookup.
#
# `session$token` and `session$onSessionEnded()` are ordinary, long-stable
# Shiny APIs (not shinychat/ellmer internals).

.assistant_session_registry <- new.env(parent = emptyenv())

#' Register this Shiny session's turn-state so process-global dispatch code
#' (the content-rendering override) can find it.
#'
#' Cleans itself up automatically when the session ends.
assistant_register_session_turn_state <- function(session, state) {
  if (is.null(session) || is.null(session$token)) return(invisible(NULL))
  token <- session$token
  assign(token, state, envir = .assistant_session_registry)
  if (is.function(session$onSessionEnded)) {
    session$onSessionEnded(function() {
      if (exists(token, envir = .assistant_session_registry, inherits = FALSE)) {
        rm(list = token, envir = .assistant_session_registry)
      }
    })
  }
  invisible(NULL)
}

#' The turn-state for the CURRENTLY EXECUTING reactive domain, or NULL.
#'
#' NULL is returned (never an error) when there is no active session (e.g.
#' called outside a running app, or the session was never registered) --
#' callers must treat NULL as "no restriction is known" and fail toward
#' the safe default rather than assuming an unrestricted route.
assistant_current_session_turn_state <- function() {
  session <- tryCatch(shiny::getDefaultReactiveDomain(), error = function(e) NULL)
  if (is.null(session) || is.null(session$token)) return(NULL)
  token <- session$token
  if (!exists(token, envir = .assistant_session_registry, inherits = FALSE)) return(NULL)
  get(token, envir = .assistant_session_registry, inherits = FALSE)
}

#' Test-only: how many sessions are currently registered.
assistant_session_registry_size <- function() {
  length(ls(.assistant_session_registry, all.names = TRUE))
}

#' Test-only: forcibly clear the registry between test runs.
assistant_session_registry_reset <- function() {
  rm(list = ls(.assistant_session_registry, all.names = TRUE),
     envir = .assistant_session_registry)
  invisible(NULL)
}

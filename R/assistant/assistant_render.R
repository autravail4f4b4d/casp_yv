# RM orchestration hardening -- suppress internal tool-call traces from the
# user-visible chat transcript.
#
# ROOT CAUSE (traced, not guessed):
#
#   user input
#   -> shinychat::chat_mod_server()'s append_stream_task
#   -> ellmer Chat$stream_async(input, stream = "content")   [chat_mod_server.R,
#      hard-coded -- this is shinychat's OWN call, not this application's]
#   -> ellmer's tool loop invokes our registered R tool functions
#   -> the async generator yields ellmer Content objects INTERLEAVED:
#      ContentText, ContentToolRequest, ContentToolResult, ContentText, ...
#   -> shinychat::chat_append(ui_id, stream) -> chat_append_stream()
#   -> PER CHUNK: shinychat's own S7 generic `contents_shinychat(content)`
#      dispatches on the chunk's class to decide what HTML reaches the DOM.
#
# shinychat ships its OWN default methods for `contents_shinychat()` on
# `ellmer::ContentToolRequest` / `ellmer::ContentToolResult` that render a
# custom `<shiny-tool-request>` / `<shiny-tool-result>` element carrying the
# LITERAL tool name and the raw JSON arguments/results as HTML attributes
# (verified directly: rendering a real ContentToolRequest for
# `assistant_search_classification` produced
# `<shiny-tool-request ... tool-name="assistant_search_classification"
# arguments="{&quot;system&quot;:...}">`). This is a deliberate shinychat
# feature (developer-facing tool-call transparency), not a bug, a debug
# flag, or anything under this application's control via configuration:
# `chat_mod_server()` takes no argument to disable it, and the existing
# system-prompt instruction "do not expose internal tool syntax" has NO
# effect here because this markup is injected directly from the raw content
# stream -- it never passes through the model's own text output.
#
# THE FIX: `contents_shinychat()` is an S7 generic (confirmed via
# `S7::is_generic()` / inspection), and S7 generics support external method
# registration for classes the caller does not own -- exactly the same
# mechanism shinychat itself used to add these methods in the first place.
# Registering our OWN methods for the two tool-content classes overrides
# shinychat's default rendering globally, for the life of the R process,
# without forking shinychat or monkey-patching ellmer. Every other content
# type (ContentText, ContentImage, ...) is untouched and keeps rendering via
# shinychat's own default methods.

# Optional neutral progress text shown while a tool call is in flight. Pure
# status language: no tool name, no argument, no result value. Repeated
# identical text is fine if the model makes multiple tool calls in one turn
# -- it carries no information a user could act on incorrectly, unlike a
# tool name or payload would.
ASSISTANT_TOOL_STATUS_TEXT <- "Checking official PSA classifications…"

# The literal tool names this suppression exists to keep out of the
# transcript. Not used for matching (the override is unconditional and
# class-based, not string-based) -- kept here so a test can assert these
# exact strings never appear in ANYTHING this module renders, independent
# of which tool happens to be involved.
ASSISTANT_INTERNAL_TOOL_NAME_LITERALS <- c(
  "assistant_search_classification",
  "assistant_get_classification_entry",
  "assistant_classification_registry",
  "assistant_search_common_pairings",
  "assistant_get_psic_rule",
  "assistant_get_classification_system_info",
  "assistant_code_occupation_and_activity",
  "assistant_coding_level"
)

#' Render one ellmer Content chunk exactly as the live chat will.
#'
#' Goes through shinychat's OWN `contents_shinychat()` generic (after our
#' override is registered), so a test exercises the identical dispatch path
#' `chat_append_stream()` uses -- not a parallel implementation that could
#' drift from what actually ships.
#'
#' @param content An ellmer `Content` object (e.g. from `ellmer::ContentText()`,
#'   `ellmer::ContentToolRequest()`, `ellmer::ContentToolResult()`).
#'
#' @return Whatever `shinychat:::contents_shinychat()` returns for that
#'   content type (HTML, a string, or NULL). NULL if shinychat is not
#'   installed or the generic cannot be found.
assistant_render_tool_content <- function(content) {
  gen <- .assistant_shinychat_content_generic()
  if (is.null(gen)) return(NULL)
  gen(content)
}

.assistant_shinychat_content_generic <- function() {
  if (!requireNamespace("shinychat", quietly = TRUE)) return(NULL)
  get0("contents_shinychat", envir = asNamespace("shinychat"), mode = "function")
}

#' Register the tool-trace suppression methods. Idempotent and safe to call
#' more than once (S7 allows re-registering the same method; it only emits
#' a message, never an error). Returns FALSE (never errors) if shinychat,
#' ellmer or S7 are unavailable, or if the generic's shape ever changes in a
#' future shinychat release -- a broken override must degrade to "tool
#' traces might show" rather than crash the whole application.
.assistant_register_tool_trace_suppression <- function() {
  if (!requireNamespace("shinychat", quietly = TRUE) ||
      !requireNamespace("ellmer", quietly = TRUE) ||
      !requireNamespace("S7", quietly = TRUE) ||
      !requireNamespace("htmltools", quietly = TRUE)) {
    return(invisible(FALSE))
  }

  gen <- .assistant_shinychat_content_generic()
  if (is.null(gen) || !inherits(gen, "S7_generic")) {
    return(invisible(FALSE))
  }

  tryCatch({
    S7::method(gen, ellmer::ContentToolRequest) <- function(content) {
      htmltools::tags$span(class = "rm-tool-status", ASSISTANT_TOOL_STATUS_TEXT)
    }
    S7::method(gen, ellmer::ContentToolResult) <- function(content) {
      # "" and not NULL, deliberately -- see
      # `assistant_render_text_content_for_route()` for the measured
      # difference between the two inside shinychat.
      ""
    }
    invisible(TRUE)
  }, error = function(e) {
    message(sprintf(
      "[rm-assistant] tool-trace suppression could not be registered: %s",
      conditionMessage(e)
    ))
    invisible(FALSE)
  })
}

# --- H2: do not stream unvalidated coding prose ----------------------------
#
# THE DEFECT THIS CLOSES: the response guard (assistant_response_guard.R)
# validates COMPLETE generated text against the coding service's
# allowed_codes. Validating only after the browser has already displayed
# the text is too late -- a fabricated "PSOC 1112" is indistinguishable
# from the correct "PSOC 1111" until the stream reaches the last digit, by
# which point it has already rendered token-by-token in front of the user.
#
# THE MECHANISM: exactly the same S7 override technique as the tool-trace
# suppression above, applied to `ellmer::ContentText` instead. For a
# session on the `contextual_coding` route this SUPPRESSES the live,
# per-chunk rendering of the assistant's generated prose (returns NULL, so
# nothing streams to the DOM). Nothing is lost: ellmer's own Turn object
# retains the complete assembled text regardless of whether shinychat
# rendered each chunk (`ellmer::contents_text(turn)`, confirmed directly).
# app.R observes `rm_chat$last_turn()` -- exposed by shinychat's own
# `chat_mod_server()` return handle -- reads the complete text back once
# the turn is fully done, runs it through `assistant_guard_response()`,
# and appends EITHER the validated text or the deterministic fallback via
# the module's own exposed `$append()` method. No unsupported API is used:
# `last_turn`, `status` and `append` are documented fields of the object
# `chat_mod_server()` returns (verified directly against the installed
# shinychat 0.4.0 source).
#
# Every route OTHER than `contextual_coding` is unaffected: the original,
# currently-installed method is captured BELOW before being replaced, and
# the new method falls through to it for every other route (or when no
# session context is resolvable at all -- see assistant_session_registry.R
# for why that case cannot occur in real usage but is still handled
# rather than assumed away).
.assistant_default_content_text_method <- NULL

# --- W4: why suppression returns "" and never NULL -------------------------
#
# TRACED, not inferred. `shinychat:::chat_append_stream_impl()` calls
#
#     msg <- contents_shinychat(msg); chat_append_(msg)
#
# and `chat_append_message()` then branches on the VALUE:
#
#     is.character(content) && !is_html   ->  ui <- list(html = content)
#     otherwise                           ->  ui <- process_ui(pre_process_ui(content))
#
# Returning NULL took the second branch. `pre_process_ui(NULL)` wraps its
# argument in shinychat's own custom element, so every suppressed chunk
# appended the LITERAL MARKUP
#
#     <shinychat-raw-html></shinychat-raw-html>
#
# into the streaming message's markdown buffer -- once per chunk, as
# transcript content, for every coding turn. (Verified by executing the
# real shinychat internals against a real ellmer content object, not by
# reading the source.) Returning a character scalar takes the first branch
# and appends nothing at all.
#
# That leaves the second half of the same defect: shinychat opens a
# streaming assistant message for every turn and its `chunk_end` reducer
# commits that message to the transcript unconditionally, empty or not.
# An assistant message whose content is empty is rendered with shinychat's
# placeholder icon -- a raw `<svg>` string injected into the DOM -- so a
# fully suppressed turn left a contentless bubble sitting next to the real
# answer. The carrier below removes it by putting the authoritative
# rendering INTO that message instead of leaving it empty.

#' Decide what a ContentText chunk renders to, given an EXPLICIT route.
#'
#' Pure function, no ambient session lookup -- this is what a test drives
#' directly to exercise every route without a live Shiny session. The
#' actual S7 method (registered below) is a thin wrapper that supplies the
#' route and state from `assistant_current_session_turn_state()`.
#'
#' @param content an `ellmer::ContentText`.
#' @param route character(1) or NA. NA is treated the same as
#'   `"contextual_coding"` -- an unresolvable route defaults to the
#'   restrictive treatment, the same fail-closed philosophy as the tool
#'   interlock (H1), not to "render normally".
#' @param state the session turn-state, or NULL. Supplies this turn's
#'   authoritative rendering, which the FIRST suppressed chunk emits in
#'   place of the model's text.
#'
#' @return whatever the captured original method returns on an unrestricted
#'   route; on a coding route either the deterministic rendering (once) or
#'   `""`. Never NULL.
assistant_render_text_content_for_route <- function(content, route, state = NULL) {
  restrict <- is.na(route) || identical(route, "contextual_coding")
  if (!restrict) {
    if (!is.function(.assistant_default_content_text_method)) return("")
    return(.assistant_default_content_text_method(content))
  }
  carrier <- assistant_turn_take_render(state)
  if (!is.null(carrier)) return(carrier)
  ""
}

.assistant_register_content_guard <- function(gen) {
  original <- tryCatch(S7::method(gen, ellmer::ContentText), error = function(e) NULL)
  if (is.function(original)) {
    .assistant_default_content_text_method <<- original
  }
  tryCatch({
    S7::method(gen, ellmer::ContentText) <- function(content) {
      state <- assistant_current_session_turn_state()
      route <- if (is.null(state)) NA_character_ else assistant_turn_current_route(state)
      assistant_render_text_content_for_route(content, route, state)
    }
    invisible(TRUE)
  }, error = function(e) {
    message(sprintf(
      "[rm-assistant] coding-route text guard could not be registered: %s",
      conditionMessage(e)
    ))
    invisible(FALSE)
  })
}

# Registered once per R process, unconditionally, at source time -- this
# file is sourced exactly once by app.R's `lapply(sort(r_files), source)`
# (and once per testthat run via the shared helper). Harmless when RM is
# disabled or misconfigured: `shinychat::chat_mod_server()` is then simply
# never invoked, so this override sits unused. Registering it here rather
# than inside `create_rm_chat_client()` means it also protects any future
# code path that streams ellmer content through shinychat, not just the one
# call site that exists today.
local({
  gen <- .assistant_shinychat_content_generic()
  invisible(.assistant_register_tool_trace_suppression())
  if (!is.null(gen) && inherits(gen, "S7_generic")) {
    invisible(.assistant_register_content_guard(gen))
  }
})

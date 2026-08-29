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
  "assistant_get_classification_system_info"
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
      NULL
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

# Registered once per R process, unconditionally, at source time -- this
# file is sourced exactly once by app.R's `lapply(sort(r_files), source)`
# (and once per testthat run via the shared helper). Harmless when RM is
# disabled or misconfigured: `shinychat::chat_mod_server()` is then simply
# never invoked, so this override sits unused. Registering it here rather
# than inside `create_rm_chat_client()` means it also protects any future
# code path that streams ellmer content through shinychat, not just the one
# call site that exists today.
invisible(.assistant_register_tool_trace_suppression())

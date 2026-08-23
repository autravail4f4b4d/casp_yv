# RM assistant LLM client construction.
#
# Provider-configurable, fail-safe, and strictly per-session.
#
# Public contract:
#   RM_DEFAULT_MODEL                                       -> character(1)
#   rm_assistant_enabled()                                 -> logical(1)
#   rm_assistant_status()                                  -> list(enabled, available, reason)
#   create_rm_chat_client(tools = NULL, system_prompt = NULL) -> ellmer Chat or NULL
#
# ############################################################################
# SESSION ISOLATION -- HARD REQUIREMENT (spec 10 and 22)
#
# create_rm_chat_client() MUST construct and return a BRAND NEW ellmer Chat on
# every call. An ellmer Chat is a mutable R6 object that accumulates the
# conversation turns. Caching one in this file's environment (or any other
# package-level environment) and handing the same object to more than one
# Shiny session would leak one public user's conversation into another user's
# chat panel. Nothing in this file may ever store a Chat object. The only
# thing memoized anywhere in the assistant layer is the immutable system
# prompt text (see R/assistant/assistant_prompt.R).
# ############################################################################

RM_DEFAULT_MODEL <- "gpt-4o-mini"

RM_DEFAULT_PROVIDER <- "openai"

# provider id -> (ellmer constructor name, credential env var)
.RM_PROVIDERS <- list(
  openai = list(fn = "chat_openai", key_env = "OPENAI_API_KEY"),
  anthropic = list(fn = "chat_anthropic", key_env = "ANTHROPIC_API_KEY")
)

# Short, non-technical reasons. Never interpolate credentials, provider error
# text, or stack traces into anything shown to a public user (spec 22).
.RM_REASON_DISABLED <- "The assistant is turned off in this deployment."
.RM_REASON_NO_PROVIDER <- "The assistant is not configured for this deployment."
.RM_REASON_NO_CREDENTIAL <- "The assistant is not configured for this deployment."
.RM_REASON_NO_PROMPT <- "The assistant is not configured for this deployment."
.RM_REASON_NO_PACKAGE <- "The assistant is unavailable in this deployment."
.RM_REASON_CLIENT_FAILED <- "The assistant could not be started right now."

.rm_env_chr <- function(name, default = "") {
  val <- Sys.getenv(name, unset = NA_character_)
  if (is.na(val) || !nzchar(trimws(val))) default else trimws(val)
}

.rm_provider_id <- function() {
  tolower(.rm_env_chr("RM_PROVIDER", RM_DEFAULT_PROVIDER))
}

.rm_model_id <- function() {
  .rm_env_chr("RM_MODEL", RM_DEFAULT_MODEL)
}

#' Is the RM assistant switched on?
#'
#' Driven solely by `RM_ASSISTANT_ENABLED`.
#'
#' Default when unset: FALSE (fail-closed). This app is public-facing and a
#' misconfigured deployment that silently enabled the assistant would bill a
#' provider API on every visitor message. Deployments must opt in explicitly.
#'
#' Recognised false-y values (case-insensitive): "false", "0", "no", "off",
#' and the empty/unset value. Anything else is treated as enabled.
rm_assistant_enabled <- function() {
  raw <- Sys.getenv("RM_ASSISTANT_ENABLED", unset = "")
  val <- tolower(trimws(raw))
  if (!nzchar(val)) return(FALSE)
  !val %in% c("false", "0", "no", "off")
}

#' Configuration status of the RM assistant.
#'
#' @return list(enabled = logical(1), available = logical(1), reason = character(1))
#'   `reason` is "" when available, otherwise a short public-safe sentence.
#'   Technical detail is emitted server-side via message()/warning() instead.
rm_assistant_status <- function() {
  mk <- function(enabled, available, reason) {
    list(enabled = enabled, available = available, reason = reason)
  }

  if (!rm_assistant_enabled()) {
    return(mk(FALSE, FALSE, .RM_REASON_DISABLED))
  }

  provider <- .rm_provider_id()
  spec <- .RM_PROVIDERS[[provider]]
  if (is.null(spec)) {
    message(sprintf(
      "[rm-assistant] Unsupported RM_PROVIDER '%s'. Supported: %s.",
      provider, paste(names(.RM_PROVIDERS), collapse = ", ")
    ))
    return(mk(TRUE, FALSE, .RM_REASON_NO_PROVIDER))
  }

  if (!requireNamespace("ellmer", quietly = TRUE)) {
    message("[rm-assistant] Package 'ellmer' is not installed.")
    return(mk(TRUE, FALSE, .RM_REASON_NO_PACKAGE))
  }

  # Presence check only. The key value is never read into a variable that
  # could be logged or surfaced -- ellmer reads the standard env var itself.
  if (!nzchar(Sys.getenv(spec$key_env, unset = ""))) {
    message(sprintf(
      "[rm-assistant] Provider credential env var %s is not set; assistant disabled.",
      spec$key_env
    ))
    return(mk(TRUE, FALSE, .RM_REASON_NO_CREDENTIAL))
  }

  prompt_ok <- tryCatch({
    invisible(rm_system_prompt())
    TRUE
  }, error = function(e) {
    message(sprintf("[rm-assistant] System prompt unavailable: %s", conditionMessage(e)))
    FALSE
  })
  if (!prompt_ok) {
    return(mk(TRUE, FALSE, .RM_REASON_NO_PROMPT))
  }

  mk(TRUE, TRUE, "")
}

#' Create a NEW per-session ellmer chat client for RM.
#'
#' @param tools list or NULL. Registered read-only classification tools
#'   (ellmer tool definitions). Registered when a non-empty list.
#' @param system_prompt character(1) or NULL. NULL loads the repository
#'   system prompt via `rm_system_prompt()`.
#' @return an ellmer `Chat` R6 object, or NULL when the assistant is disabled,
#'   unconfigured, or the provider client could not be constructed. Never
#'   errors; never returns a partially-constructed client.
#'
#' Call this once per Shiny session, inside the session's server function.
#' See the SESSION ISOLATION banner at the top of this file.
create_rm_chat_client <- function(tools = NULL, system_prompt = NULL) {
  status <- rm_assistant_status()
  if (!isTRUE(status$available)) {
    return(NULL)
  }

  prompt <- tryCatch(
    if (is.null(system_prompt)) rm_system_prompt() else system_prompt,
    error = function(e) {
      message(sprintf("[rm-assistant] System prompt unavailable: %s", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(prompt) || !nzchar(trimws(prompt))) {
    return(NULL)
  }

  provider <- .rm_provider_id()
  spec <- .RM_PROVIDERS[[provider]]

  client <- tryCatch({
    constructor <- getExportedValue("ellmer", spec$fn)
    # No api_key= here. It is deprecated in ellmer >= 0.4.0, and passing the
    # secret through R code is exactly what spec 22 forbids -- ellmer reads
    # the standard provider env var itself.
    constructor(
      system_prompt = prompt,
      model = .rm_model_id(),
      echo = "none"
    )
  }, error = function(e) {
    # Raw provider/stack detail stays server-side (spec 22).
    warning(sprintf(
      "[rm-assistant] Failed to construct %s client: %s",
      spec$fn, conditionMessage(e)
    ), call. = FALSE)
    NULL
  })

  if (is.null(client)) {
    return(NULL)
  }

  if (!is.null(tools) && length(tools) > 0) {
    ok <- tryCatch({
      client$set_tools(tools)
      TRUE
    }, error = function(e) {
      warning(sprintf(
        "[rm-assistant] Failed to register assistant tools: %s",
        conditionMessage(e)
      ), call. = FALSE)
      FALSE
    })
    # A client without its grounding tools would answer from model memory,
    # which the grounding rule forbids. Fail closed instead.
    if (!ok) {
      return(NULL)
    }
  }

  client
}

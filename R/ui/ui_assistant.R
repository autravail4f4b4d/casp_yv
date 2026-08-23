# RM Assistant screen — the conversational panel (spec sections 1.1, 9, 10, 21).
#
# Presentation only. This file contains no LLM client construction, no tool
# definitions, no prompt text, and no classification logic. Those live in
# R/assistant/assistant_client.R, R/assistant/assistant_tools.R and
# R/assistant/assistant_prompt.R and are reached only through the stable
# contracts documented below.
#
# ---------------------------------------------------------------------------
# PUBLIC CONTRACT (this file)
#
#   rm_assistant_ui(id = "rm_assistant")        -> bslib card; the chat panel
#   rm_assistant_unavailable_ui(reason = NULL)  -> bslib card; degraded state
#   rm_assistant_new_chat_ui(id = "rm_assistant") -> actionButton ("New chat")
#
# Stable module id .......... "rm_assistant"          (spec 10)
# Stable new-chat input id .. "rm_assistant-new_chat" (shiny::NS(id, "new_chat"))
# Chat element id ........... "rm_assistant-chat"     (chosen by shinychat)
#
# ---------------------------------------------------------------------------
# SERVER CONTRACT — what app.R must do to mount this panel
#
# Verified against the installed shinychat 0.4.0:
#   chat_mod_ui(id, ..., client = deprecated(), messages = NULL)
#   chat_mod_server(id, client, greeting = NULL,
#                   bookmark_on_input = TRUE, bookmark_on_response = TRUE)
#   chat_clear(id, greeting = FALSE, session = getDefaultReactiveDomain())
#   chat_set_greeting(id, greeting, session = getDefaultReactiveDomain())
#
# 1. UI side (inside page_navbar):
#
#      bslib::nav_panel(
#        "RM Assistant", value = "rm_assistant",
#        local({
#          st <- rm_assistant_status()
#          if (isTRUE(st$enabled) && isTRUE(st$available)) {
#            rm_assistant_ui()
#          } else {
#            rm_assistant_unavailable_ui(st$reason)
#          }
#        })
#      )
#
#    NOTE: rm_assistant_status() is evaluated once at UI-build time. If the
#    UI object in app.R is built once at startup (it is), the degraded panel
#    is decided at startup; that matches spec 21 (a deployment either has a
#    working provider configuration or it does not).
#
# 2. Server side (inside server <- function(input, output, session)):
#
#      # PER SESSION. Never hoist this to the global environment: an ellmer
#      # Chat is a mutable R6 object that accumulates turns, and sharing one
#      # would leak one public user's conversation into another's (spec 10/22).
#      rm_client <- create_rm_chat_client(tools = rm_assistant_tools())
#
#      if (!is.null(rm_client)) {
#        # Do NOT pass `greeting =` here. The static greeting is already
#        # baked into the UI by rm_assistant_ui() (zero model tokens, zero
#        # server round-trip). Passing it again would set it twice.
#        rm_chat <- shinychat::chat_mod_server("rm_assistant", client = rm_client)
#
#        # New chat / clear. `rm_chat$clear()` is the module's own helper:
#        # it calls chat_clear("chat", greeting = FALSE) AND resets the
#        # ellmer client's turn history, so the LLM forgets the conversation
#        # too. greeting = FALSE (the default) is correct here: shinychat's
#        # reducer restores the existing greeting to visible on clear, while
#        # greeting = TRUE would DELETE the static greeting and fire
#        # `greeting_requested`, which nothing answers (we supply no greeting
#        # function) -- the greeting would be lost for the rest of the session.
#        shiny::observeEvent(input[["rm_assistant-new_chat"]], {
#          rm_chat$clear()
#        })
#      }
#
#    Equivalent lower-level form, if the module return value is not used:
#      shiny::observeEvent(input[["rm_assistant-new_chat"]], {
#        shinychat::chat_clear("rm_assistant-chat", session = session)
#        rm_client$set_turns(list())
#      })
#    Prefer rm_chat$clear() -- it keeps UI and client history in step.
#
# 3. Sibling contracts consumed (do not redefine here):
#      rm_assistant_status()   -> list(enabled=, available=, reason=)   [WS C]
#      create_rm_chat_client(tools = NULL, system_prompt = NULL)
#                              -> ellmer::Chat or NULL                  [WS C]
#      rm_assistant_tools()    -> list of ellmer tools                  [WS B]
#      RM_GREETING, RM_FOOTER_TEXT -> character(1)                      [WS C]
#
# ---------------------------------------------------------------------------
# HIDDEN-TAB NOTE (docs/UI_CONTRACT.md)
#
# This panel declares NO shiny outputs, so the suspendWhenHidden problem that
# affects the DT widgets on the secondary tabs does not apply here. The chat
# is a custom element driven by custom messages, which are delivered whether
# or not the tab is visible, and its static greeting is present in the initial
# HTML rather than pushed from the server. No `req(input$main_nav == ...)`
# gating or `outputOptions(suspendWhenHidden = FALSE)` call is needed for
# anything in this file.
# ---------------------------------------------------------------------------


# Load-order safety net only. R/assistant/assistant_prompt.R owns the
# canonical greeting/footer text (and the four starter suggestions embedded in
# it). app.R sources every R/**/*.R file before building the UI, so in the real
# application these fallbacks are never reached; they exist so this file can be
# sourced and inspected on its own without erroring.
.RM_GREETING_FALLBACK <- paste(
  "**Madayaw! I am RM.** I can assist you in finding and understanding",
  "Philippine statistical classifications.",
  sep = "\n"
)

.RM_FOOTER_FALLBACK <- paste(
  "RM is an assistant for classification search and interpretation.",
  "Verified codes come from the classification data available in this",
  "application."
)

.rm_assistant_greeting <- function() {
  if (exists("RM_GREETING")) RM_GREETING else .RM_GREETING_FALLBACK
}

.rm_assistant_footer <- function() {
  if (exists("RM_FOOTER_TEXT")) RM_FOOTER_TEXT else .RM_FOOTER_FALLBACK
}


#' New chat / clear control
#'
#' Declared here, wired in app.R. See the SERVER CONTRACT block above: the
#' server must observe `input[["rm_assistant-new_chat"]]` and call the
#' shinychat module's `clear()` helper (equivalently
#' `shinychat::chat_clear("rm_assistant-chat", greeting = FALSE, session = session)`
#' plus `client$set_turns(list())`).
#'
#' `greeting = FALSE` is deliberate -- shinychat restores the existing
#' greeting on clear, so the static "Madayaw! I am RM." message reappears for
#' the new conversation without any model call.
rm_assistant_new_chat_ui <- function(id = "rm_assistant") {
  ns <- shiny::NS(id)
  shiny::actionButton(
    ns("new_chat"),
    label = "New chat",
    class = "btn btn-outline-secondary btn-sm rm-assistant-new-chat",
    title = "Clear this conversation and start a new chat"
  )
}


#' RM Assistant chat panel
#'
#' Streaming, the stop/cancel control and starter-suggestion handling are all
#' provided by shinychat itself: `chat_mod_ui()` calls `chat_ui()` with
#' `enable_cancel = TRUE`, and `chat_mod_server()` wires `input$chat_cancel`
#' to the ellmer stream controller. Nothing is hand-rolled here.
#'
#' The greeting is passed as a *static* string through `chat_ui(greeting=)`,
#' so it is present in the page's initial HTML. No model call and no server
#' round-trip is spent on it (spec 9).
rm_assistant_ui <- function(id = "rm_assistant") {
  bslib::card(
    class = "rm-assistant-card",
    fill = TRUE,
    # Viewport-relative, not a fixed pixel height: guarantees a usable chat
    # area even if an ancestor is not a fill container.
    min_height = "60vh",
    bslib::card_header(
      class = "d-flex justify-content-between align-items-center gap-2 rm-assistant-header",
      shiny::tags$h2("RM Assistant", class = "h5 mb-0"),
      rm_assistant_new_chat_ui(id)
    ),
    bslib::card_body(
      fillable = TRUE,
      padding = 0,
      gap = 0,
      shinychat::chat_mod_ui(
        id,
        # --- named chat_ui() arguments, forwarded through `...` ------------
        greeting = .rm_assistant_greeting(),
        placeholder = "Describe an occupation, business activity, or code...",
        footer = shiny::tags$span(
          class = "rm-assistant-disclaimer",
          .rm_assistant_footer()
        ),
        fill = TRUE,
        height = "100%",
        # Slightly wider than shinychat's 680px default so the classification
        # tables RM emits are readable; still collapses to 100% on mobile.
        width = "min(760px, 100%)",
        # --- extra HTML attributes on the chat element ---------------------
        role = "region",
        `aria-label` = "RM Assistant chat"
      )
    )
  )
}


#' Degraded state (spec 21)
#'
#' Rendered in place of the chat when the assistant is disabled or not
#' configured. Calm and informational, not an error screen.
#'
#' `reason` must already be a short, non-technical, sanitised string produced
#' by R/assistant/assistant_client.R. It is rendered as escaped plain text and
#' nothing else; this function never renders a condition object, a stack
#' trace, or provider error output.
rm_assistant_unavailable_ui <- function(reason = NULL) {
  reason_ok <- is.character(reason) &&
    length(reason) == 1L &&
    !is.na(reason) &&
    nzchar(trimws(reason))

  bslib::card(
    class = "rm-assistant-card rm-assistant-unavailable",
    min_height = "40vh",
    bslib::card_header(
      shiny::tags$h2("RM Assistant", class = "h5 mb-0")
    ),
    bslib::card_body(
      shiny::tags$div(
        role = "region",
        `aria-label` = "RM Assistant availability",
        # State is carried by the text, never by colour alone.
        shiny::tags$p(
          class = "mb-2",
          shiny::tags$strong("RM Assistant is temporarily unavailable.")
        ),
        shiny::tags$p(
          class = "mb-2",
          "You can still search and browse all classifications using the ",
          "main application."
        ),
        if (reason_ok) {
          shiny::tags$p(class = "text-muted small mb-0", trimws(reason))
        }
      )
    )
  )
}

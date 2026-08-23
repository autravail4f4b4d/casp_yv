# PSA Statistical Classifications Search — minimal, design-ready Shiny UI.
#
# This file (plus R/ui/*.R and www/app.css) is the ONLY layer Claude Design
# should need to touch in the follow-up visual pass. All classification
# lookup/search/version/archive logic lives in R/repository.R, R/search.R,
# R/registry.R, and R/adapters/*.R, and is called here only through the
# stable service contract -- no classification-specific transformation
# happens in this file. See docs/UI_CONTRACT.md for the full contract.

r_files <- list.files("R", pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
invisible(lapply(sort(r_files), source))

library(shiny)
library(bslib)

ALL_LEVELS_VALUE <- ""  # sentinel for the "All levels" select choice

#' Tab label: Phosphor glyph + visible text.
#'
#' The icon is decorative and `aria-hidden`; the visible text is the tab's
#' accessible name. bslib's navset supplies the role="tab"/aria-selected
#' semantics around this, which the restyle preserves.
nav_label <- function(icon, text) {
  shiny::tagList(
    shiny::tags$i(class = paste("ph", icon), `aria-hidden` = "true"),
    text
  )
}

ui <- bslib::page_navbar(
  title = "Statistical Classifications",
  # Dark ("nocturne") theme from the approved design. Setting bg/fg/primary
  # on bs_theme rather than overriding a light Bootstrap in CSS means every
  # Bootstrap component -- form controls, cards, tables, DT -- inherits a
  # coherent dark palette instead of needing per-component overrides.
  theme = bslib::bs_theme(
    version = 5,
    bg = "#0f1119",
    fg = "#eef0f7",
    primary = "#3ec8d0",
    "body-bg" = "#0f1119",
    "card-bg" = "#151824",
    # System font stack deliberately -- no webfont download, so the app has
    # no third-party runtime dependency and no first-paint font swap.
    base_font = bslib::font_collection(
      "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"
    )
  ),
  # `id` makes the active tab available server-side as `input$main_nav`,
  # a real, reliably-updating Shiny input -- unlike Shiny's implicit
  # per-output suspend/resume-on-visibility mechanism, which was found to
  # be unreliable in practice for outputs (especially DT widgets, which
  # can initialize at a broken zero-width layout if built while hidden)
  # inside a non-default nav_panel. Explicitly gating each secondary tab's
  # outputs on `input$main_nav` (see `render_dual_panel()` and the
  # Compare PSIC Editions / About outputs below) is the robust fix used
  # throughout this server function instead.
  id = "main_nav",
  header = shiny::tags$head(shiny::tags$link(rel = "stylesheet", href = "app.css")),
  # Visible tab LABELS change per HANDOFF §2; the `value =` identities that
  # drive input$main_nav are deliberately untouched, so every existing
  # req(input$main_nav == ...) gate below keeps working unchanged.
  #
  # nav_label() pairs each label with its Phosphor glyph. The icon is
  # aria-hidden -- the visible text is the accessible name, so the tab is
  # never announced as an icon and never relies on the glyph loading.
  bslib::nav_panel(nav_label("ph-magnifying-glass", "Search"),
                   value = "search", search_ui()),
  bslib::nav_panel(nav_label("ph-arrows-left-right", "PSOC + PSIC"),
                   value = "dual_search", dual_search_ui()),
  bslib::nav_panel(nav_label("ph-arrows-split", "Compare Editions"),
                   value = "correspondence", correspondence_ui()),
  # RM Assistant. Which panel body is built is decided ONCE at startup from
  # the deployment's provider configuration: a deployment either has a
  # working assistant configuration or it does not (spec 21). When it does
  # not, the deterministic Search/Browse/Dual/Correspondence tabs are
  # completely unaffected -- that independence is the whole point, and is
  # asserted by tests/testthat/test-assistant-integration.R.
  bslib::nav_panel(
    nav_label("ph-sparkle", "RM Assistant"), value = "rm_assistant",
    local({
      st <- rm_assistant_status()
      if (isTRUE(st$enabled) && isTRUE(st$available)) {
        rm_assistant_ui()
      } else {
        rm_assistant_unavailable_ui(st$reason)
      }
    })
  ),
  bslib::nav_panel(nav_label("ph-info", "Sources"),
                   value = "about", shiny::uiOutput("sources_panel")),
  footer = shiny::tags$footer(
    class = "text-muted small p-2 border-top mt-2",
    "Source: Philippine Statistics Authority (PSA). This is a read-only reference tool; PSA is the authoritative classification source."
  )
)

server <- function(input, output, session) {
  registry <- classification_registry()

  # --- Classification system choices (populated once; registry is static
  # for the lifetime of an R process). ---
  system_choices <- stats::setNames(registry$id, paste0(registry$short_name, " — ", registry$display_name))
  updateSelectInput(session, "classification_system", choices = system_choices, selected = system_choices[[1]])

  # --- Edition/release choices follow the selected system. ---
  #
  # Rendered as a radio group (approved design) rather than a select, so
  # every available edition AND its current/archived status are visible at
  # once -- this is where Browse/Archive lives, so hiding the archived
  # editions behind a closed dropdown would bury the feature.
  #
  # The input ID and the value it yields are unchanged; only the widget
  # type differs, hence updateRadioButtons() here instead of
  # updateSelectInput(). choiceNames carries rich HTML (edition + status
  # badge) while choiceValues stays the plain version string the whole
  # service layer already expects.
  observeEvent(input$classification_system, {
    req(input$classification_system)
    versions <- classification_versions(input$classification_system)
    current <- registry$current_version[registry$id == input$classification_system][[1]]

    choice_names <- lapply(versions, function(v) {
      shiny::tagList(
        shiny::tags$span(class = "psa-edition-name", v),
        status_badge(if (identical(v, current)) "current" else "archived")
      )
    })

    updateRadioButtons(
      session, "classification_version",
      choiceNames = choice_names,
      choiceValues = as.list(versions),
      selected = current
    )
  }, ignoreNULL = TRUE)

  # --- Level choices follow the selected system+version. Resetting to
  # "All levels" here is what satisfies UAT case 13 (switching classification
  # clears/updates invalid level/version state) -- a level id from the
  # previous system (e.g. psgc's "Bgy") can never linger as a selected but
  # invalid level for the newly selected system. ---
  observeEvent(input$classification_version, {
    req(input$classification_system, input$classification_version)
    # Defensive guard against a transient mismatched pair: when the system
    # selector changes, this observer and the system-change observer above
    # can both be mid-flight, and a client round-trip can momentarily
    # deliver a version value that belongs to the PREVIOUS system (e.g.
    # version "2022" arriving while classification_system still reads
    # "psgc"). classification_levels() would otherwise raise an uncaught
    # validation error and crash this observer. Silently skip: the
    # system-change observer's own updateRadioButtons() call will shortly
    # settle classification_version (and re-trigger this observer) to a
    # value that's actually valid for the current system.
    if (!input$classification_version %in% classification_versions(input$classification_system)) {
      return(invisible(NULL))
    }
    levels <- classification_levels(input$classification_system, input$classification_version)
    level_choices <- c("All levels" = ALL_LEVELS_VALUE, stats::setNames(levels, levels))
    updateSelectInput(session, "classification_level", choices = level_choices, selected = ALL_LEVELS_VALUE)
  }, ignoreNULL = TRUE)

  query_debounced <- reactive(input$classification_query) |> debounce(250)

  current_level <- reactive({
    lvl <- input$classification_level
    if (is.null(lvl) || identical(lvl, ALL_LEVELS_VALUE)) NULL else lvl
  })

  results <- reactive({
    req(input$classification_system, input$classification_version)
    validate(need(
      input$classification_version %in% classification_versions(input$classification_system),
      "Loading edition..."
    ))
    search_classification(
      system = input$classification_system,
      version = input$classification_version,
      query = query_debounced(),
      level = current_level(),
      limit = 200
    )
  })

  # Result count above the table (approved design). Reads the same
  # reactive as the table itself, so the two can never disagree.
  output$classification_result_count <- renderUI({
    n <- nrow(results())
    tags$div(
      class = "psa-result-count",
      tags$strong(format(n, big.mark = ",")),
      if (n == 1L) " result" else " results",
      if (!nzchar(trimws(query_debounced() %||% ""))) " · browsing" else NULL
    )
  })

  output$classification_results <- DT::renderDT({
    d <- results()
    display <- d[, c("code", "label", "level", "status")]
    names(display) <- c("Code", "Label", "Level", "Status")
    DT::datatable(
      display,
      selection = "single",
      rownames = FALSE,
      options = list(pageLength = 15, dom = "ftip"),
      class = "stripe hover"
    )
  })

  selected_entry <- reactive({
    idx <- input$classification_results_rows_selected
    d <- results()
    if (is.null(idx) || nrow(d) == 0L) {
      return(d[0, , drop = FALSE])
    }
    d[idx, , drop = FALSE]
  })

  output$selected_entry <- renderUI({
    entry_detail_ui(selected_entry())
  })

  output$sources_panel <- renderUI({
    req(input$main_nav == "about")
    sources_ui()
  })
  # Forced always-on + explicitly gated on input$main_nav (see the `id =
  # "main_nav"` comment on page_navbar() above) rather than relying on
  # Shiny's implicit suspend-when-hidden/resume-on-shown behavior, which
  # this output has no reactive inputs to naturally re-trigger and which
  # was found unreliable in practice for other outputs in this app.
  outputOptions(output, "sources_panel", suspendWhenHidden = FALSE)

  # --- Dual Search: PSOC (occupations) + PSIC (industries), one query,
  # independent result sets. Defaults to each system's current edition
  # (PSOC 2022 / PSIC Revision 5 2026) per spec section 8, but either
  # selector can be switched to an archived edition explicitly. ---
  updateSelectInput(
    session, "dual_search_psoc_version",
    choices = classification_versions("psoc"),
    selected = registry$current_version[registry$id == "psoc"][[1]]
  )
  updateSelectInput(
    session, "dual_search_psic_version",
    choices = classification_versions("psic"),
    selected = registry$current_version[registry$id == "psic"][[1]]
  )

  dual_query_debounced <- reactive(input$dual_search_query) |> debounce(250)

  # These outputs are forced always-active (suspendWhenHidden = FALSE,
  # below) so Dual Search results are ready the instant the tab is opened.
  # That means this reactive can be asked to evaluate before the
  # updateSelectInput() calls above have completed their client round-trip
  # and input$dual_search_{psoc,psic}_version are still NULL -- req()-
  # blocking on them here left the output permanently stuck in a blank/
  # never-recomputed state in testing. Falling back to the registry's own
  # current versions instead of blocking means this reactive always
  # produces a real result and self-corrects once the real inputs arrive
  # (which still invalidates and re-runs this reactive normally).
  dual_results <- reactive({
    psoc_version <- if (!is.null(input$dual_search_psoc_version)) {
      input$dual_search_psoc_version
    } else {
      registry$current_version[registry$id == "psoc"][[1]]
    }
    psic_version <- if (!is.null(input$dual_search_psic_version)) {
      input$dual_search_psic_version
    } else {
      registry$current_version[registry$id == "psic"][[1]]
    }
    search_parallel_classifications(
      query = dual_query_debounced(),
      systems = c("psoc", "psic"),
      versions = c(psoc = psoc_version, psic = psic_version),
      limit_per_system = 100
    )
  })

  # A failure or no-match on one system's side must never suppress the
  # other (spec section 10) -- each panel renders entirely from its own
  # slice of dual_results(), independently of whatever happened on the
  # other side.
  #
  # Every output here is forced always-on (suspendWhenHidden = FALSE) AND
  # explicitly gated on `req(input$main_nav == "dual_search")` as its
  # first line. The gate is what actually matters: it stops the DT widget
  # from ever being built while its nav_panel is hidden (a DT initialized
  # at `display:none` freezes at a broken zero-width layout that never
  # recovers, even after the tab becomes visible and the underlying data
  # later changes -- verified directly in manual testing via server-side
  # debug logging showing correct non-empty data being computed while the
  # client still rendered nothing). Forcing the output always-on is then
  # *safe* only because of that gate; relying on Shiny's own implicit
  # suspend-when-hidden/resume-on-tab-shown behavior alone was found
  # unreliable in this app for both plain renderUI and renderDT outputs.
  render_dual_panel <- function(system_id, results_output_id, state_output_id) {
    output[[state_output_id]] <- renderUI({
      req(input$main_nav == "dual_search")
      res <- dual_results()
      err <- res$errors[[system_id]]
      d <- res$results[[system_id]]
      if (!is.null(err)) {
        tags$p(class = "text-danger small", paste("Error:", err))
      } else if (is.null(d) || nrow(d) == 0L) {
        tags$p(class = "text-muted small", "No results.")
      } else {
        NULL
      }
    })
    output[[results_output_id]] <- DT::renderDT({
      req(input$main_nav == "dual_search")
      d <- dual_results()$results[[system_id]]
      req(d)
      req(nrow(d) > 0L)
      display <- d[, c("code", "label", "level", "status")]
      names(display) <- c("Code", "Label", "Level", "Status")
      DT::datatable(
        display, selection = "none", rownames = FALSE,
        options = list(pageLength = 10, dom = "ftip"), class = "stripe hover"
      )
    })
    outputOptions(output, state_output_id, suspendWhenHidden = FALSE)
    outputOptions(output, results_output_id, suspendWhenHidden = FALSE)
  }
  render_dual_panel("psoc", "dual_search_psoc_results", "dual_search_psoc_state")
  render_dual_panel("psic", "dual_search_psic_results", "dual_search_psic_state")

  # --- Compare PSIC Editions: bidirectional 2019<->2026 correspondence. ---
  correspondence_query_debounced <- reactive(input$correspondence_query) |> debounce(250)

  correspondence_results <- reactive({
    req(input$correspondence_direction)
    versions <- strsplit(input$correspondence_direction, "-", fixed = TRUE)[[1]]
    search_psic_correspondence(
      query = correspondence_query_debounced(),
      from_version = versions[[1]],
      to_version = versions[[2]],
      limit = 200
    )
  })

  output$correspondence_results <- DT::renderDT({
    req(input$main_nav == "correspondence")
    d <- correspondence_results()
    display <- d[, c("from_code", "from_label", "to_code", "to_label", "relation_type", "provenance", "confidence")]
    names(display) <- c("From code", "From label", "To code", "To label", "Relationship", "Provenance", "Confidence")
    DT::datatable(
      display, selection = "single", rownames = FALSE,
      options = list(pageLength = 10, dom = "ftip"), class = "stripe hover"
    )
  })
  outputOptions(output, "correspondence_results", suspendWhenHidden = FALSE)

  correspondence_selected <- reactive({
    idx <- input$correspondence_results_rows_selected
    d <- correspondence_results()
    if (is.null(idx) || nrow(d) == 0L) {
      return(d[0, , drop = FALSE])
    }
    d[idx, , drop = FALSE]
  })

  output$correspondence_detail <- renderUI({
    req(input$main_nav == "correspondence")
    correspondence_detail_ui(correspondence_selected())
  })
  outputOptions(output, "correspondence_detail", suspendWhenHidden = FALSE)

  # --- RM Assistant (see the SERVER CONTRACT block in R/ui/ui_assistant.R) ---
  #
  # PER SESSION, deliberately. An ellmer Chat is a mutable R6 object that
  # accumulates conversation turns; hoisting this out of the server function
  # would share one client across every public visitor and leak one user's
  # conversation into another's (spec 10/22). Nothing here is cached at
  # module level.
  #
  # create_rm_chat_client() returns NULL rather than erroring whenever the
  # assistant is disabled or misconfigured, so the whole block is a no-op in
  # a deployment without a provider -- the deterministic tabs above are
  # entirely unaffected.
  rm_client <- create_rm_chat_client(tools = rm_assistant_tools())

  if (!is.null(rm_client)) {
    # No `greeting =` argument: the static greeting is already baked into
    # the initial HTML by rm_assistant_ui(), costing zero model tokens and
    # zero server round-trips (spec 9). Passing it again would set it twice.
    rm_chat <- shinychat::chat_mod_server("rm_assistant", client = rm_client)

    # New chat. The module's own clear() resets BOTH the visible transcript
    # and the ellmer client's turn history, so the model forgets the
    # conversation too rather than silently retaining it behind a cleared UI.
    observeEvent(input[["rm_assistant-new_chat"]], {
      rm_chat$clear()
    })

    # KNOWN LIMITATION -- mid-stream provider failure is silent client-side.
    #
    # If the provider call fails *after* the assistant was successfully
    # configured (expired or revoked key, network fault, rate limit),
    # shinychat rolls the transcript back and restores the user's text to
    # the input box, but shows them nothing explaining why. The failure IS
    # logged server-side by shinychat, and no secret or stack trace reaches
    # the browser, so this is a UX gap rather than a safety or security one.
    # The startup-time degradation path (assistant disabled or
    # misconfigured -> rm_assistant_unavailable_ui()) works correctly and is
    # the case spec 21 is chiefly concerned with.
    #
    # A fix was attempted and deliberately reverted rather than left in
    # place half-working. Three separate approaches were tried against
    # shinychat 0.4.0 and none reached the DOM on the errored-stream path:
    # the module's own `append()` helper, the top-level
    # `shinychat::chat_append()` against the namespaced id, and
    # `showNotification()`. Detection itself was proven to work (tracing
    # confirmed the failed stream leaves an EMPTY assistant turn on the
    # ellmer client, which is distinguishable from a real reply); it is
    # only the surfacing that fails. Revisit when shinychat exposes an
    # error hook on its chat module -- see docs/ASSISTANT_CONTRACT.md.
  }
}

shinyApp(ui, server)

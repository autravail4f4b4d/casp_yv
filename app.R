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

ui <- bslib::page_navbar(
  title = "PSA Statistical Classifications Search",
  theme = bslib::bs_theme(version = 5),
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
  bslib::nav_panel("Search", value = "search", search_ui()),
  bslib::nav_panel("Dual Search", value = "dual_search", dual_search_ui()),
  bslib::nav_panel("Compare PSIC Editions", value = "correspondence", correspondence_ui()),
  bslib::nav_panel("About / Data Sources", value = "about", shiny::uiOutput("sources_panel")),
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
  observeEvent(input$classification_system, {
    req(input$classification_system)
    versions <- classification_versions(input$classification_system)
    current <- registry$current_version[registry$id == input$classification_system][[1]]
    updateSelectInput(session, "classification_version", choices = versions, selected = current)
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
    # system-change observer's own updateSelectInput() call will shortly
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
}

shinyApp(ui, server)

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
  header = shiny::tags$head(shiny::tags$link(rel = "stylesheet", href = "app.css")),
  bslib::nav_panel("Search", search_ui()),
  bslib::nav_panel("About / Data Sources", shiny::uiOutput("sources_panel")),
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
    sources_ui()
  })
  # The About/Data Sources tab isn't active on load, and this output has no
  # reactive inputs to re-trigger it once the tab becomes visible, so it
  # must render immediately rather than waiting on Shiny's default
  # suspend-when-hidden behavior for outputs inside an inactive nav_panel.
  outputOptions(output, "sources_panel", suspendWhenHidden = FALSE)
}

shinyApp(ui, server)

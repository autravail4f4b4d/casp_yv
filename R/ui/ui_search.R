# Search/Browse screen — stable input/output IDs are documented in
# docs/UI_CONTRACT.md. This function builds the UI shell only; it contains
# no classification/search logic (that lives in R/repository.R and
# R/search.R and is called from the server function in app.R).
#
# Stable IDs defined here: classification_system, classification_version,
# classification_level, classification_query, classification_results,
# selected_entry.
search_ui <- function() {
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      title = "Browse & search",
      width = 300,
      shiny::selectInput(
        "classification_system", "Classification system",
        choices = NULL
      ),
      shiny::selectInput(
        "classification_version", "Edition / release",
        choices = NULL
      ),
      shiny::selectInput(
        "classification_level", "Level",
        choices = NULL
      ),
      shiny::textInput(
        "classification_query", "Search code or keyword",
        placeholder = "e.g. a code, or part of a title"
      ),
      shiny::helpText(
        "Leave the search box blank to browse the selected level."
      )
    ),
    bslib::card(
      bslib::card_header("Results"),
      DT::DTOutput("classification_results")
    ),
    bslib::card(
      bslib::card_header("Selected entry"),
      shiny::uiOutput("selected_entry")
    )
  )
}

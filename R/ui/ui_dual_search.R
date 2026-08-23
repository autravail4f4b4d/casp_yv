# Dual Search screen — one query, independent PSOC (occupations) and PSIC
# (industries) result panels. Presentation only; all ranking/version/
# failure-isolation logic lives in R/parallel_search.R and
# R/repository.R.
#
# Stable IDs defined here: dual_search_query, dual_search_psoc_version,
# dual_search_psic_version, dual_search_psoc_results, dual_search_psic_results.
dual_search_ui <- function() {
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      title = "Search occupations and industries",
      width = 300,
      shiny::textInput(
        "dual_search_query", "Search",
        placeholder = "e.g. accountant, software developer, farmer"
      ),
      shiny::helpText(
        "One query searches PSOC (occupations) and PSIC (industries) at ",
        "the same time, as two independent result sets. A PSOC code and a ",
        "PSIC code are never the same kind of thing -- see the note below."
      ),
      shiny::tags$hr(),
      shiny::selectInput("dual_search_psoc_version", "PSOC edition", choices = NULL),
      shiny::selectInput("dual_search_psic_version", "PSIC edition", choices = NULL)
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(
        bslib::card_header("Occupations — PSOC"),
        bslib::card_body(
          shiny::p(
            class = "text-muted small",
            "PSOC classifies the kind of work a person does."
          ),
          shiny::uiOutput("dual_search_psoc_state"),
          DT::DTOutput("dual_search_psoc_results")
        )
      ),
      bslib::card(
        bslib::card_header("Industries — PSIC"),
        bslib::card_body(
          shiny::p(
            class = "text-muted small",
            "PSIC classifies the primary economic activity of an establishment or enterprise."
          ),
          shiny::uiOutput("dual_search_psic_state"),
          DT::DTOutput("dual_search_psic_results")
        )
      )
    ),
    shiny::tags$p(
      class = "text-muted small mt-2",
      shiny::tags$strong("Occupations and industries are not the same classification. "),
      "A PSOC code never implies an equivalent PSIC code, and vice versa -- ",
      "they describe different things (what a person does vs. what an ",
      "establishment does)."
    )
  )
}

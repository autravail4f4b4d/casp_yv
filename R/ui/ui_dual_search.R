# PSOC + PSIC screen (main_nav value "dual_search", relabelled from
# "Dual Search" per HANDOFF §2) — one query, two INDEPENDENT result sets.
#
# PRESENTATION ONLY. All ranking, version handling and per-system failure
# isolation live in R/parallel_search.R and R/repository.R.
#
# Stable IDs, unchanged: dual_search_query, dual_search_psoc_version,
# dual_search_psic_version, dual_search_psoc_results,
# dual_search_psic_results, dual_search_psoc_state, dual_search_psic_state.
#
# The two panel headings "Occupations — PSOC" and "Industries — PSIC" are
# MANDATORY and must not be removed or reworded (docs/UI_CONTRACT.md §14).
# The visual design unifies presentation, but the two systems remain
# semantically and technically independent: a PSOC code never implies a
# PSIC code, and neither determines the other.

dual_search_ui <- function() {
  shiny::tagList(
    shiny::tags$div(
      class = "psa-hero",
      style = "align-items: flex-start; padding-bottom: 8px;",
      shiny::tags$h2(
        style = "margin: 0 0 6px; font-size: 20px;",
        "PSOC + PSIC"
      ),
      shiny::tags$p(
        class = "psa-dual-intro",
        "One query, searched against both systems at once — occupation ",
        "(PSOC) on the left, industry (PSIC) on the right. ",
        shiny::tags$strong("They never determine each other.")
      )
    ),

    shiny::tags$div(
      style = "max-width: 640px; margin-bottom: 22px;",
      shiny::textInput(
        "dual_search_query",
        "Search occupations and industries together",
        placeholder = "e.g. accountant, software developer, farmer",
        width = "100%"
      )
    ),

    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(
        bslib::card_body(
          shiny::tags$div(
            class = "psa-panel-head",
            shiny::tags$h6("Occupations — PSOC"),
            shiny::tags$div(
              style = "min-width: 150px;",
              shiny::selectInput(
                "dual_search_psoc_version", NULL,
                choices = NULL, width = "100%"
              )
            )
          ),
          shiny::tags$p(
            class = "text-muted small",
            "PSOC classifies the kind of work a person does."
          ),
          shiny::uiOutput("dual_search_psoc_state"),
          DT::DTOutput("dual_search_psoc_results")
        )
      ),
      bslib::card(
        bslib::card_body(
          shiny::tags$div(
            class = "psa-panel-head",
            shiny::tags$h6("Industries — PSIC"),
            shiny::tags$div(
              style = "min-width: 150px;",
              shiny::selectInput(
                "dual_search_psic_version", NULL,
                choices = NULL, width = "100%"
              )
            )
          ),
          shiny::tags$p(
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
      "A PSOC code never implies an equivalent PSIC code, and vice versa — ",
      "they describe different things (what a person does vs. what an ",
      "establishment does)."
    )
  )
}

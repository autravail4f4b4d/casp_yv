# Compare PSIC Editions screen — bidirectional PSIC 2019 <-> Revision 5
# (2026) correspondence explorer. Presentation only; all matching/scoring/
# provenance logic lives in R/correspondence/*.R.
#
# Stable IDs defined here: correspondence_direction, correspondence_query,
# correspondence_results, correspondence_detail.
correspondence_ui <- function() {
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      title = "Compare PSIC editions",
      width = 300,
      shiny::selectInput(
        "correspondence_direction", "Direction",
        choices = c(
          "2019 PSIC → PSIC Revision 5 (2026)" = "2019-2026",
          "PSIC Revision 5 (2026) → 2019 PSIC" = "2026-2019"
        )
      ),
      shiny::textInput(
        "correspondence_query", "Search a code or title",
        placeholder = "e.g. a PSIC code, or part of a title"
      ),
      shiny::helpText(
        "Leave blank to browse. Each row is one relationship -- a code ",
        "that split into several categories appears as several rows."
      ),
      shiny::tags$hr(),
      shiny::tags$p(
        class = "text-muted small",
        shiny::tags$strong("Previous classification"), " and ",
        shiny::tags$strong("Related classification in Revision 5"),
        " describe a correspondence, not an equivalence -- see the note below."
      )
    ),
    bslib::card(
      bslib::card_header("PSIC edition correspondence"),
      DT::DTOutput("correspondence_results")
    ),
    bslib::card(
      bslib::card_header("Relationship detail"),
      shiny::uiOutput("correspondence_detail")
    ),
    shiny::tags$p(
      class = "text-muted small mt-2",
      CORRESPONDENCE_STATISTICAL_WARNING
    )
  )
}

#' Render one correspondence row's full detail (RelationshipDetail component).
#'
#' @param row A one-row tibble in the `get_psic_correspondence()`/
#'   `search_psic_correspondence()` from_*/to_* shape, or a zero-row/NULL
#'   value when nothing is selected.
correspondence_detail_ui <- function(row) {
  if (is.null(row) || nrow(row) == 0L) {
    return(shiny::tags$p(class = "text-muted", "Select a row in the results table to see its full relationship detail."))
  }

  provenance_badge <- function(p) {
    cls <- switch(p,
      official = "badge text-bg-success",
      derived = "badge text-bg-info",
      suggested = "badge text-bg-warning",
      "badge text-bg-secondary"
    )
    shiny::tags$span(class = cls, tools::toTitleCase(p))
  }
  confidence_badge <- function(c) {
    cls <- switch(c,
      high = "badge text-bg-success",
      moderate = "badge text-bg-warning",
      low = "badge text-bg-danger",
      "badge text-bg-secondary"
    )
    shiny::tags$span(class = cls, tools::toTitleCase(c))
  }

  no_target <- is.na(row$to_code)
  no_source <- is.na(row$from_code)

  needs_statistical_warning <- row$relation_type %in% c("split", "merged", "complex")

  shiny::tagList(
    shiny::tags$div(
      class = "row mb-3",
      shiny::tags$div(
        class = "col-sm-5",
        shiny::tags$h6(paste("Previous classification (", row$from_version, ")", sep = "")),
        if (no_source) {
          shiny::tags$p(class = "text-muted", "(no prior counterpart -- new in this edition)")
        } else {
          shiny::tagList(
            shiny::tags$p(shiny::tags$code(row$from_code), " ", row$from_label),
            shiny::tags$p(class = "text-muted small", row$from_level)
          )
        }
      ),
      shiny::tags$div(class = "col-sm-2 text-center align-self-center", shiny::tags$span(class = "fs-4", "→")),
      shiny::tags$div(
        class = "col-sm-5",
        shiny::tags$h6(paste("Related classification (", row$to_version, ")", sep = "")),
        if (no_target) {
          shiny::tags$p(class = "text-muted", "(no related category -- discontinued/absorbed)")
        } else {
          shiny::tagList(
            shiny::tags$p(shiny::tags$code(row$to_code), " ", row$to_label),
            shiny::tags$p(class = "text-muted small", row$to_level)
          )
        }
      )
    ),
    shiny::tags$dl(
      class = "row mb-2",
      shiny::tags$dt(class = "col-sm-3", "Relationship"), shiny::tags$dd(class = "col-sm-9", tools::toTitleCase(row$relation_type)),
      shiny::tags$dt(class = "col-sm-3", "Provenance"), shiny::tags$dd(class = "col-sm-9", provenance_badge(row$provenance)),
      shiny::tags$dt(class = "col-sm-3", "Confidence"), shiny::tags$dd(class = "col-sm-9", confidence_badge(row$confidence)),
      shiny::tags$dt(class = "col-sm-3", "Evidence"),
      shiny::tags$dd(class = "col-sm-9", if (is.na(row$evidence)) shiny::tags$em("Not recorded") else row$evidence)
    ),
    if (needs_statistical_warning) {
      shiny::tags$div(class = "alert alert-warning small", role = "alert", CORRESPONDENCE_STATISTICAL_WARNING)
    }
  )
}

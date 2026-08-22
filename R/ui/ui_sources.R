# About / Data Sources screen. Presentation only: lists the classification
# systems from the registry (source of truth: R/registry.R) and renders the
# PSIC Revision 5 provenance note from docs/DATA_SOURCES.md so the app and
# the docs never drift out of sync with two copies of the same text.
sources_ui <- function() {
  reg <- classification_registry()

  system_rows <- lapply(seq_len(nrow(reg)), function(i) {
    shiny::tags$tr(
      shiny::tags$td(reg$short_name[[i]]),
      shiny::tags$td(reg$display_name[[i]]),
      shiny::tags$td(reg$source[[i]]),
      shiny::tags$td(shiny::tags$a(href = reg$source_url[[i]], target = "_blank", rel = "noopener", reg$source_url[[i]]))
    )
  })

  data_sources_md <- if (file.exists("docs/DATA_SOURCES.md")) {
    shiny::markdown(paste(readLines("docs/DATA_SOURCES.md", warn = FALSE), collapse = "\n"))
  } else {
    shiny::tags$p(class = "text-muted", "docs/DATA_SOURCES.md not found.")
  }

  shiny::tagList(
    bslib::card(
      bslib::card_header("Classification systems and sources"),
      bslib::card_body(
        shiny::tags$table(
          class = "table table-sm",
          shiny::tags$thead(
            shiny::tags$tr(
              shiny::tags$th("System"), shiny::tags$th("Name"),
              shiny::tags$th("Source"), shiny::tags$th("Reference")
            )
          ),
          shiny::tags$tbody(system_rows)
        ),
        shiny::tags$p(
          class = "text-muted small mb-0",
          "PSA is the authoritative classification source. Package data (phscs, psgc) and the PSIC ",
          "Revision 5 normalization pipeline are software/data access mechanisms, not the issuing authority."
        )
      )
    ),
    bslib::card(
      bslib::card_header("PSIC Revision 5 (2026) provenance"),
      bslib::card_body(data_sources_md)
    )
  )
}

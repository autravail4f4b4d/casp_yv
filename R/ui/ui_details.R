# Presentation helpers for the "Selected entry" detail card and the
# current/archived status badge. These functions only format values already
# produced by the canonical classification schema (R/schema.R) -- they
# perform no classification lookup, search, or data transformation of their
# own, so Claude Design can restyle them freely without touching
# R/repository.R, R/search.R, or the adapters.

#' Render a small current/archived status badge (ArchiveBadge component).
#'
#' @param status character(1). "current" or "archived".
status_badge <- function(status) {
  cls <- if (identical(status, "current")) "badge text-bg-success" else "badge text-bg-secondary"
  label <- if (identical(status, "current")) "Current" else "Archived reference"
  shiny::tags$span(class = cls, label)
}

#' Render the "Selected entry" detail card body for one canonical row.
#'
#' @param entry A one-row tibble with `CLASSIFICATION_SCHEMA_COLUMNS`, or a
#'   zero-row tibble / NULL when nothing is selected.
entry_detail_ui <- function(entry) {
  if (is.null(entry) || nrow(entry) == 0L) {
    return(shiny::tags$p(class = "text-muted", "Select a row in the results table to see its details."))
  }

  shiny::tagList(
    shiny::tags$dl(
      class = "row mb-0",
      shiny::tags$dt(class = "col-sm-3", "Code"), shiny::tags$dd(class = "col-sm-9", entry$code),
      shiny::tags$dt(class = "col-sm-3", "Label"), shiny::tags$dd(class = "col-sm-9", entry$label),
      shiny::tags$dt(class = "col-sm-3", "Description"),
      shiny::tags$dd(class = "col-sm-9", if (is.na(entry$description)) shiny::tags$em("Not available") else entry$description),
      shiny::tags$dt(class = "col-sm-3", "System"), shiny::tags$dd(class = "col-sm-9", toupper(entry$system)),
      shiny::tags$dt(class = "col-sm-3", "Edition / release"), shiny::tags$dd(class = "col-sm-9", entry$version),
      shiny::tags$dt(class = "col-sm-3", "Level"), shiny::tags$dd(class = "col-sm-9", entry$level),
      shiny::tags$dt(class = "col-sm-3", "Status"), shiny::tags$dd(class = "col-sm-9", status_badge(entry$status)),
      shiny::tags$dt(class = "col-sm-3", "Source"),
      shiny::tags$dd(
        class = "col-sm-9",
        entry$source,
        if (!is.na(entry$source_url)) shiny::tags$a(href = entry$source_url, target = "_blank", rel = "noopener", " (source)")
      )
    )
  )
}

# Presentation helpers for the classification detail panel and the
# current/archived status badge.
#
# PRESENTATION ONLY. These functions format values already produced by the
# canonical classification schema (R/schema.R) -- no lookup, no search, no
# data transformation of their own.
#
# The status vocabulary defined here is the SINGLE vocabulary used across
# Search, PSOC + PSIC, Compare Editions, Sources and the RM verified card,
# so no surface can imply a different authority than another
# (HANDOFF §8).

#' Render a current/archived status badge (ArchiveBadge component).
#'
#' Status is always carried by visible TEXT as well as color
#' (docs/UI_CONTRACT.md §10) -- "Current" is accent-filled, "Archived" is
#' outlined ochre and never filled.
#'
#' @param status character(1). "current" or "archived".
#' @param prefix character(1) or NULL. Optional leading text, e.g. an
#'   edition id, rendered as "2019 · Archived".
status_badge <- function(status, prefix = NULL) {
  is_current <- identical(status, "current")
  cls <- if (is_current) "psa-tag psa-tag-current" else "psa-tag psa-tag-archived"
  label <- if (is_current) "Current" else "Archived"
  text <- if (is.null(prefix) || !nzchar(prefix)) label else paste(prefix, "·", label)
  shiny::tags$span(class = cls, text)
}

#' Compact one-line provenance (HANDOFF §10).
#'
#' Issuing authority + short citation + external link. Full methodology
#' belongs on the Sources tab only; inline stays to one line plus a link.
#' PSA is named as the issuing authority -- never phscs, psgc or RM.
source_line_ui <- function(entry) {
  shiny::tags$div(
    class = "psa-source-line",
    paste0(entry$source, " — ", toupper(entry$system), " ", entry$version, "."),
    if (!is.na(entry$source_url)) {
      shiny::tagList(
        " ",
        shiny::tags$a(
          href = entry$source_url,
          target = "_blank",
          rel = "noopener",
          "Source ↗"
        )
      )
    }
  )
}

#' Render the "Selected entry" detail body for one canonical row.
#'
#' @param entry A one-row tibble with `CLASSIFICATION_SCHEMA_COLUMNS`, or a
#'   zero-row tibble / NULL when nothing is selected.
entry_detail_ui <- function(entry) {
  if (is.null(entry) || nrow(entry) == 0L) {
    return(shiny::tags$p(
      class = "text-muted",
      "Select a row in the results table to see its details."
    ))
  }

  hierarchy <- if (!is.na(entry$parent_code)) {
    shiny::tags$div(
      class = "psa-detail-meta",
      shiny::tags$span(class = "mono", entry$parent_code),
      " → ",
      shiny::tags$span(class = "mono", entry$code)
    )
  }

  description <- if (!is.na(entry$description)) {
    shiny::tags$div(class = "psa-detail-meta", entry$description)
  }

  shiny::tagList(
    shiny::tags$div(
      class = "psa-eyebrow",
      paste(toupper(entry$system), "·", entry$version, "·", entry$level)
    ),
    shiny::tags$div(class = "mono psa-detail-code", entry$code),
    shiny::tags$h3(class = "psa-detail-title", entry$label),
    hierarchy,
    description,
    shiny::tags$div(
      style = "margin-top: 14px;",
      status_badge(entry$status)
    ),
    source_line_ui(entry)
  )
}

#' Verified-result card (HANDOFF §7).
#'
#' The SAME component RM uses to present a tool-verified code and Search
#' uses for a selected entry, so RM cannot visually claim more authority
#' than Search.
#'
#' PRESENTATION ONLY: this renders a result that has already been verified
#' upstream. The grounding rule itself -- that no code reaches a user
#' without a real tool lookup behind it -- lives in `R/assistant/*` and is
#' deliberately out of scope for this file.
verified_result_card <- function(entry) {
  if (is.null(entry) || nrow(entry) == 0L) {
    return(NULL)
  }

  shiny::tags$div(
    class = "psa-verified-card",
    lucide_icon("circle-check", 20),
    shiny::tags$div(
      shiny::tags$div(
        class = "psa-eyebrow",
        paste("Verified ·", toupper(entry$system), entry$version)
      ),
      shiny::tags$div(class = "mono psa-verified-code", entry$code),
      shiny::tags$div(style = "font-size: 14px; margin-top: 2px;", entry$label),
      shiny::tags$div(
        style = "margin-top: 8px;",
        status_badge(entry$status)
      )
    )
  )
}

# PSOC + PSIC screen (main_nav value "dual_search").
#
# TWO FULLY INDEPENDENT SEARCHES (spec section 4). Each side owns its own
# query input, its own edition selector, its own results table, its own
# result count and its own selection/detail panel. Typing on one side can
# never change the other side's query, results or selection, and clearing
# one side leaves the other side completely intact.
#
# PRESENTATION ONLY. All ranking, level handling and version validation live
# in R/search.R and R/repository.R; the pure helpers at the bottom of this
# file are thin, side-effect-free wrappers over those canonical services so
# the independence property can be asserted without launching Shiny.
#
# A PSOC code NEVER implies a PSIC code and vice versa. Nothing in this file
# derives one side's state from the other's -- the two panels share no
# reactive, no input and no mutable state.
#
# Input IDs (docs/UI_CONTRACT.md):
#   dual_search_psoc_query    dual_search_psic_query
#   dual_search_psoc_version  dual_search_psic_version
# Output IDs:
#   dual_search_psoc_state    dual_search_psic_state
#   dual_search_psoc_count    dual_search_psic_count
#   dual_search_psoc_results  dual_search_psic_results
#   dual_search_psoc_detail   dual_search_psic_detail
#
# The shared `dual_search_query` input is REMOVED; a single query for two
# different classification systems is exactly the coupling this screen must
# not have.

# --- Per-side copy -----------------------------------------------------
#
# Mandatory strings (spec section 4). The dash in the two headings is an em
# dash, written as the \u2014 escape so the rendered text is byte-for-byte
# correct regardless of the encoding this file happens to be read with.
DUAL_SEARCH_SIDES <- list(
  psoc = list(
    system = "psoc",
    heading = "PSOC \u2014 Occupation",
    helper = "Describes what a person does.",
    placeholder = "Search an occupation or PSOC code",
    query_label = "Search PSOC occupations",
    version_label = "PSOC edition"
  ),
  psic = list(
    system = "psic",
    heading = "PSIC \u2014 Industry",
    helper = "Describes the economic activity of the establishment or business.",
    placeholder = "Search an industry or PSIC code",
    query_label = "Search PSIC industries",
    version_label = "PSIC edition"
  )
)

#' Build a Shiny input/output id for one side of the dual screen.
#'
#' Pure. The ONLY place these ids are assembled, so a psoc id can never be
#' accidentally emitted inside the psic panel.
#'
#' @param system_id character(1). "psoc" or "psic".
#' @param suffix character(1). e.g. "query", "results", "detail".
dual_search_id <- function(system_id, suffix) {
  paste0("dual_search_", system_id, "_", suffix)
}

#' Build ONE independent search panel.
#'
#' Pure: returns a tag object, reads nothing, mutates nothing. The panel is
#' a `<section>` labelled by its own heading, so each side is its own
#' landmark with a distinct accessible name.
#'
#' Every input carries a real `<label>` element in the DOM (visually hidden
#' by CSS where the design does not show it) -- never placeholder-only
#' labelling.
#'
#' @param system_id character(1). "psoc" or "psic".
dual_search_panel_ui <- function(system_id) {
  side <- DUAL_SEARCH_SIDES[[system_id]]
  if (is.null(side)) {
    stop("dual_search_panel_ui(): unknown system_id '", system_id, "'")
  }
  heading_id <- paste0("dual-search-", system_id, "-heading")

  shiny::tags$section(
    class = paste0("psa-dual-panel psa-dual-panel--", system_id),
    `aria-labelledby` = heading_id,

    shiny::tags$div(
      class = "psa-dual-panel-head",
      shiny::tags$h3(
        id = heading_id,
        class = "psa-dual-panel-title",
        side$heading
      ),
      shiny::tags$div(
        class = "psa-dual-edition",
        shiny::selectInput(
          dual_search_id(system_id, "version"),
          side$version_label,
          choices = NULL,
          width = "100%"
        )
      )
    ),

    shiny::tags$p(class = "psa-dual-panel-help", side$helper),

    shiny::tags$div(
      class = "psa-dual-field",
      lucide_icon("search", 20),
      shiny::textInput(
        dual_search_id(system_id, "query"),
        side$query_label,
        placeholder = side$placeholder,
        width = "100%"
      )
    ),

    shiny::tags$div(
      class = "psa-dual-count",
      shiny::uiOutput(dual_search_id(system_id, "count"))
    ),
    shiny::tags$div(
      class = "psa-dual-state",
      shiny::uiOutput(dual_search_id(system_id, "state"))
    ),
    shiny::tags$div(
      class = "psa-dual-results",
      DT::DTOutput(dual_search_id(system_id, "results"))
    ),

    shiny::tags$div(
      class = "psa-dual-detail",
      shiny::tags$h4(class = "psa-dual-detail-head", "Selected entry"),
      shiny::uiOutput(dual_search_id(system_id, "detail"))
    )
  )
}

#' The PSOC + PSIC screen.
#'
#' Pure: builds the shell only. Two independent panels side by side on
#' desktop, stacked at tablet/mobile (see .psa-dual-grid in www/app.css).
dual_search_ui <- function() {
  shiny::tagList(
    shiny::tags$div(
      class = "psa-dual",

      shiny::tags$div(
        class = "psa-hero psa-dual-hero",
        shiny::tags$h2(class = "psa-dual-title", "PSOC + PSIC"),
        shiny::tags$p(
          class = "psa-dual-intro",
          "Two separate searches. Search an occupation on one side and an ",
          "industry on the other \u2014 each side keeps its own query, its own ",
          "results and its own selection. ",
          shiny::tags$strong("They never determine each other.")
        )
      ),

      shiny::tags$div(
        class = "psa-dual-grid",
        dual_search_panel_ui("psoc"),
        dual_search_panel_ui("psic")
      ),

      shiny::tags$p(
        class = "psa-dual-note",
        shiny::tags$strong(
          "Occupations and industries are not the same classification. "
        ),
        "A PSOC code never implies an equivalent PSIC code, and vice versa ",
        "\u2014 they describe different things (what a person does vs. what ",
        "an establishment does)."
      )
    )
  )
}

# --- Pure per-side state derivation ------------------------------------
#
# These are the functions the server calls once PER SIDE. They are ordinary
# pure functions: every value they need arrives as an argument, they hold no
# state between calls, they never assign into an enclosing environment
# (no `<<-`) and they never reference the other side. That is what makes the
# two searches independent by construction rather than by convention, and it
# is directly assertable in tests/testthat/test-dual-search-independence.R
# without launching Shiny.

#' Run ONE side's search through the canonical count-aware service.
#'
#' Does not duplicate any search logic -- it is a named, testable seam over
#' `search_classification_result()`.
#'
#' @param system character(1). "psoc" or "psic".
#' @param version character(1). Edition selected on THAT side only.
#' @param query character(1) or NULL. That side's query only.
#' @param limit integer(1). Row cap for that side only.
#'
#' @return The canonical count-aware result list:
#'   `list(data, total_matches, returned_count, limit, is_truncated)`.
dual_search_side_result <- function(system, version, query, limit = 100) {
  search_classification_result(
    system = system,
    version = version,
    query = query,
    level = NULL,
    limit = limit
  )
}

#' Derive ONE side's selected row from that side's own result + selection.
#'
#' @param result A count-aware result list (or a plain data frame).
#' @param rows_selected Integer row indices from
#'   `input$dual_search_<sys>_results_rows_selected`, or NULL.
#'
#' @return A zero- or one-row data frame. Never NULL, never errors on an
#'   out-of-range or stale index (which happens for one round-trip after a
#'   query change).
dual_search_side_selection <- function(result, rows_selected) {
  d <- if (is.data.frame(result)) result else result$data
  if (is.null(d)) {
    return(NULL)
  }
  empty <- d[0, , drop = FALSE]
  if (is.null(rows_selected) || length(rows_selected) == 0L) {
    return(empty)
  }
  idx <- rows_selected[!is.na(rows_selected)]
  idx <- idx[idx >= 1L & idx <= nrow(d)]
  if (length(idx) == 0L) {
    return(empty)
  }
  d[idx, , drop = FALSE]
}

#' The result-count line for ONE side.
#'
#' Delegates the wording entirely to the canonical `format_result_count()`
#' so the dual screen can never print a different count sentence than
#' Search does.
#'
#' @param result A count-aware result list.
#' @param query character(1) or NULL. That side's query only.
dual_search_side_count_text <- function(result, query) {
  q <- if (is.null(query) || length(query) == 0L || is.na(query[[1]])) "" else query[[1]]
  format_result_count(
    total_matches  = result$total_matches,
    returned_count = result$returned_count,
    is_truncated   = result$is_truncated,
    limit          = result$limit,
    is_browsing    = !nzchar(trimws(q))
  )
}

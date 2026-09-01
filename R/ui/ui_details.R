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

# ---------------------------------------------------------------------
# UI-03 — detail and comparison dialogs
#
# Selected PSOC/PSIC details used to sit in a large permanent block BELOW a
# long results table, where human UAT found them easy to miss. They now
# live in a dialog reached by an explicit "View details" action, and the
# below-table block is reduced to a one-line selection summary that carries
# that action (handoff UI-03).
#
# Everything here is presentation over a canonical row that a service
# already returned. No lookup, no ranking, no derivation of one system's
# code from another's.
# ---------------------------------------------------------------------

# Verbatim from the handoff (UI-03). This sentence is the whole reason the
# comparison view is allowed to exist: two selected codes shown side by
# side must never read as a mapping between them.
PSOC_PSIC_INDEPENDENCE_NOTE <-
  "A PSOC code does not imply an equivalent PSIC code, and vice versa."

.detail_fact <- function(term, value) {
  if (is.null(value) || length(value) == 0L || is.na(value[[1]]) ||
      !nzchar(as.character(value[[1]]))) {
    return(NULL)
  }
  shiny::tagList(shiny::tags$dt(term), shiny::tags$dd(value))
}

# "Classification hierarchy" for the dialog: the published ancestor chain
# where the edition genuinely has one, otherwise the single parent_code the
# schema carries. Never a constructed path.
.detail_hierarchy_ui <- function(entry) {
  chain <- character(0)
  eligible <- tryCatch(
    hierarchy_is_eligible(entry$system, entry$version),
    error = function(e) FALSE
  )
  if (isTRUE(eligible)) {
    chain <- tryCatch(
      hierarchy_ancestors(entry$system, entry$version, entry$code),
      error = function(e) character(0)
    )
  }
  if (length(chain) == 0L) {
    if (is.na(entry$parent_code)) {
      return(NULL)
    }
    chain <- entry$parent_code
  }
  shiny::tags$div(
    class = "psa-hierarchy__breadcrumb",
    paste(chain, collapse = " › "),
    " › ",
    shiny::tags$strong(entry$code)
  )
}

#' The shared detail body used by the single-record dialog and by each
#' column of the comparison dialog.
entry_detail_body_ui <- function(entry) {
  if (is.null(entry) || nrow(entry) == 0L) {
    return(psa_dialog_empty_ui("No record selected."))
  }
  entry <- entry[1, , drop = FALSE]

  shiny::tagList(
    shiny::tags$div(class = "mono psa-detail-code", entry$code),
    shiny::tags$h3(class = "psa-detail-title", entry$label),
    shiny::tags$div(
      style = "margin-top: 8px;",
      status_badge(entry$status, prefix = release_display_label(entry$version))
    ),
    shiny::tags$dl(
      class = "psa-detail-dialog__facts",
      .detail_fact("Level", level_display_label(entry$system, entry$level)),
      .detail_fact("Description", entry$description)
    ),
    shiny::tags$div(
      class = "psa-detail-dialog__hierarchy",
      shiny::tags$dl(
        class = "psa-detail-dialog__facts",
        shiny::tags$dt("Classification hierarchy")
      ),
      .detail_hierarchy_ui(entry) %||%
        shiny::tags$p(class = "text-muted small", "Top-level entry.")
    ),
    source_line_ui(entry)
  )
}

# "PSOC 2022 — Occupation details" / "PSIC 2026 — Industry details".
# The kind word is fixed per system so the dialog can never describe an
# occupation as an industry.
.DETAIL_DIALOG_KIND <- c(psoc = "Occupation details", psic = "Industry details")

.detail_dialog_title <- function(entry) {
  kind <- .DETAIL_DIALOG_KIND[[entry$system]]
  if (is.null(kind) || is.na(kind)) {
    kind <- "Classification details"
  }
  paste0(
    toupper(entry$system), " ", release_display_label(entry$version),
    " — ", kind
  )
}

#' Single-record detail dialog (UI-03).
#'
#' @param entry A one-row canonical tibble.
#' @param view_input_id character(1) or NULL. When supplied, a
#'   "View in Search" action is added to the footer.
entry_detail_dialog_ui <- function(entry, view_input_id = NULL) {
  if (is.null(entry) || nrow(entry) == 0L) {
    return(psa_dialog_ui(
      id = "entry-detail",
      title = "No record selected",
      body = psa_dialog_empty_ui(
        "Select a row in the results table, then choose View details."
      ),
      close_label = "Close details"
    ))
  }
  entry <- entry[1, , drop = FALSE]

  psa_dialog_ui(
    id = paste0("entry-detail-", entry$system),
    variant = "modal",
    size = "lg",
    eyebrow = paste(toupper(entry$system), release_display_label(entry$version)),
    title = .detail_dialog_title(entry),
    close_label = "Close details",
    body = entry_detail_body_ui(entry),
    footer = shiny::tagList(
      psa_dialog_close_button(),
      if (!is.null(view_input_id)) {
        psa_dialog_action_button(view_input_id, "View in Search")
      }
    )
  )
}

#' PSOC + PSIC comparison dialog (UI-03).
#'
#' Desktop shows PSOC left / PSIC right; the same markup stacks at <=768px
#' (www/ui-dialog.css) rather than squeezing two columns onto a phone.
#'
#' The independence sentence is ALWAYS rendered, including in the
#' incomplete-selection state -- there is no path through this function
#' that shows two codes together without it.
entry_comparison_dialog_ui <- function(psoc_entry, psic_entry) {
  has_psoc <- !is.null(psoc_entry) && nrow(psoc_entry) > 0L
  has_psic <- !is.null(psic_entry) && nrow(psic_entry) > 0L

  body <- if (!has_psoc || !has_psic) {
    shiny::tagList(
      psa_dialog_empty_ui(paste(
        "Select one PSOC row and one PSIC row to compare them side by side.",
        if (has_psoc) "A PSIC row is still needed."
        else if (has_psic) "A PSOC row is still needed."
        else ""
      )),
      shiny::tags$p(class = "psa-compare-note", PSOC_PSIC_INDEPENDENCE_NOTE)
    )
  } else {
    shiny::tagList(
      shiny::tags$div(
        class = "psa-compare-grid",
        shiny::tags$section(
          class = "psa-compare-col psa-compare-col--psoc psa-liquid-glass psa-liquid-glass--quiet",
          `aria-label` = "PSOC occupation details",
          shiny::tags$h4(
            class = "psa-compare-col__head",
            "PSOC — occupation (what the person does)"
          ),
          entry_detail_body_ui(psoc_entry)
        ),
        shiny::tags$section(
          class = "psa-compare-col psa-compare-col--psic psa-liquid-glass psa-liquid-glass--quiet",
          `aria-label` = "PSIC industry details",
          shiny::tags$h4(
            class = "psa-compare-col__head",
            "PSIC — industry (what the establishment does)"
          ),
          entry_detail_body_ui(psic_entry)
        )
      ),
      shiny::tags$p(class = "psa-compare-note", PSOC_PSIC_INDEPENDENCE_NOTE)
    )
  }

  psa_dialog_ui(
    id = "entry-comparison",
    variant = "modal",
    size = "xl",
    eyebrow = "PSOC + PSIC",
    title = "Compare selected details",
    description = "Two separate classifications, shown together for reference only.",
    close_label = "Close the comparison",
    body = body,
    footer = psa_dialog_close_button()
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

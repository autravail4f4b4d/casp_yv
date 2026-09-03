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

  # DEFINITION PREVIEW (W3). The first official definition paragraph only,
  # trimmed -- enough to tell the reader whether this is the right record
  # without turning the selected-entry card into the reference itself. The
  # full definition, tasks and examples live in View details.
  #
  # It reads the same verified descriptive record the dialog does, and it
  # is nothing to do with retrieval: no descriptive text is indexed, ranked
  # or matched against anywhere.
  preview <- psoc_descriptive_preview(entry)

  shiny::tagList(
    shiny::tags$div(
      class = "psa-eyebrow",
      paste(toupper(entry$system), "·", entry$version, "·", entry$level)
    ),
    shiny::tags$div(class = "mono psa-detail-code", entry$code),
    shiny::tags$h3(class = "psa-detail-title", entry$label),
    hierarchy,
    description,
    if (!is.null(preview)) {
      shiny::tags$p(class = "psa-detail-preview", preview)
    },
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
      # HIERARCHY STAYS CANONICAL. The descriptive artifact carries its own
      # parent ids, and they are deliberately not used here: the repository
      # is the authority on structure, and the descriptive layer is the
      # authority on nothing at all.
      .detail_hierarchy_ui(entry) %||%
        shiny::tags$p(class = "text-muted small", "Top-level entry."),
    ),
    # OFFICIAL DESCRIPTIVE SECTIONS (PSOC 2022). Rendered only for a
    # verified PSOC record that the artifact actually describes; every
    # other system, edition or undescribed code renders nothing here and
    # the dialog looks exactly as it did before.
    psoc_descriptive_sections_ui(entry),
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

#' The coding check shown beneath the two records (UAT-UI-03).
#'
#' WHAT THIS IS FOR. A coding processor holding one PSOC and one PSIC
#' selection needs to know which checks the application HAS made and which
#' it cannot make. It states the separate-concept safeguard, whether either
#' record is archived, and the detail level of each.
#'
#' WHAT IT MUST NEVER SAY. That the pair is correct, equivalent, matched or
#' consistent. Nothing in this application knows the establishment or the
#' person, so nothing here can validate the pair against them -- and a
#' green tick on an unvalidated pair is precisely the false assurance a
#' statistical utility must not give.
entry_coding_check_ui <- function(psoc_entry, psic_entry) {
  archived <- character(0)
  for (e in list(psoc_entry, psic_entry)) {
    st <- as.character(e$status[[1]])
    if (!is.na(st) && !identical(tolower(st), "current")) {
      archived <- c(archived, sprintf("%s %s is from an archived edition (%s)",
                                      toupper(e$system[[1]]), e$code[[1]],
                                      release_display_label(e$version[[1]])))
    }
  }

  item <- function(...) shiny::tags$li(class = "psa-coding-check__item", ...)

  shiny::tags$section(
    class = "psa-coding-check",
    `aria-label` = "Coding check",
    shiny::tags$h4(class = "psa-coding-check__head", "Coding check"),
    shiny::tags$ul(
      class = "psa-coding-check__list",
      item(
        shiny::tags$strong("Separate concepts. "),
        PSOC_PSIC_INDEPENDENCE_NOTE
      ),
      item(
        shiny::tags$strong("Edition status. "),
        if (length(archived) == 0L) {
          "Both records are from the current edition of their own system."
        } else {
          paste0(paste(archived, collapse = "; "),
                 ". An archived code is a historical reference, not a current assignment.")
        }
      ),
      item(
        shiny::tags$strong("Detail level. "),
        sprintf("PSOC is coded at %s; PSIC is coded at %s.",
                level_display_label("psoc", as.character(psoc_entry$level[[1]])),
                level_display_label("psic", as.character(psic_entry$level[[1]])))
      )
    ),
    shiny::tags$p(
      class = "psa-coding-check__limit",
      shiny::tags$strong("Not checked. "),
      "This application has not been told who the person is or what the ",
      "establishment does, so it cannot confirm that either code is right ",
      "for them, and it does not claim the pair is correct or equivalent."
    )
  )
}

#' PSOC + PSIC coding-pair review dialog (UI-03, reworked by UAT-UI-03).
#'
#' Renamed from "Compare selected details": the processor-facing task is a
#' REVIEW of two selections, not a comparison of two things that might be
#' the same. The old wording invited exactly the reading the independence
#' safeguard exists to prevent.
#'
#' Desktop shows PSOC left / PSIC right; the same markup stacks at <=768px
#' (www/ui-dialog.css) rather than squeezing two columns onto a phone.
#'
#' The independence sentence is ALWAYS rendered, including in the
#' incomplete-selection state -- there is no path through this function
#' that shows two codes together without it.
#'
#' @param ask_rm logical(1). Whether to offer the RM review action. FALSE
#'   where the deployment has no working assistant configuration.
entry_comparison_dialog_ui <- function(psoc_entry, psic_entry, ask_rm = TRUE) {
  has_psoc <- !is.null(psoc_entry) && nrow(psoc_entry) > 0L
  has_psic <- !is.null(psic_entry) && nrow(psic_entry) > 0L

  body <- if (!has_psoc || !has_psic) {
    shiny::tagList(
      psa_dialog_empty_ui(paste(
        "Select one PSOC row and one PSIC row to review them as a coding pair.",
        if (has_psoc) "A PSIC row is still needed."
        else if (has_psic) "A PSOC row is still needed."
        else ""
      )),
      shiny::tags$p(class = "psa-compare-note", PSOC_PSIC_INDEPENDENCE_NOTE)
    )
  } else {
    shiny::tagList(
      # States what the two systems ARE before showing either, so the
      # reader meets the distinction before the codes.
      shiny::tags$p(
        class = "psa-compare-intro",
        shiny::tags$strong("PSOC"), " is the occupation — the kind of work the ",
        "person does. ", shiny::tags$strong("PSIC"), " is the establishment's ",
        "principal economic activity. One does not imply the other."
      ),
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
      entry_coding_check_ui(psoc_entry, psic_entry)
    )
  }

  footer <- if (has_psoc && has_psic) {
    shiny::tagList(
      psa_dialog_close_button(),
      # Change PSOC / Change PSIC close the dialog and return the processor
      # to the side they need to re-pick. No queue, no adjudication: this
      # pass reviews one pair.
      psa_dialog_action_button(DUAL_SEARCH_CHANGE_PSOC_INPUT, "Change PSOC",
                               class = "psa-dialog__btn--ghost"),
      psa_dialog_action_button(DUAL_SEARCH_CHANGE_PSIC_INPUT, "Change PSIC",
                               class = "psa-dialog__btn--ghost"),
      if (isTRUE(ask_rm)) {
        psa_dialog_action_button(DUAL_SEARCH_ASK_RM_INPUT,
                                 "Ask RM to review this coding pair")
      }
    )
  } else {
    psa_dialog_close_button()
  }

  psa_dialog_ui(
    id = "entry-comparison",
    variant = "modal",
    size = "xl",
    eyebrow = "PSOC + PSIC",
    title = "Review coding pair",
    description = "Two separate classifications, reviewed together for coding.",
    close_label = "Close the coding pair review",
    body = body,
    footer = footer
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

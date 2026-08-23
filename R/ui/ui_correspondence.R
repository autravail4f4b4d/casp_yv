# Compare Editions screen (main_nav value "correspondence", relabelled from
# "Compare PSIC Editions" per HANDOFF §2) — bidirectional PSIC 2019 <->
# Revision 5 (2026) correspondence.
#
# PRESENTATION ONLY. All matching, scoring, cardinality and provenance
# logic lives in R/correspondence/*.R.
#
# Stable IDs, unchanged: correspondence_direction, correspondence_query,
# correspondence_results, correspondence_detail.
#
# Every correspondence state is preserved and must remain visually
# distinct: one-to-one, split, merged, complex, reverse lookup, no match,
# provenance, qualitative confidence, and the statistical-safety warning.
# A split or merge is NEVER flattened into a false one-to-one relationship
# -- each target/source is listed separately in the relationship row.

correspondence_ui <- function() {
  shiny::tagList(
    shiny::tags$div(
      class = "psa-hero",
      style = "align-items: flex-start; padding-bottom: 8px;",
      shiny::tags$h2(
        style = "margin: 0 0 6px; font-size: 20px;",
        "Compare Editions"
      ),
      shiny::tags$p(
        class = "psa-dual-intro",
        "See how a PSIC 2019 code maps to Revision 5 (2026), or the reverse."
      )
    ),

    shiny::tags$div(
      style = "display: flex; align-items: flex-end; gap: 26px; flex-wrap: wrap; margin-bottom: 22px;",
      shiny::tags$div(
        style = "min-width: 260px;",
        shiny::selectInput(
          "correspondence_direction", "Direction",
          choices = c(
            "2019 PSIC → PSIC Revision 5 (2026)" = "2019-2026",
            "PSIC Revision 5 (2026) → 2019 PSIC" = "2026-2019"
          ),
          width = "100%"
        )
      ),
      shiny::tags$div(
        style = "flex: 1 1 auto; max-width: 380px;",
        shiny::textInput(
          "correspondence_query", "Search a code or title",
          placeholder = "e.g. a PSIC code, or part of a title",
          width = "100%"
        )
      )
    ),

    bslib::card(
      bslib::card_header("PSIC edition correspondence"),
      bslib::card_body(
        shiny::tags$p(
          class = "text-muted small",
          "Leave blank to browse. Each row is one relationship — a code ",
          "that split into several categories appears as several rows."
        ),
        DT::DTOutput("correspondence_results")
      )
    ),

    bslib::card(
      bslib::card_body(
        shiny::tags$div(
          class = "psa-detail-head",
          shiny::tags$h6("Relationship detail"),
          # Reserved layout slot (HANDOFF §12) -- inert placeholder, NOT a
          # control: a <span>, aria-hidden, not focusable, no cursor or
          # hover affordance.
          shiny::tags$span(
            class = "psa-askrm-reserved",
            `aria-hidden` = "true",
            shiny::tags$i(class = "ph ph-sparkle"),
            "Ask RM to explain this change"
          )
        ),
        shiny::uiOutput("correspondence_detail")
      )
    ),

    shiny::tags$p(
      class = "text-muted small mt-2",
      CORRESPONDENCE_STATISTICAL_WARNING
    )
  )
}

#' Provenance badge. Never color alone -- the level is always spelled out.
#'
#' As of this build no mapping in the shipped artifact is `official`; that
#' is a data fact enforced by tests, not a presentation choice.
provenance_badge <- function(p) {
  cls <- switch(p,
    official  = "psa-tag psa-tag-current",
    derived   = "psa-tag psa-tag-neutral",
    suggested = "psa-tag psa-tag-archived",
    "psa-tag psa-tag-neutral"
  )
  shiny::tags$span(class = cls, paste("Provenance:", tools::toTitleCase(p)))
}

#' Qualitative confidence badge. Ordinal, never a probability.
confidence_badge <- function(c) {
  cls <- switch(c,
    high     = "psa-tag psa-tag-current",
    moderate = "psa-tag psa-tag-neutral",
    low      = "psa-tag psa-tag-archived",
    "psa-tag psa-tag-neutral"
  )
  shiny::tags$span(class = cls, paste("Confidence:", tools::toTitleCase(c)))
}

#' One side of a relationship (source or target).
#'
#' A missing counterpart renders its explicit message rather than an empty
#' cell, and never a fabricated code (HANDOFF §9).
.correspondence_side <- function(code, label, level, version, missing_message) {
  if (is.na(code)) {
    return(shiny::tags$div(class = "psa-no-counterpart", missing_message))
  }
  shiny::tags$div(
    shiny::tags$span(class = "mono", style = "font-size: 17px;", code),
    shiny::tags$div(style = "font-size: 13px; margin-top: 3px;", label),
    shiny::tags$div(
      style = "margin-top: 6px;",
      status_badge(
        if (identical(version, "2026")) "current" else "archived",
        prefix = version
      )
    ),
    if (!is.na(level)) {
      shiny::tags$div(class = "text-muted small", style = "margin-top: 4px;", level)
    }
  )
}

#' Render one correspondence row's full detail.
#'
#' @param row A one-row tibble in the `get_psic_correspondence()` /
#'   `search_psic_correspondence()` from_*/to_* shape, or a zero-row/NULL
#'   value when nothing is selected.
correspondence_detail_ui <- function(row) {
  if (is.null(row) || nrow(row) == 0L) {
    return(shiny::tags$p(
      class = "text-muted",
      "Select a row in the results table to see its full relationship detail."
    ))
  }

  # Cardinality drives the arrow glyph so a split/merge is visually
  # distinguishable from a one-to-one at a glance.
  arrow_icon <- switch(row$relation_type,
    split   = "ph-arrows-split",
    merged  = "ph-arrows-merge",
    complex = "ph-arrows-split",
    "ph-arrows-left-right"
  )

  needs_statistical_warning <- row$relation_type %in% c("split", "merged", "complex")

  shiny::tagList(
    shiny::tags$div(
      class = "psa-corr-row",
      .correspondence_side(
        row$from_code, row$from_label, row$from_level, row$from_version,
        "(no prior counterpart — new in this edition)"
      ),
      shiny::tags$i(
        class = paste("ph", arrow_icon, "psa-corr-arrow"),
        `aria-hidden` = "true"
      ),
      .correspondence_side(
        row$to_code, row$to_label, row$to_level, row$to_version,
        "(no related category — discontinued/absorbed)"
      )
    ),

    shiny::tags$div(
      style = "display: flex; gap: 8px; flex-wrap: wrap; margin-top: 14px; align-items: center;",
      shiny::tags$span(
        class = "psa-tag psa-tag-neutral",
        paste("Relationship:", tools::toTitleCase(row$relation_type))
      ),
      # Provenance and confidence are always shown together, never one
      # without the other (docs/UI_CONTRACT.md §15).
      provenance_badge(row$provenance),
      confidence_badge(row$confidence)
    ),

    shiny::tags$div(
      class = "psa-source-line",
      shiny::tags$strong("Evidence: "),
      if (is.na(row$evidence)) shiny::tags$em("Not recorded") else row$evidence
    ),

    # Mandatory presentation, not optional styling: the verbatim
    # statistical-safety warning for every split / merged / complex
    # relationship.
    if (needs_statistical_warning) {
      shiny::tags$div(
        class = "psa-stat-warning",
        role = "note",
        shiny::tags$i(class = "ph ph-warning", `aria-hidden` = "true"),
        CORRESPONDENCE_STATISTICAL_WARNING
      )
    }
  )
}

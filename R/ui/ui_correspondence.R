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

# ---- Column terminology help (UI-POST-01) ---------------------------------
#
# The three column concepts readers conflate are kept explicitly distinct:
#
#   Relationship -> WHAT HAPPENED to the concept between editions
#                   (a structural change);
#   Provenance   -> WHERE THE EVIDENCE for the mapping came from
#                   (source / evidence);
#   Confidence   -> HOW STRONG the mapping is (certainty), ordinal only.
#
# The glossary keys below are the *vocabulary constants* from
# R/correspondence/schema.R, not re-typed literals. Nothing here restates a
# code, a title, a count or any other value that lives in the correspondence
# artifact, so the help text cannot drift away from the data. If the schema
# vocabulary ever changes, `.correspondence_gloss_rows()` drops the stale
# entry instead of describing a value the data no longer contains.

#' Vocabulary constant lookup that tolerates the UI file being sourced on
#' its own (tests, tooling) without R/correspondence/schema.R present.
.corr_vocab <- function(name, fallback = character()) {
  if (exists(name, inherits = TRUE)) as.character(get(name, inherits = TRUE)) else fallback
}

.CORRESPONDENCE_RELATION_GLOSS <- list(
  split        = list(label = "Split",
                      text  = "one old category became multiple new categories."),
  merged       = list(label = "Merged",
                      text  = "multiple old categories became one."),
  reclassified = list(label = "Reclassified",
                      text  = "the activity moved, or was recoded, to another category."),
  unchanged    = list(label = "Continued / unchanged",
                      text  = "the concept remains substantially the same.")
)

.CORRESPONDENCE_PROVENANCE_GLOSS <- list(
  official  = list(label = "Official",
                   text  = "the mapping is stated in a PSA-published correspondence document."),
  derived   = list(label = "Derived",
                   text  = paste(
                     "this application worked the mapping out from the published",
                     "classification structures. It is not a PSA ruling."
                   )),
  suggested = list(label = "Suggested",
                   text  = paste(
                     "a likely match this application proposes for review.",
                     "Treat it as a lead to check, not as an official mapping."
                   ))
)

.CORRESPONDENCE_CONFIDENCE_GLOSS <- list(
  high     = list(label = "High",     text = "the evidence for this mapping is strong."),
  moderate = list(label = "Moderate", text = "the evidence is partial; check it before relying on it."),
  low      = list(label = "Low",      text = "the evidence is weak; verify against the source classifications.")
)

#' Render a glossary as a <dl>, keeping only terms still in the schema
#' vocabulary so the help can never describe a retired value.
.correspondence_gloss_rows <- function(gloss, allowed) {
  keys <- if (length(allowed)) intersect(names(gloss), allowed) else names(gloss)
  shiny::tags$dl(
    class = "psa-term-help-list",
    lapply(keys, function(k) {
      shiny::tagList(
        shiny::tags$dt(gloss[[k]]$label),
        shiny::tags$dd(gloss[[k]]$text)
      )
    })
  )
}

#' One term's help, as a native <details>/<summary> disclosure.
#'
#' <summary> on purpose, and not a <div>, an <i>, or a CSS `:hover` tooltip:
#' it is a real focusable element in the tab order, it opens with Enter or
#' Space, it opens on tap on touch devices (where `:hover` never fires), and
#' the browser publishes its own expanded/collapsed state to assistive
#' technology without any JavaScript. No tooltip library is introduced.
#'
#' The body is referenced by BOTH `aria-controls` (which region this trigger
#' opens) and `aria-describedby` (so the definition is announced as the
#' trigger's description). `aria-expanded` is deliberately NOT hand-written:
#' the native element owns that state and a static attribute would go stale.
.correspondence_term_help <- function(id, term, intro, gloss, allowed) {
  body_id <- paste0(id, "-body")
  shiny::tags$details(
    class = "psa-term-help",
    id = id,
    shiny::tags$summary(
      class = "psa-term-help-trigger",
      `aria-label` = paste0("What does ", term, " mean?"),
      `aria-controls` = body_id,
      `aria-describedby` = body_id,
      shiny::tags$span(class = "psa-term-help-term", term),
      shiny::tags$i(class = "ph ph-question", `aria-hidden` = "true")
    ),
    shiny::tags$div(
      id = body_id,
      class = "psa-term-help-body",
      role = "note",
      shiny::tags$p(class = "psa-term-help-intro", intro),
      .correspondence_gloss_rows(gloss, allowed)
    )
  )
}

#' The "What these columns mean" legend that sits directly above the results
#' table. It is a sibling of DT::DTOutput("correspondence_results"), never a
#' wrapper around it, so the table's own sorting and filtering are untouched.
correspondence_column_legend <- function() {
  relationship <- .correspondence_term_help(
    "corr-help-relationship", "Relationship",
    "How a classification changed between editions.",
    .CORRESPONDENCE_RELATION_GLOSS,
    .corr_vocab("CORRESPONDENCE_RELATION_TYPES")
  )

  provenance <- .correspondence_term_help(
    "corr-help-provenance", "Provenance",
    paste(
      "Where the evidence for this correspondence came from — its source,",
      "not how strong it is."
    ),
    .CORRESPONDENCE_PROVENANCE_GLOSS,
    .corr_vocab("CORRESPONDENCE_PROVENANCE_VALUES")
  )

  confidence <- .correspondence_term_help(
    "corr-help-confidence", "Confidence",
    paste(
      "How strong or certain this particular mapping is. It is an ordinal",
      "rating, not a probability, and it is separate from where the evidence",
      "came from."
    ),
    .CORRESPONDENCE_CONFIDENCE_GLOSS,
    .corr_vocab("CORRESPONDENCE_CONFIDENCE_VALUES")
  )

  shiny::tags$div(
    class = "psa-col-legend",
    role = "group",
    `aria-label` = "What these columns mean",
    shiny::tags$span(class = "psa-col-legend-title", "What these columns mean"),
    relationship,
    provenance,
    confidence
  )
}

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
        # Terminology help for the table's Relationship / Provenance /
        # Confidence columns. A SIBLING of the DT output, never a wrapper:
        # the table object itself is untouched, so DT's own sorting and
        # filtering keep working exactly as before.
        correspondence_column_legend(),
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

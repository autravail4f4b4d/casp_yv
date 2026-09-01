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
                      text  = "the concept remains substantially the same."),
  # The four above are the ones readers ask about most, but they are not the
  # whole supported vocabulary. Every remaining value in
  # CORRESPONDENCE_RELATION_TYPES is glossed too, so the help can never be
  # silent about a value the table is actually showing.
  renamed      = list(label = "Renamed",
                      text  = "the same concept is kept under a different title."),
  new          = list(label = "New",
                      text  = "the category has no counterpart in the earlier edition."),
  discontinued = list(label = "Discontinued",
                      text  = "the category has no counterpart in the later edition."),
  complex      = list(label = "Complex",
                      text  = "several old and several new categories are involved together."),
  possible     = list(label = "Possible",
                      text  = "a plausible counterpart that still needs checking."),
  unknown      = list(label = "Unknown",
                      text  = "the relationship has not been established.")
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
  # "Medium", not "Moderate" (addendum section 7). The STORED value stays
  # `moderate` -- it is schema vocabulary asserted by
  # tests/testthat/test-correspondence-schema.R and nothing in the data
  # model moves. This `label` is the single source of display truth, so the
  # badge and this glossary can never disagree about the word.
  moderate = list(label = "Medium", text = "the evidence is partial; check it before relying on it."),
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
    class = "psa-term-help psa-liquid-glass psa-liquid-glass--flow",
    id = id,
    shiny::tags$summary(
      class = "psa-term-help-trigger",
      `aria-label` = paste0("What does ", term, " mean?"),
      `aria-controls` = body_id,
      `aria-describedby` = body_id,
      shiny::tags$span(class = "psa-term-help-term", term),
      lucide_icon("circle-help", 14)
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

# Id of the single collapsible help panel (UI-05). Named once so the
# trigger's aria-controls, the trigger's data-bs-target and the panel's own
# id can never drift apart.
.CORR_HOWTO_PANEL_ID <- "corr-howto-panel"

#' The statistical-use safeguard, in neutral/informational dress.
#'
#' Two sentences on purpose. The first is the instruction a statistician
#' needs in one line; the second is `CORRESPONDENCE_STATISTICAL_WARNING`,
#' the vocabulary constant from R/correspondence/schema.R, so the fuller
#' wording is never re-typed here and cannot drift from the rest of the app.
#'
#' `role="note"`, never `role="alert"`, and no error styling: a revised
#' classification is a normal outcome, not a failure.
correspondence_safeguard_note <- function() {
  shiny::tags$div(
    class = "psa-stat-warning psa-safeguard-note",
    role = "note",
    lucide_icon("info", 16),
    shiny::tags$span(
      shiny::tags$strong(
        "Correspondence metadata does not itself justify automatic ",
        "redistribution of historical statistical values."
      ),
      " ",
      .corr_vocab("CORRESPONDENCE_STATISTICAL_WARNING")
    )
  )
}

#' A small info button beside a table-header term, opening a short popover.
#'
#' A real `<button>` inside `bslib::popover()`, deliberately not a `:hover`
#' tooltip and not another disclosure: it is in the tab order, it opens on
#' Enter/Space, it opens on tap, and -- the point of UI-05 -- it adds no
#' vertical space to the page, so reading a column definition never pushes
#' the results table down.
.correspondence_column_tip <- function(term, gloss, allowed, intro) {
  bslib::popover(
    shiny::tags$button(
      type = "button",
      class = "psa-col-tip",
      `aria-label` = paste0("What does ", term, " mean?"),
      shiny::tags$span(class = "psa-col-tip-term", term),
      lucide_icon("circle-help", 13)
    ),
    shiny::tags$p(class = "psa-term-help-intro", intro),
    .correspondence_gloss_rows(gloss, allowed),
    title = term,
    placement = "bottom"
  )
}

#' The "How to read this table" help that sits directly above the results
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

  # UI-05. The three term disclosures no longer sit open-ended on the page:
  # they are the CONTENT of one collapsed panel behind a single compact
  # control, so the review workflow is never pushed down the page by help
  # text the reader did not ask for.
  #
  # The trigger is a Bootstrap 5 collapse button rather than a fourth
  # <details>: nesting a disclosure inside a disclosure reads badly to
  # screen-reader users, and Bootstrap keeps `aria-expanded` in sync on the
  # button itself. The three inner <details> keep their ids, their native
  # summary semantics and their programmatic associations exactly as before.
  shiny::tags$div(
    class = "psa-col-legend",
    role = "group",
    `aria-label` = "How to read this table",
    shiny::tags$div(
      class = "psa-col-legend-bar",
      shiny::tags$button(
        type = "button",
        class = "psa-howto-toggle",
        `data-bs-toggle` = "collapse",
        `data-bs-target` = paste0("#", .CORR_HOWTO_PANEL_ID),
        `aria-expanded` = "false",
        `aria-controls` = .CORR_HOWTO_PANEL_ID,
        lucide_icon("circle-help", 15),
        shiny::tags$span(class = "psa-col-legend-title", "How to read this table")
      ),
      # Column-level help, kept next to the table's own header row rather
      # than in a page-expanding panel. Each is a real <button> inside a
      # bslib popover, so it is keyboard-operable, works on touch, and adds
      # no vertical space to the page when closed.
      shiny::tags$span(
        class = "psa-col-tips",
        `aria-label` = "Column help",
        role = "group",
        .correspondence_column_tip(
          "Relationship", .CORRESPONDENCE_RELATION_GLOSS,
          .corr_vocab("CORRESPONDENCE_RELATION_TYPES"),
          "What changed between editions."
        ),
        # No Provenance column tip: Provenance is no longer a column in
        # this table (addendum section 4), and a column tip for a column
        # that does not exist is worse than none. The concept is still
        # documented in the expanded "How to read this table" panel below,
        # and the field is still carried in the data model.
        .correspondence_column_tip(
          "Confidence", .CORRESPONDENCE_CONFIDENCE_GLOSS,
          .corr_vocab("CORRESPONDENCE_CONFIDENCE_VALUES"),
          "How strong the supporting evidence is. An ordinal rating, not a probability."
        )
      )
    ),
    shiny::tags$div(
      id = .CORR_HOWTO_PANEL_ID,
      class = "collapse psa-howto-panel",
      shiny::tags$div(
        class = "psa-howto-panel-inner psa-liquid-glass psa-liquid-glass--flow",
        relationship,
        provenance,
        confidence,
        correspondence_safeguard_note()
      )
    )
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

    # FILTER REGION (follow-up addendum sections 3 and 10).
    #
    # MEASURED DEFECT, not a preference. This region used to be an inline
    # flex row in which the Direction column was a bare
    # `<div style="min-width: 260px;">` with NO flex declaration, so it
    # defaulted to `flex: 0 1 auto` and never grew. Measured at 1440px:
    # the Direction control sat at 263px and the search field at 380px
    # inside a 1382px row -- roughly 713px of the row was empty while the
    # longest value, "2019 PSIC -> PSIC Revision 5 (2026)", was squeezed
    # into 233px of text box with ~28px of slack and `text-overflow:
    # ellipsis` already armed. At 375px the same wrapper stayed pinned at
    # 263px instead of going full width.
    #
    # It is now a real grid with named classes rather than inline styles,
    # so the layout is a testable hook and the breakpoints live in CSS
    # beside every other responsive rule. Direction takes the wide column;
    # both controls go full width when the grid collapses to one column.
    # Input ids and the values they yield are untouched.
    shiny::tags$div(
      class = "psa-corr-filters",
      shiny::tags$div(
        class = "psa-corr-filter psa-corr-filter--direction",
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
        class = "psa-corr-filter psa-corr-filter--query",
        shiny::textInput(
          "correspondence_query", "Search a code or title",
          placeholder = "e.g. a PSIC code, or part of a title",
          width = "100%"
        )
      )
    ),

    # UI-04. Table and inspector are siblings in one grid, so selecting a
    # row updates the panel beside the table instead of replacing the page.
    # The grid collapses to a slide-over at tablet width and to a
    # full-screen sheet at phone width -- all in CSS (www/ui-filters.css),
    # so no re-render is involved and DT's paging, sorting and scroll
    # position survive a selection change untouched.
    shiny::tags$div(
    class = "psa-corr-workspace",
    shiny::tags$div(
    class = "psa-corr-table-col",
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
    )
    ),

    # The inspector. `correspondence_detail` keeps its stable id and stays a
    # uiOutput, so the server contract is unchanged; only where it renders
    # and what it renders into have moved.
    correspondence_inspector_shell(
      shiny::uiOutput("correspondence_detail")
    )
    ),

    shiny::tags$p(
      class = "text-muted small mt-2",
      CORRESPONDENCE_STATISTICAL_WARNING
    )
  )
}

# ---- Relationship inspector (UI-04) ---------------------------------------

#' INTEGRATION SEAM -- shared dialog/drawer shell (owned by workstream UI-A).
#'
#' The inspector is a persistent side region on desktop and only becomes a
#' modal-like surface (slide-over, then full-screen sheet) at narrower
#' widths, so it deliberately does NOT hand its whole lifetime to a modal
#' component. What it does need from the shared shell is the narrow-width
#' behaviour: Escape-to-close, focus move-in/trap while the sheet covers the
#' page, `aria-modal`, and focus restoration to the table row that opened it.
#'
#' This one function is the only place that has to change to adopt it. The
#' signature assumed of UI-A is:
#'
#'   ui_dialog_shell(id, title, body,
#'                   close_input_id = NULL,
#'                   variant = c("modal", "drawer", "sheet"),
#'                   labelled_by = NULL,
#'                   width = NULL)
#'
#' Until that exists, the markup below is self-contained and degrades
#' honestly: the region is labelled and announced, and the close control is
#' an ordinary Shiny input that clears the table selection (which is what
#' closes the inspector) without disturbing query, direction or paging.
correspondence_inspector_shell <- function(body) {
  shiny::tags$aside(
    id = "correspondence-inspector",
    class = "psa-corr-inspector psa-liquid-glass",
    role = "region",
    `aria-labelledby` = "correspondence-inspector-title",
    # Selection changes update the panel in place while focus stays in the
    # table, so the new content is announced rather than silently swapped.
    `aria-live` = "polite",
    shiny::tags$div(
      class = "psa-corr-inspector-head",
      shiny::tags$h3(
        id = "correspondence-inspector-title",
        class = "psa-corr-inspector-title",
        "Relationship detail"
      ),
      shiny::actionButton(
        "correspondence_inspector_close",
        "Close",
        class = "psa-corr-inspector-close",
        `aria-label` = "Close relationship detail"
      )
    ),
    shiny::tags$div(class = "psa-corr-inspector-body", body)
  )
}

#' Swap the from_*/to_* sides of a correspondence tibble.
#'
#' Pure column relabelling, used only to bring a reverse-direction lookup
#' back into the direction the user is reading. No value is altered.
.corr_swap_sides <- function(g) {
  out <- g
  for (f in c("system", "version", "code", "level", "label")) {
    a <- paste0("from_", f)
    b <- paste0("to_", f)
    out[[a]] <- g[[b]]
    out[[b]] <- g[[a]]
  }
  out
}

#' The full verified relationship group a selected row belongs to.
#'
#' A split row is one edge of a one-to-many change and a merged row is one
#' edge of a many-to-one change; showing either on its own reads as a
#' one-to-one mapping, which is precisely the misreading UI-04 exists to
#' prevent. This re-queries the deterministic service for every sibling edge
#' of the same change. It adds NO data: every row returned is a row the
#' correspondence artifact already contains.
#'
#' @param row A one-row tibble in the `search_psic_correspondence()` shape.
#' @param data_path character or NULL. Override for tests.
#'
#' @return A tibble in the same shape, ordered as the service returns it, or
#'   NULL when the row is not part of a group (or the lookup is
#'   unavailable). NULL means "show the single verified row" -- never a
#'   fabricated group.
correspondence_relationship_group <- function(row, data_path = NULL) {
  if (is.null(row) || nrow(row) == 0L) {
    return(NULL)
  }
  rt <- as.character(row$relation_type[[1]])
  if (!rt %in% c("split", "merged", "complex")) {
    return(NULL)
  }

  fv <- as.character(row$from_version[[1]])
  tv <- as.character(row$to_version[[1]])

  # `merged` is grouped on the TARGET (many old -> one new), which means
  # asking the service the question from the other side and swapping the
  # answer back into the direction on screen.
  by_target <- identical(rt, "merged")
  key <- if (by_target) row$to_code[[1]] else row$from_code[[1]]
  if (is.na(key)) {
    return(NULL)
  }

  out <- tryCatch(
    {
      g <- if (by_target) {
        .corr_swap_sides(get_psic_correspondence(key, tv, fv, data_path = data_path))
      } else {
        get_psic_correspondence(key, fv, tv, data_path = data_path)
      }
      g
    },
    error = function(e) NULL
  )

  if (is.null(out) || nrow(out) < 2L) {
    return(NULL)
  }
  out
}

#' One node in a split/merge structure: code, title, edition, level.
#'
#' `selected` marks the edge the user actually clicked, so the row they came
#' from stays findable inside its group.
.corr_tree_node <- function(code, label, level, version, selected = FALSE) {
  shiny::tags$li(
    class = if (isTRUE(selected)) "psa-corr-node psa-corr-node-selected" else "psa-corr-node",
    `aria-current` = if (isTRUE(selected)) "true" else NULL,
    shiny::tags$span(class = "mono psa-corr-node-code", code),
    shiny::tags$span(class = "psa-corr-node-label", label),
    shiny::tags$span(
      class = "psa-corr-node-meta",
      status_badge(if (identical(version, "2026")) "current" else "archived", prefix = version),
      if (!is.na(level)) shiny::tags$span(class = "text-muted small", level)
    )
  )
}

#' The relationship-specific structural view.
#'
#' Split shows the whole verified split group, merged shows every verified
#' contributing source, and everything else shows the verified pair. The
#' glyph and the framing are neutral throughout: a revised classification is
#' a normal outcome, never an error, so no failure styling and no
#' triangle-alert appears here.
.correspondence_structure_ui <- function(row, group) {
  rt <- as.character(row$relation_type[[1]])
  fv <- as.character(row$from_version[[1]])
  tv <- as.character(row$to_version[[1]])

  # No verified group available: fall back to the single verified pair
  # rather than implying a structure the data does not state.
  if (is.null(group) || nrow(group) < 2L) {
    return(shiny::tags$div(
      class = "psa-corr-struct psa-corr-struct-pair",
      shiny::tags$p(
        class = "psa-corr-struct-lead",
        switch(rt,
          unchanged    = "Continued - one-to-one continuity between the two editions.",
          renamed      = "Continued under a new title - one-to-one between the two editions.",
          reclassified = "Reclassified - the activity moved, or was recoded, to another category.",
          new          = "New in this edition - no verified counterpart in the earlier edition.",
          discontinued = "Discontinued - no verified counterpart in the later edition.",
          possible     = "Possible counterpart - proposed for review, not an established mapping.",
          "One verified relationship between these two editions."
        )
      ),
      shiny::tags$div(
        class = "psa-corr-row",
        .correspondence_side(
          row$from_code, row$from_label, row$from_level, row$from_version,
          "(no prior counterpart - new in this edition)"
        ),
        shiny::tags$span(
          class = "psa-corr-arrow",
          lucide_icon("arrow-left-right", 20)
        ),
        .correspondence_side(
          row$to_code, row$to_label, row$to_level, row$to_version,
          "(no related category - discontinued/absorbed)"
        )
      )
    ))
  }

  if (identical(rt, "merged")) {
    sources <- group[!duplicated(group$from_code), , drop = FALSE]
    return(shiny::tags$div(
      class = "psa-corr-struct psa-corr-struct-merged",
      shiny::tags$p(
        class = "psa-corr-struct-lead",
        lucide_icon("merge", 17),
        sprintf(
          "Merged - %d verified %s categories became one %s category.",
          nrow(sources), fv, tv
        )
      ),
      shiny::tags$ul(
        class = "psa-corr-tree psa-corr-tree-sources",
        `aria-label` = paste("Contributing", fv, "categories"),
        lapply(seq_len(nrow(sources)), function(i) {
          .corr_tree_node(
            sources$from_code[[i]], sources$from_label[[i]],
            sources$from_level[[i]], sources$from_version[[i]],
            selected = identical(sources$from_code[[i]], row$from_code[[1]])
          )
        })
      ),
      shiny::tags$div(class = "psa-corr-struct-joint", "becomes"),
      shiny::tags$ul(
        class = "psa-corr-tree psa-corr-tree-target",
        `aria-label` = paste("Resulting", tv, "category"),
        .corr_tree_node(
          row$to_code[[1]], row$to_label[[1]], row$to_level[[1]],
          row$to_version[[1]],
          selected = TRUE
        )
      )
    ))
  }

  # split / complex: one source, every verified target.
  targets <- group[!duplicated(group$to_code), , drop = FALSE]
  shiny::tags$div(
    class = "psa-corr-struct psa-corr-struct-split",
    shiny::tags$p(
      class = "psa-corr-struct-lead",
      lucide_icon("split", 17),
      sprintf(
        if (identical(rt, "complex")) {
          "Complex - one %s category relates to %d verified %s categories."
        } else {
          "Split - one %s category became %d verified %s categories."
        },
        fv, nrow(targets), tv
      )
    ),
    shiny::tags$ul(
      class = "psa-corr-tree psa-corr-tree-source",
      `aria-label` = paste("Original", fv, "category"),
      .corr_tree_node(
        row$from_code[[1]], row$from_label[[1]], row$from_level[[1]],
        row$from_version[[1]],
        selected = TRUE
      )
    ),
    shiny::tags$div(class = "psa-corr-struct-joint", "became"),
    shiny::tags$ul(
      class = "psa-corr-tree psa-corr-tree-targets",
      `aria-label` = paste("Resulting", tv, "categories"),
      lapply(seq_len(nrow(targets)), function(i) {
        .corr_tree_node(
          targets$to_code[[i]], targets$to_label[[i]],
          targets$to_level[[i]], targets$to_version[[i]],
          selected = identical(targets$to_code[[i]], row$to_code[[1]])
        )
      })
    )
  )
}

#' One-line contextual gloss for a value, drawn from the same glossary the
#' help panel uses (UI-05 "inspector integration"). Silently absent for a
#' value with no gloss rather than inventing an explanation.
.corr_inline_gloss <- function(gloss, value) {
  entry <- gloss[[as.character(value)]]
  if (is.null(entry)) {
    return(NULL)
  }
  shiny::tags$dd(class = "psa-corr-meta-gloss", entry$text)
}

# ---- User-facing evidence summary (follow-up addendum sections 5-8) -------

# Marker that the verified evidence string actually cites the UN ISIC
# Rev.4 -> Rev.5 correspondence. Matched as a literal, and deliberately
# narrow: corroboration is only ever CLAIMED when the artifact itself
# recorded it. Measured against the shipped artifact, 948 of 2000
# relationships carry it and 1052 do not, so this genuinely discriminates.
.CORR_UN_ISIC_MARKER <- "UN ISIC"

#' Summarise one relationship's evidence for a reader, not for an engineer.
#'
#' PRESENTATION ONLY, and deliberately a pure function of the row so the
#' wording can be tested without a session or a browser.
#'
#' The stored `evidence` string is an engineering artifact. It reads, in
#' full, like this:
#'
#'   "2019 section A corresponds to 2026 section A. Identical letters were
#'    verified against the section graph, not assumed. Code '01196' ->
#'    '01191' (same class). Label evidence supporting only
#'    (normalized-token similarity 0.25). Search method:
#'    class_prefix_continuity."
#'
#' That is a debugging trace: section-graph terminology, similarity scores
#' and internal search-method names. The addendum forbids all of it on the
#' user-facing surface, so this function does not reformat the string -- it
#' REPLACES it with the two facts a statistician can act on: that the
#' mapping is derived rather than PSA-published, and whether the UN
#' correspondence independently supports it.
#'
#' Nothing is invented. `corroboration` is NULL unless the row's own
#' evidence cites the UN correspondence, which is what keeps the stronger
#' sentence honest.
#'
#' @param row A one-row correspondence tibble.
#'
#' @return list(derived = character(1), corroboration = character(1) or NULL,
#'   has_un = logical(1)).
correspondence_evidence_summary <- function(row) {
  ev <- if (is.null(row) || !("evidence" %in% names(row))) NA_character_
        else as.character(row$evidence[[1]])

  has_un <- !is.na(ev) && grepl(.CORR_UN_ISIC_MARKER, ev, fixed = TRUE)

  list(
    derived = paste(
      "This relationship was derived from verified classification",
      "correspondence evidence."
    ),
    corroboration = if (has_un) {
      paste(
        "Supported by the official UN ISIC Rev.4 to Rev.5 correspondence."
      )
    } else {
      NULL
    },
    has_un = has_un
  )
}

#' The relationship facts block shared by BOTH inspector renderers.
#'
#' One implementation on purpose. The previous pass shipped two renderers
#' for this surface -- `correspondence_detail_ui()` (the one app.R actually
#' mounts) and `correspondence_inspector_ui()` -- and they had already
#' drifted apart. Simplifying only the mounted one would have left the other
#' still showing a standalone Provenance row and a raw evidence dump for
#' whoever wired it next.
#'
#' Shows Relationship, Confidence, the derived note and -- only where the
#' evidence records it -- the UN corroboration. Provenance is deliberately
#' NOT a row here: it is still carried in the data model, still validated,
#' still available to `correspondence_ask_rm_context()`, and still explained
#' in the terminology help. It is simply not a per-row field the reader has
#' to step over on the way to a decision (addendum section 4).
correspondence_relationship_facts_ui <- function(row) {
  rt <- as.character(row$relation_type[[1]])
  conf <- as.character(row$confidence[[1]])
  summary <- correspondence_evidence_summary(row)

  shiny::tags$div(
    class = "psa-corr-facts",

    shiny::tags$div(
      class = "psa-corr-fact",
      shiny::tags$span(class = "psa-corr-fact-label", "Relationship"),
      shiny::tags$span(
        class = "psa-tag psa-tag-neutral psa-corr-fact-value",
        tools::toTitleCase(rt)
      )
    ),

    shiny::tags$div(
      class = "psa-corr-fact",
      shiny::tags$span(class = "psa-corr-fact-label", "Confidence"),
      confidence_badge(conf, with_label = FALSE)
    ),

    shiny::tags$div(
      class = "psa-corr-note",
      shiny::tags$span(class = "psa-corr-note-title", "Derived correspondence"),
      shiny::tags$p(class = "psa-corr-note-text", summary$derived)
    ),

    if (!is.null(summary$corroboration)) {
      shiny::tags$div(
        class = "psa-corr-note psa-corr-note--corroboration",
        shiny::tags$span(class = "psa-corr-note-title", "Corroboration"),
        shiny::tags$p(class = "psa-corr-note-text", summary$corroboration)
      )
    }
  )
}

#' Render the selected relationship into the inspector.
#'
#' @param row A one-row tibble in the `search_psic_correspondence()` shape,
#'   or NULL / zero rows when nothing is selected.
#' @param group Optional. The verified relationship group from
#'   `correspondence_relationship_group()`.
correspondence_inspector_ui <- function(row, group = NULL) {
  if (is.null(row) || nrow(row) == 0L) {
    return(shiny::tags$p(
      class = "text-muted psa-corr-inspector-empty",
      "Select a row in the results table to see the full relationship, ",
      "including every category involved in a split or a merge."
    ))
  }

  shiny::tagList(
    .correspondence_structure_ui(row, group),

    # Relationship / Confidence / derived note / corroboration -- one shared
    # block, no standalone Provenance row and no raw evidence dump. See
    # `correspondence_relationship_facts_ui()` for why both renderers share
    # it rather than each formatting the row themselves.
    correspondence_relationship_facts_ui(row),

    # Always shown in the inspector, not only for split/merge: the reader is
    # here precisely because they are about to act on a mapping.
    correspondence_safeguard_note(),

    shiny::actionButton(
      "correspondence_ask_rm",
      shiny::tagList(
        lucide_icon("sparkles", 14),
        "Ask RM to explain this relationship"
      ),
      class = "psa-corr-askrm"
    )
  )
}

#' The verified, bounded context an "Ask RM" action may carry.
#'
#' Explicitly a whitelist, and explicitly built from the SELECTED ROW only:
#' nothing inferred, nothing from the model, no free text from the user, and
#' no column the correspondence artifact did not verify. Returns NULL when
#' there is no selection, so the caller can never send an empty shell.
correspondence_ask_rm_context <- function(row) {
  if (is.null(row) || nrow(row) == 0L) {
    return(NULL)
  }
  keep <- c(
    "from_system", "from_version", "from_code", "from_level", "from_label",
    "to_system", "to_version", "to_code", "to_level", "to_label",
    "relation_type", "provenance", "confidence"
  )
  keep <- intersect(keep, names(row))
  lapply(stats::setNames(keep, keep), function(k) as.character(row[[k]][[1]]))
}

#' Provenance badge. Never color alone -- the level is always spelled out.
#'
#' As of this build no mapping in the shipped artifact is `official`; that
#' is a data fact enforced by tests, not a presentation choice.
#'
#' NO LONGER RENDERED on the Compare Editions surface (follow-up addendum
#' section 4): provenance is not a per-row field the reader has to step over
#' on the way to a decision, and every shipped mapping is `derived` or
#' `suggested`, so the badge repeated the same word down the whole table.
#' Kept rather than deleted because section 13 of that addendum is explicit
#' that this pass simplifies PRESENTATION only -- the `provenance` field is
#' still in the canonical schema, still validated by
#' tests/testthat/test-correspondence-provenance.R, still carried into
#' `correspondence_ask_rm_context()`, and still explained in the "How to
#' read this table" glossary. If a diagnostic view is ever added, this is
#' the renderer it should use.
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
#' @param with_label When TRUE (the default, and what every pre-existing
#'   caller relies on) the badge reads "Confidence: High". The simplified
#'   relationship facts block already prints its own CONFIDENCE label above
#'   the badge, so it passes FALSE and gets just the ordinal word -- the
#'   alternative rendered as "CONFIDENCE / Confidence: High", which is the
#'   kind of duplicated metadata this pass exists to remove.
confidence_badge <- function(c, with_label = TRUE) {
  cls <- switch(c,
    high     = "psa-tag psa-tag-current",
    moderate = "psa-tag psa-tag-neutral",
    low      = "psa-tag psa-tag-archived",
    "psa-tag psa-tag-neutral"
  )
  # Label comes from the glossary, not from title-casing the stored value,
  # so `moderate` renders as "Medium" in exactly one place. Ordinal words
  # only -- never a percentage, because the source defines no probability
  # (addendum section 7).
  entry <- .CORRESPONDENCE_CONFIDENCE_GLOSS[[as.character(c)]]
  label <- if (is.null(entry)) tools::toTitleCase(as.character(c)) else entry$label
  shiny::tags$span(
    class = cls,
    if (isTRUE(with_label)) paste("Confidence:", label) else label
  )
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
  # Lucide glyphs per handoff §12.3: `split` for a split, `merge` for a
  # merge, `arrow-right` for a one-to-one reclassification. Rendered in
  # --color-primary, NEVER in an error colour: a split or a merge is a
  # normal classification outcome, not a failure (§12.3, §12.6).
  arrow_icon <- switch(row$relation_type,
    split   = "split",
    merged  = "merge",
    complex = "split",
    "arrow-left-right"
  )

  needs_statistical_warning <- row$relation_type %in% c("split", "merged", "complex")

  shiny::tagList(
    shiny::tags$div(
      class = "psa-corr-row",
      .correspondence_side(
        row$from_code, row$from_label, row$from_level, row$from_version,
        "(no prior counterpart — new in this edition)"
      ),
      shiny::tags$span(
        class = "psa-corr-arrow",
        lucide_icon(arrow_icon, 20)
      ),
      .correspondence_side(
        row$to_code, row$to_label, row$to_level, row$to_version,
        "(no related category — discontinued/absorbed)"
      )
    ),

    # Relationship / Confidence / derived note / corroboration. Shared with
    # `correspondence_inspector_ui()` so the two can never drift again.
    correspondence_relationship_facts_ui(row),

    # STATISTICAL-USE SAFEGUARD.
    #
    # Now shown for EVERY relationship, not only split / merged / complex.
    # The reader reaches this panel precisely because they are about to act
    # on a mapping, and the follow-up addendum requires the safeguard to
    # survive the evidence simplification. Widening it is the conservative
    # direction: no relationship that used to carry the notice loses it.
    #
    # A split, merge or complex relationship is a NORMAL classification
    # outcome, not an error, so this keeps the neutral/plum treatment and
    # the relationship glyph. triangle-alert and every red/ochre/amber
    # value remain forbidden here.
    shiny::tags$div(
      class = "psa-stat-warning",
      role = "note",
      lucide_icon(if (needs_statistical_warning) arrow_icon else "info", 17),
      shiny::tags$span(
        shiny::tags$strong("Statistical-use note "),
        CORRESPONDENCE_STATISTICAL_WARNING
      )
    )
  )
}

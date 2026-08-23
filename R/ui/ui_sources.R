# Sources screen (main_nav value "about", relabelled from
# "About / Data Sources" per HANDOFF §2) — provenance, data sources and
# methodology ONLY.
#
# PRESENTATION ONLY. The system list is read from the registry
# (source of truth: R/registry.R) and the PSIC Revision 5 provenance prose
# is rendered from docs/DATA_SOURCES.md, so the app and the docs never
# drift into two copies of the same text.
#
# Scope is deliberately unchanged: no Search and no RM content belongs
# here. This is the ONLY place carrying full methodology depth (retrieval
# date, SHA-256, validated structural counts); every other surface keeps
# provenance to one line plus a link (HANDOFF §10).
#
# PSA is named as the issuing authority throughout. phscs, psgc, the PSIC
# Revision 5 normalization pipeline and RM are access mechanisms, never the
# classification authority -- the app must never imply otherwise.

sources_ui <- function() {
  reg <- classification_registry()

  system_rows <- lapply(seq_len(nrow(reg)), function(i) {
    current <- reg$current_version[[i]]
    versions <- reg$available_versions[[i]]
    archived <- setdiff(versions, current)

    shiny::tags$tr(
      shiny::tags$td(shiny::tags$strong(reg$short_name[[i]])),
      shiny::tags$td(reg$display_name[[i]]),
      # Current and archived editions are always distinguished explicitly,
      # by text as well as by the shared status vocabulary.
      shiny::tags$td(
        shiny::tags$div(
          style = "display: flex; gap: 6px; flex-wrap: wrap;",
          status_badge("current", prefix = current),
          if (length(archived) > 0) {
            lapply(archived, function(v) status_badge("archived", prefix = v))
          }
        )
      ),
      shiny::tags$td(reg$source[[i]]),
      shiny::tags$td(
        shiny::tags$a(
          href = reg$source_url[[i]],
          target = "_blank",
          rel = "noopener",
          "PSA ↗"
        )
      )
    )
  })

  data_sources_md <- if (file.exists("docs/DATA_SOURCES.md")) {
    shiny::markdown(paste(readLines("docs/DATA_SOURCES.md", warn = FALSE), collapse = "\n"))
  } else {
    shiny::tags$p(class = "text-muted", "docs/DATA_SOURCES.md not found.")
  }

  correspondence_md <- if (file.exists("docs/CORRESPONDENCE_SOURCES.md")) {
    shiny::markdown(paste(readLines("docs/CORRESPONDENCE_SOURCES.md", warn = FALSE), collapse = "\n"))
  } else {
    NULL
  }

  shiny::tagList(
    shiny::tags$div(
      class = "psa-hero",
      style = "align-items: flex-start; padding-bottom: 8px;",
      shiny::tags$h2(style = "margin: 0 0 6px; font-size: 20px;", "Sources"),
      shiny::tags$p(
        class = "psa-dual-intro",
        "Where every classification in this application comes from, which ",
        "edition is current, and how the supplemental editions were built."
      )
    ),

    bslib::card(
      bslib::card_header("Classification systems and issuing authority"),
      bslib::card_body(
        shiny::tags$table(
          class = "table table-sm align-middle",
          shiny::tags$thead(
            shiny::tags$tr(
              shiny::tags$th(scope = "col", "System"),
              shiny::tags$th(scope = "col", "Name"),
              shiny::tags$th(scope = "col", "Editions"),
              shiny::tags$th(scope = "col", "Issuing authority"),
              shiny::tags$th(scope = "col", "Reference")
            )
          ),
          shiny::tags$tbody(system_rows)
        ),
        shiny::tags$p(
          class = "psa-sources-note mb-0",
          shiny::tags$strong("The Philippine Statistics Authority (PSA) is the authoritative source "),
          "for every classification shown in this application. The ",
          shiny::tags$code("phscs"), " and ", shiny::tags$code("psgc"),
          " R packages, the PSIC Revision 5 and PSOC 2022 normalization ",
          "pipelines, and the RM assistant are software and data-access ",
          "mechanisms — not the issuing authority, and not a source of ",
          "classification codes in their own right."
        )
      )
    ),

    bslib::card(
      bslib::card_header("Supplemental edition provenance — PSIC Revision 5 and PSOC 2022"),
      bslib::card_body(
        shiny::tags$div(class = "psa-sources-prose", data_sources_md)
      )
    ),

    if (!is.null(correspondence_md)) {
      bslib::card(
        bslib::card_header("PSIC 2019 ↔ Revision 5 correspondence — source audit and method"),
        bslib::card_body(
          shiny::tags$div(class = "psa-sources-prose", correspondence_md)
        )
      )
    }
  )
}

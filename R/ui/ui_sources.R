# Sources screen (main_nav value "about", relabelled from
# "About / Data Sources" per HANDOFF §2) — provenance, data sources and
# methodology ONLY.
#
# PRESENTATION ONLY. Nothing in this file computes, transforms or caches a
# classification fact. Every value rendered here is read from an existing
# service contract:
#   * the system deck   -> classification_registry()  (R/registry.R)
#   * supplemental cards-> the adapters' own *_metadata() provenance lists
#   * correspondence    -> data/psic_2019_to_2026_correspondence_metadata.rds
#   * long-form prose   -> docs/DATA_SOURCES.md, docs/CORRESPONDENCE_SOURCES.md
# so the app and the docs never drift into two copies of the same text.
#
# THE SYSTEM DECK IS REGISTRY-DRIVEN, DELIBERATELY (UI repair spec §3).
# It iterates whatever classification_registry() actually returns. There is
# no hard-coded list of systems anywhere below: a system that is registered
# gets a card automatically, and a system whose ingestion or validation
# failed (so it never reaches the registry) silently gets none. Adding
# PSCC / PTSCS / PSCrCS to the registry is therefore the ONLY change needed
# for them to appear here.
#
# For the same reason nothing here overrides or "corrects" a registry
# field. `display_name` is rendered verbatim -- a UI-only alias that
# papered over a wrong canonical value would hide the defect rather than
# fix it (UI repair spec §7). Scope/purpose is likewise NOT synthesised
# from `category`: that column groups education and crime classifications
# under "economic", so deriving public scope text from it would put a
# factually wrong sentence on a public page. Only fields the registry can
# actually vouch for are shown.
#
# LAYOUT CONTRACT (UI repair spec §3): one normal page scroll. No card has
# a fixed height and nothing on this page is an internal scroll region --
# the previous 620px `overflow-y: auto` prose panels were nested scrollbars
# inside an already-scrolling page. Long audit/technical material now sits
# behind semantic <details>/<summary> disclosures: keyboard-operable,
# correctly represented in the accessibility tree, and no JavaScript.
#
# PSA is named as the issuing authority throughout. phscs, psgc, the PSIC
# Revision 5 / PSOC 2022 normalization pipelines and RM are access
# mechanisms, never the classification authority -- the app must never
# imply otherwise.


# ---- small shared builders ------------------------------------------------

#' Semantic disclosure: <details> + <summary>, collapsed by default.
#'
#' Native element on purpose. It is keyboard-operable without any script,
#' exposes its own expanded/collapsed state to assistive technology, and
#' adds exactly one focus stop per disclosure.
.sources_disclosure <- function(label, ..., open = FALSE) {
  shiny::tags$details(
    class = "psa-disclosure",
    open = if (isTRUE(open)) NA else NULL,
    shiny::tags$summary(label),
    shiny::tags$div(class = "psa-disclosure-body", ...)
  )
}

#' A label/value row pair for a card's definition list.
.sources_dl_row <- function(label, value) {
  if (is.null(value)) {
    return(NULL)
  }
  shiny::tagList(shiny::tags$dt(label), shiny::tags$dd(value))
}

.sources_or <- function(x, fallback) {
  if (is.null(x) || length(x) != 1L || is.na(x) || !nzchar(as.character(x))) fallback else x
}

#' Render a repository Markdown document with its headings DEMOTED.
#'
#' docs/*.md are standalone documents and start at `#` (an <h1>). Splicing
#' that verbatim into a page whose own heading is an <h4> produced an
#' <h1> nested inside an <h4> section, i.e. a broken heading outline for
#' anyone navigating by headings. Shifting every ATX heading down by
#' `by` levels (clamped at <h6>) keeps ONE copy of the prose -- the doc
#' file stays the single source of truth -- while the rendered page keeps
#' a correct outline. Only line-leading `#` runs are touched, so fenced
#' code and inline text are unaffected.
.sources_markdown_demoted <- function(path, by) {
  if (!file.exists(path)) {
    return(NULL)
  }
  lines <- readLines(path, warn = FALSE)
  in_fence <- FALSE
  for (i in seq_along(lines)) {
    if (grepl("^\\s*```", lines[[i]])) {
      in_fence <- !in_fence
      next
    }
    if (in_fence) next
    m <- regmatches(lines[[i]], regexpr("^#{1,6}(?= )", lines[[i]], perl = TRUE))
    if (length(m) == 1L) {
      depth <- min(nchar(m) + by, 6L)
      lines[[i]] <- sub("^#{1,6}(?= )", strrep("#", depth), lines[[i]], perl = TRUE)
    }
  }
  shiny::markdown(paste(lines, collapse = "\n"))
}

.sources_external_link <- function(url, label) {
  if (is.null(url) || length(url) != 1L || is.na(url) || !nzchar(url)) {
    return(NULL)
  }
  shiny::tags$a(href = url, target = "_blank", rel = "noopener", label)
}

#' Safely read a sibling-owned adapter's provenance metadata.
#'
#' Same defensive contract R/registry.R uses for these adapters: the
#' function may not be defined, and its runtime artifact is read lazily
#' from disk and can throw. A missing supplemental source must degrade to
#' "no card" rather than blanking the whole Sources page.
.sources_try_metadata <- function(fn_name) {
  tryCatch(
    {
      if (!exists(fn_name, mode = "function")) {
        return(NULL)
      }
      meta <- get(fn_name, mode = "function")()
      if (is.list(meta) && length(meta) > 0L) meta else NULL
    },
    error = function(e) NULL
  )
}


# ---- classification system cards ------------------------------------------

#' One public provenance card for one REGISTERED classification system.
#'
#' @param row A one-row slice of classification_registry().
.sources_system_card <- function(row) {
  current <- row$current_version[[1]]
  versions <- row$available_versions[[1]]
  archived <- setdiff(versions, current)
  levels <- row$available_levels[[1]]

  shiny::tags$div(
    class = "psa-source-card",

    shiny::tags$div(
      class = "psa-source-card-head",
      shiny::tags$h4(row$short_name[[1]]),
      # Status is carried by the word "Current"/"Archived" as well as by the
      # accent/ochre vocabulary — never by colour alone.
      status_badge("current", prefix = current)
    ),

    # Rendered verbatim from the registry. See the file header.
    shiny::tags$p(class = "psa-source-card-name", row$display_name[[1]]),

    shiny::tags$dl(
      class = "psa-card-dl",
      .sources_dl_row("Current edition", current),
      .sources_dl_row(
        "Archived editions",
        if (length(archived) > 0L) {
          paste(length(archived), if (length(archived) == 1L) "available" else "available")
        } else {
          "None in this application"
        }
      ),
      .sources_dl_row(
        "Levels",
        if (length(levels) > 0L) paste(levels, collapse = ", ") else NULL
      ),
      .sources_dl_row("Issuing authority", row$source[[1]])
    ),

    # PSGC alone carries 12 archived releases; as always-visible badges they
    # dominated the card and buried the current edition. Behind a
    # disclosure the reader sees the summary count first and opts in to the
    # full list (UI repair spec §3.1).
    if (length(archived) > 0L) {
      .sources_disclosure(
        "View archived editions",
        shiny::tags$ul(
          class = "psa-edition-list",
          lapply(archived, function(v) {
            shiny::tags$li(status_badge("archived", prefix = v))
          })
        )
      )
    },

    shiny::tags$div(
      class = "psa-card-link",
      .sources_external_link(
        row$source_url[[1]],
        paste0("PSA reference for ", row$short_name[[1]], " ↗")
      )
    )
  )
}


# ---- supplemental / current-edition provenance cards ----------------------

# PSIC Revision 5 and PSOC 2022 are the two editions this application had to
# normalize from PSA's own published workbooks because no package or API
# served them yet. They are declared here by metadata FUNCTION NAME, not by
# hard-coded content: every fact on the card is read out of the adapter's
# own provenance record, so the card cannot drift from the artifact it
# describes, and a supplemental source that is absent or unreadable simply
# produces no card.
.sources_supplemental_specs <- function() {
  list(
    list(system_id = "psic", metadata_fn = "psic2026_metadata"),
    list(system_id = "psoc", metadata_fn = "psoc2022_metadata")
  )
}

#' Compare an adapter's parsed structural counts against PSA's own stated
#' totals. Returns a list(summary = character(1), rows = list()) or NULL.
#'
#' Never "reconciles" a difference: a documented discrepancy is reported as
#' a discrepancy, exactly as the build pipeline recorded it.
.sources_validation <- function(meta) {
  parsed <- meta$parsed_counts
  stated <- meta$psa_stated_counts
  if (!is.list(parsed) || !is.list(stated) || length(parsed) == 0L) {
    return(NULL)
  }
  keys <- intersect(names(parsed), names(stated))
  if (length(keys) == 0L) {
    return(NULL)
  }
  matched <- vapply(keys, function(k) isTRUE(as.numeric(parsed[[k]]) == as.numeric(stated[[k]])), logical(1))
  n_diff <- sum(!matched)

  summary_text <- if (n_diff == 0L) {
    paste0(
      "All ", length(keys),
      " structural levels match the totals PSA states for this edition."
    )
  } else {
    paste0(
      sum(matched), " of ", length(keys),
      " structural levels match the totals PSA states for this edition; ",
      n_diff, if (n_diff == 1L) " documented discrepancy" else " documented discrepancies",
      " remains unreconciled and is reported rather than adjusted."
    )
  }

  rows <- lapply(keys, function(k) {
    shiny::tags$tr(
      shiny::tags$td(gsub("_", " ", k, fixed = TRUE)),
      shiny::tags$td(format(as.numeric(stated[[k]]), big.mark = ",")),
      shiny::tags$td(format(as.numeric(parsed[[k]]), big.mark = ",")),
      shiny::tags$td(if (isTRUE(matched[[k]])) "Match" else "Discrepancy")
    )
  })

  list(summary = summary_text, rows = rows)
}

.sources_supplemental_card <- function(spec, reg) {
  meta <- .sources_try_metadata(spec$metadata_fn)
  if (is.null(meta)) {
    return(NULL)
  }
  reg_row <- reg[reg$id == spec$system_id, , drop = FALSE]
  if (nrow(reg_row) == 0L) {
    return(NULL)
  }

  status <- if (identical(meta$status, "current")) "current" else "archived"
  validation <- .sources_validation(meta)

  shiny::tags$div(
    class = "psa-source-card",

    shiny::tags$div(
      class = "psa-source-card-head",
      shiny::tags$h4(meta$display_version %||% meta$version),
      status_badge(status)
    ),

    shiny::tags$p(class = "psa-source-card-name", reg_row$display_name[[1]]),

    shiny::tags$dl(
      class = "psa-card-dl",
      .sources_dl_row("Issuing authority", meta$source),
      .sources_dl_row("Edition status", if (identical(status, "current")) {
        "Current edition in this application"
      } else {
        "Archived reference edition"
      }),
      .sources_dl_row("Official PSA source", .sources_external_link(
        meta$source_artifact_url %||% meta$source_url, "PSA published workbook ↗"
      )),
      .sources_dl_row("Retrieved", meta$retrieved_at),
      .sources_dl_row("Retrieval", meta$retrieval_method),
      .sources_dl_row("Licence", meta$license),
      .sources_dl_row(
        "Runtime",
        paste0(
          "PSA's workbook was normalized once, offline, into a local ",
          "snapshot that ships with this application. Searching this ",
          "edition never contacts the PSA website, so it behaves ",
          "identically whether or not psa.gov.ph is reachable."
        )
      ),
      if (!is.null(validation)) .sources_dl_row("Structure validation", validation$summary)
    ),

    if (!is.null(validation)) {
      .sources_disclosure(
        "View structure validation",
        shiny::tags$table(
          class = "table table-sm align-middle mb-0",
          shiny::tags$caption(
            class = "psa-sources-note",
            "Counts parsed from PSA's workbook, against the totals PSA states."
          ),
          shiny::tags$thead(
            shiny::tags$tr(
              shiny::tags$th(scope = "col", "Level"),
              shiny::tags$th(scope = "col", "PSA stated"),
              shiny::tags$th(scope = "col", "Parsed"),
              shiny::tags$th(scope = "col", "Result")
            )
          ),
          shiny::tags$tbody(validation$rows)
        )
      )
    },

    shiny::tags$div(
      class = "psa-card-link",
      .sources_external_link(meta$source_url, "PSA classification page ↗")
    )
  )
}


# ---- PSIC edition correspondence methodology ------------------------------

.sources_correspondence_card <- function() {
  meta <- tryCatch(
    {
      path <- "data/psic_2019_to_2026_correspondence_metadata.rds"
      if (file.exists(path)) readRDS(path) else NULL
    },
    error = function(e) NULL
  )

  by_prov <- if (is.list(meta)) meta$row_counts$by_provenance else NULL
  official_n <- if (is.list(by_prov) && !is.null(by_prov$official)) as.integer(by_prov$official) else 0L

  shiny::tags$div(
    class = "psa-source-card",

    shiny::tags$div(
      class = "psa-source-card-head",
      shiny::tags$h4("PSIC 2019 ↔ Revision 5 correspondence"),
      status_badge(if (official_n > 0L) "current" else "archived",
                   prefix = if (official_n > 0L) "Official records present" else "No official records")
    ),

    # Precise about what is and is not claimed: this states what this
    # application has incorporated, not what PSA does or does not publish.
    shiny::tags$p(
      class = "psa-sources-note",
      shiny::tags$strong("Official crosswalk status. "),
      "No explicit PSA-published PSIC 2019 ↔ Revision 5 correspondence ",
      "record has been incorporated into this application. The source ",
      "audit recorded below did not locate one at the time it was carried ",
      "out, so every correspondence shown in Compare Editions is marked ",
      "Derived or Suggested and none is marked Official. If PSA publishes ",
      "an official crosswalk, it takes precedence over everything shown here."
    ),

    shiny::tags$p(
      class = "psa-sources-note mb-0",
      shiny::tags$strong("Evidence used. "),
      "Each edition's own published code structure and hierarchy; ",
      "similarity between the two editions' own official labels; and the ",
      "United Nations Statistics Division's official ISIC Rev.4 ↔ Rev.5 ",
      "correspondence table, used only as corroborating evidence and only ",
      "where both PSIC editions demonstrably follow ISIC's own numbering ",
      "at that position — PSIC is a national adaptation of ISIC, not ISIC ",
      "verbatim."
    ),

    shiny::tags$dl(
      class = "psa-provenance-dl",
      shiny::tags$dt("Official"),
      shiny::tags$dd("Explicit PSA-published correspondence record."),
      shiny::tags$dt("Derived"),
      shiny::tags$dd("Supported by authoritative structural evidence."),
      shiny::tags$dt("Suggested"),
      shiny::tags$dd("Algorithmic candidate requiring caution.")
    ),

    if (is.list(by_prov) && length(by_prov) > 0L) {
      shiny::tags$dl(
        class = "psa-card-dl",
        .sources_dl_row(
          "Records by provenance",
          paste(
            vapply(
              names(by_prov),
              function(k) paste0(format(as.integer(by_prov[[k]]), big.mark = ","), " ", k),
              character(1)
            ),
            collapse = " · "
          )
        ),
        .sources_dl_row("Official records", format(official_n, big.mark = ",")),
        .sources_dl_row(
          "Confidence reporting",
          "High, Moderate or Low only. These are ordinal signals, never calibrated probabilities."
        )
      )
    },

    shiny::tags$div(
      class = "psa-stat-warning",
      lucide_icon("triangle-alert", 17),
      CORRESPONDENCE_STATISTICAL_WARNING
    ),

    if (file.exists("docs/CORRESPONDENCE_SOURCES.md")) {
      .sources_disclosure(
        "View detailed source audit",
        shiny::tags$div(
          class = "psa-sources-prose",
          shiny::markdown(
            paste(readLines("docs/CORRESPONDENCE_SOURCES.md", warn = FALSE), collapse = "\n")
          )
        )
      )
    }
  )
}


# ---- technical implementation details (collapsed) -------------------------

# Repository paths are discovered by listing the deployment, not hard-coded:
# a deployment that ships without scripts/ simply shows fewer entries, and
# files added by a later ingestion milestone appear without editing this
# file.
.sources_path_list <- function(label, dir, pattern) {
  files <- tryCatch(
    sort(list.files(dir, pattern = pattern, full.names = TRUE)),
    error = function(e) character(0)
  )
  if (length(files) == 0L) {
    return(NULL)
  }
  shiny::tagList(
    shiny::tags$dt(label),
    shiny::tags$dd(shiny::tags$code(paste(files, collapse = "  ")))
  )
}

.sources_technical_section <- function() {
  data_sources_md <- if (file.exists("docs/DATA_SOURCES.md")) {
    shiny::markdown(paste(readLines("docs/DATA_SOURCES.md", warn = FALSE), collapse = "\n"))
  } else {
    NULL
  }

  paths <- shiny::tagList(
    .sources_path_list("Build pipelines", "scripts", "[.]R$"),
    .sources_path_list("Runtime adapters", "R/adapters", "[.]R$"),
    .sources_path_list("Local runtime artifacts", "data", "[.]rds$"),
    .sources_path_list("Verification suite", "tests/testthat", "^test-.*[.]R$")
  )

  shiny::tags$div(
    class = "psa-sources-section",
    shiny::tags$h3("Technical implementation details"),
    shiny::tags$p(
      class = "psa-section-note",
      "Repository internals, build pipelines and the full supplemental ",
      "source record. Kept collapsed — nothing here is needed to use the ",
      "classifications, and none of it is a classification authority."
    ),
    .sources_disclosure(
      "Show technical implementation details",
      shiny::tags$dl(class = "psa-card-dl", paths),
      if (!is.null(data_sources_md)) {
        shiny::tagList(
          shiny::tags$h4(
            style = "margin: 18px 0 8px; font-size: 14px;",
            "Full supplemental-edition source record"
          ),
          shiny::tags$div(class = "psa-sources-prose", data_sources_md)
        )
      }
    )
  )
}


# ---- page ------------------------------------------------------------------

sources_ui <- function() {
  reg <- classification_registry()

  system_cards <- lapply(
    seq_len(nrow(reg)),
    function(i) .sources_system_card(reg[i, , drop = FALSE])
  )

  supplemental_cards <- Filter(
    Negate(is.null),
    lapply(.sources_supplemental_specs(), .sources_supplemental_card, reg = reg)
  )

  shiny::tagList(
    shiny::tags$div(
      class = "psa-hero",
      style = "align-items: flex-start; padding-bottom: 8px;",
      shiny::tags$h2(style = "margin: 0 0 6px; font-size: 20px;", "Sources"),
      shiny::tags$p(
        class = "psa-dual-intro",
        "Where every classification in this application comes from, which ",
        "edition is current, which editions are archived, and how the ",
        "supplemental editions were sourced."
      )
    ),

    shiny::tags$div(
      class = "psa-sources-section",
      shiny::tags$h3("Classification systems"),
      shiny::tags$p(
        class = "psa-section-note",
        shiny::tags$strong("The Philippine Statistics Authority (PSA) is the authoritative source "),
        "for every classification below. The ", shiny::tags$code("phscs"),
        " and ", shiny::tags$code("psgc"), " R packages, the supplemental ",
        "normalization pipelines and the RM assistant are software and ",
        "data-access mechanisms — not the issuing authority, and not a ",
        "source of classification codes in their own right."
      ),
      shiny::tags$div(class = "psa-card-deck", system_cards)
    ),

    if (length(supplemental_cards) > 0L) {
      shiny::tags$div(
        class = "psa-sources-section",
        shiny::tags$h3("Current edition provenance"),
        shiny::tags$p(
          class = "psa-section-note",
          "Two current editions are not yet served by any R package or PSA ",
          "API, so this application normalizes PSA's own published workbook ",
          "into a local snapshot instead. Each card records exactly which ",
          "PSA file was used and how the result was checked."
        ),
        shiny::tags$div(class = "psa-card-deck psa-card-deck-2", supplemental_cards)
      )
    },

    shiny::tags$div(
      class = "psa-sources-section",
      shiny::tags$h3("PSIC edition correspondence methodology"),
      shiny::tags$p(
        class = "psa-section-note",
        "How Compare Editions decides that a PSIC 2019 category corresponds ",
        "to a PSIC Revision 5 category, and how far that claim can be taken."
      ),
      shiny::tags$div(class = "psa-card-deck psa-card-deck-2", .sources_correspondence_card())
    ),

    .sources_technical_section()
  )
}

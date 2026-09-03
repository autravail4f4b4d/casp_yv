# Official PSOC descriptive sections for the details surface.
#
# PRESENTATION ONLY. Every string rendered here comes from the descriptive
# artifact via `get_psoc_descriptive_metadata()`, which serves a code the
# CALLER has already verified against the canonical repository. Nothing here
# looks anything up, decides anything, or falls back to prose of its own.
#
# THE PRODUCT RULE THIS IMPLEMENTS. A user should not need the assistant --
# or the source workbook -- to read what the official reference says about a
# code. View details is the reference surface; RM is for interpretation.
#
# ABSENT MEANS ABSENT. The workbook does not describe every group: 618 of
# 649 records carry a definition, 456 carry tasks, 457 carry examples, and
# only 1 carries an exclusion. A section with no source content is not
# rendered at all -- no placeholder, no "not available" filler, and above
# all nothing synthesised. Source irregularities stay visible as they are.

#' The official descriptive block for a verified PSOC entry, or NULL.
#'
#' @param entry A one-row canonical tibble. Anything that is not a current
#'   PSOC 2022 record returns NULL, so no other system or edition can ever
#'   render PSOC prose.
psoc_descriptive_sections_ui <- function(entry) {
  if (is.null(entry) || nrow(entry) == 0L) return(NULL)
  entry <- entry[1, , drop = FALSE]
  if (!identical(as.character(entry$system), "psoc")) return(NULL)

  # The canonical row is the key. `level` is passed so a disagreement
  # between the repository and the artifact about what this code IS shows
  # nothing rather than the wrong thing.
  rec <- get_psoc_descriptive_metadata(
    version = as.character(entry$version),
    code = as.character(entry$code),
    level = as.character(entry$level)
  )
  if (is.null(rec) || !psoc_descriptive_has_content(rec)) return(NULL)

  shiny::tags$div(
    class = "psa-psoc-desc",
    .psoc_desc_definition(rec),
    .psoc_desc_tasks(rec),
    .psoc_desc_task_summary(rec),
    .psoc_desc_examples(rec),
    .psoc_desc_related(rec),
    .psoc_desc_list_section(rec$exclusions, "Exclusions", "exclusions"),
    .psoc_desc_list_section(rec$notes, "Notes", "notes"),
    .psoc_desc_crosswalk(rec),
    .psoc_desc_source(rec)
  )
}

.psoc_desc_section <- function(title, ..., class = NULL) {
  shiny::tags$section(
    class = paste(c("psa-psoc-desc__section", class), collapse = " "),
    shiny::tags$h4(class = "psa-psoc-desc__head", title),
    ...
  )
}

.psoc_desc_definition <- function(rec) {
  if (length(rec$definition) == 0L) return(NULL)
  .psoc_desc_section(
    "Definition",
    class = "psa-psoc-desc__section--definition",
    # Source order is content: the paragraphs read as one passage.
    lapply(rec$definition, function(p) {
      shiny::tags$p(class = "psa-psoc-desc__para", p)
    })
  )
}

.psoc_desc_tasks <- function(rec) {
  if (length(rec$tasks) == 0L) return(NULL)
  .psoc_desc_section(
    "Typical tasks",
    # The workbook letters its tasks (a), (b), (c). The letter is part of
    # the official text, so it is rendered rather than replaced by the
    # browser's own list numbering.
    shiny::tags$ul(
      class = "psa-psoc-desc__tasks",
      lapply(rec$tasks, function(t) {
        shiny::tags$li(
          class = "psa-psoc-desc__task",
          if (!is.na(t$label)) {
            shiny::tags$span(class = "psa-psoc-desc__task-label",
                             paste0("(", t$label, ")"))
          },
          shiny::tags$span(class = "psa-psoc-desc__task-text", t$text)
        )
      })
    )
  )
}

.psoc_desc_task_summary <- function(rec) {
  if (length(rec$task_summary) == 0L) return(NULL)
  .psoc_desc_section(
    "Task summary",
    lapply(rec$task_summary, function(p) {
      shiny::tags$p(class = "psa-psoc-desc__para", p)
    })
  )
}

.psoc_desc_examples <- function(rec) {
  if (length(rec$examples) == 0L) return(NULL)
  .psoc_desc_section(
    "Examples of occupations classified here",
    shiny::tags$ul(
      class = "psa-psoc-desc__examples",
      lapply(rec$examples, function(x) shiny::tags$li(x))
    )
  )
}

.psoc_desc_related <- function(rec) {
  if (length(rec$related_occupations) == 0L) return(NULL)
  .psoc_desc_section(
    "Related occupations classified elsewhere",
    shiny::tags$ul(
      class = "psa-psoc-desc__related",
      lapply(rec$related_occupations, function(r) {
        shiny::tags$li(
          shiny::tags$span(r$title),
          if (!is.na(r$code)) {
            shiny::tagList(
              " — ",
              shiny::tags$span(class = "mono psa-psoc-desc__related-code", r$code)
            )
          },
          # A partial mapping is stated, never rounded up to a full one.
          if (isTRUE(r$partial)) {
            shiny::tags$span(class = "psa-psoc-desc__partial", " (part)")
          }
        )
      })
    )
  )
}

.psoc_desc_list_section <- function(items, title, class) {
  if (length(items) == 0L) return(NULL)
  .psoc_desc_section(
    title,
    class = paste0("psa-psoc-desc__section--", class),
    lapply(items, function(p) shiny::tags$p(class = "psa-psoc-desc__para", p))
  )
}

.psoc_desc_crosswalk_side <- function(side, label) {
  if (is.null(side)) return(NULL)
  has_codes <- length(side$codes) > 0L
  if (!has_codes && (is.null(side$raw) || is.na(side$raw))) return(NULL)

  value <- if (has_codes) {
    shiny::tagList(lapply(seq_along(side$codes), function(i) {
      c <- side$codes[[i]]
      shiny::tagList(
        if (i > 1L) ", ",
        shiny::tags$span(class = "mono", c$code),
        if (isTRUE(c$partial)) {
          shiny::tags$span(class = "psa-psoc-desc__partial", " (part)")
        }
      )
    }))
  } else {
    # The workbook sometimes states a mapping the parser could not resolve
    # into codes. The raw wording is shown rather than dropped.
    shiny::tags$span(side$raw)
  }

  shiny::tagList(shiny::tags$dt(label), shiny::tags$dd(value))
}

.psoc_desc_crosswalk <- function(rec) {
  body <- shiny::tagList(
    .psoc_desc_crosswalk_side(rec$crosswalk$psoc_1992, "PSOC 1992"),
    .psoc_desc_crosswalk_side(rec$crosswalk$isco_2008, "ISCO 2008")
  )
  if (length(body) == 0L || all(vapply(body, is.null, logical(1)))) return(NULL)

  .psoc_desc_section(
    "Historical correspondence",
    shiny::tags$p(
      class = "psa-psoc-desc__note",
      "Reference mappings published with the classification. A correspondence ",
      "is a historical relationship, not a current coding instruction, and ",
      "“part” marks a partial mapping."
    ),
    shiny::tags$dl(class = "psa-psoc-desc__crosswalk", body)
  )
}

.psoc_desc_source <- function(rec) {
  src <- psoc_descriptive_source()
  if (is.null(src)) return(NULL)
  shiny::tags$p(
    class = "psa-psoc-desc__provenance",
    "Descriptive text: ", shiny::tags$strong(src$issuing_authority),
    if (!is.na(src$file_name)) shiny::tagList(", ", src$file_name),
    if (!is.na(rec$source$sheet)) {
      shiny::tagList(" (", rec$source$sheet, ")")
    },
    "."
  )
}

#' One-line definition preview for a verified PSOC entry, or NULL (W3).
#'
#' The FIRST definition paragraph only, trimmed to a readable length. Used
#' where the layout has room for a hint but not for the reference itself --
#' the full text belongs in View details.
#'
#' Deliberately a plain read of the same verified record: nothing here
#' summarises, paraphrases or rewrites the official wording.
psoc_descriptive_preview <- function(entry, max_chars = 220L) {
  if (is.null(entry) || nrow(entry) == 0L) return(NULL)
  entry <- entry[1, , drop = FALSE]
  if (!identical(as.character(entry$system), "psoc")) return(NULL)

  rec <- get_psoc_descriptive_metadata(
    version = as.character(entry$version),
    code = as.character(entry$code),
    level = as.character(entry$level)
  )
  if (is.null(rec) || length(rec$definition) == 0L) return(NULL)

  first <- rec$definition[[1L]]
  if (is.na(first) || !nzchar(first)) return(NULL)
  if (nchar(first) > max_chars) {
    # Cut on a word boundary so the preview never ends mid-word, and mark
    # the truncation so it is never mistaken for the whole definition.
    cut <- substr(first, 1L, max_chars)
    sp <- regexpr("[[:space:]][^[:space:]]*$", cut)
    if (sp > 0L) cut <- substr(cut, 1L, sp - 1L)
    first <- paste0(cut, "…")
  }
  first
}

# PSCC-specific presentation helpers.
#
# PSCC (Philippine Standard Commodity Classification, 2022) is NOT PSCCS
# (Philippine Standard Classification of Crime for Statistical Purposes).
# Nothing in this file may route, alias or merge one into the other.
#
# Everything here is either
#   (a) a PURE function over the canonical PSCC tibble -- directly testable,
#       no Shiny, no reactives, no I/O beyond the memoised adapter; or
#   (b) a thin Shiny tag builder that formats what (a) already derived.
#
# There is no lookup, ranking or hierarchy logic of its own: the display tree,
# breadcrumbs and cross-references are all built once at build time by
# scripts/build_pscc_2022.R and simply read back here.
#
# Public contract (app.R depends on these names):
#   pscc_level_labels()                      -> named chr, internal -> public
#   pscc_level_label(level)                  -> vectorised public label
#   pscc_level_choices(levels, include_all)  -> named chr for selectInput
#   pscc_result_fields(row)                  -> list, spec 9.5 result shape
#   pscc_result_ui(row)                      -> Shiny tags, spec 9.5
#   pscc_detail_fields(row)                  -> data.frame, spec 9.12 rows
#   pscc_detail_ui(row)                      -> Shiny tags, spec 9.12
#   pscc_match_reason_text(field, value)     -> chr, spec 9.11 wording
#   pscc_crossref_search(query, ...)         -> matches + labelled reasons
#   pscc_browse_children(parent_code, ...)   -> bounded one-level browse

# ---------------------------------------------------------------------------
# Level vocabulary (spec 9.9 / 9.10)
# ---------------------------------------------------------------------------

#' Map internal PSCC level values to public, human-readable labels.
#'
#' The internal 8-digit level is `intermediate_category`, never
#' "ahtn subheading": AHTN 2022 is a CROSS-REFERENCE column and must never be
#' offered as a hierarchy level in the public Level selector (spec 9.9).
#' Where the workbook does not give an intermediate row a formal named PSA
#' level, the public label is the neutral "Intermediate category" rather than
#' an invented official term (spec 9.10).
#'
#' @return A named character vector: names are the internal `level` values
#'   found in the artifact, values are the labels to show users.
pscc_level_labels <- function() {
  c(
    section               = "Section",
    chapter               = "Chapter",
    heading               = "Heading",
    subheading            = "Subheading",
    intermediate_category = "Intermediate category",
    commodity             = "Commodity item",
    structural_group      = "Structural group"
  )
}

#' Public label for one or more internal level values.
#'
#' Unknown values are returned unchanged rather than dropped, so a future
#' level added by the build script degrades to its raw name instead of
#' vanishing from the UI.
pscc_level_label <- function(level) {
  labels <- pscc_level_labels()
  out <- unname(labels[level])
  ifelse(is.na(out), as.character(level), out)
}

#' Named choices vector for a PSCC Level selector.
#'
#' @param levels character. Internal level values, normally `pscc2022_levels()`.
#' @param include_all logical. Prepend an "All levels" entry mapping to "".
#'
#' @return A named character vector suitable for `shiny::selectInput(choices=)`
#'   -- names are what the user reads, values are the internal level ids.
pscc_level_choices <- function(levels = pscc2022_levels(), include_all = TRUE) {
  choices <- stats::setNames(levels, pscc_level_label(levels))
  if (include_all) choices <- c(stats::setNames("", "All levels"), choices)
  choices
}

# ---------------------------------------------------------------------------
# Row helpers
# ---------------------------------------------------------------------------

.pscc_one_row <- function(row) {
  if (is.null(row)) return(NULL)
  if (is.data.frame(row)) {
    if (nrow(row) == 0L) return(NULL)
    row <- as.list(row[1L, , drop = FALSE])
  }
  lapply(row, function(v) if (length(v) == 0L) NA else v[[1L]])
}

.pscc_present <- function(x) {
  !is.null(x) && length(x) == 1L && !is.na(x) && nzchar(as.character(x))
}

# ---------------------------------------------------------------------------
# Search result shape (spec 9.5)
# ---------------------------------------------------------------------------

#' Derive the fields a PSCC search result should display.
#'
#' PURE: takes one canonical PSCC row, returns a plain list. Tests call this
#' directly; `pscc_result_ui()` only decorates it.
#'
#' Ordering follows spec 9.5 -- the 2022 PSCC code (when the row has one) then
#' the human-readable description as the primary line, with breadcrumb, unit
#' and cross-references as clearly-labelled SECONDARY metadata. Nothing is
#' concatenated into one long title, and a cross-reference is never returned
#' in the `code` slot.
#'
#' @param row A one-row data frame / list from `pscc2022_get()`.
#'
#' @return A list with `code`, `description`, `breadcrumb`, `level_label`,
#'   `is_selectable_code`, `is_structural_label` and a `secondary` named list
#'   of `Unit` / `2019 PSCC` / `AHTN 2022` entries (only those present).
pscc_result_fields <- function(row) {
  r <- .pscc_one_row(row)
  if (is.null(r)) return(NULL)

  secondary <- list()
  if (.pscc_present(r$unit_of_quantity)) secondary[["Unit"]] <- r$unit_of_quantity
  if (.pscc_present(r$pscc_2019_code))   secondary[["2019 PSCC"]] <- r$pscc_2019_code
  if (.pscc_present(r$ahtn_2022_code))   secondary[["AHTN 2022"]] <- r$ahtn_2022_code

  list(
    # `code` is the 2022 PSCC code and ONLY the 2022 PSCC code. Structural
    # rows carry a synthetic PSCC-STRUCT id, which is never shown as a code.
    code = if (.pscc_present(r$pscc_2022_code)) as.character(r$pscc_2022_code) else NA_character_,
    heading_code = if (.pscc_present(r$heading_code)) as.character(r$heading_code) else NA_character_,
    description = as.character(r$label),
    breadcrumb = if (.pscc_present(r$breadcrumb)) as.character(r$breadcrumb) else NA_character_,
    level = as.character(r$level),
    level_label = pscc_level_label(as.character(r$level)),
    is_selectable_code = isTRUE(r$is_selectable_code),
    is_structural_label = isTRUE(r$is_structural_label),
    secondary = secondary
  )
}

#' Render one PSCC search result (spec 9.5).
pscc_result_ui <- function(row) {
  f <- pscc_result_fields(row)
  if (is.null(f)) return(NULL)

  code_line <- if (!is.na(f$code)) {
    shiny::tags$div(class = "mono psa-pscc-code", f$code)
  } else {
    shiny::tags$div(
      class = "psa-eyebrow",
      # A structural row has no code at all. Say so, rather than borrowing a
      # neighbouring code or showing the internal PSCC-STRUCT id.
      if (isTRUE(f$is_structural_label)) "Hierarchy label · no PSCC code" else f$level_label
    )
  }

  shiny::tags$div(
    class = if (isTRUE(f$is_structural_label)) "psa-pscc-result psa-pscc-structural" else "psa-pscc-result",
    `data-pscc-level` = f$level,
    code_line,
    shiny::tags$div(class = "psa-pscc-description", f$description),
    if (!is.na(f$breadcrumb)) {
      shiny::tags$div(
        class = "psa-pscc-breadcrumb",
        `aria-label` = "Classification hierarchy",
        f$breadcrumb
      )
    },
    if (length(f$secondary) > 0L) {
      shiny::tags$div(
        class = "psa-pscc-secondary",
        lapply(names(f$secondary), function(k) {
          shiny::tags$span(
            class = "psa-pscc-meta",
            shiny::tags$span(class = "psa-pscc-meta-label", paste0(k, ": ")),
            shiny::tags$span(class = "mono", f$secondary[[k]])
          )
        })
      )
    }
  )
}

# ---------------------------------------------------------------------------
# Detail panel (spec 9.12)
# ---------------------------------------------------------------------------

#' Derive the labelled rows of the PSCC detail panel.
#'
#' PURE. Cross-references are labelled explicitly as cross-references (spec
#' 9.9) so no field in this table can be mistaken for the 2022 PSCC code.
#'
#' @return A data.frame with `label` and `value` columns, in display order.
#'   Fields with no value are omitted rather than shown blank.
pscc_detail_fields <- function(row) {
  r <- .pscc_one_row(row)
  if (is.null(r)) return(NULL)

  pairs <- list()
  add <- function(label, value) {
    if (.pscc_present(value)) pairs[[length(pairs) + 1L]] <<- c(label, as.character(value))
  }

  if (.pscc_present(r$pscc_2022_code)) {
    add("2022 PSCC", r$pscc_2022_code)
  } else {
    add("Node type", pscc_level_label(as.character(r$level)))
  }
  add("Description", r$label)
  add("Hierarchy", r$breadcrumb)
  add("Section", r$section_code)
  add("Chapter", r$chapter_code)
  add("Heading", r$heading_code)
  add("Unit of Quantity", r$unit_of_quantity)
  add("2019 PSCC cross-reference", r$pscc_2019_code)
  add("AHTN 2022 cross-reference", r$ahtn_2022_code)
  add("Source description", r$raw_description)

  data.frame(
    label = vapply(pairs, `[`, character(1), 1L),
    value = vapply(pairs, `[`, character(1), 2L),
    stringsAsFactors = FALSE
  )
}

#' Render the PSCC detail panel (spec 9.12).
pscc_detail_ui <- function(row) {
  fields <- pscc_detail_fields(row)
  if (is.null(fields) || nrow(fields) == 0L) {
    return(shiny::tags$p(
      class = "text-muted",
      "Select a row in the results table to see its details."
    ))
  }

  mono_labels <- c("2022 PSCC", "Section", "Chapter", "Heading",
                    "2019 PSCC cross-reference", "AHTN 2022 cross-reference")

  shiny::tags$dl(
    class = "psa-pscc-detail",
    lapply(seq_len(nrow(fields)), function(i) {
      shiny::tagList(
        shiny::tags$dt(fields$label[i]),
        shiny::tags$dd(
          class = if (fields$label[i] %in% mono_labels) "mono" else NULL,
          fields$value[i]
        )
      )
    })
  )
}

# ---------------------------------------------------------------------------
# Cross-reference search (spec 9.11)
# ---------------------------------------------------------------------------

# Which stored field a PSCC match came from. `pscc_2022` is the authoritative
# code; the other two are CROSS-REFERENCES and are always announced as such.
PSCC_MATCH_FIELDS <- c("pscc_2022", "pscc_2019", "ahtn_2022")

PSCC_MATCH_FIELD_COLUMN <- c(
  pscc_2022 = "pscc_2022_code",
  pscc_2019 = "pscc_2019_code",
  ahtn_2022 = "ahtn_2022_code"
)

#' Human-readable reason a PSCC row matched (spec 9.11).
#'
#' PURE and vectorised. A cross-reference hit ALWAYS says which edition it
#' came from, so the matched value can never read as if it were the 2022 code:
#'
#'   "Matched 2022 PSCC code: 0101.21.00-000"
#'   "Matched 2019 PSCC cross-reference: 0101.21.00-00"
#'   "Matched AHTN 2022 cross-reference: 0101.21.00"
#'
#' @param match_field character. One of `PSCC_MATCH_FIELDS`.
#' @param matched_value character. The stored value that matched.
pscc_match_reason_text <- function(match_field, matched_value) {
  prefix <- c(
    pscc_2022 = "Matched 2022 PSCC code: ",
    pscc_2019 = "Matched 2019 PSCC cross-reference: ",
    ahtn_2022 = "Matched AHTN 2022 cross-reference: "
  )[match_field]
  unknown <- is.na(prefix)
  prefix[unknown] <- paste0("Matched ", match_field[unknown], ": ")
  paste0(unname(prefix), matched_value)
}

.pscc_norm_code <- function(x) toupper(trimws(as.character(x)))

#' Search PSCC by 2022 code or by a 2019 PSCC / AHTN 2022 cross-reference.
#'
#' PURE (aside from reading the memoised adapter artifact). Exact matches are
#' preferred; if there are none, a prefix match is attempted so a user can
#' paste a shorter published code. The 2022 PSCC column is always tried first,
#' so an authoritative code never loses to a cross-reference.
#'
#' Each returned row keeps its own 2022 PSCC code untouched and gains:
#'   `match_field`   -- which stored field matched
#'   `matched_value` -- the stored value that matched
#'   `match_reason`  -- the sentence to show the user
#'
#' A cross-reference is NEVER copied into `code` or `pscc_2022_code`.
#'
#' @param query character(1). A code-shaped query.
#' @param data A PSCC tibble; defaults to the runtime artifact.
#' @param limit integer(1). Maximum rows returned (bounded, spec 9.16).
#'
#' @return A tibble of matches with the three extra columns above; zero rows
#'   (never NULL, never an error) when nothing matches or the query is blank.
pscc_crossref_search <- function(query, data = NULL, limit = 100L) {
  if (is.null(data)) data <- pscc2022_get()
  empty <- data[0L, , drop = FALSE]
  empty$match_field <- character(0)
  empty$matched_value <- character(0)
  empty$match_reason <- character(0)

  if (is.null(query) || length(query) != 1L || is.na(query)) return(empty)
  q <- .pscc_norm_code(query)
  if (!nzchar(q)) return(empty)

  # EXACT matches are exhausted across all three fields before any prefix
  # matching is attempted. Otherwise a shorter published cross-reference such
  # as the 2019 code "0101.21.00-00" would be swallowed as a prefix of the
  # 2022 code "0101.21.00-000" and reported under the wrong edition.
  for (mode in c("exact", "prefix")) {
    for (field in PSCC_MATCH_FIELDS) {
      col <- .pscc_norm_code(data[[PSCC_MATCH_FIELD_COLUMN[[field]]]])
      hit <- if (mode == "exact") {
        !is.na(col) & col == q
      } else {
        !is.na(col) & startsWith(col, q)
      }
      if (!any(hit)) next

      out <- data[hit, , drop = FALSE]
      matched <- data[[PSCC_MATCH_FIELD_COLUMN[[field]]]][hit]
      if (nrow(out) > limit) {
        out <- out[seq_len(limit), , drop = FALSE]
        matched <- matched[seq_len(limit)]
      }
      out$match_field <- field
      out$matched_value <- matched
      out$match_reason <- pscc_match_reason_text(field, matched)
      return(out)
    }
  }

  empty
}

#' Render the match reason as a labelled badge.
pscc_match_reason_ui <- function(match_reason) {
  if (!.pscc_present(match_reason)) return(NULL)
  shiny::tags$div(class = "psa-pscc-match-reason", match_reason)
}

# ---------------------------------------------------------------------------
# Bounded hierarchical browse (spec 9.6 / 9.16)
# ---------------------------------------------------------------------------

#' One level of the PSCC tree, never the whole workbook.
#'
#' Browsing PSCC must not materialise all 24k rows at once (spec 9.6). This
#' returns ONLY the direct children of `parent_code` (the 21 sections when
#' `parent_code` is NULL), capped at `limit`, in source order.
#'
#' @param parent_code character(1) or NULL for the roots.
#' @param data A PSCC tibble; defaults to the runtime artifact.
#' @param limit integer(1). Hard cap on rows returned.
#'
#' @return A list with `data` (tibble of children), `total_children` (the true
#'   pre-limit count, so the UI can report a truthful total) and `is_truncated`.
pscc_browse_children <- function(parent_code = NULL, data = NULL, limit = 200L) {
  if (is.null(data)) data <- pscc2022_get()

  hit <- if (is.null(parent_code) || is.na(parent_code) || !nzchar(parent_code)) {
    is.na(data$parent_code)
  } else {
    !is.na(data$parent_code) & data$parent_code == parent_code
  }

  total <- sum(hit)
  out <- data[hit, , drop = FALSE]
  if (nrow(out) > 0L) out <- out[order(out$source_order), , drop = FALSE]
  truncated <- total > limit
  if (truncated) out <- out[seq_len(limit), , drop = FALSE]

  list(data = out, total_children = total, is_truncated = truncated, limit = limit)
}

#' Ancestor rows of a PSCC node, root-first.
#'
#' Walks `parent_code` upward. Bounded by `max_depth` so a malformed artifact
#' can never spin forever.
pscc_ancestors <- function(code, data = NULL, max_depth = 20L) {
  if (is.null(data)) data <- pscc2022_get()
  chain <- integer(0)
  cur <- code
  for (i in seq_len(max_depth)) {
    idx <- which(data$code == cur)
    if (length(idx) == 0L) break
    parent <- data$parent_code[idx[1L]]
    if (is.na(parent)) break
    pidx <- which(data$code == parent)
    if (length(pidx) == 0L) break
    chain <- c(pidx[1L], chain)
    cur <- parent
  }
  data[chain, , drop = FALSE]
}

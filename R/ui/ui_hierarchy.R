# UI-02 — hierarchy browser.
#
# PRESENTATION ONLY, and deliberately so: this module NEVER invents a
# parent/child relationship. Every edge it draws is a `parent_code` value
# that an adapter already published in the canonical schema (R/schema.R),
# and every node is a real record returned by `get_classification()`. If a
# system has no genuine canonical hierarchy, the browser is not offered at
# all -- PTSCS and PSCrCS group their records thematically by `component`
# and mint no codes of their own, so forcing them into a tree would be a
# fabricated structure, which the handoff explicitly forbids.
#
# ELIGIBILITY IS DERIVED, NEVER HARDCODED
# ---------------------------------------
# `hierarchy_is_eligible()` asks the repository two questions:
#   1. does the registry report the system as non-composite?
#   2. does its data actually contain at least one root (NA parent_code)
#      AND at least one child whose parent_code resolves to a real code in
#      the same edition?
# A system that stops publishing parent codes stops being eligible on its
# own, with no list to maintain here.
#
# INTERACTION
# -----------
# Lazy expansion: only top-level nodes are built on open; a node's children
# are rendered when the user expands it. Local search reveals matching
# nodes together with their ancestors (never a flat, context-free hit list).
#
# ACCESSIBILITY
# -------------
# Nested <ul>/<li> disclosure pattern. Every expandable node has a real
# <button> toggle carrying `aria-expanded` and `aria-controls`; every node
# label is a real <button>, so keyboard activation, focus order and focus
# visibility are native rather than re-implemented. The selected node
# carries `aria-current="true"` in addition to its visual treatment, so
# selection is never colour-only.
#
# PUBLIC CONTRACT:
#   hierarchy_is_eligible(system, version)
#   hierarchy_eligible_systems()
#   hierarchy_children(system, version, parent_code)
#   hierarchy_ancestors(system, version, code)
#   hierarchy_local_search(system, version, query, limit)
#   hierarchy_tree_ui(system, version, expanded, selected, matches, reveal)
#   hierarchy_entry_pane_ui(entry, system, version)
#   hierarchy_dialog_ui(system, version, query)
#   hierarchy_browse_button_ui(system, version)
#   hierarchy_browse_slot_ui()
#   hierarchy_browser_server(input, output, session, system, version, results)

# Input ids (documented in docs/UI_CONTRACT.md by the integrator).
HIERARCHY_INPUT_OPEN <- "hierarchy_open"
HIERARCHY_INPUT_TOGGLE <- "hierarchy_toggle"
HIERARCHY_INPUT_SELECT <- "hierarchy_select"
HIERARCHY_INPUT_QUERY <- "hierarchy_query"
HIERARCHY_INPUT_VIEW <- "hierarchy_view_in_search"
HIERARCHY_OUTPUT_SLOT <- "hierarchy_browse_slot"
HIERARCHY_OUTPUT_TREE <- "hierarchy_tree"
HIERARCHY_OUTPUT_ENTRY <- "hierarchy_entry"

# Rendering caps. A PSGC province can carry several hundred barangays; a
# capped list keeps the dialog usable and the DOM bounded. The cap is a
# DISPLAY limit only and is always announced, never silent.
HIERARCHY_CHILD_CAP <- 200L
HIERARCHY_SEARCH_CAP <- 40L

.hierarchy_cache <- new.env(parent = emptyenv())


# --- Index -------------------------------------------------------------

.hierarchy_key <- function(system, version) paste0(system, "@@", version)

# Build (once per system+version per R process) the small structures the
# tree needs: a parent map, a children index and a row lookup. This reads
# the canonical tibble and reshapes it; it computes no relationships of its
# own.
.hierarchy_index <- function(system, version) {
  key <- .hierarchy_key(system, version)
  hit <- .hierarchy_cache[[key]]
  if (!is.null(hit)) {
    return(hit)
  }

  d <- get_classification(system, version)
  code <- as.character(d$code)
  parent <- as.character(d$parent_code)

  # A parent_code that names no record in this edition is not a usable edge.
  # Treating it as one would draw a branch to a node that does not exist,
  # so such a row is indexed as a root instead of being silently dropped.
  resolvable <- !is.na(parent) & parent %in% code
  bucket <- ifelse(resolvable, parent, "__root__")

  idx <- list(
    system = system,
    version = version,
    data = d,
    code = code,
    parent = ifelse(resolvable, parent, NA_character_),
    row_of = stats::setNames(seq_along(code), code),
    children = split(code, factor(bucket, levels = unique(c("__root__", code)))),
    n_roots = sum(bucket == "__root__"),
    n_edges = sum(resolvable)
  )
  .hierarchy_cache[[key]] <- idx
  idx
}


# --- Eligibility -------------------------------------------------------

#' Does this system+version have a genuine canonical hierarchy?
#'
#' Derived from repository metadata and the data itself -- never from a
#' hardcoded list of system ids.
#'
#' @param system character(1).
#' @param version character(1) or NULL. NULL uses the registry's current
#'   version for that system.
#'
#' @return TRUE only when the registry reports a non-composite system whose
#'   data contains both roots and at least one resolvable parent edge.
hierarchy_is_eligible <- function(system, version = NULL) {
  if (is.null(system) || length(system) != 1L || is.na(system) || !nzchar(system)) {
    return(FALSE)
  }
  reg <- tryCatch(classification_registry(), error = function(e) NULL)
  if (is.null(reg)) {
    return(FALSE)
  }
  row <- reg[reg$id == system, , drop = FALSE]
  if (nrow(row) == 0L) {
    return(FALSE)
  }
  # A composite/thematic system partitions by component, not by code
  # hierarchy. It gets the Component control on Search, not a tree.
  if (isTRUE(row$is_composite[[1]])) {
    return(FALSE)
  }
  if (is.null(version) || is.na(version) || !nzchar(version)) {
    version <- row$current_version[[1]]
  }
  if (!version %in% row$available_versions[[1]]) {
    return(FALSE)
  }

  idx <- tryCatch(.hierarchy_index(system, version), error = function(e) NULL)
  if (is.null(idx)) {
    return(FALSE)
  }
  idx$n_roots > 0L && idx$n_edges > 0L
}

#' System ids whose current edition has a genuine canonical hierarchy.
hierarchy_eligible_systems <- function() {
  reg <- classification_registry()
  keep <- vapply(
    seq_len(nrow(reg)),
    function(i) hierarchy_is_eligible(reg$id[[i]], reg$current_version[[i]]),
    logical(1)
  )
  reg$id[keep]
}


# --- Navigation --------------------------------------------------------

#' Direct children of one node (or the roots when `parent_code` is NA).
#'
#' @return A zero-or-more-row slice of the canonical tibble, in the order
#'   the adapter published it. Never reordered by label: the published
#'   order is part of the classification.
hierarchy_children <- function(system, version, parent_code = NA) {
  idx <- .hierarchy_index(system, version)
  key <- if (is.null(parent_code) || length(parent_code) == 0L ||
             is.na(parent_code) || !nzchar(parent_code)) {
    "__root__"
  } else {
    parent_code
  }
  codes <- idx$children[[key]]
  if (is.null(codes) || length(codes) == 0L) {
    return(idx$data[0, , drop = FALSE])
  }
  idx$data[unname(idx$row_of[codes]), , drop = FALSE]
}

#' Ancestor codes of one node, ROOT FIRST, excluding the node itself.
#'
#' Cycle-safe: a malformed artifact that pointed a code at one of its own
#' ancestors would otherwise loop forever here.
hierarchy_ancestors <- function(system, version, code) {
  idx <- .hierarchy_index(system, version)
  out <- character(0)
  seen <- character(0)
  cur <- code
  while (TRUE) {
    pos <- idx$row_of[[cur]]
    if (is.null(pos) || is.na(pos)) break
    p <- idx$parent[[pos]]
    if (is.na(p) || p %in% seen) break
    out <- c(p, out)
    seen <- c(seen, p)
    cur <- p
  }
  out
}

#' Local hierarchy search: matching nodes PLUS their ancestors.
#'
#' Matching is a plain case-insensitive substring test over code and label.
#' It deliberately does NOT reuse the ranked retrieval engine: this is a
#' "find it in the tree I am looking at" affordance, not a second search
#' authority, and it must never present a different result order than the
#' published hierarchy.
#'
#' @return list(matches, reveal, total, truncated, query) where `reveal` is
#'   every code that must be rendered for each match to be visible in
#'   context (matches + all their ancestors).
hierarchy_local_search <- function(system, version, query, limit = HIERARCHY_SEARCH_CAP) {
  q <- if (is.null(query) || length(query) == 0L || is.na(query[[1]])) "" else trimws(query[[1]])
  if (!nzchar(q)) {
    return(list(matches = character(0), reveal = character(0),
                total = 0L, truncated = FALSE, query = ""))
  }
  idx <- .hierarchy_index(system, version)
  needle <- tolower(q)
  hit <- grepl(needle, tolower(idx$code), fixed = TRUE) |
    grepl(needle, tolower(as.character(idx$data$label)), fixed = TRUE)

  all_matches <- idx$code[hit]
  total <- length(all_matches)
  matches <- utils::head(all_matches, limit)

  ancestors <- unique(unlist(
    lapply(matches, function(cd) hierarchy_ancestors(system, version, cd)),
    use.names = FALSE
  ))
  list(
    matches = matches,
    reveal = unique(c(ancestors, matches)),
    total = total,
    truncated = total > length(matches),
    query = q
  )
}


# --- Tree rendering ----------------------------------------------------

# Escape a classification code for embedding in a single-quoted JS string.
# Codes are PSA-issued and alphanumeric today; this exists so that can
# never become an injection surface if an edition ever ships punctuation.
.hier_js_string <- function(x) {
  x <- gsub("\\", "\\\\", as.character(x), fixed = TRUE)
  x <- gsub("'", "\\'", x, fixed = TRUE)
  gsub("[\r\n]", " ", x)
}

.hier_dom_id <- function(prefix, code) {
  paste0(prefix, gsub("[^A-Za-z0-9_-]", "_", as.character(code)))
}

.hier_set_input <- function(input_id, code) {
  sprintf(
    "Shiny.setInputValue('%s', '%s', {priority: 'event'}); return false;",
    input_id, .hier_js_string(code)
  )
}

# A PSCC structural node has a synthetic id rather than a PSA code (see the
# Search results table). Printing that id would invite exactly the
# confusion the spec forbids, so the code slot is left blank for those rows
# and the level carries the distinction instead.
.hier_display_code <- function(row) {
  if ("is_selectable_code" %in% names(row) && isFALSE(row$is_selectable_code[[1]])) {
    return(NULL)
  }
  as.character(row$code[[1]])
}

.hier_node_ui <- function(idx, code, system, version, expanded, selected,
                          matches, reveal, depth) {
  pos <- idx$row_of[[code]]
  row <- idx$data[pos, , drop = FALSE]

  kids <- idx$children[[code]]
  if (!is.null(reveal) && length(reveal) > 0L && !is.null(kids)) {
    kids <- kids[kids %in% reveal]
  }
  has_children <- !is.null(kids) && length(kids) > 0L
  is_open <- has_children && code %in% expanded
  is_selected <- !is.null(selected) && identical(code, selected)
  is_match <- code %in% matches

  children_id <- .hier_dom_id("psa-hier-children-", code)
  label_text <- as.character(row$label[[1]])
  disp_code <- .hier_display_code(row)

  toggle <- if (has_children) {
    shiny::tags$button(
      type = "button",
      class = "psa-hier-toggle",
      `aria-expanded` = if (is_open) "true" else "false",
      `aria-controls` = children_id,
      # The accessible name states the action AND the node, so a screen
      # reader user never hears a column of unlabelled "Expand" buttons.
      `aria-label` = paste0(
        if (is_open) "Collapse " else "Expand ",
        if (is.null(disp_code)) label_text else paste(disp_code, label_text)
      ),
      onclick = .hier_set_input(HIERARCHY_INPUT_TOGGLE, code),
      shiny::tags$span(`aria-hidden` = "true", if (is_open) "▾" else "▸")
    )
  } else {
    shiny::tags$span(class = "psa-hier-spacer", `aria-hidden` = "true")
  }

  node_class <- paste(c(
    "psa-hier-node",
    if (is_selected) "psa-hier-node--selected",
    if (is_match) "psa-hier-node--match"
  ), collapse = " ")

  shiny::tags$li(
    class = node_class,
    `data-code` = code,
    shiny::tags$div(
      class = "psa-hier-row",
      toggle,
      shiny::tags$button(
        type = "button",
        class = "psa-hier-label",
        `aria-current` = if (is_selected) "true",
        onclick = .hier_set_input(HIERARCHY_INPUT_SELECT, code),
        if (!is.null(disp_code)) {
          shiny::tags$span(class = "psa-hier-code mono", disp_code)
        },
        shiny::tags$span(class = "psa-hier-text", label_text),
        # Search hits are labelled in TEXT, not only tinted.
        if (is_match) shiny::tags$span(class = "psa-hier-badge", "Match")
      )
    ),
    if (is_open) {
      .hier_list_ui(idx, kids, system, version, expanded, selected,
                    matches, reveal, depth + 1L, children_id)
    }
  )
}

.hier_list_ui <- function(idx, codes, system, version, expanded, selected,
                          matches, reveal, depth, list_id = NULL,
                          aria_label = NULL) {
  shown <- utils::head(codes, HIERARCHY_CHILD_CAP)
  shiny::tags$ul(
    id = list_id,
    class = "psa-hier-list",
    `aria-label` = aria_label,
    lapply(shown, function(cd) {
      .hier_node_ui(idx, cd, system, version, expanded, selected,
                    matches, reveal, depth)
    }),
    if (length(codes) > length(shown)) {
      shiny::tags$li(
        class = "psa-hier-node psa-hier-node--more",
        shiny::tags$p(
          class = "psa-hierarchy__hint",
          sprintf(
            "Showing the first %d of %d entries at this branch. Narrow the search above to see the rest.",
            length(shown), length(codes)
          )
        )
      )
    }
  )
}

#' Render the hierarchy tree.
#'
#' @param expanded character vector of node codes currently expanded.
#' @param selected character(1) or NULL.
#' @param matches character vector of local-search hits (badged).
#' @param reveal character vector or NULL. When non-NULL, only these codes
#'   (plus roots) are rendered -- the search-reveal view.
hierarchy_tree_ui <- function(system, version,
                              expanded = character(0),
                              selected = NULL,
                              matches = character(0),
                              reveal = NULL) {
  if (!hierarchy_is_eligible(system, version)) {
    return(psa_dialog_empty_ui(
      "This classification is not published with parent-child relationships, so it has no hierarchy to browse."
    ))
  }
  idx <- .hierarchy_index(system, version)
  roots <- idx$children[["__root__"]]
  if (!is.null(reveal) && length(reveal) > 0L) {
    roots <- roots[roots %in% reveal]
  }
  if (length(roots) == 0L) {
    return(psa_dialog_empty_ui("No entries match that search in this hierarchy."))
  }
  .hier_list_ui(
    idx, roots, system, version, expanded, selected, matches, reveal, 0L,
    aria_label = paste(toupper(system), version, "hierarchy")
  )
}


# --- Selected-entry pane -----------------------------------------------

.hier_fact <- function(term, value) {
  if (is.null(value) || length(value) == 0L || is.na(value) || !nzchar(as.character(value))) {
    return(NULL)
  }
  shiny::tagList(
    shiny::tags$dt(term),
    shiny::tags$dd(value)
  )
}

#' The selected-entry pane: code, label, level, edition, status, source and
#' the View in Search action (handoff UI-02).
hierarchy_entry_pane_ui <- function(entry, system = NULL, version = NULL) {
  if (is.null(entry) || nrow(entry) == 0L) {
    return(shiny::tags$div(
      class = "psa-hierarchy__entry",
      psa_dialog_empty_ui("Select an entry in the tree to see its details.")
    ))
  }
  entry <- entry[1, , drop = FALSE]
  system <- system %||% entry$system
  version <- version %||% entry$version

  ancestors <- tryCatch(
    hierarchy_ancestors(system, version, entry$code),
    error = function(e) character(0)
  )
  breadcrumb <- if (length(ancestors) > 0L) {
    shiny::tags$div(
      class = "psa-hierarchy__breadcrumb",
      paste(ancestors, collapse = " › "),
      " › ",
      shiny::tags$strong(entry$code)
    )
  }

  disp_code <- .hier_display_code(entry)

  shiny::tags$div(
    class = "psa-hierarchy__entry",
    shiny::tags$div(
      class = "psa-eyebrow",
      paste(toupper(system), "·", release_display_label(version))
    ),
    breadcrumb,
    if (!is.null(disp_code)) {
      shiny::tags$div(class = "mono psa-detail-code", disp_code)
    },
    shiny::tags$h3(class = "psa-detail-title", entry$label),
    shiny::tags$dl(
      class = "psa-hierarchy__facts",
      .hier_fact("Level", level_display_label(system, entry$level)),
      .hier_fact("Edition / release", release_display_label(version)),
      .hier_fact("Description", entry$description)
    ),
    shiny::tags$div(
      style = "margin-top: 12px;",
      status_badge(entry$status)
    ),
    source_line_ui(entry),
    shiny::tags$div(
      style = "margin-top: 16px;",
      psa_dialog_action_button(
        HIERARCHY_INPUT_VIEW,
        "View in Search",
        class = "psa-hierarchy__view"
      )
    )
  )
}


# --- Dialog ------------------------------------------------------------

#' The Browse hierarchy dialog.
#'
#' Body is two live outputs (tree + selected entry) so expansion and
#' selection re-render without rebuilding the dialog, which is what keeps
#' focus stable while the user navigates.
hierarchy_dialog_ui <- function(system, version, query = "") {
  reg <- classification_registry()
  row <- reg[reg$id == system, , drop = FALSE]
  short <- if (nrow(row) > 0L) row$short_name[[1]] else toupper(system)
  full <- if (nrow(row) > 0L) row$display_name[[1]] else toupper(system)

  psa_dialog_ui(
    id = "hierarchy-browser",
    variant = "modal",
    size = "xl",
    eyebrow = paste(short, "·", release_display_label(version)),
    title = paste(full, "— browse hierarchy"),
    description = paste(
      "Published parent-child structure for this edition.",
      "Expand a branch to load its entries."
    ),
    close_label = "Close the hierarchy browser",
    body = shiny::tagList(
      shiny::tags$div(
        class = "psa-hierarchy__search",
        shiny::textInput(
          HIERARCHY_INPUT_QUERY,
          "Find within this hierarchy",
          value = query,
          placeholder = "Find a code or title in this hierarchy",
          width = "100%"
        )
      ),
      shiny::tags$p(
        class = "psa-hierarchy__hint",
        "Matches are shown together with the branches they sit under."
      ),
      shiny::tags$div(
        class = "psa-hierarchy",
        shiny::tags$div(
          class = "psa-hierarchy__tree",
          shiny::uiOutput(HIERARCHY_OUTPUT_TREE)
        ),
        shiny::uiOutput(HIERARCHY_OUTPUT_ENTRY)
      )
    ),
    footer = psa_dialog_close_button()
  )
}

#' The "Browse hierarchy" trigger, or NULL for an ineligible system.
hierarchy_browse_button_ui <- function(system, version = NULL) {
  if (!hierarchy_is_eligible(system, version)) {
    return(NULL)
  }
  psa_dialog_open_button(
    HIERARCHY_INPUT_OPEN,
    "Browse hierarchy",
    class = "psa-dialog-open--quiet",
    aria_label = paste("Browse the", toupper(system), "hierarchy in a dialog")
  )
}

#' Placement slot for the trigger. Put this wherever the Search filters
#' live; the server fills or empties it as the selected system changes.
hierarchy_browse_slot_ui <- function() {
  shiny::tagList(
    psa_dialog_deps(),
    shiny::tags$div(
      class = "psa-hierarchy-slot",
      shiny::uiOutput(HIERARCHY_OUTPUT_SLOT)
    )
  )
}


# --- Server ------------------------------------------------------------

#' Install every hierarchy-browser observer and output.
#'
#' One call from app.R wires the whole feature. All state is local to this
#' function, so it is per-session by construction.
#'
#' @param system,version Reactives returning the currently selected Search
#'   system/version. Default to the public Search inputs.
#' @param results Optional reactive returning the Search results data frame,
#'   passed through to `view_in_search_apply()` so the record is selected in
#'   the table after the dialog closes.
hierarchy_browser_server <- function(input, output, session,
                                     system = NULL,
                                     version = NULL,
                                     results = NULL) {
  system <- system %||% shiny::reactive(input$classification_system)
  version <- version %||% shiny::reactive(input$classification_version)

  state <- shiny::reactiveValues(
    system = NULL,
    version = NULL,
    expanded = character(0),
    selected = NULL,
    search = NULL
  )

  output[[HIERARCHY_OUTPUT_SLOT]] <- shiny::renderUI({
    hierarchy_browse_button_ui(system(), version())
  })

  shiny::observeEvent(input[[HIERARCHY_INPUT_OPEN]], {
    sys <- system()
    ver <- version()
    shiny::req(hierarchy_is_eligible(sys, ver))
    state$system <- sys
    state$version <- ver
    state$expanded <- character(0)
    state$selected <- NULL
    state$search <- NULL
    psa_dialog_show(hierarchy_dialog_ui(sys, ver, query = ""), session = session)
  })

  hier_query <- shiny::debounce(
    shiny::reactive(input[[HIERARCHY_INPUT_QUERY]]),
    300
  )

  shiny::observeEvent(hier_query(), ignoreInit = TRUE, {
    shiny::req(state$system, state$version)
    res <- hierarchy_local_search(state$system, state$version, hier_query())
    if (length(res$matches) == 0L && !nzchar(res$query)) {
      state$search <- NULL
      return()
    }
    state$search <- res
    # Reveal each hit IN CONTEXT: its ancestors are expanded, never a flat
    # hit list detached from the branch it belongs to.
    state$expanded <- unique(c(
      state$expanded,
      unlist(lapply(res$matches, function(cd) {
        hierarchy_ancestors(state$system, state$version, cd)
      }), use.names = FALSE)
    ))
  })

  shiny::observeEvent(input[[HIERARCHY_INPUT_TOGGLE]], {
    code <- input[[HIERARCHY_INPUT_TOGGLE]]
    shiny::req(state$system, code)
    state$expanded <- if (code %in% state$expanded) {
      setdiff(state$expanded, code)
    } else {
      c(state$expanded, code)
    }
  })

  shiny::observeEvent(input[[HIERARCHY_INPUT_SELECT]], {
    shiny::req(state$system)
    state$selected <- input[[HIERARCHY_INPUT_SELECT]]
  })

  output[[HIERARCHY_OUTPUT_TREE]] <- shiny::renderUI({
    shiny::req(state$system, state$version)
    s <- state$search
    hierarchy_tree_ui(
      state$system, state$version,
      expanded = state$expanded,
      selected = state$selected,
      matches = if (is.null(s)) character(0) else s$matches,
      reveal = if (is.null(s)) NULL else s$reveal
    )
  })

  output[[HIERARCHY_OUTPUT_ENTRY]] <- shiny::renderUI({
    shiny::req(state$system, state$version)
    if (is.null(state$selected)) {
      return(hierarchy_entry_pane_ui(NULL))
    }
    entry <- get_classification_entry(state$system, state$version, state$selected)
    hierarchy_entry_pane_ui(entry, state$system, state$version)
  })

  shiny::observeEvent(input[[HIERARCHY_INPUT_VIEW]], {
    shiny::req(state$system, state$version, state$selected)
    entry <- get_classification_entry(state$system, state$version, state$selected)
    view_in_search_apply(entry, session = session, results = results)
  })

  for (o in c(HIERARCHY_OUTPUT_SLOT, HIERARCHY_OUTPUT_TREE, HIERARCHY_OUTPUT_ENTRY)) {
    shiny::outputOptions(output, o, suspendWhenHidden = FALSE)
  }

  invisible(NULL)
}

# Search screen — the default, dominant destination.
#
# PRESENTATION ONLY. This function builds the UI shell; it contains no
# classification/search logic (that lives in R/repository.R and R/search.R
# and is called from the server function in app.R).
#
# Stable IDs defined here, unchanged from the previous layout and
# documented in docs/UI_CONTRACT.md §4:
#   classification_system, classification_version, classification_level,
#   classification_query, classification_results, selected_entry
#
# Browse/Archive is NOT a separate destination. It lives here, exactly as
# before, through three preserved mechanisms:
#   1. the edition control (every edition, each tagged Current or Archived)
#   2. the level control
#   3. blank-query browse (an empty query lists the selected level)
#
# The edition control is a radio group rather than a select so that every
# available edition and its current/archived status are visible at a
# glance, per the approved design. The input ID and the value it yields are
# unchanged; only the widget type differs, so app.R updates it with
# updateRadioButtons() instead of updateSelectInput().

# ---- System selector: acronym + full official title (UI-01) ---------------
#
# The option text is ONE string, "PSIC — Philippine Standard Industrial
# Classification" (see `system_choice_label()`), and the two-line treatment
# is produced by splitting that string in selectize's own renderer. Doing it
# this way rather than by passing two fields buys three things:
#
#   1. Type-ahead keeps working by acronym AND by title terms with no extra
#      configuration: selectize's default `searchField: ["label"]` searches
#      exactly the string that contains both.
#   2. The <option> text in the underlying <select> -- what assistive
#      technology and any non-selectize fallback read -- still carries the
#      acronym and the full title.
#   3. Nothing about the submitted value changes; the renderer is presentation
#      only and the choice value stays the raw registry id.
#
# The renderer survives `updateSelectInput()`: Shiny's selectize binding
# destroys and re-creates the control by re-reading the
# `<script data-for="...">` config block that still sits in the DOM, so the
# `render`/`data-eval` options are reapplied on every choice update.
#
# `escape()` is selectize's own HTML escaper and is applied to both halves.
# The body is written out twice rather than hoisted into a shared global:
# these strings are eval'd by the selectize binding at input-init time, and
# depending on a separate <script> having already run would make the
# renderer's availability an ordering question for no real saving.
.psa_system_render_body <- function(cls) {
  paste0(
    "function(item, escape) {",
    "  var label = String(item.label == null ? '' : item.label);",
    "  var sep = label.indexOf(' \\u2014 ');",
    "  var acronym = sep === -1 ? label : label.slice(0, sep);",
    "  var title = sep === -1 ? '' : label.slice(sep + 3);",
    "  return '<div class=\"psa-sys-line ", cls, "\">'",
    "       + '<span class=\"psa-sys-acronym\">' + escape(acronym) + '</span>'",
    "       + (title ? '<span class=\"psa-sys-title\">' + escape(title) + '</span>' : '')",
    "       + '</div>';",
    "}"
  )
}

system_selector_render <- function() {
  I(paste0(
    "{ option: ", .psa_system_render_body("psa-sys-opt"),
    ", item: ", .psa_system_render_body("psa-sys-item"), " }"
  ))
}

#' Radio-group choices for the edition/release control (UI-01).
#'
#' Presentation only, and deliberately a pure function of its arguments so
#' the ordering rule can be tested without a session: it returns exactly the
#' three pieces `updateRadioButtons()` needs.
#'
#' Newest/current first, ordered by `release_newest_first()` -- canonical
#' identifiers, never display labels. `selected` is the current edition, so
#' reordering the list cannot change which edition is in effect.
#'
#' Current/Archived is carried by `status_badge()`, which spells the word
#' out; the row never relies on colour to say which is which.
#'
#' @param versions character vector of canonical edition identifiers, in
#'   repository order.
#' @param current character(1). The registry's current edition for this
#'   system.
#'
#' @return list(choiceNames = <list of tags>, choiceValues = <list of
#'   character(1)>, selected = character(1)).
edition_choice_spec <- function(versions, current) {
  ordered <- release_newest_first(versions, current)

  names_html <- lapply(ordered, function(v) {
    is_current <- identical(v, current)
    shiny::tags$span(
      class = if (is_current) "psa-edition-row psa-edition-row-current" else "psa-edition-row",
      shiny::tags$span(class = "psa-edition-name", release_display_label(v)),
      status_badge(if (is_current) "current" else "archived")
    )
  })

  list(
    choiceNames = names_html,
    choiceValues = as.list(ordered),
    selected = current
  )
}

search_ui <- function() {
  shiny::tagList(
    # --- Hero search (HANDOFF §4) -----------------------------------------
    # Same `classification_query` input as before; only its size and
    # position change. The <label> stays in the DOM for assistive tech and
    # is visually hidden by .psa-hero-field label -- never placeholder-only
    # labelling (docs/UI_CONTRACT.md §10).
    shiny::tags$div(
      class = "psa-hero",
      # The approved Search design intentionally leads with the input
      # rather than a visible page title, but the panel still needs a
      # top-level heading so the document's heading hierarchy isn't
      # missing its first rung for screen-reader users. Visually hidden,
      # semantically present.
      shiny::tags$h2(class = "visually-hidden", "Search classifications"),
      shiny::tags$div(
        class = "psa-hero-field",
        lucide_icon("search", 20),
        shiny::textInput(
          "classification_query",
          "Search a classification code or keyword",
          placeholder = "Search a code or keyword",
          width = "100%"
        )
      ),
      shiny::tags$p(
        class = "psa-hero-help",
        "Leave blank to browse the selected system and edition below."
      )
    ),

    # --- Sidebar + results/detail (HANDOFF §4) ----------------------------
    shiny::tags$div(
      class = "psa-search-body",
      shiny::tags$aside(
        class = "psa-sidebar psa-sidebar-wide",
        `aria-label` = "Classification filters",
        # UI-01: the System control keeps its stable id and its plain
        # `choices` contract; only the renderer changes, so
        # updateSelectInput() from app.R still drives it.
        shiny::div(
          class = "psa-system-field",
          shiny::selectizeInput(
            "classification_system", "System",
            choices = NULL, width = "100%",
            options = list(render = system_selector_render())
          )
        ),
        shiny::tags$div(
          class = "psa-edition-group",
          shiny::radioButtons(
            "classification_version",
            "Edition / release",
            choices = character(0),
            selected = character(0)
          )
        ),
        # Component control for composite/thematic systems (UI-05).
        #
        # Shown ONLY when the registry reports the selected system as
        # composite -- PTSCS and PSCrCS today. Those systems group records
        # by component (tourism industry vs. product; creative industry vs.
        # good/service vs. occupation) rather than by a code hierarchy, so
        # they get their own control instead of having their components
        # misrepresented as hierarchy levels. The ordinary Level control is
        # never globally renamed.
        #
        # The condition reads a server-side flag derived from the registry,
        # so a system whose ingestion failed and never registered can never
        # surface this control.
        shiny::conditionalPanel(
          condition = "output.classification_is_composite",
          shiny::selectInput(
            "classification_component", "Component",
            choices = NULL, width = "100%"
          )
        ),
        # Level control (UI-POST-03).
        #
        # Shown only when Level adds information beyond Component. For the
        # composite systems (PTSCS, PSCrCS) the level column repeats the
        # component token exactly, so offering both asks the same question
        # twice and exposes machine values such as `tourism_product`. The
        # flag is derived from the artifact server-side by
        # classification_level_is_informative(), never hard-coded per
        # system, and `level` stays fully available in the data model and
        # to every service function.
        shiny::conditionalPanel(
          condition = "output.classification_level_is_informative",
          shiny::selectInput(
            "classification_level", "Level",
            choices = NULL, width = "100%"
          )
        )
      ),
      shiny::tags$div(
        class = "psa-results-split",
        shiny::tags$div(
          shiny::uiOutput("classification_result_count"),
          DT::DTOutput("classification_results")
        ),
        shiny::tags$div(
          shiny::tags$div(
            class = "psa-detail-head",
            shiny::tags$h6("Selected entry"),
            # Reserved layout slot (HANDOFF §12) -- inert placeholder, NOT a
            # control. A <span>, aria-hidden, not focusable, no hover or
            # cursor affordance. Wiring it later means swapping this span
            # for a real control in the same position; nothing else moves.
            shiny::tags$span(
              class = "psa-askrm-reserved",
              `aria-hidden` = "true",
              lucide_icon("sparkles", 14),
              "Ask RM about this"
            )
          ),
          shiny::uiOutput("selected_entry")
        )
      )
    )
  )
}

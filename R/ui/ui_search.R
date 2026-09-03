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
# EDITION CONTROL (imported design, surface 1a).
#
# The edition control used to be a permanently expanded radio list, so a
# system with thirteen PSGC releases pushed Level off the bottom of the
# rail. It is now a COLLAPSED control that states the selected release and
# its CURRENT / ARCHIVED status on one line and discloses the full grouped
# list on demand -- a popover on desktop, a sheet at phone width.
#
# The radio group itself is unchanged and merely MOVED inside that panel:
# same `classification_version` id, same widget type, same
# `updateRadioButtons()` update path, same raw canonical values. The
# disclosure layer lives in R/ui/ui_pickers.R.

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
#' GROUPING (imported design, surface 1a). The disclosed list is grouped
#' into Current and Archived, with the archived group carrying its own
#' count. The headers ride inside the first choice of each group rather
#' than being separate DOM nodes, because `radioButtons()` owns the
#' structure between the choices and interleaving markup there would mean
#' hand-building the group and losing the Shiny input binding. Ordering is
#' untouched: the header follows the group, the group does not follow the
#' header.
#'
#' @param versions character vector of canonical edition identifiers, in
#'   repository order.
#' @param current character(1). The registry's current edition for this
#'   system.
#'
#' @return list(choiceNames = <list of tags>, choiceValues = <list of
#'   character(1)>, selected = character(1)).
# The Search screen's own "View details" trigger. Named here rather than in
# app.R so the id has one owner, like every other Search input in this file.
SEARCH_VIEW_DETAILS_INPUT <- "search_view_details"

edition_choice_spec <- function(versions, current) {
  ordered <- release_newest_first(versions, current)
  is_current <- vapply(ordered, function(v) identical(v, current), logical(1))
  n_archived <- sum(!is_current)
  first_archived <- if (n_archived > 0L) which(!is_current)[[1]] else NA_integer_

  names_html <- lapply(seq_along(ordered), function(i) {
    v <- ordered[[i]]
    cur <- is_current[[i]]
    header <- if (i == 1L && cur) {
      shiny::tags$span(class = "psa-edition-group-head", "Current")
    } else if (!is.na(first_archived) && i == first_archived) {
      shiny::tags$span(
        class = "psa-edition-group-head",
        sprintf("Archived · %d", n_archived)
      )
    }
    shiny::tags$span(
      class = if (cur) "psa-edition-row psa-edition-row-current" else "psa-edition-row",
      header,
      shiny::tags$span(class = "psa-edition-name", release_display_label(v)),
      status_badge(if (cur) "current" else "archived")
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
    # Disclosure behaviour for the collapsed System / Edition controls, and
    # the shared dialog shell the mobile System sheet opens into. Both are
    # idempotent.
    psa_picker_deps(),
    psa_dialog_deps(),

    # --- Page head + search field (design surface 1a) ---------------------
    #
    # The design removes the hero BAND: there is no eyebrow, no wash and no
    # centred display treatment. What is left is a page title, one line of
    # help, and a single full-width search field directly beneath -- the
    # widest control on the page, which is what marks it as the primary
    # action. The `classification_query` input, its visually-hidden
    # <label> and its placeholder are unchanged.
    shiny::tags$div(
      class = "psa-hero psa-hero--page",
      shiny::tags$div(
        class = "psa-hero-head",
        shiny::tags$div(
          class = "psa-hero-headings",
          shiny::tags$h2(
            class = "psa-hero-title",
            "Find the ", shiny::tags$em("official"), " code"
          ),
          shiny::tags$p(
            class = "psa-hero-help",
            "Search one classification system at a time. Leave the field ",
            "blank to browse the selected system and edition."
          )
        ),
        # Contextual assistant entry point for the selected record lives in
        # the selected-entry card (below); this one is page-level.
        shiny::tags$div(class = "psa-hero-actions", rm_ask_button_ui(
          "search_ask_rm_page", "Ask RM about a code"
        ))
      ),
      shiny::tags$div(
        class = "psa-hero-field psa-liquid-glass",
        lucide_icon("search", 20),
        shiny::textInput(
          "classification_query",
          "Search a classification code or keyword",
          placeholder = "Search a code or keyword",
          width = "100%"
        )
      )
    ),

    # --- Filter rail + results/detail (design surface 1a) -----------------
    shiny::tags$div(
      class = "psa-search-body",
      shiny::tags$aside(
        class = "psa-sidebar psa-sidebar-wide psa-liquid-glass psa-liquid-glass--flow",
        `aria-label` = "Classification filters",
        # UI-01: the System control keeps its stable id and its plain
        # `choices` contract; only the renderer changes, so
        # updateSelectizeInput() from app.R still drives it. The phone-width
        # sheet trigger travels with it (R/ui/ui_pickers.R).
        system_field_ui(),
        # Collapsed Edition / release control. The radio group it discloses
        # is the same `classification_version` input as before.
        edition_field_ui(),
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
          class = "psa-results-col",
          # RESULTS TOOLBAR (design surface 1a).
          #
          # Browse hierarchy leaves the bottom of the filter rail and joins
          # the count it scopes. Only the MOUNT POINT moves: the slot, the
          # trigger it renders, the dialog, lazy expansion and View in
          # Search are all the existing hierarchy feature, wired by the one
          # unchanged `hierarchy_browser_server()` call in app.R.
          shiny::tags$div(
            class = "psa-results-toolbar",
            shiny::uiOutput("classification_result_count"),
            hierarchy_browse_slot_ui()
          ),
          DT::DTOutput("classification_results")
        ),
        shiny::tags$div(
          class = "psa-detail-col",
          shiny::tags$div(
            class = "psa-detail-head",
            shiny::tags$h6("Selected entry")
          ),
          shiny::uiOutput("selected_entry"),
          # Actions for the selected record: View details (the official
          # reference) and, where the deployment has an assistant, Ask RM.
          # Rendered as one slot so the pair cannot drift apart.
          # Contextual assistant entry point for the selected record. This
          # replaces the inert `.psa-askrm-reserved` placeholder the
          # previous pass left here: the reserved slot is now a real
          # control in the same position, and it opens the global assistant
          # with this record attached rather than navigating anywhere.
          shiny::uiOutput("selected_entry_actions")
        )
      )
    )
  )
}

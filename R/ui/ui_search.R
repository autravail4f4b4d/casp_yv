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
        shiny::tags$i(class = "ph ph-magnifying-glass", `aria-hidden` = "true"),
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
        class = "psa-sidebar",
        `aria-label` = "Classification filters",
        shiny::selectInput(
          "classification_system", "System",
          choices = NULL, width = "100%"
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
              shiny::tags$i(class = "ph ph-sparkle"),
              "Ask RM about this"
            )
          ),
          shiny::uiOutput("selected_entry")
        )
      )
    )
  )
}

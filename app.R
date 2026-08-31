# PSA Statistical Classifications Search — minimal, design-ready Shiny UI.
#
# This file (plus R/ui/*.R and www/app.css) is the ONLY layer Claude Design
# should need to touch in the follow-up visual pass. All classification
# lookup/search/version/archive logic lives in R/repository.R, R/search.R,
# R/registry.R, and R/adapters/*.R, and is called here only through the
# stable service contract -- no classification-specific transformation
# happens in this file. See docs/UI_CONTRACT.md for the full contract.

r_files <- list.files("R", pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
invisible(lapply(sort(r_files), source))

library(shiny)
library(bslib)

# Sentinel for the "All levels" / "All components" choices (UI-04).
#
# Deliberately a non-empty string. An empty-string value makes selectize
# render the entry as greyed PLACEHOLDER text rather than a chosen option,
# so "All levels" looked like an empty control the user had failed to fill
# in -- which is what human UAT reported. A real token renders as a real
# selected option while still meaning "no level restriction": it is
# translated back to NULL before it ever reaches a service, so the
# repository never sees a literal "All levels" where it expects a
# classification level.
ALL_LEVELS_VALUE <- "__all_levels__"
ALL_COMPONENTS_VALUE <- "__all_components__"

#' Tab label: Lucide glyph + visible text.
#'
#' The icon is decorative and `aria-hidden`; the visible text is the tab's
#' accessible name. bslib's navset supplies the role="tab"/aria-selected
#' semantics around this, which the restyle preserves. Glyphs are inlined
#' local SVG (R/ui/ui_icons.R) -- no CDN request and no icon font, so a tab
#' can never render as a blank square on a restricted network.
nav_label <- function(icon, text) {
  shiny::tagList(
    lucide_icon(icon, 18, class = "psa-nav-icon"),
    text
  )
}

# NOTE: the former `.component_display_name()` helper lived here. It
# title-cased the raw component token, which could never produce the
# published category names ("Tourism Characteristic Products"). It has been
# replaced by component_display_label() / component_choice_vector() in
# R/ui/ui_labels.R, where the explicit mapping is defined and tested.

ui <- bslib::page_navbar(
  title = "Statistical Classifications",
  # "Subtle Gradient" light theme (HANDOFF-CLAUDE-CODE.md v2.0), which
  # supersedes the v1.0 Nocturne dark system entirely.
  #
  # Setting bg/fg/primary on bs_theme rather than overriding Bootstrap in
  # CSS is what makes every Bootstrap component -- form controls, cards,
  # tables, DT -- inherit the palette coherently. It is also why the
  # dark-to-light inversion has to happen HERE and not only in app.css: a
  # stylesheet override alone would leave DT, selectize and the navbar
  # rendering dark chrome under light content.
  theme = bslib::bs_theme(
    version = 5,
    bg = "#ffffff",
    fg = "#202124",
    primary = "#54436b",
    "body-bg" = "#ffffff",
    "card-bg" = "#ffffff",
    "border-color" = "#e6e6e6",
    "link-color" = "#2f5f8f",
    "link-hover-color" = "#416fa1",
    # System font stack deliberately -- no webfont download, so the app has
    # no third-party runtime dependency and no first-paint font swap.
    base_font = bslib::font_collection(
      "system-ui", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "sans-serif"
    )
  ),
  # `id` makes the active tab available server-side as `input$main_nav`,
  # a real, reliably-updating Shiny input -- unlike Shiny's implicit
  # per-output suspend/resume-on-visibility mechanism, which was found to
  # be unreliable in practice for outputs (especially DT widgets, which
  # can initialize at a broken zero-width layout if built while hidden)
  # inside a non-default nav_panel. Explicitly gating each secondary tab's
  # outputs on `input$main_nav` (see `render_dual_panel()` and the
  # Compare PSIC Editions / About outputs below) is the robust fix used
  # throughout this server function instead.
  id = "main_nav",
  header = shiny::tags$head(shiny::tags$link(rel = "stylesheet", href = "app.css")),
  # Visible tab LABELS change per HANDOFF §2; the `value =` identities that
  # drive input$main_nav are deliberately untouched, so every existing
  # req(input$main_nav == ...) gate below keeps working unchanged.
  #
  # nav_label() pairs each label with its Phosphor glyph. The icon is
  # aria-hidden -- the visible text is the accessible name, so the tab is
  # never announced as an icon and never relies on the glyph loading.
  bslib::nav_panel(nav_label("search", "Search"),
                   value = "search", search_ui()),
  bslib::nav_panel(nav_label("arrow-left-right", "PSOC + PSIC"),
                   value = "dual_search", dual_search_ui()),
  bslib::nav_panel(nav_label("split", "Compare Editions"),
                   value = "correspondence", correspondence_ui()),
  # RM Assistant. Which panel body is built is decided ONCE at startup from
  # the deployment's provider configuration: a deployment either has a
  # working assistant configuration or it does not (spec 21). When it does
  # not, the deterministic Search/Browse/Dual/Correspondence tabs are
  # completely unaffected -- that independence is the whole point, and is
  # asserted by tests/testthat/test-assistant-integration.R.
  bslib::nav_panel(
    nav_label("sparkles", "RM Assistant"), value = "rm_assistant",
    local({
      st <- rm_assistant_status()
      if (isTRUE(st$enabled) && isTRUE(st$available)) {
        rm_assistant_ui()
      } else {
        rm_assistant_unavailable_ui(st$reason)
      }
    })
  ),
  bslib::nav_panel(nav_label("info", "Sources"),
                   value = "about", shiny::uiOutput("sources_panel")),
  footer = shiny::tags$footer(
    class = "text-muted small p-2 border-top mt-2",
    "Source: Philippine Statistics Authority (PSA). This is a read-only reference tool; PSA is the authoritative classification source."
  )
)

server <- function(input, output, session) {
  registry <- classification_registry()

  # --- Classification system choices (populated once; registry is static
  # for the lifetime of an R process). ---
  system_choices <- stats::setNames(registry$id, paste0(registry$short_name, " — ", registry$display_name))
  updateSelectInput(session, "classification_system", choices = system_choices, selected = system_choices[[1]])

  # --- Edition/release choices follow the selected system. ---
  #
  # Rendered as a radio group (approved design) rather than a select, so
  # every available edition AND its current/archived status are visible at
  # once -- this is where Browse/Archive lives, so hiding the archived
  # editions behind a closed dropdown would bury the feature.
  #
  # The input ID and the value it yields are unchanged; only the widget
  # type differs, hence updateRadioButtons() here instead of
  # updateSelectInput(). choiceNames carries rich HTML (edition + status
  # badge) while choiceValues stays the plain version string the whole
  # service layer already expects.
  observeEvent(input$classification_system, {
    req(input$classification_system)
    versions <- classification_versions(input$classification_system)
    current <- registry$current_version[registry$id == input$classification_system][[1]]

    # UI-POST-06: the label is humanised (`Q1_2023` -> `Q1 2023`) while
    # choiceValues stays the raw identifier the whole service layer expects,
    # so nothing downstream sees the pretty form. Order is untouched, which
    # keeps the release history chronological.
    choice_names <- lapply(versions, function(v) {
      shiny::tagList(
        shiny::tags$span(class = "psa-edition-name", release_display_label(v)),
        status_badge(if (identical(v, current)) "current" else "archived")
      )
    })

    updateRadioButtons(
      session, "classification_version",
      choiceNames = choice_names,
      choiceValues = as.list(versions),
      selected = current
    )
  }, ignoreNULL = TRUE)

  # --- Level choices follow the selected system+version. Resetting to
  # "All levels" here is what satisfies UAT case 13 (switching classification
  # clears/updates invalid level/version state) -- a level id from the
  # previous system (e.g. psgc's "Bgy") can never linger as a selected but
  # invalid level for the newly selected system. ---
  observeEvent(input$classification_version, {
    req(input$classification_system, input$classification_version)
    # Defensive guard against a transient mismatched pair: when the system
    # selector changes, this observer and the system-change observer above
    # can both be mid-flight, and a client round-trip can momentarily
    # deliver a version value that belongs to the PREVIOUS system (e.g.
    # version "2022" arriving while classification_system still reads
    # "psgc"). classification_levels() would otherwise raise an uncaught
    # validation error and crash this observer. Silently skip: the
    # system-change observer's own updateRadioButtons() call will shortly
    # settle classification_version (and re-trigger this observer) to a
    # value that's actually valid for the current system.
    if (!input$classification_version %in% classification_versions(input$classification_system)) {
      return(invisible(NULL))
    }
    # UI-POST-03: labels are humanised, values stay raw. `Bgy` shows as
    # "Barangay" and `sub_major_group` as "Sub major group", but the
    # repository still receives the exact level token it validates against.
    levels <- classification_levels(input$classification_system, input$classification_version)
    level_choices <- c(
      "All levels" = ALL_LEVELS_VALUE,
      level_choice_vector(input$classification_system, levels)
    )
    updateSelectInput(session, "classification_level", choices = level_choices, selected = ALL_LEVELS_VALUE)

    # --- Component control for composite systems (UI-05) -----------------
    #
    # PTSCS and PSCrCS are thematic: they mint no codes of their own, they
    # select codes out of PSIC / CPC / PSOC and group them by component.
    # Forcing those components into the Level control would present them as
    # a code hierarchy, which they are not. So the Component select is a
    # SEPARATE control, shown only for systems the registry marks composite
    # -- the ordinary Level control is never renamed globally.
    components <- classification_components(input$classification_system)
    if (length(components) > 0L) {
      # UI-POST-03: the published category names ("Tourism Characteristic
      # Products", "Creative Goods and Services"), not a title-cased token.
      component_choices <- c(
        "All components" = ALL_COMPONENTS_VALUE,
        component_choice_vector(input$classification_system, components)
      )
      updateSelectInput(
        session, "classification_component",
        choices = component_choices, selected = ALL_COMPONENTS_VALUE
      )
    }
  }, ignoreNULL = TRUE)

  # Drives the conditionalPanel wrapping the Component control: TRUE only
  # for systems the registry itself reports as composite, so a system whose
  # ingestion failed (and so never reached the registry) can never surface
  # a component control.
  output$classification_is_composite <- reactive({
    req(input$classification_system)
    length(classification_components(input$classification_system)) > 0L
  })
  outputOptions(output, "classification_is_composite", suspendWhenHidden = FALSE)

  # --- Should the Level control be shown at all? (UI-POST-03) ------------
  #
  # Component is the primary public filter for composite systems. In both
  # PTSCS and PSCrCS the `level` column repeats the component token exactly
  # (audited: every component maps to exactly one level, and the two strings
  # are identical), so offering Level asks the same question twice and leaks
  # machine tokens like `tourism_product` into the UI.
  #
  # The verdict is DERIVED from the artifact by
  # classification_level_is_informative(), not hard-coded per system: a
  # future edition that introduces genuine sub-levels inside a component
  # starts showing the control again with no change here.
  output$classification_level_is_informative <- reactive({
    req(input$classification_system, input$classification_version)
    if (!input$classification_version %in% classification_versions(input$classification_system)) {
      return(TRUE)
    }
    classification_level_is_informative(
      input$classification_system,
      input$classification_version,
      component = current_component()
    )
  })
  outputOptions(output, "classification_level_is_informative", suspendWhenHidden = FALSE)

  query_debounced <- reactive(input$classification_query) |> debounce(250)

  # Sentinel -> NULL, and anything that is not a genuine level for the
  # CURRENT system+version -> NULL as well. Two states need that second
  # guard: the input's initial "" before the first updateSelectInput()
  # round-trip lands, and a stale level left over for one round-trip after
  # the user switches system (psgc's "Bgy" while psic is already selected).
  # Both must read as "no restriction" rather than reaching the repository,
  # which correctly rejects an unknown level.
  current_level <- reactive({
    lvl <- input$classification_level
    if (is.null(lvl) || !nzchar(lvl) || identical(lvl, ALL_LEVELS_VALUE)) {
      return(NULL)
    }
    req(input$classification_system, input$classification_version)
    if (!input$classification_version %in% classification_versions(input$classification_system)) {
      return(NULL)
    }
    if (!lvl %in% classification_levels(input$classification_system, input$classification_version)) {
      return(NULL)
    }
    # UI-POST-03: when the Level control is hidden because it only restates
    # Component, a level value left behind in the client input must not go
    # on silently filtering results that the user can no longer see a
    # control for. Hidden means inert, not merely invisible.
    if (!classification_level_is_informative(
      input$classification_system, input$classification_version,
      component = current_component()
    )) {
      return(NULL)
    }
    lvl
  })

  # Sentinel -> NULL, and never send a component to a system that has none
  # (a stale value can linger for one round-trip after switching systems).
  current_component <- reactive({
    cmp <- input$classification_component
    if (is.null(cmp) || identical(cmp, ALL_COMPONENTS_VALUE)) {
      return(NULL)
    }
    if (!cmp %in% classification_components(input$classification_system)) {
      return(NULL)
    }
    cmp
  })

  # UI-POST-03: changing Component can leave a Level selection that is no
  # longer valid inside the new component. Reset to "All levels" so a stale
  # choice can never silently narrow the result set.
  observeEvent(input$classification_component, {
    req(input$classification_system)
    if (length(classification_components(input$classification_system)) == 0L) {
      return(invisible(NULL))
    }
    updateSelectInput(session, "classification_level", selected = ALL_LEVELS_VALUE)
  }, ignoreNULL = TRUE, ignoreInit = TRUE)

  # UI-POST-05: the search service now returns the true match total
  # alongside the materialized page, so the count line and the table can
  # never disagree and the 200-row rendering cap is never mistaken for the
  # number of matches.
  search_result <- reactive({
    req(input$classification_system, input$classification_version)
    validate(need(
      input$classification_version %in% classification_versions(input$classification_system),
      "Loading edition..."
    ))
    res <- search_classification_result(
      system = input$classification_system,
      version = input$classification_version,
      query = query_debounced(),
      level = current_level(),
      limit = 200,
      component = current_component()
    )

    # UI-POST-07 section 9.11: PSCC publishes two cross-reference columns
    # (2019 PSCC and AHTN 2022) that the ordinary ranked search does not
    # look at, because they are NOT this edition's codes. Searching a 2019
    # code such as "0101.29.00-01" therefore returned nothing at all, even
    # though the workbook maps it to a live 2022 commodity.
    #
    # The fallback runs ONLY when the ordinary search found nothing, so
    # normal ranking and ordering are untouched for every other query --
    # this adds a way to find a record, it does not reorder the ones that
    # were already found. The match reason is surfaced separately so a
    # cross-reference is never mistaken for the 2022 code itself.
    res$match_reason <- NULL
    if (identical(input$classification_system, "pscc") &&
        res$total_matches == 0L &&
        nzchar(trimws(query_debounced() %||% ""))) {
      xr <- pscc_crossref_search(query_debounced(), limit = 200)
      if (nrow(xr) > 0L) {
        reason <- unique(xr$match_reason)
        res <- list(
          data = xr[, setdiff(names(xr), c("match_field", "matched_value", "match_reason")), drop = FALSE],
          total_matches = nrow(xr),
          returned_count = nrow(xr),
          limit = 200L,
          is_truncated = FALSE,
          match_reason = if (length(reason) == 1L) reason else NULL
        )
      }
    }
    res
  })

  # Every existing consumer of results() keeps working unchanged: it is now
  # just the materialized slice of the count-aware result.
  results <- reactive(search_result()$data)

  # Result count above the table (approved design). Reads the same
  # reactive as the table itself, so the two can never disagree. The exact
  # wording lives in format_result_count() in R/search.R -- a single pure
  # function -- so the UI cannot reinvent the truncation phrasing.
  output$classification_result_count <- renderUI({
    r <- search_result()
    tags$div(
      tags$div(
        class = "psa-result-count",
        format_result_count(
          r$total_matches, r$returned_count, r$is_truncated,
          limit = r$limit,
          is_browsing = !nzchar(trimws(query_debounced() %||% ""))
        )
      ),
      # "Matched 2019 PSCC cross-reference: 0101.29.00-01" -- shown only when
      # the match came through a cross-reference column, so the user is never
      # left thinking the code they typed is this edition's code.
      pscc_match_reason_ui(r$match_reason)
    )
  })

  output$classification_results <- DT::renderDT({
    d <- results()
    display <- d[, c("code", "label", "level", "status")]
    # UI-POST-03: the Level column is a public column too -- printing the raw
    # token here would leak `sub_major_group` / `tourism_product` just as
    # surely as the selector did. The underlying value is untouched.
    display$level <- level_display_label(input$classification_system, display$level)
    # UI-POST-07: PSCC carries genuine structural nodes (section captions,
    # descriptor-only hierarchy rows, sub-chapter markers) alongside real
    # commodity codes. Those nodes have no PSA code at all -- the adapter
    # gives them a synthetic `PSCC-STRUCT-nnnnn` id purely so the canonical
    # schema's non-NA code contract holds. Printing that id in the Code
    # column would invite exactly the confusion the spec forbids, so the
    # column shows an em dash and the Level column ("Structural group")
    # carries the distinction instead. The underlying row is untouched.
    if ("is_selectable_code" %in% names(d)) {
      display$code[!d$is_selectable_code] <- "—"
    }
    names(display) <- c("Code", "Label", "Level", "Status")
    DT::datatable(
      display,
      selection = "single",
      rownames = FALSE,
      # dom = "tip", NOT "ftip" (UI-03). The "f" is DataTables' own search
      # box, which sat directly under the 56px hero search and filtered only
      # the rows already returned -- a different mental model from the hero
      # field, which queries the whole classification repository. Human UAT
      # found the pair confusing. Sorting ("t" table), pagination ("p") and
      # the result-count info line ("i") are all retained.
      #
      # order = list() (pre-commit retrieval hardening audit, H12): DataTables'
      # own default is an initial ascending sort on column 0, applied purely
      # as STRING comparison -- so "833" (a prefix of "8332") sorts before
      # "8332" regardless of which one the server ranked first. This was
      # invisible before hybrid retrieval because an exact-code/exact-title
      # match was always the ONLY row returned; the hybrid tiers can now add
      # a second, lower-relevance row underneath it, and DT's default sort
      # was silently displaying that lower-relevance row on top -- exactly
      # backwards from "exact code/title outranks everything" (core contract
      # 1-2), even though the server's own `data` was already ordered
      # correctly. Disabling only the INITIAL sort restores server order on
      # first paint; `ordering` stays at its default TRUE, so a user can
      # still click a header to sort interactively.
      options = list(pageLength = 15, dom = "tip", order = list()),
      class = "stripe hover"
    )
  })

  selected_entry <- reactive({
    idx <- input$classification_results_rows_selected
    d <- results()
    if (is.null(idx) || nrow(d) == 0L) {
      return(d[0, , drop = FALSE])
    }
    d[idx, , drop = FALSE]
  })

  output$selected_entry <- renderUI({
    entry <- selected_entry()
    # UI-POST-07 section 9.12: a commodity record is not well served by the
    # generic code/label detail block -- it needs its hierarchy breadcrumb,
    # unit of quantity, and the 2019 PSCC / AHTN 2022 values shown as
    # explicitly labelled CROSS-REFERENCES rather than as further codes of
    # its own. PSCC therefore gets its own detail panel; every other system
    # keeps the shared one.
    if (identical(input$classification_system, "pscc") && nrow(entry) > 0L) {
      pscc_detail_ui(entry)
    } else {
      entry_detail_ui(entry)
    }
  })

  output$sources_panel <- renderUI({
    req(input$main_nav == "about")
    sources_ui()
  })
  # Forced always-on + explicitly gated on input$main_nav (see the `id =
  # "main_nav"` comment on page_navbar() above) rather than relying on
  # Shiny's implicit suspend-when-hidden/resume-on-shown behavior, which
  # this output has no reactive inputs to naturally re-trigger and which
  # was found unreliable in practice for other outputs in this app.
  outputOptions(output, "sources_panel", suspendWhenHidden = FALSE)

  # --- PSOC + PSIC: TWO INDEPENDENT SEARCHES (UI-POST-02, spec section 4) --
  #
  # Each side owns its own query input, its own edition selector, its own
  # count, its own table and its own selection/detail panel. There is no
  # shared query reactive and no shared result object any more: no PSIC
  # output reads any PSOC input, or vice versa, so a PSOC code can never
  # imply a PSIC code by construction rather than merely by convention.
  #
  # Defaults are each system's current edition (PSOC 2022 / PSIC Revision 5
  # 2026) per spec section 8; either selector can be switched to an archived
  # edition independently of the other.
  updateSelectInput(
    session, "dual_search_psoc_version",
    choices = classification_versions("psoc"),
    selected = registry$current_version[registry$id == "psoc"][[1]]
  )
  updateSelectInput(
    session, "dual_search_psic_version",
    choices = classification_versions("psic"),
    selected = registry$current_version[registry$id == "psic"][[1]]
  )

  dual_psoc_query <- reactive(input$dual_search_psoc_query) |> debounce(250)
  dual_psic_query <- reactive(input$dual_search_psic_query) |> debounce(250)

  # Version fallback, unchanged in spirit from the previous single-query
  # implementation: these outputs are forced always-active, so a side can be
  # asked to evaluate before updateSelectInput()'s client round-trip has
  # landed and input$dual_search_*_version is still NULL. req()-blocking here
  # left the output permanently stuck in a blank/never-recomputed state in
  # testing. Falling back to the registry's own current version always
  # produces a real result and self-corrects once the real input arrives
  # (which invalidates and re-runs the reactive normally).
  dual_version <- function(system_id) {
    v <- input[[paste0("dual_search_", system_id, "_version")]]
    if (is.null(v) || !nzchar(v)) {
      registry$current_version[registry$id == system_id][[1]]
    } else {
      v
    }
  }

  # Per-side failure isolation (spec section 10). search_parallel_
  # classifications() used to provide this; with two different queries a
  # shared parallel call no longer fits, so the isolation is explicit here.
  # A validation failure on one system must never blank the other side.
  dual_side_search <- function(system_id, version, query) {
    tryCatch(
      list(
        result = dual_search_side_result(system_id, version, query, limit = 100),
        error = NULL
      ),
      error = function(e) list(result = NULL, error = conditionMessage(e))
    )
  }

  dual_psoc <- reactive(
    dual_side_search("psoc", dual_version("psoc"), dual_psoc_query())
  )
  dual_psic <- reactive(
    dual_side_search("psic", dual_version("psic"), dual_psic_query())
  )

  # Every output here is forced always-on (suspendWhenHidden = FALSE) AND
  # explicitly gated on `req(input$main_nav == "dual_search")` as its FIRST
  # line. The gate is what actually matters: it stops the DT widget from ever
  # being built while its nav_panel is hidden (a DT initialized at
  # `display:none` freezes at a broken zero-width layout that never recovers,
  # even after the tab becomes visible and the underlying data later
  # changes). Forcing the output always-on is safe only because of that gate.
  render_dual_panel <- function(system_id, side, query_r) {
    id <- function(suffix) paste0("dual_search_", system_id, "_", suffix)

    output[[id("count")]] <- renderUI({
      req(input$main_nav == "dual_search")
      s <- side()
      if (!is.null(s$error)) return(NULL)
      tags$div(
        class = "psa-result-count",
        dual_search_side_count_text(s$result, query_r())
      )
    })

    output[[id("state")]] <- renderUI({
      req(input$main_nav == "dual_search")
      s <- side()
      if (!is.null(s$error)) {
        tags$p(class = "text-danger small", paste("Error:", s$error))
      } else if (nrow(s$result$data) == 0L) {
        tags$p(class = "text-muted small", "No results.")
      } else {
        NULL
      }
    })

    output[[id("results")]] <- DT::renderDT({
      req(input$main_nav == "dual_search")
      s <- side()
      req(is.null(s$error))
      d <- s$result$data
      req(nrow(d) > 0L)
      display <- d[, c("code", "label", "level", "status")]
      # Same public-label rule as the Search grid (UI-POST-03).
      display$level <- level_display_label(system_id, display$level)
      names(display) <- c("Code", "Label", "Level", "Status")
      # order = list(): same fix and same reason as the Search results table
      # (H12) -- this panel is fed by the same hybrid-aware
      # search_classification_result(), so it carries the identical latent
      # risk of DT's default string-ascending sort displacing an exact
      # code/title match beneath a lower-relevance hybrid-tier row.
      DT::datatable(
        display, selection = "single", rownames = FALSE,
        options = list(pageLength = 10, dom = "tip", order = list()),
        class = "stripe hover"
      )
    })

    # This side's selection is derived ONLY from this side's result and this
    # side's rows_selected input -- both detail panels can therefore be
    # populated at the same time, and neither can clear the other.
    output[[id("detail")]] <- renderUI({
      req(input$main_nav == "dual_search")
      s <- side()
      if (!is.null(s$error)) return(NULL)
      entry_detail_ui(dual_search_side_selection(
        s$result,
        input[[paste0(id("results"), "_rows_selected")]]
      ))
    })

    for (o in c("count", "state", "results", "detail")) {
      outputOptions(output, id(o), suspendWhenHidden = FALSE)
    }
  }
  render_dual_panel("psoc", dual_psoc, dual_psoc_query)
  render_dual_panel("psic", dual_psic, dual_psic_query)

  # --- Compare PSIC Editions: bidirectional 2019<->2026 correspondence. ---
  correspondence_query_debounced <- reactive(input$correspondence_query) |> debounce(250)

  correspondence_results <- reactive({
    req(input$correspondence_direction)
    versions <- strsplit(input$correspondence_direction, "-", fixed = TRUE)[[1]]
    search_psic_correspondence(
      query = correspondence_query_debounced(),
      from_version = versions[[1]],
      to_version = versions[[2]],
      limit = 200
    )
  })

  output$correspondence_results <- DT::renderDT({
    req(input$main_nav == "correspondence")
    d <- correspondence_results()
    display <- d[, c("from_code", "from_label", "to_code", "to_label", "relation_type", "provenance", "confidence")]
    names(display) <- c("From code", "From label", "To code", "To label", "Relationship", "Provenance", "Confidence")
    DT::datatable(
      display, selection = "single", rownames = FALSE,
      options = list(pageLength = 10, dom = "tip"), class = "stripe hover"
    )
  })
  outputOptions(output, "correspondence_results", suspendWhenHidden = FALSE)

  correspondence_selected <- reactive({
    idx <- input$correspondence_results_rows_selected
    d <- correspondence_results()
    if (is.null(idx) || nrow(d) == 0L) {
      return(d[0, , drop = FALSE])
    }
    d[idx, , drop = FALSE]
  })

  output$correspondence_detail <- renderUI({
    req(input$main_nav == "correspondence")
    correspondence_detail_ui(correspondence_selected())
  })
  outputOptions(output, "correspondence_detail", suspendWhenHidden = FALSE)

  # --- RM Assistant (see the SERVER CONTRACT block in R/ui/ui_assistant.R) ---
  #
  # PER SESSION, deliberately. An ellmer Chat is a mutable R6 object that
  # accumulates conversation turns; hoisting this out of the server function
  # would share one client across every public visitor and leak one user's
  # conversation into another's (spec 10/22). Nothing here is cached at
  # module level.
  #
  # create_rm_chat_client() returns NULL rather than erroring whenever the
  # assistant is disabled or misconfigured, so the whole block is a no-op in
  # a deployment without a provider -- the deterministic tabs above are
  # entirely unaffected.
  # DETERMINISTIC TOOL ROUTING (RM_DETERMINISTIC_TOOL_ROUTING_ENFORCEMENT),
  # HARDENED (RM_DETERMINISTIC_TOOL_ROUTING_ENFORCEMENT micro-gate H1/H2).
  #
  # Per-session clarification/route state, created inside `server` for the
  # same reason the chat client is: two browser sessions must never observe
  # each other's pending question or route.
  rm_turn_state <- assistant_new_turn_state()

  # The tool closures read `rm_turn_state` directly (H1's hard interlock,
  # see assistant_tools.R) -- passing it at CLIENT-CREATION time, not
  # relying only on later `set_tools()` narrowing, is what makes the
  # interlock work even if the tool-swap observer below never runs (e.g.
  # its very first invocation, before `ignoreInit` would otherwise have let
  # anything through) or fails.
  rm_client <- create_rm_chat_client(tools = rm_assistant_tools(turn_state = rm_turn_state))

  # H2: let the process-global content-rendering override (assistant_render.R)
  # find THIS session's turn-state. Harmless no-op if `rm_client` ends up
  # NULL below (RM disabled/misconfigured) -- the registry entry is simply
  # never consulted because `contents_shinychat()` is never invoked for a
  # session that never streams anything.
  assistant_register_session_turn_state(session, rm_turn_state)

  if (!is.null(rm_client)) {
    # ROUTE-SPECIFIC TOOL SURFACE + HARD INTERLOCK (H1).
    #
    # The original defect: all eight tools were registered at once, so the
    # MODEL chose the authoritative route. The fix layers TWO independent
    # mechanisms rather than relying on either alone:
    #
    #   1. `set_tools()` below narrows what tools are even OFFERED to the
    #      provider for a coding turn -- an optimisation/UX layer, evaluated
    #      synchronously before the provider round-trip.
    #   2. The tool closures themselves (assistant_tools.R) check
    #      `assistant_turn_current_route(rm_turn_state)` at the instant
    #      ellmer's tool loop actually invokes them -- a plain synchronous R
    #      check inside the tool body, independent of Shiny observer
    #      ordering, `set_tools()` having run, or this observer having
    #      fired at all. This is the actual authority boundary: (1) is a
    #      convenience that keeps the model from being OFFERED the wrong
    #      tool; (2) is what makes it structurally impossible for a call to
    #      the low-level tools to ever SUCCEED on a coding turn, regardless
    #      of why or how the model still attempted it.
    #
    # Both `rm_turn_state$current_route` and `...$current_requested_systems`
    # are set HERE, synchronously, before any asynchronous provider
    # round-trip begins -- this is what interlock (2) actually reads.
    rm_all_tools <- rm_assistant_tools(turn_state = rm_turn_state)

    # Holds THIS turn's deterministic result between the pre-model observer
    # below and the post-turn render observer further down. A plain
    # environment, not a reactiveVal: it is written and read inside the
    # same user turn, and it must never itself trigger invalidation.
    rm_server_result <- new.env(parent = emptyenv())
    rm_server_result$current <- NULL

    observeEvent(input[["rm_assistant-chat_user_input"]],
      {
        msg <- input[["rm_assistant-chat_user_input"]]

        # ==================================================================
        # SERVER-SIDE DETERMINISTIC EXECUTION (v10, spec 9/10)
        # ==================================================================
        #
        # This is the change that makes live behaviour match local tests.
        # Previously the server only chose the ROUTE and then handed the
        # turn to the model, which chose the coding tool AND the slot
        # values passed to it -- so "mayor psoc psic" could yield a
        # clarification on one turn and 84113 on the next, from the same
        # deterministic service, because the model supplied different
        # arguments each time. See the root-cause block at the top of
        # R/assistant/assistant_execution.R.
        #
        # `assistant_handle_turn()` now performs route determination, slot
        # extraction, the coding-service call, pending-state update and
        # authoritative rendering BEFORE any provider round-trip. It also
        # records route/requested-systems on the turn state, so the tool
        # interlock and render suppression stay primed exactly as before.
        res <- tryCatch(
          assistant_handle_turn(msg, rm_turn_state),
          error = function(e) {
            # FAIL CLOSED. `assistant_handle_turn()` already clears the
            # latest packet on internal failure; this outer guard covers a
            # failure in routing itself, before it could do so.
            message(sprintf("[rm-assistant] server turn handler failed: %s",
                            conditionMessage(e)))
            assistant_turn_set_route(rm_turn_state, "contextual_coding")
            assistant_turn_set_latest_packet(rm_turn_state, NULL)
            NULL
          }
        )
        rm_server_result$current <- res

        # TOOL SURFACE.
        #
        # On a route the server has ALREADY answered, the model is given NO
        # tools at all. It cannot call the coding service, cannot choose
        # slots, and cannot emit a tool-status chunk -- which is what
        # removes the repeated "Checking official PSA classifications..."
        # loop on batch turns (one status line per model tool call, with
        # the prose suppressed behind it, leaving an apparently empty
        # answer). The model's only remaining job on these routes is
        # optional explanation of a result R has already fixed.
        #
        # Non-coding routes keep their ordinary route-specific tool set.
        target_tools <- if (isTRUE(res$handled)) {
          list()
        } else {
          assistant_tools_for_route(
            if (is.null(res)) "contextual_coding" else res$route,
            rm_all_tools
          )
        }
        tryCatch(
          rm_client$set_tools(target_tools),
          error = function(e) {
            # A failure here can no longer change the ANSWER on a handled
            # route -- the deterministic packet already exists. Re-assert
            # the most restrictive surface anyway.
            message(sprintf("[rm-assistant] route tool swap failed: %s",
                            conditionMessage(e)))
            assistant_turn_set_route(rm_turn_state, "contextual_coding")
            tryCatch(
              rm_client$set_tools(assistant_tools_for_route("contextual_coding", rm_all_tools)),
              error = function(e2) {
                message(sprintf(
                  "[rm-assistant] restrictive fallback tool swap also failed: %s",
                  conditionMessage(e2)
                ))
              }
            )
          }
        )
      },
      priority = 1000L,
      ignoreInit = TRUE
    )

    # No `greeting =` argument: the static greeting is already baked into
    # the initial HTML by rm_assistant_ui(), costing zero model tokens and
    # zero server round-trips (spec 9). Passing it again would set it twice.
    rm_chat <- shinychat::chat_mod_server("rm_assistant", client = rm_client)

    # AUTHORITATIVE RENDER (v10, spec 11).
    #
    # For a route the server handled, the answer was already computed in
    # R before the provider was called, and `assistant_render.R` suppresses
    # the model's live text on coding routes. This observer emits the
    # DETERMINISTIC rendering -- code, label, level, coding role, edition,
    # status, source and clarification question all come from the packet,
    # never from generated prose.
    #
    # DETERMINISTIC ONLY (RM_CLARIFICATION_LIFECYCLE spec 20/21). A coding
    # turn ends at the deterministic rendering. The model's own text is
    # NEVER appended automatically, because on a handled turn it is
    # commentary on a question R has already answered and it contradicted
    # that answer live: a resolved PSOC 1111 + PSIC 84113 was followed by a
    # fresh Tagalog request for the mayor's duties, a resolved PSIC 78200
    # by "please hold on while I look for the appropriate PSIC", and a
    # deterministic clarification by a second, differently-worded copy of
    # itself. The model may speak only when the user explicitly asks it to
    # (`assistant_explanation_requested()`), which arrives here as an
    # UNHANDLED coding turn and is served by the guarded path below.
    #
    # Non-coding routes are untouched: live streaming already rendered
    # them, so appending here would duplicate.
    observeEvent(rm_chat$last_turn(), {
      turn <- rm_chat$last_turn()
      if (is.null(turn)) return(invisible(NULL))

      res <- rm_server_result$current
      if (isTRUE(res$handled)) {
        # The authoritative block, straight from R. On a normal turn the
        # stream already carried it (assistant_turn_take_render(), which
        # is what stops shinychat committing an empty assistant bubble
        # next to the answer); this append is the fallback for a turn
        # where the provider emitted no content chunk at all.
        if (!assistant_turn_render_emitted(rm_turn_state) &&
            !is.na(res$render) && nzchar(trimws(res$render))) {
          rm_chat$append(res$render, role = "assistant")
        }

        # Ground the provider's own history with what the user actually
        # saw, replacing the prose that was discarded. Best-effort: a
        # failure here cannot affect the answer that has already been
        # rendered.
        tryCatch(
          rm_client$set_turns(
            assistant_ground_turns(rm_client$get_turns(), res$render)
          ),
          error = function(e) {
            message(sprintf("[rm-assistant] could not ground chat history: %s",
                            conditionMessage(e)))
          }
        )
        return(invisible(NULL))
      }

      # Unhandled route that is nonetheless on a coding route (e.g. the
      # handler failed): fall back to the previous validate-then-append
      # behaviour so nothing unvalidated can reach the DOM.
      if (!identical(assistant_turn_current_route(rm_turn_state), "contextual_coding")) {
        return(invisible(NULL))
      }
      text <- tryCatch(ellmer::contents_text(turn), error = function(e) NULL)
      if (is.null(text) || !nzchar(trimws(text))) return(invisible(NULL))
      packet <- assistant_turn_latest_packet(rm_turn_state)
      guarded <- assistant_guard_response(text, packet)
      rm_chat$append(guarded$text, role = "assistant")
    })

    # New chat. The module's own clear() resets BOTH the visible transcript
    # and the ellmer client's turn history, so the model forgets the
    # conversation too rather than silently retaining it behind a cleared UI.
    observeEvent(input[["rm_assistant-new_chat"]], {
      rm_chat$clear()
      # A fresh chat must not inherit a pending clarification, route, or
      # coding packet from the conversation the user just discarded.
      assistant_turn_clear(rm_turn_state)
      assistant_turn_set_route(rm_turn_state, "contextual_coding")
      assistant_turn_set_requested_systems(rm_turn_state, c("psoc", "psic"))
      assistant_turn_set_latest_packet(rm_turn_state, NULL)
      # The previous turn's deterministic result must not survive into the
      # new conversation and be re-rendered against an unrelated turn.
      rm_server_result$current <- NULL
    })

    # KNOWN LIMITATION -- mid-stream provider failure is silent client-side.
    #
    # If the provider call fails *after* the assistant was successfully
    # configured (expired or revoked key, network fault, rate limit),
    # shinychat rolls the transcript back and restores the user's text to
    # the input box, but shows them nothing explaining why. The failure IS
    # logged server-side by shinychat, and no secret or stack trace reaches
    # the browser, so this is a UX gap rather than a safety or security one.
    # The startup-time degradation path (assistant disabled or
    # misconfigured -> rm_assistant_unavailable_ui()) works correctly and is
    # the case spec 21 is chiefly concerned with.
    #
    # A fix was attempted and deliberately reverted rather than left in
    # place half-working. Three separate approaches were tried against
    # shinychat 0.4.0 and none reached the DOM on the errored-stream path:
    # the module's own `append()` helper, the top-level
    # `shinychat::chat_append()` against the namespaced id, and
    # `showNotification()`. Detection itself was proven to work (tracing
    # confirmed the failed stream leaves an EMPTY assistant turn on the
    # ellmer client, which is distinguishable from a real reply); it is
    # only the surfacing that fails. Revisit when shinychat exposes an
    # error hook on its chat module -- see docs/ASSISTANT_CONTRACT.md.
  }
}

shinyApp(ui, server)

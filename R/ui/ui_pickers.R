# Collapsed pickers — System and Edition / release (design surfaces 1a, 1b, 1c).
#
# PRESENTATION ONLY. Nothing here reads, ranks or validates classification
# data. Every option list is derived from the canonical registry/repository
# services by the caller and passed in; this file draws controls.
#
# ---------------------------------------------------------------------------
# WHY THIS FILE EXISTS
#
# The imported design collapses BOTH filters that used to occupy the sidebar
# rail into single-line controls that state their own value:
#
#   System            acronym + full official title, one control
#   Edition / release selected release + its CURRENT / ARCHIVED state,
#                     one control -- NOT a permanently expanded radio list
#
# Each opens a chooser rather than expanding in place: a popover on desktop
# and a full-width sheet on mobile, so a picker can never float across the
# control underneath it (the measured defect the design calls out for the
# System control at 390px).
#
# ---------------------------------------------------------------------------
# INPUT CONTRACTS — DELIBERATELY UNCHANGED
#
#   classification_system    still a selectizeInput; still updated with
#                            updateSelectizeInput(); still yields a raw
#                            registry id.
#   classification_version   still a radioButtons group; still updated with
#                            updateRadioButtons(); still yields a raw
#                            canonical edition identifier.
#
# That is why the radio group survives at all: it is MOVED inside the
# popover, not replaced. Every existing consumer -- app.R's observers,
# `view_in_search_apply()`, the hierarchy browser's `version()` reactive --
# keeps working with no change, and the "long radio list eating rail height"
# problem is solved by where the group is mounted rather than by inventing a
# second version input that the service layer would then have to learn.
#
# Ids added by this file (all presentational):
#   system_picker_open        actionButton  — opens the mobile System sheet
#   system_picker_query       textInput     — search inside that sheet
#   system_picker_choice      JS input      — chosen registry id
#   system_picker_list        uiOutput      — the sheet's filtered list
#   classification_version_summary  uiOutput — the collapsed Edition value
#
# ---------------------------------------------------------------------------
# SCOPE RULE (explicit, and tested in test-ui-pickers.R)
#
# The System picker exposes the COMPLETE registry-supported classification
# set on every surface it appears on. The design artifact demonstrates five
# systems in its mobile sheet; that is a drawing, not a scope. Both the
# desktop control and the mobile sheet are built from
# `classification_registry()`, so a system the registry gains or loses
# appears or disappears with no edit here and no hard-coded list anywhere.


# ---- Shared picker behaviour ---------------------------------------------
#
# One small idempotent script, installed once per page. It owns ONLY
# disclosure: open/close, aria-expanded, Escape, click-outside, and focus
# return to the trigger. It never touches an input value -- Shiny's own
# radio binding still owns `classification_version`.
.PSA_PICKER_JS <- '
(function () {
  if (window.__psaPickerInstalled) { return; }
  window.__psaPickerInstalled = true;

  function panelFor(trigger) {
    var id = trigger.getAttribute("aria-controls");
    return id ? document.getElementById(id) : null;
  }

  function close(trigger, refocus) {
    var panel = panelFor(trigger);
    if (!panel) { return; }
    panel.hidden = true;
    trigger.setAttribute("aria-expanded", "false");
    document.body.classList.remove("psa-picker-open");
    if (refocus) { try { trigger.focus(); } catch (e) { /* non-fatal */ } }
  }

  function closeAll(except, refocus) {
    var triggers = document.querySelectorAll("[data-psa-picker-toggle]");
    Array.prototype.forEach.call(triggers, function (t) {
      if (t !== except) { close(t, refocus && t === except); }
    });
  }

  function open(trigger) {
    var panel = panelFor(trigger);
    if (!panel) { return; }
    closeAll(trigger, false);
    panel.hidden = false;
    trigger.setAttribute("aria-expanded", "true");
    // Marks the phone-width sheet state so the page behind it can be
    // locked. Harmless on desktop, where the panel is a popover.
    document.body.classList.add("psa-picker-open");
    // Focus the CHECKED option first, then the first thing that is
    // actually rendered. The zero-size filter matters: the panel carries a
    // sheet header that is display:none at desktop width, and its close
    // button would otherwise be the first match and swallow the focus --
    // measured, not theoretical.
    var candidates = panel.querySelectorAll(
      "input:checked, input:not([disabled]), button:not([disabled]), " +
      "[tabindex]:not([tabindex=\'-1\'])"
    );
    var first = Array.prototype.filter.call(candidates, function (el) {
      return el.offsetWidth > 0 || el.offsetHeight > 0;
    })[0];
    if (first) { try { first.focus(); } catch (e) { /* non-fatal */ } }
  }

  document.addEventListener("click", function (e) {
    var trigger = e.target.closest ? e.target.closest("[data-psa-picker-toggle]") : null;
    if (trigger) {
      e.preventDefault();
      var expanded = trigger.getAttribute("aria-expanded") === "true";
      if (expanded) { close(trigger, true); } else { open(trigger); }
      return;
    }
    // A dismiss control inside a panel.
    var dismiss = e.target.closest ? e.target.closest("[data-psa-picker-dismiss]") : null;
    if (dismiss) {
      var owner = document.querySelector(
        "[aria-controls=\'" + dismiss.getAttribute("data-psa-picker-dismiss") + "\']"
      );
      if (owner) { close(owner, true); }
      return;
    }
    // Anywhere outside an open panel closes it, without stealing focus.
    var panel = e.target.closest ? e.target.closest(".psa-picker-panel") : null;
    if (!panel) { closeAll(null, false); }
  });

  // Choosing a release closes the popover. Delegated, so it keeps working
  // after Shiny re-renders the radio group for a different system.
  document.addEventListener("change", function (e) {
    var panel = e.target.closest ? e.target.closest(".psa-picker-panel") : null;
    if (!panel || e.target.type !== "radio") { return; }
    var owner = document.querySelector("[aria-controls=\'" + panel.id + "\']");
    if (owner) { close(owner, true); }
  });

  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape" && e.key !== "Esc") { return; }
    var panel = e.target.closest ? e.target.closest(".psa-picker-panel") : null;
    if (panel) {
      var owner = document.querySelector("[aria-controls=\'" + panel.id + "\']");
      if (owner) { e.stopPropagation(); close(owner, true); }
      return;
    }
    closeAll(null, false);
  });
})();
'

#' Install the picker disclosure behaviour. Idempotent.
psa_picker_deps <- function() {
  shiny::tags$script(shiny::HTML(.PSA_PICKER_JS))
}


# ---- The collapsed trigger -------------------------------------------------

#' The positioned wrapper a trigger and its panel share.
#'
#' THE PANEL MUST BE A DESCENDANT OF THIS ELEMENT, not a sibling of it.
#' The desktop popover is `position: absolute`, so it resolves against the
#' nearest positioned ancestor; if the panel sits outside the field it
#' anchors to the page instead and lands somewhere else entirely. Found in
#' browser UAT, which is why the two are composed by ONE function rather
#' than assembled by each caller.
#'
#' @param class character(1) or NULL. Extra classes.
#' @param ... The trigger and its panel, in that order.
psa_picker_field <- function(class = NULL, ...) {
  shiny::tags$div(
    class = paste(c("psa-picker-field", class), collapse = " "),
    ...
  )
}

#' A single-line control that states its own value and opens a chooser.
#'
#' A real `<button>` with a real accessible name, `aria-expanded` and
#' `aria-controls` -- never a styled `<div>`. The value it shows is passed
#' in, so this function stays pure.
#'
#' Returns the label and the button only. Wrap it and its panel together in
#' `psa_picker_field()`.
#'
#' @param panel_id character(1). DOM id of the panel it discloses.
#' @param label character(1). The field label rendered above the control.
#' @param value Tag/tagList. The current value, drawn inside the button.
#' @param aria_label character(1). Accessible name for the button itself.
#' @param id character(1) or NULL. Optional DOM id for the button.
psa_picker_trigger <- function(panel_id,
                               label,
                               value,
                               aria_label,
                               id = NULL) {
  shiny::tagList(
    shiny::tags$span(class = "psa-picker-label", id = paste0(panel_id, "-label"), label),
    shiny::tags$button(
      id = id,
      type = "button",
      class = "psa-picker-trigger",
      `data-psa-picker-toggle` = "",
      `aria-controls` = panel_id,
      `aria-expanded` = "false",
      `aria-label` = aria_label,
      shiny::tags$span(class = "psa-picker-value", value),
      lucide_icon("chevron-down", 14, class = "psa-picker-caret")
    )
  )
}

#' The panel a trigger discloses. Hidden until opened.
#'
#' Rendered as a popover on desktop and as a full-width sheet at phone
#' width; both states are CSS on this one element, so there is only ever one
#' copy of the control inside it and no duplicate Shiny input id.
#'
#' @param panel_id character(1). Must match the trigger's `aria-controls`.
#' @param title character(1). Sheet heading, shown at phone width.
#' @param ... Panel body.
psa_picker_panel <- function(panel_id, title, ...) {
  shiny::tags$div(
    id = panel_id,
    class = "psa-picker-panel",
    role = "group",
    `aria-labelledby` = paste0(panel_id, "-label"),
    hidden = NA,
    shiny::tags$div(
      class = "psa-picker-panel-head",
      shiny::tags$span(class = "psa-picker-panel-title", title),
      shiny::tags$button(
        type = "button",
        class = "psa-picker-panel-close",
        `data-psa-picker-dismiss` = panel_id,
        `aria-label` = paste("Close the", tolower(title), "chooser"),
        lucide_icon("x", 15)
      )
    ),
    shiny::tags$div(class = "psa-picker-panel-body", ...)
  )
}


# ---- System ---------------------------------------------------------------

SYSTEM_PICKER_OPEN <- "system_picker_open"
SYSTEM_PICKER_QUERY <- "system_picker_query"
SYSTEM_PICKER_CHOICE <- "system_picker_choice"
SYSTEM_PICKER_LIST <- "system_picker_list"

#' The System field: one searchable control, plus a mobile sheet trigger.
#'
#' The desktop control is the EXISTING selectize input, unchanged in id, in
#' choice contract and in renderer -- it already draws the design's two-line
#' acronym + official-title row and it is already type-ahead searchable by
#' both halves. Only the mobile affordance is new.
system_field_ui <- function() {
  shiny::tags$div(
    class = "psa-system-field",
    # Desktop / tablet: the searchable select itself.
    shiny::div(
      class = "psa-system-select",
      shiny::selectizeInput(
        "classification_system", "System",
        choices = NULL, width = "100%",
        options = list(render = system_selector_render())
      )
    ),
    # Phone: a trigger that opens the dedicated sheet (design 1c). Shown by
    # CSS at <=767px only. It is a Shiny actionButton rather than a JS
    # picker because the sheet's contents are server-rendered from the
    # registry.
    shiny::tags$div(
      class = "psa-system-sheet-trigger",
      shiny::tags$span(class = "psa-picker-label", "System"),
      shiny::actionButton(
        SYSTEM_PICKER_OPEN,
        label = shiny::tagList(
          shiny::tags$span(class = "psa-picker-value",
                           shiny::uiOutput("classification_system_summary",
                                           container = shiny::tags$span,
                                           inline = TRUE)),
          lucide_icon("chevron-down", 14, class = "psa-picker-caret")
        ),
        class = "psa-picker-trigger",
        `aria-label` = "Choose a classification system"
      )
    )
  )
}

#' The collapsed System value: acronym over full official title.
#'
#' @param entry A one-row slice of the registry, or NULL.
system_summary_ui <- function(entry) {
  if (is.null(entry) || nrow(entry) == 0L) {
    return(shiny::tags$span(class = "psa-picker-value-main", "Choose a system"))
  }
  shiny::tagList(
    shiny::tags$span(class = "psa-picker-value-main", entry$short_name[[1]]),
    shiny::tags$span(class = "psa-picker-value-sub", entry$display_name[[1]])
  )
}

#' One option row inside the System sheet.
#'
#' A real `<button>`; selection is reported through a plain Shiny input, so
#' no per-option observer is created and the row count can change freely.
.system_picker_option <- function(id, short_name, display_name, selected) {
  shiny::tags$button(
    type = "button",
    class = if (isTRUE(selected)) "psa-picker-option is-selected" else "psa-picker-option",
    `aria-pressed` = if (isTRUE(selected)) "true" else "false",
    onclick = sprintf(
      "Shiny.setInputValue('%s', '%s', {priority: 'event'});",
      SYSTEM_PICKER_CHOICE, id
    ),
    shiny::tags$span(
      class = "psa-picker-option-text",
      shiny::tags$span(class = "psa-picker-option-acronym", short_name),
      shiny::tags$span(class = "psa-picker-option-title", display_name)
    ),
    if (isTRUE(selected)) {
      # Selected state is a spelled-out word plus a check, never colour
      # alone (docs/UI_CONTRACT.md §11).
      shiny::tags$span(class = "psa-tag psa-tag-current", "Selected")
    }
  )
}

#' The System sheet's option list.
#'
#' @param registry The FULL registry data frame. Never a subset chosen here.
#' @param selected character(1) or NULL. Currently selected system id.
#' @param query character(1) or NULL. Free-text filter (acronym or title).
system_picker_list_ui <- function(registry, selected = NULL, query = NULL) {
  q <- trimws(tolower(query %||% ""))
  keep <- if (nzchar(q)) {
    grepl(q, tolower(registry$short_name), fixed = TRUE) |
      grepl(q, tolower(registry$display_name), fixed = TRUE)
  } else {
    rep(TRUE, nrow(registry))
  }
  shown <- registry[keep, , drop = FALSE]

  if (nrow(shown) == 0L) {
    return(shiny::tags$p(
      class = "psa-picker-empty text-muted",
      "No classification system matches that text."
    ))
  }

  shiny::tags$div(
    class = "psa-picker-options",
    role = "group",
    `aria-label` = "Classification systems",
    lapply(seq_len(nrow(shown)), function(i) {
      .system_picker_option(
        id = shown$id[[i]],
        short_name = shown$short_name[[i]],
        display_name = shown$display_name[[i]],
        selected = identical(shown$id[[i]], selected)
      )
    })
  )
}

#' The System sheet itself (design 1c).
#'
#' Reuses the shared dialog shell, so Escape, focus entry, focus return and
#' the phone-width full-screen treatment are the ones every other dialog in
#' the app already uses. It covers the Edition control rather than floating
#' beside it, which is the collision the design calls out.
system_picker_dialog_ui <- function() {
  psa_dialog_ui(
    id = "system-picker",
    title = "Classification system",
    description = "Choose one system to search.",
    variant = "drawer",
    size = "full",
    body = shiny::tagList(
      shiny::tags$div(
        class = "psa-picker-search",
        lucide_icon("search", 16),
        shiny::textInput(
          SYSTEM_PICKER_QUERY,
          "Search acronym or title",
          placeholder = "Search acronym or title",
          width = "100%"
        )
      ),
      shiny::uiOutput(SYSTEM_PICKER_LIST)
    ),
    footer = psa_dialog_close_button("Cancel")
  )
}


# ---- Edition / release -----------------------------------------------------

EDITION_PANEL_ID <- "psa-edition-panel"

#' The collapsed Edition / release value.
#'
#' States the selected release AND its status in one line, which is what
#' replaces the permanently expanded list. Status is the spelled-out word
#' from `status_badge()`, never colour alone.
#'
#' @param version character(1) or NULL. Canonical edition identifier.
#' @param current character(1) or NULL. The system's current edition.
edition_summary_ui <- function(version, current = NULL) {
  if (is.null(version) || !nzchar(version)) {
    return(shiny::tags$span(class = "psa-picker-value-main", "Loading editions"))
  }
  shiny::tagList(
    shiny::tags$span(class = "psa-picker-value-main", release_display_label(version)),
    status_badge(if (identical(version, current)) "current" else "archived")
  )
}

#' The Edition / release field: collapsed control + disclosed chooser.
#'
#' The radio group inside the panel IS `classification_version` -- the same
#' input id, the same widget type and the same update path as before. What
#' changed is that it is disclosed rather than always expanded.
edition_field_ui <- function() {
  psa_picker_field(
    class = "psa-edition-field",
    psa_picker_trigger(
      panel_id = EDITION_PANEL_ID,
      label = "Edition / release",
      value = shiny::uiOutput("classification_version_summary",
                              container = shiny::tags$span, inline = TRUE),
      aria_label = "Choose an edition or release"
    ),
    psa_picker_panel(
      EDITION_PANEL_ID,
      title = "Edition / release",
      shiny::tags$div(
        class = "psa-edition-group",
        shiny::radioButtons(
          "classification_version",
          "Edition / release",
          choices = character(0),
          selected = character(0)
        )
      )
    )
  )
}


# ---- Server ---------------------------------------------------------------

#' Wire the System sheet and both collapsed summaries.
#'
#' ONE call from app.R. All state is local to this function, so it is
#' per-session by construction. It changes no search semantics: the only
#' thing it ever writes is the existing `classification_system` input, and
#' it writes exactly the registry id the user chose.
#'
#' @param registry The full registry data frame, as app.R already holds it.
search_pickers_server <- function(input, output, session, registry) {
  # The collapsed System value (phone trigger).
  output$classification_system_summary <- shiny::renderUI({
    sel <- input$classification_system
    if (is.null(sel) || !nzchar(sel)) {
      return(system_summary_ui(NULL))
    }
    system_summary_ui(registry[registry$id == sel, , drop = FALSE])
  })
  shiny::outputOptions(output, "classification_system_summary", suspendWhenHidden = FALSE)

  # The collapsed Edition value.
  output$classification_version_summary <- shiny::renderUI({
    sel <- input$classification_system
    ver <- input$classification_version
    current <- if (is.null(sel) || !nzchar(sel)) {
      NULL
    } else {
      registry$current_version[registry$id == sel][[1]]
    }
    edition_summary_ui(ver, current)
  })
  shiny::outputOptions(output, "classification_version_summary", suspendWhenHidden = FALSE)

  # The mobile System sheet.
  shiny::observeEvent(input[[SYSTEM_PICKER_OPEN]], {
    shiny::updateTextInput(session, SYSTEM_PICKER_QUERY, value = "")
    psa_dialog_show(system_picker_dialog_ui(), session = session)
  })

  output[[SYSTEM_PICKER_LIST]] <- shiny::renderUI({
    # The COMPLETE registry, filtered only by what the user typed. The
    # design's five-system illustration is not a scope limit.
    system_picker_list_ui(
      registry,
      selected = input$classification_system,
      query = input[[SYSTEM_PICKER_QUERY]]
    )
  })
  shiny::outputOptions(output, SYSTEM_PICKER_LIST, suspendWhenHidden = FALSE)

  shiny::observeEvent(input[[SYSTEM_PICKER_CHOICE]], {
    chosen <- input[[SYSTEM_PICKER_CHOICE]]
    # Never trust a client-supplied id: it must be one the registry knows.
    shiny::req(chosen %in% registry$id)
    shiny::updateSelectizeInput(session, "classification_system", selected = chosen)
    psa_dialog_close(session)
  })

  invisible(NULL)
}

# Contract tests for the collapsed System and Edition / release pickers
# (imported Claude Design surfaces 1a, 1b, 1c).
#
# These assert SEMANTIC facts that fail silently in a browser, never pixels:
#
#   1. the System picker exposes the COMPLETE registry-supported set --
#      the design artifact illustrates five systems and that is a drawing,
#      not a scope;
#   2. the Edition control is no longer a permanently expanded radio list,
#      but the `classification_version` INPUT is byte-for-byte the same
#      radio group it always was, so no server observer detached;
#   3. current-first ordering survived being moved inside a popover;
#   4. the two pickers cannot collide, because the phone-width System
#      chooser is a sheet rather than an anchored popover;
#   5. every new control has a real accessible name and a real state.

.render <- function(tag) paste(as.character(htmltools::renderTags(tag)$html),
                               collapse = "")

.repo <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)

.read_file <- function(...) {
  path <- file.path(.repo, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

.has <- function(haystack, needle) grepl(haystack, x = needle, fixed = TRUE)


# ---------------------------------------------------------------------------
# 1. Complete registry scope
# ---------------------------------------------------------------------------

test_that("the System sheet lists every registry-supported system", {
  reg <- classification_registry()
  expect_gt(nrow(reg), 0L)

  html <- .render(system_picker_list_ui(reg, selected = reg$id[[1]]))

  # One option button per registered system. Counted on the opening tag so
  # the class-bearing children inside each row cannot inflate the count.
  buttons <- gregexpr("<button", html, fixed = TRUE)[[1]]
  expect_identical(length(buttons), nrow(reg))

  # And every registry id and acronym is actually reachable.
  for (i in seq_len(nrow(reg))) {
    expect_true(grepl(reg$id[[i]], html, fixed = TRUE), info = reg$id[[i]])
    expect_true(grepl(reg$short_name[[i]], html, fixed = TRUE),
                info = reg$short_name[[i]])
  }
})

test_that("the System scope is derived, never a hard-coded design list", {
  # The artifact draws PSGC / PSIC / PSOC / PSCED / PCOICOP. If those five
  # ever appear as a literal vector in the picker source, the picker has
  # stopped following the registry.
  src <- .read_file("R", "ui", "ui_pickers.R")
  expect_false(grepl('c("psgc"', src, fixed = TRUE))
  expect_false(grepl('"pcoicop"', src, fixed = TRUE))
  # It reads the registry the caller passes in, and nothing else.
  expect_true(grepl("registry$short_name", src, fixed = TRUE))
  expect_true(grepl("registry$display_name", src, fixed = TRUE))
})

test_that("a client-supplied system id is validated against the registry", {
  # The sheet reports its choice through a plain JS input, so the server
  # must never trust it. `req(chosen %in% registry$id)` is that gate.
  src <- .read_file("R", "ui", "ui_pickers.R")
  expect_true(grepl("shiny::req(chosen %in% registry$id)", src, fixed = TRUE))
})

test_that("the sheet's filter narrows without ever changing the source set", {
  reg <- classification_registry()

  by_acronym <- .render(system_picker_list_ui(reg, query = "psoc"))
  expect_identical(length(gregexpr("<button", by_acronym, fixed = TRUE)[[1]]), 1L)

  # Titles are searchable too, not just acronyms.
  by_title <- .render(system_picker_list_ui(reg, query = "geographic"))
  expect_true(grepl("PSGC", by_title, fixed = TRUE))

  # A miss says so rather than rendering an empty box.
  none <- .render(system_picker_list_ui(reg, query = "zzzznomatch"))
  expect_true(grepl("No classification system matches", none, fixed = TRUE))

  # Empty query = the whole set.
  all_of_it <- .render(system_picker_list_ui(reg, query = ""))
  expect_identical(length(gregexpr("<button", all_of_it, fixed = TRUE)[[1]]),
                   nrow(reg))
})


# ---------------------------------------------------------------------------
# 2. The Edition input contract is unchanged
# ---------------------------------------------------------------------------

test_that("classification_version is still the same radio group", {
  html <- .render(edition_field_ui())

  # Same id, same widget type. `updateRadioButtons()` in app.R and
  # `view_in_search_apply()` both depend on this.
  expect_true(grepl('id="classification_version"', html, fixed = TRUE))
  expect_true(grepl('type="radio"', html, fixed = TRUE) ||
                grepl("shiny-input-radiogroup", html, fixed = TRUE))
  expect_true(grepl("shiny-input-radiogroup", html, fixed = TRUE))
})

test_that("app.R still drives the edition control as a radio group", {
  app <- .read_file("app.R")
  expect_true(grepl("updateRadioButtons(", app, fixed = TRUE))
  expect_true(grepl('session, "classification_version"', app, fixed = TRUE))

  dialog <- .read_file("R", "ui", "ui_dialog.R")
  expect_true(grepl(
    'shiny::updateRadioButtons(session, "classification_version"',
    dialog, fixed = TRUE
  ))
})

test_that("the edition list is disclosed, not permanently expanded", {
  html <- .render(edition_field_ui())

  # A collapsed trigger that states its own value...
  expect_true(grepl("psa-picker-trigger", html, fixed = TRUE))
  expect_true(grepl('aria-expanded="false"', html, fixed = TRUE))
  expect_true(grepl('aria-controls="psa-edition-panel"', html, fixed = TRUE))
  expect_true(grepl('aria-label="Choose an edition or release"', html,
                    fixed = TRUE))

  # ...and a panel that starts hidden.
  expect_true(grepl('id="psa-edition-panel"', html, fixed = TRUE))
  expect_true(grepl("psa-picker-panel", html, fixed = TRUE))
  expect_true(grepl("hidden", html, fixed = TRUE))
})

test_that("the collapsed edition value states the release AND its status", {
  current <- .render(edition_summary_ui("2026", current = "2026"))
  expect_true(grepl("Current", current, fixed = TRUE))

  archived <- .render(edition_summary_ui("2019", current = "2026"))
  expect_true(grepl("Archived", archived, fixed = TRUE))

  # Never colour alone: the word itself is in the DOM in both states.
  expect_false(identical(current, archived))

  # And it degrades to a neutral line before the first update lands rather
  # than rendering an empty control.
  expect_true(grepl("Loading editions",
                    .render(edition_summary_ui(NULL)), fixed = TRUE))
})


# ---------------------------------------------------------------------------
# 3. Ordering and grouping survived the move
# ---------------------------------------------------------------------------

test_that("current-first ordering is unchanged inside the popover", {
  spec <- edition_choice_spec(c("Q1_2023", "Q2_2026", "APRIL_2024"), "Q2_2026")

  expect_identical(unlist(spec$choiceValues),
                   c("Q2_2026", "APRIL_2024", "Q1_2023"))
  expect_identical(spec$selected, "Q2_2026")
})

test_that("the disclosed list is grouped Current then Archived, with a count", {
  spec <- edition_choice_spec(c("Q1_2023", "Q2_2026", "APRIL_2024"), "Q2_2026")
  html <- vapply(spec$choiceNames,
                 function(x) paste(as.character(htmltools::renderTags(x)$html),
                                   collapse = ""),
                 character(1))

  # The Current header rides on the current release, which is first.
  expect_true(grepl("psa-edition-group-head", html[[1]], fixed = TRUE))
  expect_true(grepl(">Current<", html[[1]], fixed = TRUE))

  # The Archived header rides on the FIRST archived release and carries the
  # archived count, not the total.
  expect_true(grepl("Archived · 2", html[[2]], fixed = TRUE))
  expect_false(grepl("psa-edition-group-head", html[[3]], fixed = TRUE))
})

test_that("a system with only a current edition renders no archived group", {
  spec <- edition_choice_spec("2022", "2022")
  html <- paste(as.character(htmltools::renderTags(spec$choiceNames[[1]])$html),
                collapse = "")
  expect_true(grepl(">Current<", html, fixed = TRUE))
  expect_false(grepl("Archived ·", html, fixed = TRUE))
})


# ---------------------------------------------------------------------------
# 4. The two pickers cannot collide
# ---------------------------------------------------------------------------

test_that("the phone System chooser is a sheet, not an anchored popover", {
  # The measured defect the design calls out: at 390px an anchored popover
  # floats ACROSS the Edition control beneath it. The System chooser is
  # therefore the shared full-screen dialog shell, which covers it.
  html <- .render(system_picker_dialog_ui())
  expect_true(grepl('data-psa-dialog="system-picker"', html, fixed = TRUE))
  expect_true(grepl("psa-dialog--drawer", html, fixed = TRUE))
  expect_true(grepl("modal-fullscreen", html, fixed = TRUE))
  # It brings the shell's modal semantics with it.
  expect_true(grepl('role="dialog"', html, fixed = TRUE))
  expect_true(grepl('aria-modal="true"', html, fixed = TRUE))
})

test_that("the Edition popover is positioned inside its own field", {
  # `position: absolute` INSIDE .psa-picker-field is what stops the
  # disclosed release list from displacing Level -- which is the whole
  # reason it stopped being permanently expanded.
  css <- .read_file("www", "ui-design.css")
  expect_true(grepl(".psa-picker-field {\n  position: relative;", css, fixed = TRUE))

  # UAT-UI-01. `absolute` was the defect: an absolutely-positioned box is
  # still laid out inside its ancestors' clipping and stacking context, so
  # the disclosed release list collided with the controls below it. `fixed`
  # escapes every ancestor by construction -- no z-index escalation, no
  # margins -- and the picker script anchors it to its trigger in viewport
  # coordinates, which CSS alone cannot do.
  expect_true(grepl(".psa-picker-panel {\n  position: fixed;", css, fixed = TRUE))

  src <- .read_file("R", "ui", "ui_pickers.R")
  expect_true(grepl("function anchor(trigger, panel)", src, fixed = TRUE))
  expect_true(grepl("trigger.getBoundingClientRect()", src, fixed = TRUE))
  # Anchored overlays must follow their trigger, and be re-anchored on any
  # scroll -- captured, so a scroll inside the filter rail counts too.
  expect_true(grepl('window.addEventListener("resize", anchorOpen)', src, fixed = TRUE))
  expect_true(grepl('window.addEventListener("scroll", anchorOpen, true)', src, fixed = TRUE))
  # Viewport-constrained and internally scrollable rather than clipped.
  expect_true(grepl("panel.style.maxHeight", src, fixed = TRUE))
  expect_true(grepl(".psa-picker-panel-body {\n  overflow-y: auto;", css, fixed = TRUE))

  # AND the panel is a DESCENDANT of that positioned field, not a sibling
  # of it. Found in browser UAT: as siblings the popover resolved against
  # the page instead and opened in the wrong place entirely. Asserted on
  # the nesting, because the CSS above passes either way.
  html <- .render(edition_field_ui())
  field_open <- regexpr("psa-picker-field", html, fixed = TRUE)
  panel_open <- regexpr('id="psa-edition-panel"', html, fixed = TRUE)
  expect_gt(field_open, 0L)
  expect_gt(panel_open, field_open)
  # The field div is not closed before the panel starts.
  before_panel <- substr(html, field_open, panel_open)
  expect_false(grepl("</div></div>", before_panel, fixed = TRUE))

  # ...and becomes a docked sheet at phone width instead.
  expect_true(grepl("@media (max-width: 767.98px)", css, fixed = TRUE))
  expect_true(grepl("inset: auto 0 0 0;", css, fixed = TRUE))

  # A `position: fixed` sheet resolves against the nearest ancestor with a
  # TRANSFORM, not against the viewport -- and the entrance reveal puts one
  # on exactly the containers these controls live in. Measured at 375px:
  # the sheet docked to the filter rail 2600px down the document instead of
  # to the bottom of the screen. The reveal is therefore suspended while a
  # sheet is open, in the sheet that owns motion and loads last.
  motion <- .read_file("www", "ui-motion.css")
  expect_true(grepl("body.psa-picker-open .psa-search-body", motion, fixed = TRUE))
  expect_true(grepl("  animation: none;\n  transform: none;", motion, fixed = TRUE))
})

test_that("exactly one System control is visible at any width", {
  html <- .render(system_field_ui())
  expect_true(grepl("psa-system-select", html, fixed = TRUE))
  expect_true(grepl("psa-system-sheet-trigger", html, fixed = TRUE))

  css <- .read_file("www", "ui-design.css")
  # The sheet trigger is hidden by default and the select is hidden below
  # the breakpoint -- never both, never neither.
  expect_true(grepl(".psa-system-sheet-trigger { display: none; }", css, fixed = TRUE))
  expect_true(grepl(".psa-system-select { display: none; }", css, fixed = TRUE))
})


# ---------------------------------------------------------------------------
# 5. Accessibility
# ---------------------------------------------------------------------------

test_that("every picker control is a real button with a real name", {
  for (html in list(.render(system_field_ui()), .render(edition_field_ui()))) {
    # No <div onclick>. Triggers are <button>, and Shiny action buttons
    # render as <button> too.
    expect_true(grepl("<button", html, fixed = TRUE))
    expect_true(grepl("aria-label", html, fixed = TRUE))
  }
})

test_that("the sheet's option rows carry a non-colour selected state", {
  reg <- classification_registry()
  html <- .render(system_picker_list_ui(reg, selected = reg$id[[1]]))
  expect_true(grepl('aria-pressed="true"', html, fixed = TRUE))
  expect_true(grepl('aria-pressed="false"', html, fixed = TRUE))
  # Plus the word itself, so the state is never carried by the rail alone.
  expect_true(grepl(">Selected<", html, fixed = TRUE))
})

test_that("the sheet's search field keeps a real label in the DOM", {
  html <- .render(system_picker_dialog_ui())
  expect_true(grepl("<label", html, fixed = TRUE))
  expect_true(grepl("Search acronym or title", html, fixed = TRUE))
  # Hidden visually only -- never `display:none`, which removes it from the
  # accessibility tree too.
  css <- .read_file("www", "ui-design.css")
  expect_true(grepl(".psa-picker-search label {", css, fixed = TRUE))
  expect_true(grepl("clip: rect(0, 0, 0, 0);", css, fixed = TRUE))
})

test_that("the picker script handles Escape and returns focus to the trigger", {
  src <- .read_file("R", "ui", "ui_pickers.R")
  expect_true(grepl('e.key !== "Escape"', src, fixed = TRUE))
  expect_true(grepl("trigger.focus()", src, fixed = TRUE))
  expect_true(grepl('setAttribute("aria-expanded"', src, fixed = TRUE))
  # Installed once per page, however many screens include it.
  expect_true(grepl("window.__psaPickerInstalled", src, fixed = TRUE))
})

test_that("picker input ids are unique across the Search screen", {
  html <- .render(search_ui())
  for (id in c("classification_system", "classification_version",
               "classification_level")) {
    hits <- gregexpr(sprintf('id="%s"', id), html, fixed = TRUE)[[1]]
    expect_identical(length(hits[hits > 0]), 1L, info = id)
  }
})

test_that("Browse hierarchy is mounted in the results toolbar", {
  html <- .render(search_ui())
  expect_true(grepl("psa-results-toolbar", html, fixed = TRUE))

  # The slot sits INSIDE the toolbar, beside the count it scopes -- not at
  # the bottom of the filter rail, and not appended after the whole screen
  # by app.R any more.
  toolbar <- regmatches(
    html,
    regexpr('psa-results-toolbar.*?psa-hierarchy-slot', html)
  )
  expect_gt(length(toolbar), 0L)

  app <- .read_file("app.R")
  expect_false(grepl("search_ui(),\n                   hierarchy_browse_slot_ui()",
                     app, fixed = TRUE))
  # The feature itself is wired by the same single unchanged call.
  expect_true(grepl("hierarchy_browser_server(input, output, session",
                    app, fixed = TRUE))
})

test_that("the rail raises whichever filter field is currently open", {
  # UAT-UI-11, found in browser UAT of the descriptive-metadata pass.
  #
  # `position: fixed` on the panel escapes CLIPPING, but it does not escape
  # STACKING: ui-glass.css gives every direct child of a glass surface
  # `position: relative; z-index: 1` so glass content clears the blur layer,
  # and that turns each filter field into its own stacking context. A trapped
  # overlay cannot outrank a sibling however high its own z-index is, so
  # painting order fell back to DOM order and the controls around an open
  # overlay were drawn on top of it: Level over the Edition list, and -- the
  # damaging one -- the Edition trigger over the middle of the open System
  # list, where it also took the clicks aimed at the options behind it.
  #
  # Raising the two fields by a FIXED ORDER is not the fix, and was rejected
  # in UAT for a reason worth recording: it cures the desktop rail and breaks
  # the phone one, where the Edition panel becomes a full-width bottom sheet
  # that has to clear every field including the one above it. A static order
  # can only be right in one direction.
  #
  # So the rule keys on open state, which only one field can hold at a time,
  # and reads that state from `aria-expanded` -- already published by the
  # picker trigger and by selectize -- rather than from a second class that
  # could drift out of step with the accessibility contract.
  glass <- .read_file("www", "ui-glass.css")
  expect_true(grepl(".psa-liquid-glass > * { position: relative; z-index: 1; }",
                    glass, fixed = TRUE))

  css <- .read_file("www", "ui-design.css")
  expect_true(grepl('.psa-sidebar > *:has([aria-expanded="true"]) { z-index: 5; }',
                    css, fixed = TRUE))

  # The raise must be CONDITIONAL. A bare z-index on either field class is
  # the rejected fixed-order fix returning, so fail on it explicitly.
  expect_false(grepl(".psa-sidebar > .psa-system-field { z-index:", css, fixed = TRUE))
  expect_false(grepl(".psa-sidebar > .psa-picker-field { z-index:", css, fixed = TRUE))

  # And the state the rule keys on is really the state the trigger publishes.
  src <- .read_file("R", "ui", "ui_pickers.R")
  expect_true(grepl('aria-expanded', src, fixed = TRUE))
  html <- .render(edition_field_ui())
  expect_true(grepl('aria-expanded="false"', html, fixed = TRUE))
})

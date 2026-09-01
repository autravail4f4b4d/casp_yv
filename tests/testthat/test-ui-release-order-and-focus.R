# Acceptance regressions for the two blockers found in browser UAT.
#
#   1. UI-01 release order — the app listed PSGC oldest-first with the
#      CURRENT release last, because app.R composed its own choice list
#      instead of calling the tested `edition_choice_spec()` helper.
#   2. Shared dialog focus restoration — focus was not returned to the
#      originating trigger on close.
#
# WHY THESE TESTS LOOK THE WAY THEY DO
#
# Both defects passed the previous suite. That is the thing worth fixing
# about the tests, not just the code:
#
#   * `edition_choice_spec()` was unit-tested in isolation and was correct
#     the whole time — it simply was not wired in. A test of the helper can
#     therefore never catch this class of defect. The test below drives
#     app.R's REAL observer through `shiny::testServer()` and inspects what
#     the app actually sends to the client, and separately asserts that the
#     canonical helper is the thing that produced it.
#   * Focus restoration was asserted structurally ("the handler string is
#     present"), which stayed true while the runtime behaviour was broken.
#     This project has no headless browser, so the behavioural proof is the
#     browser UAT; what is asserted here instead are the two architectural
#     facts that make one browser-verified fix cover every dialog, plus the
#     specific lifecycle mistake that caused the failure.

.repo2 <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)

.slurp <- function(...) {
  path <- file.path(.repo2, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}


# =========================================================================
# BLOCKER 1 — UI-01 release order, through the real integration path
# =========================================================================

# Drives app.R's own `observeEvent(input$classification_system, ...)` and
# captures the argument list it hands to `updateRadioButtons()`.
.capture_edition_update <- function(system_id) {
  captured <- new.env(parent = emptyenv())
  captured$args <- NULL

  testthat::local_mocked_bindings(
    updateRadioButtons = function(session, inputId, ...) {
      if (identical(inputId, "classification_version")) {
        captured$args <- list(...)
      }
      invisible(NULL)
    },
    .package = "shiny"
  )


  shiny::testServer(.repo2, {
    session$setInputs(main_nav = "search", classification_system = system_id)
    session$elapse(500)
  })

  list(
    values = as.character(unlist(captured$args$choiceValues)),
    selected = captured$args$selected,
    n_names = length(captured$args$choiceNames),
    # Rendered option markup, so a test can fingerprint WHICH code produced
    # it rather than only checking the order came out right.
    names_html = vapply(
      captured$args$choiceNames %||% list(),
      function(x) as.character(htmltools::renderTags(x)$html),
      character(1)
    )
  )
}


test_that("the live app sends PSGC releases current-first, then descending", {
  # THE ACTUAL DEFECT. Before the fix this observer emitted repository
  # order, so the list opened on "Q1 2023 ARCHIVED" and the current release
  # sat at the bottom of a 13-item radio group.
  got <- .capture_edition_update("psgc")

  expect_gt(length(got$values), 1L)
  expect_identical(got$values[[1]], got$selected)

  # Descending by canonical release key, so the assertion holds however
  # many PSGC releases exist.
  #
  # NON-INCREASING, not strictly decreasing, and that is not a weakening:
  # the month-token map scores q3 and july identically (both = 7), so
  # "Q3_2025" and "July_2025" are the SAME effective release period and
  # tie. A tie is broken by repository order, which is the conservative
  # outcome. Strict descent is asserted across the distinct keys instead,
  # which is the part that actually catches a repository-order regression.
  keys <- .release_effective_key(got$values)
  datable <- !is.na(keys)
  expect_true(all(diff(keys[datable]) <= 0))
  expect_true(all(diff(unique(keys[datable])) < 0))
  expect_gt(length(unique(keys[datable])), 1L)

  # Every release is still offered and every one still gets a label; the
  # ordering fix must not drop or duplicate an edition.
  expect_identical(length(got$values), length(unique(got$values)))
  expect_identical(got$n_names, length(got$values))
})


test_that("the live app orders every multi-release system the same way", {
  reg <- classification_registry()
  ids <- reg$id[vapply(reg$id,
                       function(i) length(classification_versions(i)) > 1L,
                       logical(1))]
  expect_gt(length(ids), 0L)

  for (id in ids) {
    got <- .capture_edition_update(id)
    expect_identical(got$values[[1]], got$selected, info = id)
    keys <- .release_effective_key(got$values)
    datable <- !is.na(keys)
    if (sum(datable) > 1L) {
      expect_true(all(diff(keys[datable]) <= 0), info = id)
      expect_true(all(diff(unique(keys[datable])) < 0), info = id)
    }
  }
})


test_that("app.R builds the edition list THROUGH edition_choice_spec()", {
  # This is the assertion that fails if someone re-inlines the ordering
  # logic in the observer. Getting the ORDER right by hand is not enough:
  # duplicated presentation logic that can silently diverge from the tested
  # helper IS the defect, so the helper has to be the single producer.
  #
  # Asserted by FINGERPRINT rather than by mocking the function. app.R
  # sources R/ into its own evaluation environment (see its `lapply(...,
  # source)` preamble), which shadows the global bindings the test session
  # holds, so a rebinding here can never intercept the observer. What the
  # helper does emit and the old inline code did not is the
  # `psa-edition-row` wrapper, with `psa-edition-row-current` on exactly
  # the current release -- read here off the live update payload.
  got <- .capture_edition_update("psgc")

  expect_identical(sum(grepl("psa-edition-row-current", got$names_html)), 1L)
  expect_true(grepl("psa-edition-row-current", got$names_html[[1]]))
  expect_true(all(grepl("psa-edition-row", got$names_html)))
  expect_identical(got$values[[1]], got$selected)

  # Second gate, at the source: the observer must not have grown its own
  # copy of the choice-list construction again.
  app_code <- paste(sub("#.*$", "", readLines(file.path(.repo2, "app.R"),
                                              warn = FALSE)), collapse = "\n")
  expect_true(grepl("edition_choice_spec(versions, current)", app_code, fixed = TRUE))
  expect_false(grepl("choiceNames = choice_names", app_code, fixed = TRUE))
})


test_that("ordering is derived from release metadata, not a string sort", {
  # A lexical sort of the identifiers would put "April_2024" before every
  # "Q..." release and "July_2025" before "Q1_2023". The canonical key is
  # numeric (year * 100 + month), so the month-named releases interleave
  # with the quarterly ones in true release order.
  v <- c("Q1_2023", "April_2024", "Q2_2024", "July_2025", "Q2_2026")
  ordered <- release_newest_first(v, current = "Q2_2026")

  expect_identical(
    ordered,
    c("Q2_2026", "July_2025", "Q2_2024", "April_2024", "Q1_2023")
  )
  expect_false(identical(ordered, sort(v, decreasing = TRUE)))
})


test_that("reordering the list cannot change which edition is in effect", {
  # The ordering is presentation only: values stay canonical identifiers and
  # `selected` stays the registry's current version, so nothing downstream
  # in search/retrieval sees the reordering.
  reg <- classification_registry()
  for (id in c("psgc", "psoc", "psic")) {
    got <- .capture_edition_update(id)
    expect_identical(got$selected, reg$current_version[reg$id == id][[1]], info = id)
    expect_true(all(got$values %in% classification_versions(id)), info = id)
    expect_setequal(got$values, classification_versions(id))
  }
})


# =========================================================================
# BLOCKER 2 — shared dialog focus restoration
# =========================================================================

test_that("restoration is not gated on the event that never arrives", {
  # ROOT CAUSE, encoded. `shiny::showModal()` wraps the dialog in
  # `#shiny-modal` and Shiny removes that wrapper as the modal hides, so
  # Bootstrap dispatches the native `hidden.bs.modal` on an ALREADY
  # DETACHED element and it never bubbles to `document`. Instrumented in
  # the browser: show/shown/hide all reached a native document listener,
  # `hidden` reached only jQuery.
  #
  # So a restore bound solely to `hidden.bs.modal` is dead code. This
  # asserts the binding that actually fires is present.
  js <- .slurp("R", "ui", "ui_dialog.R")

  expect_true(grepl('addEventListener("hide.bs.modal"', js, fixed = TRUE))
  expect_true(grepl('addEventListener("hidden.bs.modal"', js, fixed = TRUE))

  # ...and that both funnel into one shared restore rather than two
  # divergent copies.
  expect_identical(
    length(gregexpr("function restoreFocus", js, fixed = TRUE)[[1]]), 1L
  )
})


test_that("there is exactly ONE focus-restoration implementation", {
  # The handoff asks for the smallest generic shared fix and forbids
  # per-dialog focus hacks. This fails if a second one appears anywhere in
  # the UI layer, which is what would silently un-fix the other dialogs.
  ui_files <- list.files(file.path(.repo2, "R", "ui"), pattern = "[.]R$",
                         full.names = TRUE)
  offenders <- Filter(function(p) {
    if (basename(p) == "ui_dialog.R") return(FALSE)
    txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
    grepl("bs.modal", txt, fixed = TRUE) ||
      grepl("__psaOrigin", txt, fixed = TRUE) ||
      grepl("restoreFocus", txt, fixed = TRUE)
  }, ui_files)

  expect_identical(basename(offenders), character(0))
})


test_that("every dialog in the app is built by the shared shell", {
  # This is what makes one browser-verified fix cover hierarchy browse,
  # PSOC details, PSIC details, the PSOC+PSIC comparison and any future
  # consumer: they all go through psa_dialog_ui(), so they all inherit the
  # one focus implementation. A dialog opened with a bare
  # shiny::modalDialog() would bypass it entirely.
  ui_files <- list.files(file.path(.repo2, "R", "ui"), pattern = "[.]R$",
                         full.names = TRUE)
  # Comments are stripped first: ui_dialog.R legitimately NAMES
  # shiny::modalDialog() while explaining why it does not use it, and a
  # naive text scan would flag the shell that implements the contract.
  code_only <- function(p) {
    ln <- readLines(p, warn = FALSE)
    paste(sub("#.*$", "", ln), collapse = "\n")
  }
  raw_modals <- Filter(function(p) {
    grepl("modalDialog(", code_only(p), fixed = TRUE)
  }, ui_files)
  expect_identical(basename(raw_modals), character(0))

  app_code <- paste(sub("#.*$", "", readLines(file.path(.repo2, "app.R"),
                                              warn = FALSE)), collapse = "\n")
  expect_false(grepl("modalDialog(", app_code, fixed = TRUE))

  # The known consumers really do route through the shell.
  expect_true(grepl("psa_dialog_ui(", .slurp("R", "ui", "ui_hierarchy.R"), fixed = TRUE))
  expect_true(grepl("psa_dialog_ui(", .slurp("R", "ui", "ui_details.R"), fixed = TRUE))
})


test_that("the restore is deferred and re-resolves a re-rendered trigger", {
  # Two failure modes the browser run exposed, both encoded here because
  # both are easy to "simplify" away:
  #   1. focusing synchronously loses the race with the node removal that
  #      drops focus to <body>, so the call is deferred;
  #   2. a trigger living in a uiOutput can be re-rendered while the dialog
  #      is open, leaving the snapshotted node detached, so it is
  #      re-resolved by id.
  js <- .slurp("R", "ui", "ui_dialog.R")
  expect_true(grepl("requestAnimationFrame", js, fixed = TRUE))
  expect_true(grepl("document.getElementById(origin.id)", js, fixed = TRUE))
})


test_that("the runtime focus probe is exposed for browser acceptance", {
  # Behaviour here is only provable in a browser, so the shell publishes a
  # boolean probe the UAT step reads instead of a human eyeballing a
  # cursor. It carries an event name and two booleans -- never user
  # content, never classification data.
  js <- .slurp("R", "ui", "ui_dialog.R")
  expect_true(grepl("window.__psaDialogFocus", js, fixed = TRUE))
  expect_true(grepl("hadOrigin", js, fixed = TRUE))
  expect_true(grepl("restored", js, fixed = TRUE))
})


# =========================================================================
# POLISH 3 — short status vocabulary must not break inside a word
# =========================================================================

test_that("short status columns are tagged no-break at the column, not by index", {
  app <- .slurp("app.R")
  # Attached by column identity in the DT column definition, so it follows
  # the column if the layout changes, rather than a positional CSS rule
  # that would silently target the wrong column.
  expect_identical(
    length(gregexpr('className = "psa-nowrap"', app, fixed = TRUE)[[1]]), 3L
  )

  css <- .slurp("www", "ui-tokens.css")
  expect_true(grepl("td.psa-nowrap", css, fixed = TRUE))
  expect_true(grepl("white-space: nowrap;", css, fixed = TRUE))

  # A wider column must scroll inside its own container, never widen the
  # page (handoff section 18).
  expect_true(grepl(".psa-dual-results .dataTables_wrapper", css, fixed = TRUE))
  expect_true(grepl("overflow-x: auto;", css, fixed = TRUE))
})

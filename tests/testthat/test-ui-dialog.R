# Shared dialog/drawer shell — UI-A (handoff sections 3 and 4).
#
# These assert the ACCESSIBILITY CONTRACT of the overlay, not its looks.
# Every rule here is one that fails silently in a browser: a dialog with no
# accessible name, an icon-only close button, a trap that never receives
# focus, or focus that vanishes to the top of the document on close.

.render <- function(tag) as.character(htmltools::renderTags(tag)$html)

.dialog <- function(...) {
  psa_dialog_ui(id = "test-dialog", title = "Test dialog", body = "Body", ...)
}


test_that("a dialog is announced as a modal dialog with an accessible name", {
  html <- .render(.dialog())

  expect_true(grepl('role="dialog"', html, fixed = TRUE))
  expect_true(grepl('aria-modal="true"', html, fixed = TRUE))

  # The accessible name must be wired to the VISIBLE title, not duplicated
  # into an aria-label that can drift away from it.
  expect_true(grepl('aria-labelledby="psa-dialog-title-test-dialog"', html, fixed = TRUE))
  expect_true(grepl('id="psa-dialog-title-test-dialog"', html, fixed = TRUE))
  expect_true(grepl("Test dialog", html, fixed = TRUE))
})

test_that("the overlay keeps Shiny's showModal contract", {
  html <- .render(.dialog())
  # showModal()/removeModal() and Shiny's own hidden.bs.modal cleanup all
  # key off this id. Renaming it would break closing, not just styling.
  expect_true(grepl('id="shiny-modal"', html, fixed = TRUE))
  expect_true(grepl("modal fade psa-dialog", html, fixed = TRUE))
  expect_true(grepl("bootstrap.Modal", html, fixed = TRUE))
})

test_that("Escape closes and the backdrop is active", {
  html <- .render(.dialog())
  expect_true(grepl('data-bs-keyboard="true"', html, fixed = TRUE))
  expect_true(grepl('data-bs-backdrop="true"', html, fixed = TRUE))
  # The static/no-keyboard combination shiny::modalDialog() defaults to
  # would make Escape a no-op.
  expect_false(grepl('data-bs-backdrop="static"', html, fixed = TRUE))
  expect_false(grepl('data-bs-keyboard="false"', html, fixed = TRUE))
})

test_that("the close control is a real button with a real accessible label", {
  html <- .render(.dialog(close_label = "Close the hierarchy browser"))

  expect_true(grepl('aria-label="Close the hierarchy browser"', html, fixed = TRUE))
  expect_true(grepl('data-bs-dismiss="modal"', html, fixed = TRUE))
  # Never a div-with-a-click-handler, and never an unlabelled glyph.
  close_tag <- regmatches(
    html, regexpr("<[a-z]+[^>]*psa-dialog__close[^>]*>", html)
  )
  expect_length(close_tag, 1L)
  expect_true(grepl("^<button", close_tag))
})

test_that("focus management ships with every dialog", {
  html <- .render(.dialog())

  # Focus moves in on open...
  expect_true(grepl("shown.bs.modal", html, fixed = TRUE))
  # ...is trapped while open...
  expect_true(grepl('e.key !== "Tab"', html, fixed = TRUE))
  # ...and returns to the originating control on close.
  expect_true(grepl("hidden.bs.modal", html, fixed = TRUE))
  expect_true(grepl("__psaOrigin", html, fixed = TRUE))
})

test_that("the focus script installs exactly once per page", {
  html <- .render(shiny::tagList(psa_dialog_deps(), psa_dialog_deps(), .dialog()))
  expect_true(grepl("__psaDialogInstalled", html, fixed = TRUE))
  # The guard, not the number of <script> copies, is what prevents double
  # listeners -- assert the guard is present in every copy.
  n_bodies <- length(gregexpr("__psaDialogInstalled = true", html, fixed = TRUE)[[1]])
  n_guards <- length(gregexpr("if (window.__psaDialogInstalled)", html, fixed = TRUE)[[1]])
  expect_equal(n_guards, n_bodies)
})

test_that("modal and drawer are the same primitive with different placement", {
  modal <- .render(.dialog(variant = "modal"))
  drawer <- .render(.dialog(variant = "drawer"))

  expect_true(grepl("psa-dialog--modal", modal, fixed = TRUE))
  expect_true(grepl("psa-dialog--drawer", drawer, fixed = TRUE))

  # The drawer must not lose any of the modal's accessibility behaviour.
  for (html in list(modal, drawer)) {
    expect_true(grepl('aria-modal="true"', html, fixed = TRUE))
    expect_true(grepl('role="dialog"', html, fixed = TRUE))
    expect_true(grepl("shown.bs.modal", html, fixed = TRUE))
  }
})

test_that("sizes map onto Bootstrap's own width classes", {
  expect_true(grepl("modal-lg", .render(.dialog(size = "lg")), fixed = TRUE))
  expect_true(grepl("modal-xl", .render(.dialog(size = "xl")), fixed = TRUE))
  expect_true(grepl("modal-fullscreen", .render(.dialog(size = "full")), fixed = TRUE))
  expect_false(grepl("modal-lg", .render(.dialog(size = "md")), fixed = TRUE))
})

test_that("an unknown variant or size is rejected rather than rendered wrong", {
  expect_error(.dialog(variant = "popover"))
  expect_error(.dialog(size = "enormous"))
})

test_that("a description is wired as aria-describedby", {
  html <- .render(.dialog(description = "Published structure for this edition."))
  expect_true(grepl('aria-describedby="psa-dialog-desc-test-dialog"', html, fixed = TRUE))
  expect_true(grepl('id="psa-dialog-desc-test-dialog"', html, fixed = TRUE))
})

test_that("a dialog with no description emits no dangling aria-describedby", {
  html <- .render(.dialog())
  expect_false(grepl("aria-describedby", html, fixed = TRUE))
})

test_that("an open trigger always has a visible text label", {
  html <- .render(psa_dialog_open_button("open_x", "Browse hierarchy"))
  expect_true(grepl("Browse hierarchy", html, fixed = TRUE))
  expect_true(grepl("psa-dialog-open", html, fixed = TRUE))
  expect_true(grepl('id="open_x"', html, fixed = TRUE))
})

test_that("a disabled trigger is disabled to the browser AND to assistive tech", {
  html <- .render(psa_dialog_open_button("open_x", "Compare", disabled = TRUE))
  expect_true(grepl("disabled", html, fixed = TRUE))
  expect_true(grepl('aria-disabled="true"', html, fixed = TRUE))
})

test_that("the footer action does not self-dismiss", {
  # The server decides whether the action succeeded; a self-dismissing
  # button would close the dialog on an action that never happened.
  html <- .render(psa_dialog_action_button("do_x", "View in Search"))
  expect_false(grepl("data-bs-dismiss", html, fixed = TRUE))
  expect_true(grepl('id="do_x"', html, fixed = TRUE))
})

test_that("the default footer offers a working Close", {
  html <- .render(.dialog())
  expect_true(grepl("psa-dialog__footer", html, fixed = TRUE))
  expect_true(grepl(">Close</button>", html, fixed = TRUE))
})

test_that("view_in_search_apply is a no-op for an empty selection", {
  empty <- get_classification("psoc", "2022")[0, , drop = FALSE]
  expect_null(view_in_search_apply(empty, session = NULL))
  expect_null(view_in_search_apply(NULL, session = NULL))
})

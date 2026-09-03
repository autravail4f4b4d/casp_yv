# UI-03 — PSOC/PSIC detail and comparison dialogs.
#
# The safeguard this file protects: showing a PSOC code and a PSIC code in
# one dialog must never read as a mapping between them. The independence
# sentence is therefore asserted on EVERY path through the comparison
# builder, including the incomplete-selection path.

.render <- function(tag) as.character(htmltools::renderTags(tag)$html)

.psoc_row <- function(n = 1L) {
  d <- search_classification("psoc", "2022", "farmer", limit = 5)
  if (nrow(d) == 0L) d <- get_classification("psoc", "2022")
  d[min(n, nrow(d)), , drop = FALSE]
}

.psic_row <- function(n = 1L) {
  d <- search_classification("psic", "2026", "growing", limit = 5)
  if (nrow(d) == 0L) d <- get_classification("psic", "2026")
  d[min(n, nrow(d)), , drop = FALSE]
}


# ---------------------------------------------------------------------
# The safeguard sentence
# ---------------------------------------------------------------------

test_that("the independence sentence is the handoff's wording, verbatim", {
  expect_equal(
    PSOC_PSIC_INDEPENDENCE_NOTE,
    "A PSOC code does not imply an equivalent PSIC code, and vice versa."
  )
})

test_that("the comparison always states that neither code implies the other", {
  html <- .render(entry_comparison_dialog_ui(.psoc_row(), .psic_row()))
  expect_true(grepl(PSOC_PSIC_INDEPENDENCE_NOTE, html, fixed = TRUE))
})

test_that("the safeguard survives every incomplete-selection path", {
  cases <- list(
    list(.psoc_row(), NULL),
    list(NULL, .psic_row()),
    list(NULL, NULL),
    list(get_classification("psoc", "2022")[0, ], get_classification("psic", "2026")[0, ])
  )
  for (cs in cases) {
    html <- .render(entry_comparison_dialog_ui(cs[[1]], cs[[2]]))
    expect_true(grepl(PSOC_PSIC_INDEPENDENCE_NOTE, html, fixed = TRUE))
  }
})

test_that("the safeguard is informational, never error-styled", {
  # A methodological caution is not a failure (handoff section 2).
  html <- .render(entry_comparison_dialog_ui(.psoc_row(), .psic_row()))
  # In the populated review the safeguard is the first item of the coding
  # check rather than a trailing note; the SENTENCE is what matters and it
  # is asserted here as well as in the incomplete-state test above.
  expect_true(grepl(PSOC_PSIC_INDEPENDENCE_NOTE, html, fixed = TRUE))
  expect_true(grepl("psa-coding-check", html, fixed = TRUE))
  expect_false(grepl("status-error", html, fixed = TRUE))
  expect_false(grepl("alert-danger", html, fixed = TRUE))
  expect_false(grepl("text-danger", html, fixed = TRUE))
})

test_that("the coding check never claims the pair is correct", {
  # UAT-UI-03. Nothing in this application knows the establishment or the
  # person, so nothing here may validate the pair against them. A green
  # tick on an unvalidated pair is exactly the false assurance a
  # statistical utility must not give.
  html <- .render(entry_comparison_dialog_ui(.psoc_row(), .psic_row()))

  # AFFIRMATIVE claims only. A bare substring scan is wrong here: the
  # dialog says "does not claim the pair is correct or equivalent", and
  # "does not imply an equivalent PSIC code" -- both NEGATIONS, and both
  # exactly what this test wants to see.
  # Phrasings that could only ever be affirmative. "the pair is correct" is
  # deliberately NOT in this list: it is a substring of the dialog's own
  # disclaimer, "does not claim the pair is correct or equivalent", which
  # the positive assertions below pin instead.
  for (claim in c("codes are equivalent", "correctly coded",
                  "this pair is valid", "the pair matches",
                  "pair is consistent", "appears correct", "looks correct")) {
    expect_false(grepl(claim, html, ignore.case = TRUE), info = claim)
  }
  # And it says so explicitly rather than merely omitting the claim.
  expect_true(grepl("has not been told who the person is", html, fixed = TRUE))
  expect_true(grepl("does not claim the pair is correct", html, fixed = TRUE))
})


# ---------------------------------------------------------------------
# Comparison layout and labelling
# ---------------------------------------------------------------------

test_that("the comparison keeps PSOC and PSIC as distinct, named things", {
  psoc <- .psoc_row()
  psic <- .psic_row()
  html <- .render(entry_comparison_dialog_ui(psoc, psic))

  expect_true(grepl("psa-compare-col--psoc", html, fixed = TRUE))
  expect_true(grepl("psa-compare-col--psic", html, fixed = TRUE))
  # PSOC is left, PSIC is right (desktop); the grid stacks on mobile.
  expect_lt(
    regexpr("psa-compare-col--psoc", html, fixed = TRUE),
    regexpr("psa-compare-col--psic", html, fixed = TRUE)
  )
  expect_true(grepl("what the person does", html, fixed = TRUE))
  expect_true(grepl("what the establishment does", html, fixed = TRUE))
  expect_true(grepl(psoc$code, html, fixed = TRUE))
  expect_true(grepl(psic$code, html, fixed = TRUE))
})

test_that("the comparison is an accessible dialog", {
  html <- .render(entry_comparison_dialog_ui(.psoc_row(), .psic_row()))
  expect_true(grepl('aria-modal="true"', html, fixed = TRUE))
  expect_true(grepl('aria-label="Close the coding pair review"', html, fixed = TRUE))
  expect_true(grepl("Review coding pair", html, fixed = TRUE))

  # UAT-UI-03 renamed it. "Compare" invited the reading the independence
  # safeguard exists to prevent -- two things compared are two things a
  # reader expects to line up -- so the old wording must be gone, not just
  # supplemented.
  expect_false(grepl("Compare selected details", html, fixed = TRUE))
})

test_that("the review offers the processor's three actions", {
  html <- .render(entry_comparison_dialog_ui(.psoc_row(), .psic_row()))
  expect_true(grepl("Change PSOC", html, fixed = TRUE))
  expect_true(grepl("Change PSIC", html, fixed = TRUE))
  expect_true(grepl("Ask RM to review this coding pair", html, fixed = TRUE))
  expect_true(grepl(DUAL_SEARCH_ASK_RM_INPUT, html, fixed = TRUE))

  # The RM action is withheld where the deployment cannot deliver it.
  off <- .render(entry_comparison_dialog_ui(.psoc_row(), .psic_row(), ask_rm = FALSE))
  expect_false(grepl(DUAL_SEARCH_ASK_RM_INPUT, off, fixed = TRUE))
  expect_true(grepl("Change PSOC", off, fixed = TRUE))
})


# ---------------------------------------------------------------------
# Single-record dialogs
# ---------------------------------------------------------------------

test_that("a PSOC detail dialog names the occupation, not an industry", {
  entry <- .psoc_row()
  html <- .render(entry_detail_dialog_ui(entry))
  expect_true(grepl("Occupation details", html, fixed = TRUE))
  expect_false(grepl("Industry details", html, fixed = TRUE))
  expect_true(grepl(entry$code, html, fixed = TRUE))
  expect_true(grepl(entry$label, html, fixed = TRUE))
})

test_that("a PSIC detail dialog names the industry, not an occupation", {
  entry <- .psic_row()
  html <- .render(entry_detail_dialog_ui(entry))
  expect_true(grepl("Industry details", html, fixed = TRUE))
  expect_false(grepl("Occupation details", html, fixed = TRUE))
})

test_that("a detail dialog carries hierarchy, status, level and source", {
  entry <- .psic_row()
  html <- .render(entry_detail_dialog_ui(entry))
  expect_true(grepl("Classification hierarchy", html, fixed = TRUE))
  expect_true(grepl("Level", html, fixed = TRUE))
  expect_true(grepl("psa-tag-", html))
  expect_true(grepl("psa-source-line", html, fixed = TRUE))
  expect_true(grepl("Philippine Statistics Authority", html, fixed = TRUE))
})

test_that("View in Search appears only when the caller wires an id for it", {
  entry <- .psoc_row()
  with_action <- .render(entry_detail_dialog_ui(entry, view_input_id = "dual_search_view_in_search"))
  without <- .render(entry_detail_dialog_ui(entry))

  expect_true(grepl('id="dual_search_view_in_search"', with_action, fixed = TRUE))
  expect_true(grepl("View in Search", with_action, fixed = TRUE))
  expect_false(grepl("View in Search", without, fixed = TRUE))
})

test_that("an empty selection produces a prompt dialog, never a blank one", {
  html <- .render(entry_detail_dialog_ui(get_classification("psoc", "2022")[0, ]))
  expect_true(grepl("No record selected", html, fixed = TRUE))
  expect_true(grepl('aria-modal="true"', html, fixed = TRUE))
})


# ---------------------------------------------------------------------
# Row click selects only; details are an explicit action
# ---------------------------------------------------------------------

test_that("the panel shell opens nothing by itself", {
  html <- .render(dual_search_panel_ui("psoc"))
  # No modal markup and no click-to-open handler baked into the table area.
  expect_false(grepl("shiny-modal", html, fixed = TRUE))
  expect_false(grepl("data-bs-toggle=\"modal\"", html, fixed = TRUE))
})

test_that("the selection line offers an explicit View details action", {
  entry <- .psoc_row()
  html <- .render(dual_selection_summary_ui(entry, "psoc"))

  expect_true(grepl("View details", html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psoc_view_details"', html, fixed = TRUE))
  expect_true(grepl(entry$code, html, fixed = TRUE))
  # Compact: the full source/description block now lives in the dialog.
  expect_false(grepl("psa-source-line", html, fixed = TRUE))
})

test_that("with nothing selected the action is genuinely disabled and says why", {
  html <- .render(dual_selection_summary_ui(NULL, "psic"))
  expect_true(grepl("No row selected", html, fixed = TRUE))
  expect_true(grepl('aria-disabled="true"', html, fixed = TRUE))
  expect_true(grepl("disabled", html, fixed = TRUE))
})

test_that("each side's selection line names only its own inputs", {
  psoc <- .render(dual_selection_summary_ui(.psoc_row(), "psoc"))
  psic <- .render(dual_selection_summary_ui(.psic_row(), "psic"))

  expect_true(grepl("dual_search_psoc_view_details", psoc, fixed = TRUE))
  expect_false(grepl("dual_search_psic", psoc, fixed = TRUE))

  expect_true(grepl("dual_search_psic_view_details", psic, fixed = TRUE))
  expect_false(grepl("dual_search_psoc", psic, fixed = TRUE))
})


# ---------------------------------------------------------------------
# Compare control state
# ---------------------------------------------------------------------

test_that("Compare is enabled only when one row of each kind is selected", {
  both <- .render(dual_search_compare_ui(.psoc_row(), .psic_row()))
  expect_false(grepl('aria-disabled="true"', both, fixed = TRUE))
  expect_true(grepl('id="dual_search_compare_open"', both, fixed = TRUE))

  for (state in list(
    dual_search_compare_ui(.psoc_row(), NULL),
    dual_search_compare_ui(NULL, .psic_row()),
    dual_search_compare_ui(NULL, NULL)
  )) {
    html <- .render(state)
    expect_true(grepl('aria-disabled="true"', html, fixed = TRUE))
  }
})

test_that("the disabled Compare control explains what is missing", {
  expect_true(grepl(
    "Select a PSIC row as well",
    .render(dual_search_compare_ui(.psoc_row(), NULL)), fixed = TRUE
  ))
  expect_true(grepl(
    "Select a PSOC row as well",
    .render(dual_search_compare_ui(NULL, .psic_row())), fixed = TRUE
  ))
  expect_true(grepl(
    "Select one PSOC row and one PSIC row",
    .render(dual_search_compare_ui(NULL, NULL)), fixed = TRUE
  ))
})


# ---------------------------------------------------------------------
# The screen still declares its independence, and still has no shared query
# ---------------------------------------------------------------------

test_that("the dual screen keeps both independent panels and the compare slot", {
  html <- .render(dual_search_ui())

  expect_true(grepl('id="dual_search_psoc_query"', html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psic_query"', html, fixed = TRUE))
  expect_true(grepl('id="dual_search_compare"', html, fixed = TRUE))
  # The removed shared query must stay removed.
  expect_false(grepl('id="dual_search_query"', html, fixed = TRUE))
  # Focus management for the new dialogs ships with the screen.
  expect_true(grepl("__psaDialogInstalled", html, fixed = TRUE))
})

test_that("the old permanent below-table detail block is gone", {
  html <- .render(dual_search_panel_ui("psoc"))
  # The heading is retained for assistive tech only; the large detail card
  # it used to introduce is replaced by the one-line selection summary.
  expect_true(grepl("psa-dual-detail-head visually-hidden", html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psoc_detail"', html, fixed = TRUE))
})

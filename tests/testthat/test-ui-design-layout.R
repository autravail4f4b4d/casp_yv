# Layout contracts introduced by the imported Claude Design artifact
# ("PSA Classifications Redesign", surfaces 1d/1e, 1f/1g).
#
# These are the two placement decisions the design makes that a later edit
# could silently undo, because neither errors when it regresses:
#
#   1. "Compare selected details" is a PAGE-LEVEL action in the head, not a
#      strip below two DataTables. Regressing it does not break anything --
#      it just puts the control a user reaches for immediately after their
#      second selection back underneath everything they just used.
#   2. On desktop the correspondence table and the relationship inspector
#      share one top and one bottom edge. Regressing that leaves two cards
#      of unrelated heights beside each other, which reads as a rendering
#      fault rather than a layout choice.

.render <- function(tag) paste(as.character(htmltools::renderTags(tag)$html),
                               collapse = "")

.repo <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)

.read_file <- function(...) {
  path <- file.path(.repo, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}


# ---------------------------------------------------------------------------
# PSOC + PSIC — the page-level action                        (surface 1d/1e)
# ---------------------------------------------------------------------------

test_that("Compare selected details sits in the page head, above both panels", {
  html <- .render(dual_search_ui())

  head_at <- regexpr("psa-dual-hero", html, fixed = TRUE)
  compare_at <- regexpr("psa-dual-compare", html, fixed = TRUE)
  grid_at <- regexpr("psa-dual-grid", html, fixed = TRUE)
  note_at <- regexpr("psa-dual-note", html, fixed = TRUE)

  expect_gt(head_at, 0L)
  expect_gt(compare_at, 0L)
  expect_gt(grid_at, 0L)

  # In the head...
  expect_lt(head_at, compare_at)
  # ...and BEFORE the two result panels, so it is reachable without
  # scrolling past them at any width.
  expect_lt(compare_at, grid_at)
  # The safeguard sentence stays at the foot of the page, where it always
  # was. It is not the thing that moved.
  expect_gt(note_at, grid_at)
})

test_that("the compare control keeps its ids and its disabled contract", {
  # Moving a control must not rename it: `dual_search_details_server()`
  # renders into the output and observes the input by these exact names.
  expect_identical(DUAL_SEARCH_COMPARE_OUTPUT, "dual_search_compare")
  expect_identical(DUAL_SEARCH_COMPARE_INPUT, "dual_search_compare_open")

  html <- .render(dual_search_ui())
  expect_true(grepl(DUAL_SEARCH_COMPARE_OUTPUT, html, fixed = TRUE))
})

test_that("the PSOC/PSIC independence safeguard survived the move", {
  html <- .render(dual_search_ui())
  # Stated once on the page, in the intro and in the note -- and always
  # again inside the comparison dialog itself.
  expect_true(grepl("They never determine each other", html, fixed = TRUE))
  expect_true(grepl("never implies an equivalent PSIC code", html, fixed = TRUE))

  dialog <- .render(entry_comparison_dialog_ui(NULL, NULL))
  expect_true(grepl(PSOC_PSIC_INDEPENDENCE_NOTE, dialog, fixed = TRUE))
})

test_that("at phone width the action goes full width, still above the panels", {
  css <- .read_file("www", "ui-design.css")
  expect_true(grepl(".psa-dual-hero {", css, fixed = TRUE))
  expect_true(grepl("@media (max-width: 767.98px)", css, fixed = TRUE))
  expect_true(grepl(".psa-dual-compare .psa-dialog-open { width: 100%;",
                    css, fixed = TRUE))
})


# ---------------------------------------------------------------------------
# Compare Editions — direction width and matched-height row  (surface 1f/1g)
# ---------------------------------------------------------------------------

test_that("Direction takes the wide column and cannot clip its longest value", {
  css <- .read_file("www", "ui-design.css")
  # ~1.4fr against the search field's 1fr, which is what the artifact
  # draws. The longest value is "2019 PSIC → PSIC Revision 5 (2026)".
  expect_true(grepl(
    "@media (min-width: 768px) {\n  .psa-corr-filters {\n    grid-template-columns: minmax(320px, 1.4fr) minmax(240px, 1fr);\n  }\n}",
    css, fixed = TRUE
  ))

  # Scoped to >= 768: this sheet loads after ui-filters.css, so an
  # unconditional rule here would outrank that sheet's phone-width collapse
  # to one full-width column. Measured at 320px, where the 320px minimum
  # pushed Direction 24px past the viewport and the page's overflow guard
  # then clipped it.
  filters <- .read_file("www", "ui-filters.css")
  expect_true(grepl("grid-template-columns: minmax(0, 1fr);", filters, fixed = TRUE))

  html <- .render(correspondence_ui())
  expect_true(grepl("psa-corr-filter--direction", html, fixed = TRUE))
  # Both directions are still offered, and the input id is unchanged.
  expect_true(grepl("correspondence_direction", html, fixed = TRUE))
  expect_true(grepl("2019-2026", html, fixed = TRUE))
  expect_true(grepl("2026-2019", html, fixed = TRUE))
})

test_that("desktop stretches the table and inspector to one shared height", {
  css <- .read_file("www", "ui-design.css")
  expect_true(grepl("@media (min-width: 992px)", css, fixed = TRUE))
  expect_true(grepl(".psa-corr-workspace { align-items: stretch; }",
                    css, fixed = TRUE))
  # The table's own body flexes to fill whatever height the taller card
  # sets, and pagination is pushed to the bottom edge rather than floating
  # in the middle of the card.
  expect_true(grepl(".psa-corr-table-col .dataTables_wrapper {", css, fixed = TRUE))
  expect_true(grepl("margin-top: auto;", css, fixed = TRUE))
  # An edge-matched inspector has nothing left to stick past. The two-class
  # selector is required, not decorative: ui-glass.css carries
  # `.psa-corr-inspector.psa-liquid-glass { position: sticky }`, which is a
  # specificity step above a plain class and wins regardless of load order.
  # Measured in the browser, where the cards stayed 12px and 36px apart.
  expect_true(grepl(
    ".psa-corr-inspector,\n  .psa-corr-inspector.psa-liquid-glass {\n    position: static;",
    css, fixed = TRUE
  ))

  # Bootstrap's 24px .card bottom margin is zeroed, or the two bottom edges
  # sit 24px apart however tall the row grows.
  expect_true(grepl("margin-bottom: 0;", css, fixed = TRUE))
})

test_that("mobile keeps natural per-card heights", {
  # Forcing equalisation on a stacked column pads one card out with dead
  # space. The stretch rule is therefore inside a min-width query, and the
  # narrow-width rules in ui-filters.css are untouched.
  css <- .read_file("www", "ui-design.css")
  stretch_at <- regexpr(".psa-corr-workspace { align-items: stretch; }", css, fixed = TRUE)
  desktop_at <- regexpr("@media (min-width: 992px)", css, fixed = TRUE)
  expect_gt(stretch_at, desktop_at)

  filters <- .read_file("www", "ui-filters.css")
  expect_true(grepl("@media (max-width: 991.98px)", filters, fixed = TRUE))
})


# ---------------------------------------------------------------------------
# Relationship detail — what it may and may not expose
# ---------------------------------------------------------------------------

test_that("the relationship detail exposes only user-facing statistics", {
  d <- search_psic_correspondence(query = "", from_version = "2019",
                                  to_version = "2026", limit = 5)
  skip_if(nrow(d) == 0L, "no correspondence rows in the artifact")
  html <- .render(correspondence_detail_ui(d[1, , drop = FALSE]))

  # Present: the facts a statistician acts on.
  expect_true(grepl("Relationship", html, fixed = TRUE))
  expect_true(grepl("Confidence", html, fixed = TRUE))
  expect_true(grepl("Derived correspondence", html, fixed = TRUE))
  expect_true(grepl("Statistical-use note", html, fixed = TRUE))

  # Absent: a standalone Provenance row, and every internal retrieval
  # diagnostic. The underlying FIELDS are untouched in the data -- this is
  # a presentation contract, not a data one.
  expect_false(grepl("Provenance:", html, fixed = TRUE))
  for (internal in c("normalized_token", "class_prefix_continuity",
                     "section_graph", "search_method", "score", "ranking")) {
    expect_false(grepl(internal, html, fixed = TRUE), info = internal)
  }
})

test_that("provenance is still carried in the data and in the RM context", {
  d <- search_psic_correspondence(query = "", from_version = "2019",
                                  to_version = "2026", limit = 5)
  skip_if(nrow(d) == 0L, "no correspondence rows in the artifact")
  expect_true("provenance" %in% names(d))

  ctx <- correspondence_ask_rm_context(d[1, , drop = FALSE])
  expect_true("provenance" %in% names(ctx))
})

test_that("the relationship-level Ask RM action is reachable from the app", {
  # It used to be built only by `correspondence_inspector_ui()`, which the
  # running application never renders -- so the button was in the source
  # and not in the DOM. Both renderers now build it from one helper.
  d <- search_psic_correspondence(query = "", from_version = "2019",
                                  to_version = "2026", limit = 5)
  skip_if(nrow(d) == 0L, "no correspondence rows in the artifact")
  row <- d[1, , drop = FALSE]

  expect_true(grepl("correspondence_ask_rm", .render(correspondence_detail_ui(row)),
                    fixed = TRUE))
  expect_true(grepl("correspondence_ask_rm", .render(correspondence_inspector_ui(row)),
                    fixed = TRUE))

  # And it is suppressed where it cannot be delivered.
  expect_false(grepl("correspondence_ask_rm",
                     .render(correspondence_detail_ui(row, ask_rm = FALSE)),
                     fixed = TRUE))
})


# ---------------------------------------------------------------------------
# Responsive safety — nothing introduced here can push the page sideways
# ---------------------------------------------------------------------------

test_that("every new grid and flex container can shrink below its content", {
  # `min-width: auto` on a grid/flex item is what turns a wide table into
  # horizontal overflow on <body> instead of a scroll inside its own card.
  css <- .read_file("www", "ui-design.css")
  for (rule in c(".psa-results-col", ".psa-detail-col",
                 ".psa-picker-field", ".psa-dual-hero-text")) {
    pattern <- paste0("[.]", substring(rule, 2), "[ ][{][^}]*[}]")
    block <- regmatches(css, regexpr(pattern, css))
    expect_true(length(block) > 0L, info = rule)
    expect_true(grepl("min-width: 0", block, fixed = TRUE), info = rule)
  }
})

test_that("phone-width touch targets clear 44px for every new control", {
  css <- .read_file("www", "ui-design.css")
  expect_true(grepl("@media (max-width: 575.98px)", css, fixed = TRUE))
  expect_true(grepl(".psa-askrm { min-height: 44px; }", css, fixed = TRUE))
  expect_true(grepl("min-width: 44px; min-height: 44px;", css, fixed = TRUE))
})

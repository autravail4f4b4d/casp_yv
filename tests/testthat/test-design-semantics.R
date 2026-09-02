# Visual-contract tests for the "Subtle Gradient" design pass
# (HANDOFF-CLAUDE-CODE.md v2.0).
#
# These assert the SEMANTIC rules of the design system, not its pixel
# values. Colours and spacing are expected to be retuned; what must never
# drift is which meaning gets which treatment. Two rules in particular are
# regressions that would be silent and harmful:
#
#   1. A classification relationship is not an error. Styling a split or a
#      merge as a failure tells a statistician the data is broken when it
#      is simply revised. v1.0 of the handoff got this wrong and v2.0
#      corrects it explicitly, so it is worth a test rather than a comment.
#   2. Status must never rest on colour alone.

.render <- function(tag) as.character(htmltools::renderTags(tag)$html)

# Lucide path fragments, used as fingerprints for "which glyph is this".
GLYPH_TRIANGLE_ALERT <- "21.73 18"
GLYPH_SPLIT <- "M16 3h5v5"
GLYPH_MERGE <- "m8 6 4-4 4 4"
GLYPH_CIRCLE_CHECK <- "m9 12 2 2 4-4"


# ---------------------------------------------------------------------
# Classification relationships are NEVER error-styled (handoff §12.3)
# ---------------------------------------------------------------------

.correspondence_row <- function(relation_type) {
  d <- search_psic_correspondence(
    query = "", from_version = "2019", to_version = "2026", limit = 4000
  )
  hits <- d[d$relation_type == relation_type, , drop = FALSE]
  if (nrow(hits) == 0L) {
    return(NULL)
  }
  hits[1, , drop = FALSE]
}

test_that("split and merged relationships carry no error semantics", {
  for (rt in c("split", "merged")) {
    row <- .correspondence_row(rt)
    skip_if(is.null(row), paste("no", rt, "relationship in the artifact"))

    html <- .render(correspondence_detail_ui(row))

    # The statistical-safety notice must be present for these types...
    expect_true(grepl("psa-stat-warning", html, fixed = TRUE), info = rt)

    # ...but must NOT be dressed as a failure. The warning glyph is
    # explicitly forbidden on relationship rows and on this notice.
    expect_false(grepl(GLYPH_TRIANGLE_ALERT, html, fixed = TRUE), info = rt)
    expect_false(grepl("status-error", html, fixed = TRUE), info = rt)
    expect_false(grepl("psa-rm-failure", html, fixed = TRUE), info = rt)
    # No raw brick/amber/ochre value inline either.
    expect_false(grepl("b84a3a", html, ignore.case = TRUE), info = rt)
    expect_false(grepl("oklch\\(0\\.66", html), info = rt)
  }
})

test_that("the relationship glyph matches the relationship kind", {
  split_row <- .correspondence_row("split")
  skip_if(is.null(split_row), "no split relationship in the artifact")
  expect_true(grepl(GLYPH_SPLIT, .render(correspondence_detail_ui(split_row)), fixed = TRUE))

  merged_row <- .correspondence_row("merged")
  skip_if(is.null(merged_row), "no merged relationship in the artifact")
  expect_true(grepl(GLYPH_MERGE, .render(correspondence_detail_ui(merged_row)), fixed = TRUE))
})

test_that("the statistical-safety text itself is still verbatim", {
  row <- .correspondence_row("split")
  skip_if(is.null(row), "no split relationship in the artifact")

  # Restyling the notice must not have touched its wording, which is fixed
  # in R/correspondence/schema.R.
  html <- .render(correspondence_detail_ui(row))
  expect_true(nzchar(CORRESPONDENCE_STATISTICAL_WARNING))
  expect_true(grepl(
    gsub("\\s+", " ", CORRESPONDENCE_STATISTICAL_WARNING),
    gsub("\\s+", " ", html),
    fixed = TRUE
  ))
})

test_that("a no-match row states its reason rather than showing an error", {
  for (rt in c("discontinued", "new")) {
    row <- .correspondence_row(rt)
    skip_if(is.null(row), paste("no", rt, "row in the artifact"))
    html <- .render(correspondence_detail_ui(row))

    expect_false(grepl(GLYPH_TRIANGLE_ALERT, html, fixed = TRUE), info = rt)
    expect_false(grepl("status-error", html, fixed = TRUE), info = rt)
    # An explicit sentence, never a blank cell.
    expect_true(grepl("no prior counterpart|no related category", html), info = rt)
  }
})


# ---------------------------------------------------------------------
# Status is never colour alone (handoff §12.1, UI_CONTRACT §10)
# ---------------------------------------------------------------------

test_that("edition status badges always carry their word", {
  current <- .render(status_badge("current"))
  archived <- .render(status_badge("archived"))

  expect_true(grepl("Current", current, ignore.case = TRUE))
  expect_true(grepl("Archived", archived, ignore.case = TRUE))
  expect_true(grepl("psa-tag-current", current, fixed = TRUE))
  expect_true(grepl("psa-tag-archived", archived, fixed = TRUE))
})


# ---------------------------------------------------------------------
# Icons (handoff §21)
# ---------------------------------------------------------------------

test_that("every icon is inline local SVG, never a CDN or webfont", {
  panels <- list(
    search_ui(), dual_search_ui(), correspondence_ui()
  )
  for (p in panels) {
    html <- .render(p)
    # No Phosphor remnants and no remote icon source.
    expect_false(grepl("class=\"ph ", html, fixed = TRUE))
    expect_false(grepl("unpkg.com", html, fixed = TRUE))
    expect_false(grepl("cdn.jsdelivr", html, fixed = TRUE))
    expect_false(grepl("lucide.min.js", html, fixed = TRUE))
  }
})

test_that("decorative icons are hidden and never focusable", {
  html <- .render(search_ui())
  icons <- regmatches(html, gregexpr("<svg[^>]*>", html))[[1]]

  expect_gt(length(icons), 0L)
  for (i in icons) {
    expect_match(i, 'aria-hidden="true"', fixed = TRUE)
    expect_match(i, 'focusable="false"', fixed = TRUE)
  }
})

test_that("lucide_icon rejects an unknown glyph rather than rendering blank", {
  # A missing glyph is a build mistake, not a runtime state -- failing
  # loudly is what stops a silently empty icon shipping.
  expect_error(lucide_icon("no-such-glyph"), "Unknown Lucide glyph")
  expect_silent(lucide_icon("search"))
})

# ---------------------------------------------------------------------
# Reserved "Ask RM" slots stay inert (handoff §17)
# ---------------------------------------------------------------------

test_that("the reserved Ask RM slots are now real, activated controls", {
  # The previous pass parked an inert `aria-hidden` <span> where the
  # contextual assistant actions were going to go. The imported design
  # (surface 1l) activates them: each is a real control that opens the
  # global assistant panel with that record attached. This test replaces
  # the one that asserted the placeholder stayed inert -- the placeholder
  # is what was supposed to be temporary.
  panels <- list(search = .render(search_ui()),
                 correspondence = .render(correspondence_ui()))

  for (nm in names(panels)) {
    # No inert placeholder is left behind anywhere.
    expect_false(grepl("psa-askrm-reserved", panels[[nm]], fixed = TRUE), info = nm)
  }

  # The page-level launcher on Search is a real button with a real
  # accessible name, and it discloses rather than navigates.
  expect_match(panels$search, 'data-psa-rm-open', fixed = TRUE)
  expect_match(panels$search, "Ask RM about a code", fixed = TRUE)

  # The two record-level launchers are Shiny inputs, because the server has
  # to build the verified context before the panel opens.
  entry_action <- .render(rm_context_button_ui("search_ask_rm_entry",
                                               "Ask RM about this entry"))
  expect_match(entry_action, "^<button", info = "entry action is a button")
  expect_match(entry_action, "search_ask_rm_entry", fixed = TRUE)
  # The CONTROL is exposed to assistive technology. Only the decorative
  # glyph inside it is hidden, so the check is against the opening tag
  # rather than the whole subtree.
  open_tag <- regmatches(entry_action, regexpr("^<button[^>]*>", entry_action))
  expect_false(grepl('aria-hidden="true"', open_tag, fixed = TRUE))

  corr_action <- .render(correspondence_ask_rm_button())
  expect_match(corr_action, "correspondence_ask_rm", fixed = TRUE)
  expect_match(corr_action, "Ask RM to explain this relationship", fixed = TRUE)
})

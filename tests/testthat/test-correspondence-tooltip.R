# Tests for the Compare Editions column terminology help (UI-POST-01).
#
# Presentation-only: the panel is rendered as a tag object and inspected as
# HTML, so nothing here launches Shiny and nothing here touches the frozen
# correspondence service or data layer.

.corr_help_html <- function() {
  as.character(htmltools::renderTags(correspondence_ui())$html)
}

.corr_help_text <- function() {
  # Strip tags so prose assertions are not satisfied by attribute values.
  html <- .corr_help_html()
  txt <- gsub("<[^>]*>", " ", html)
  txt <- gsub("&mdash;|&#8212;", "-", txt)
  gsub("[[:space:]]+", " ", txt)
}

test_that("all three column terms have terminology help", {
  html <- .corr_help_html()
  for (id in c("corr-help-relationship", "corr-help-provenance", "corr-help-confidence")) {
    expect_match(html, id, fixed = TRUE)
  }
  # Exactly three disclosures in the legend.
  expect_equal(
    length(gregexpr("psa-term-help-trigger", html, fixed = TRUE)[[1]]),
    3L
  )
})

test_that("every required Relationship clause is present in the visible text", {
  txt <- .corr_help_text()

  expect_match(txt, "how a classification changed between editions", ignore.case = TRUE)
  # split
  expect_match(txt, "Split", fixed = TRUE)
  expect_match(txt, "one old category became multiple new categories", ignore.case = TRUE)
  # merged
  expect_match(txt, "Merged", fixed = TRUE)
  expect_match(txt, "multiple old categories became one", ignore.case = TRUE)
  # reclassified
  expect_match(txt, "Reclassified", fixed = TRUE)
  expect_match(txt, "the activity moved, or was recoded, to another category", ignore.case = TRUE)
  # continued / unchanged
  expect_match(txt, "Continued / unchanged", fixed = TRUE)
  expect_match(txt, "the concept remains substantially the same", ignore.case = TRUE)
})

test_that("Relationship, Provenance and Confidence are kept conceptually distinct", {
  txt <- .corr_help_text()
  # Provenance = source of the evidence.
  expect_match(txt, "Where the evidence for this correspondence came from", ignore.case = TRUE)
  # Confidence = strength/certainty, explicitly not a probability.
  expect_match(txt, "How strong or certain this particular mapping is", ignore.case = TRUE)
  expect_match(txt, "not a probability", ignore.case = TRUE)
  # And the two are explicitly separated from each other.
  expect_match(txt, "separate from where the evidence came from", ignore.case = TRUE)
})

test_that("derived and suggested evidence is never described as official", {
  txt <- .corr_help_text()
  expect_match(txt, "not a PSA ruling", ignore.case = TRUE)
  expect_match(txt, "not as an official mapping", ignore.case = TRUE)
  # "Official" is described only as the PSA-published case.
  expect_match(txt, "stated in a PSA-published correspondence document", ignore.case = TRUE)
})

test_that("each trigger is a natively focusable summary with an accessible name", {
  html <- .corr_help_html()

  # <summary>, not a <div>/<i>/<span> pretending to be a control, and not a
  # :hover-only tooltip. Native <summary> is in the tab order, activates on
  # Enter/Space, and activates on tap.
  triggers <- regmatches(
    html,
    gregexpr("<summary[^>]*>", html, perl = TRUE)
  )[[1]]
  expect_equal(length(triggers), 3L)

  for (t in triggers) {
    expect_match(t, "psa-term-help-trigger", fixed = TRUE)
    # Non-empty accessible name.
    nm <- regmatches(t, regexpr('aria-label="[^"]+"', t))
    expect_length(nm, 1L)
    expect_true(nchar(sub('aria-label="([^"]+)"', "\\1", nm)) > 0L)
  }

  for (term in c("Relationship", "Provenance", "Confidence")) {
    expect_match(
      html,
      paste0('aria-label="What does ', term, ' mean?"'),
      fixed = TRUE
    )
  }

  # No hand-written aria-expanded ON THE DISCLOSURES: a native
  # <details>/<summary> publishes its own state, and a static attribute
  # would immediately go stale.
  #
  # Scoped to the <details> elements rather than the whole fragment,
  # because UI-05 wraps these three disclosures in one collapsed "How to
  # read this table" panel whose trigger IS a Bootstrap collapse button --
  # and on a button `aria-expanded` is the correct ARIA, kept in sync by
  # Bootstrap rather than hand-written and stale. Asserting over the whole
  # fragment would forbid the correct attribute along with the wrong one.
  details <- regmatches(html, gregexpr("<details.*?</details>", html))[[1L]]
  expect_gt(length(details), 0L)
  for (d in details) {
    expect_false(grepl("aria-expanded", d, fixed = TRUE))
  }
})

test_that("the UI-05 help panel trigger carries correct collapse semantics", {
  html <- .corr_help_html()
  # One compact control, not three page-expanding blocks.
  expect_match(html, 'class="psa-howto-toggle"', fixed = TRUE)
  expect_match(html, 'data-bs-toggle="collapse"', fixed = TRUE)
  # Starts collapsed, so the review workflow is not pushed down the page.
  expect_match(html, 'aria-expanded="false"', fixed = TRUE)
})

test_that("help content is programmatically associated with its trigger", {
  html <- .corr_help_html()
  for (id in c("corr-help-relationship", "corr-help-provenance", "corr-help-confidence")) {
    body_id <- paste0(id, "-body")
    expect_match(html, paste0('aria-controls="', body_id, '"'), fixed = TRUE)
    expect_match(html, paste0('aria-describedby="', body_id, '"'), fixed = TRUE)
    expect_match(html, paste0('id="', body_id, '"'), fixed = TRUE)
  }
  # Native disclosure semantics: each trigger really is inside a <details>.
  expect_equal(
    length(gregexpr("<details", html, fixed = TRUE)[[1]]),
    3L
  )
})

test_that("decorative icons in the help are hidden from assistive technology", {
  # Asserted against the BEHAVIOUR, not the icon vendor: the help carries
  # one decorative glyph per term and none of them may reach the
  # accessibility tree. (The icon set moved from a Phosphor webfont <i> to
  # inline Lucide SVG in the Subtle Gradient pass; the requirement that
  # every decorative glyph is aria-hidden is unchanged, so the test now
  # matches any icon element rather than one vendor's class name.)
  html <- .corr_help_html()

  icons <- regmatches(html, gregexpr("<svg[^>]*>|<i [^>]*>", html))[[1]]

  # One glyph per term, at minimum. The rendered region also carries the
  # reserved "Ask RM" sparkle, which is decorative in exactly the same way,
  # so the count is a floor rather than an equality -- what actually
  # matters is that EVERY icon here is hidden, not how many there are.
  expect_gte(length(icons), 3L)
  for (i in icons) expect_match(i, 'aria-hidden="true"', fixed = TRUE)

  # And nothing decorative slipped in with a label or a tab stop.
  for (i in icons) {
    expect_false(grepl("aria-label", i, fixed = TRUE))
    expect_false(grepl("tabindex", i, fixed = TRUE))
  }

  # The three terms themselves are still each present and focusable.
  triggers <- regmatches(html, gregexpr("<summary[^>]*>", html))[[1]]
  expect_equal(length(triggers), 3L)
})

test_that("the DT output is still present and not wrapped", {
  panel <- correspondence_ui()
  html <- as.character(htmltools::renderTags(panel)$html)
  expect_match(html, "correspondence_results", fixed = TRUE)
  # The other stable IDs are untouched too.
  for (id in c("correspondence_direction", "correspondence_query", "correspondence_detail")) {
    expect_match(html, id, fixed = TRUE)
  }
  # The legend sits BEFORE the table and does not contain it.
  legend_html <- as.character(htmltools::renderTags(correspondence_column_legend())$html)
  expect_false(grepl("correspondence_results", legend_html, fixed = TRUE))
  expect_lt(
    regexpr("psa-col-legend", html, fixed = TRUE),
    regexpr("correspondence_results", html, fixed = TRUE)
  )
})

test_that("the help vocabulary is derived from the schema constants, not re-typed", {
  expect_true(all(
    names(.CORRESPONDENCE_RELATION_GLOSS) %in% CORRESPONDENCE_RELATION_TYPES
  ))
  expect_true(all(
    names(.CORRESPONDENCE_PROVENANCE_GLOSS) %in% CORRESPONDENCE_PROVENANCE_VALUES
  ))
  expect_true(all(
    names(.CORRESPONDENCE_CONFIDENCE_GLOSS) %in% CORRESPONDENCE_CONFIDENCE_VALUES
  ))

  # A retired vocabulary value is dropped from the help rather than described.
  rows <- as.character(htmltools::renderTags(
    .correspondence_gloss_rows(.CORRESPONDENCE_RELATION_GLOSS, c("split", "merged"))
  )$html)
  expect_match(rows, "Split", fixed = TRUE)
  expect_false(grepl("Reclassified", rows, fixed = TRUE))
})

test_that("no correspondence data values are hard-coded in the help text", {
  txt <- gsub("<[^>]*>", " ", as.character(
    htmltools::renderTags(correspondence_column_legend())$html
  ))

  # No PSIC/PSOC-shaped codes, and no row/record counts, may appear: those
  # live in the artifact and would drift the moment the data is rebuilt.
  expect_false(grepl("\\b[A-Z]?[0-9]{3,5}\\b", txt))
  expect_false(grepl("\\b[0-9]+ (rows|records|mappings|codes)\\b", txt, ignore.case = TRUE))
  # No classification titles or edition labels are restated here either.
  expect_false(grepl("Revision 5", txt, fixed = TRUE))
})

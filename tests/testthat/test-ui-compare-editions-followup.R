# Compare Editions simplification and mobile follow-up
# (UI_COMPARE_EDITIONS_AND_MOBILE_FOLLOWUP_ADDENDUM.md).
#
# WHAT IS ASSERTED, AND WHY IT IS SHAPED THIS WAY
#
# The addendum is a PRESENTATION change over data that must not move, so the
# tests are written to fail in both directions:
#
#   * they fail if the simplified surface starts leaking engineering detail
#     again (the stored `evidence` string is a debugging trace and the
#     addendum forbids all of it on the user-facing surface);
#   * they fail if the simplification quietly took real data with it — the
#     provenance field, the confidence vocabulary and the statistical-use
#     safeguard all have to survive.
#
# Nothing here asserts a pixel or a hex value: the layout is checked through
# the class hooks and the CSS contract that owns them, not by measurement.

.frender <- function(tag) as.character(htmltools::renderTags(tag)$html)

.frepo <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)

.fread <- function(...) {
  path <- file.path(.frepo, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

.fhas <- function(haystack, needle) grepl(needle, haystack, fixed = TRUE)

# One relationship WITH recorded UN corroboration and one WITHOUT, taken
# from the shipped artifact rather than hand-built, so the corroboration
# assertions are anchored to real evidence.
.corr_rows <- local({
  cache <- NULL
  function() {
    if (!is.null(cache)) return(cache)
    d <- search_psic_correspondence(
      query = "", from_version = "2019", to_version = "2026", limit = 800
    )
    un <- d[grepl("UN ISIC", d$evidence, fixed = TRUE), , drop = FALSE]
    no <- d[!grepl("UN ISIC", d$evidence, fixed = TRUE), , drop = FALSE]
    cache <<- list(
      un = if (nrow(un)) un[1, , drop = FALSE] else NULL,
      no = if (nrow(no)) no[1, , drop = FALSE] else NULL
    )
    cache
  }
})


# --- Direction control layout (addendum section 3) ------------------------

test_that("the Direction control is laid out by class, not by inline width", {
  # ROOT CAUSE, encoded. The control used to sit in a bare
  # `<div style="min-width: 260px;">` with no flex declaration, so it
  # defaulted to `flex: 0 1 auto` and never grew into the row. Measured at
  # 1440px: 263px of control in a 1382px row.
  html <- .frender(correspondence_ui())

  expect_true(.fhas(html, "psa-corr-filters"))
  expect_true(.fhas(html, "psa-corr-filter--direction"))
  expect_true(.fhas(html, "psa-corr-filter--query"))

  # The old inline sizing must not come back.
  expect_false(.fhas(html, "min-width: 260px"))
})

test_that("the Direction column is given room rather than a compact floor", {
  css <- .fread("www", "ui-filters.css")

  # A grid with a real lower AND upper bound on the Direction column. The
  # lower bound is what stops it collapsing; asserting only that it exists
  # would let a future edit reinstate a 260px cap.
  expect_true(.fhas(css, ".psa-corr-filters"))
  expect_true(.fhas(css, "grid-template-columns: minmax(300px, 460px)"))

  # min-width: 0 on the columns is what keeps a long option from pushing the
  # document wider than the viewport.
  expect_true(.fhas(css, ".psa-corr-filter { min-width: 0; }"))
})

test_that("the Direction value is not structurally truncated", {
  css <- .fread("www", "ui-filters.css")

  # Desktop: the selected value shows in full instead of ellipsising.
  expect_true(.fhas(css, ".psa-corr-filter--direction .selectize-input > .item"))
  expect_true(.fhas(css, "text-overflow: clip"))

  # Phone: it may wrap to a second line, which is readable; what it may not
  # do is get cut off.
  expect_true(.fhas(css, ".psa-corr-filter--direction .selectize-input > .item { white-space: normal; }"))
})

test_that("the mobile control stack collapses to one full-width column", {
  css <- .fread("www", "ui-filters.css")
  block <- sub(".*Compare Editions . mobile.*?\\{", "", css)
  expect_true(.fhas(css, "@media (max-width: 767.98px)"))
  expect_true(.fhas(css, "grid-template-columns: minmax(0, 1fr);"))
  # Actions stack and keep a usable touch target rather than crowding a row.
  expect_true(.fhas(css, "min-height: 44px"))
})


# --- Provenance is gone from the primary surface (section 4) --------------

test_that("the results table no longer carries a Provenance column", {
  app <- .fread("app.R")
  expect_true(.fhas(
    app,
    '"from_code", "from_label", "to_code", "to_label", "relation_type", "confidence"'
  ))
  expect_false(.fhas(app, '"relation_type", "provenance", "confidence"'))
})

test_that("Provenance is absent from the rendered relationship detail", {
  rows <- .corr_rows()
  for (nm in names(rows)) {
    row <- rows[[nm]]
    skip_if(is.null(row), paste("no", nm, "row in the artifact"))

    for (html in list(
      .frender(correspondence_detail_ui(row)),
      .frender(correspondence_inspector_ui(row))
    )) {
      # No standalone Provenance field, and no bare provenance value badge.
      expect_false(.fhas(html, "Provenance"), info = nm)
      expect_false(.fhas(html, ">derived<"), info = nm)
      expect_false(.fhas(html, ">suggested<"), info = nm)
    }
  }
})

test_that("provenance survives in the data model and the glossary", {
  # Section 13: this pass simplifies presentation only.
  d <- search_psic_correspondence(
    query = "", from_version = "2019", to_version = "2026", limit = 5
  )
  expect_true("provenance" %in% names(d))
  expect_true(all(nzchar(as.character(d$provenance))))

  # Still carried into the bounded Ask-RM context.
  ctx <- correspondence_ask_rm_context(d[1, , drop = FALSE])
  expect_true("provenance" %in% names(ctx))

  # Still explained where a reader can look it up.
  expect_true(.fhas(.frender(correspondence_column_legend()), "Provenance"))

  # The renderer is retained for a future diagnostic view.
  expect_true(is.function(provenance_badge))
})


# --- Relationship / confidence / notes (sections 5, 7, 8) -----------------

test_that("the relationship detail keeps Relationship and Confidence", {
  rows <- .corr_rows()
  row <- rows$un %||% rows$no
  skip_if(is.null(row), "no correspondence rows in the artifact")

  html <- .frender(correspondence_detail_ui(row))
  expect_true(.fhas(html, "psa-corr-facts"))

  # Both facts are LABELLED, and the value is not a bare colour-coded chip:
  # the label row carries the field name and the badge carries the word.
  expect_true(.fhas(html, ">Relationship<"))
  expect_true(.fhas(html, ">Confidence<"))
  expect_true(grepl(">(High|Medium|Low)<", html))

  # ...and the badge does not repeat its own field name underneath that
  # label, which is exactly the duplicated metadata this pass removes.
  expect_false(.fhas(html, "Confidence: "))
})

test_that("confidence is ordinal words, never a probability", {
  # Stored vocabulary is unchanged; only the DISPLAY of `moderate` moves to
  # the addendum's preferred "Medium".
  expect_setequal(CORRESPONDENCE_CONFIDENCE_VALUES, c("high", "moderate", "low"))

  expect_true(.fhas(.frender(confidence_badge("high")), "Confidence: High"))
  expect_true(.fhas(.frender(confidence_badge("moderate")), "Confidence: Medium"))
  expect_true(.fhas(.frender(confidence_badge("low")), "Confidence: Low"))

  # No percentage anywhere in the badge.
  for (v in c("high", "moderate", "low")) {
    expect_false(grepl("%|probab", .frender(confidence_badge(v))))
  }
})

test_that("the derived note is present once, not repeated per row", {
  rows <- .corr_rows()
  row <- rows$un %||% rows$no
  skip_if(is.null(row), "no correspondence rows in the artifact")

  html <- .frender(correspondence_detail_ui(row))
  expect_true(.fhas(html, "Derived correspondence"))
  # Section 8: one concise explanatory location is enough.
  expect_identical(
    length(gregexpr("Derived correspondence", html, fixed = TRUE)[[1]]), 1L
  )
})


# --- UN ISIC corroboration is claimed only when recorded (sections 5, 6) --

test_that("UN ISIC corroboration appears only when the evidence records it", {
  rows <- .corr_rows()
  skip_if(is.null(rows$un) || is.null(rows$no),
          "artifact lacks both a corroborated and an uncorroborated row")

  with_un <- .frender(correspondence_detail_ui(rows$un))
  expect_true(.fhas(with_un, "Corroboration"))
  expect_true(.fhas(with_un, "UN ISIC Rev.4 to Rev.5"))

  without <- .frender(correspondence_detail_ui(rows$no))
  expect_false(.fhas(without, "Corroboration"))
  expect_false(.fhas(without, "UN ISIC"))
})

test_that("the evidence summary never invents corroboration", {
  # A pure-function guard on the honesty rule: no UN marker in, no UN claim
  # out — including when the evidence is missing entirely.
  fake <- data.frame(evidence = "Code A is unchanged across editions.",
                     stringsAsFactors = FALSE)
  s <- correspondence_evidence_summary(fake)
  expect_false(s$has_un)
  expect_null(s$corroboration)
  expect_true(nzchar(s$derived))

  none <- data.frame(evidence = NA_character_, stringsAsFactors = FALSE)
  expect_false(correspondence_evidence_summary(none)$has_un)
  expect_null(correspondence_evidence_summary(none)$corroboration)

  real <- data.frame(
    evidence = "Corroborated by the official UN ISIC Rev.4->Rev.5 class correspondence.",
    stringsAsFactors = FALSE
  )
  expect_true(correspondence_evidence_summary(real)$has_un)
  expect_true(nzchar(correspondence_evidence_summary(real)$corroboration))
})


# --- Internal diagnostics stay out of the UI (section 6) ------------------

test_that("engineering evidence never reaches the rendered inspector", {
  rows <- .corr_rows()
  # The stored evidence string is a debugging trace; these are the exact
  # phrases the addendum names.
  jargon <- c(
    "section graph", "normalized-token", "class_prefix_continuity",
    "Search method", "similarity", "Label evidence supporting",
    "Evidence:", "corresponds to 2026 section"
  )

  for (nm in names(rows)) {
    row <- rows[[nm]]
    skip_if(is.null(row), paste("no", nm, "row in the artifact"))

    # Guard the guard: the underlying string really does contain the jargon,
    # so a passing test means it was filtered rather than absent.
    expect_true(
      any(vapply(jargon, function(j) .fhas(as.character(row$evidence[[1]]), j),
                 logical(1))),
      info = paste(nm, "- fixture no longer carries diagnostic evidence")
    )

    for (html in list(
      .frender(correspondence_detail_ui(row)),
      .frender(correspondence_inspector_ui(row))
    )) {
      for (j in jargon) {
        expect_false(.fhas(html, j), info = paste(nm, j))
      }
    }
  }
})


# --- Statistical-use safeguard (section 12) -------------------------------

test_that("the statistical-use safeguard survives on every relationship", {
  d <- search_psic_correspondence(
    query = "", from_version = "2019", to_version = "2026", limit = 400
  )
  types <- unique(as.character(d$relation_type))
  expect_gt(length(types), 1L)

  for (rt in types) {
    row <- d[d$relation_type == rt, , drop = FALSE][1, , drop = FALSE]
    html <- .frender(correspondence_detail_ui(row))

    # Widened from split/merged/complex only: the reader is here because
    # they are about to act on a mapping, whatever its type.
    expect_true(.fhas(html, "psa-stat-warning"), info = rt)
    expect_true(.fhas(html, "Statistical-use note"), info = rt)
    expect_true(
      .fhas(gsub("[[:space:]]+", " ", html),
            gsub("[[:space:]]+", " ", CORRESPONDENCE_STATISTICAL_WARNING)),
      info = rt
    )

    # A relationship is not an error, and the safeguard is not an alarm.
    expect_false(.fhas(html, "status-error"), info = rt)
  }
})


# --- Control placement and accessibility (section 9) ----------------------

test_that("simplifying the inspector kept its actions and dialog hooks", {
  rows <- .corr_rows()
  row <- rows$un %||% rows$no
  skip_if(is.null(row), "no correspondence rows in the artifact")

  # The Ask RM action keeps its stable input id.
  expect_true(.fhas(.frender(correspondence_inspector_ui(row)),
                    "correspondence_ask_rm"))

  # The inspector region keeps its labelled-region semantics and close id.
  shell <- .frender(correspondence_inspector_shell("body"))
  expect_true(.fhas(shell, 'id="correspondence-inspector"'))
  expect_true(.fhas(shell, 'role="region"'))
  expect_true(.fhas(shell, "correspondence_inspector_close"))

  # Filter input ids are untouched by the layout change.
  page <- .frender(correspondence_ui())
  expect_true(.fhas(page, "correspondence_direction"))
  expect_true(.fhas(page, "correspondence_query"))
  expect_true(.fhas(page, "correspondence_results"))
  expect_true(.fhas(page, "correspondence_detail"))
})

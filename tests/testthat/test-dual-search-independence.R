# PSOC + PSIC = TWO INDEPENDENT SEARCHES (spec section 4).
#
# These tests run entirely against the pure UI-construction and pure
# state-derivation functions in R/ui/ui_dual_search.R -- no Shiny app is
# launched. Independence is asserted structurally (neither panel's markup
# can reference the other side's ids) and functionally (the per-side
# helpers are side-effect free, so exercising one side cannot alter the
# other side's value).

EM_DASH <- "\u2014"

panel_html <- function(system_id) {
  as.character(htmltools::renderTags(dual_search_panel_ui(system_id))$html)
}

screen_html <- function() {
  as.character(htmltools::renderTags(dual_search_ui())$html)
}

# Every id="..." that appears on an <input> or <select> element.
form_control_ids <- function(html) {
  tags <- unlist(stringr::str_extract_all(html, "<(input|select)\\b[^>]*>"))
  ids <- stringr::str_match(tags, "\\bid=\"([^\"]+)\"")[, 2]
  ids[!is.na(ids)]
}

# --- Structure: two panels, each with its own inputs -------------------

test_that("both panels are produced, each with its own distinct query input", {
  html <- screen_html()

  expect_true(grepl('id="dual_search_psoc_query"', html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psic_query"', html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psoc_results"', html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psic_results"', html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psoc_detail"', html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psic_detail"', html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psoc_version"', html, fixed = TRUE))
  expect_true(grepl('id="dual_search_psic_version"', html, fixed = TRUE))
})

test_that("the shared dual_search_query input no longer exists anywhere", {
  # A single query driving two different classification systems is exactly
  # the coupling this screen must not have.
  expect_false(grepl('"dual_search_query"', screen_html(), fixed = TRUE))
  expect_false(grepl('"dual_search_query"', panel_html("psoc"), fixed = TRUE))
  expect_false(grepl('"dual_search_query"', panel_html("psic"), fixed = TRUE))
  expect_false(any(form_control_ids(screen_html()) == "dual_search_query"))
})

test_that("the two query input ids differ", {
  expect_false(identical(
    dual_search_id("psoc", "query"),
    dual_search_id("psic", "query")
  ))
  ids <- form_control_ids(screen_html())
  expect_equal(anyDuplicated(ids), 0L)
})

# --- Mandatory copy ----------------------------------------------------

test_that("the PSOC panel carries the exact required heading, helper and placeholder", {
  html <- panel_html("psoc")
  expect_true(grepl(paste0("PSOC ", EM_DASH, " Occupation"), html, fixed = TRUE))
  expect_true(grepl("Describes what a person does.", html, fixed = TRUE))
  expect_true(grepl(
    'placeholder="Search an occupation or PSOC code"', html, fixed = TRUE
  ))
})

test_that("the PSIC panel carries the exact required heading, helper and placeholder", {
  html <- panel_html("psic")
  expect_true(grepl(paste0("PSIC ", EM_DASH, " Industry"), html, fixed = TRUE))
  expect_true(grepl(
    "Describes the economic activity of the establishment or business.",
    html, fixed = TRUE
  ))
  expect_true(grepl(
    'placeholder="Search an industry or PSIC code"', html, fixed = TRUE
  ))
})

# --- Structural independence: no cross-references ----------------------

test_that("the PSOC panel's markup never references any PSIC id", {
  html <- panel_html("psoc")
  expect_false(grepl("dual_search_psic_", html, fixed = TRUE))
  # Nothing PSIC-flavoured at all on the PSOC side: a PSOC panel that
  # mentions PSIC is a panel that could imply one from the other.
  expect_false(grepl("psic", html, ignore.case = TRUE))
})

test_that("the PSIC panel's markup never references any PSOC id", {
  html <- panel_html("psic")
  expect_false(grepl("dual_search_psoc_", html, fixed = TRUE))
  expect_false(grepl("psoc", html, ignore.case = TRUE))
})

test_that("each panel is its own landmark with its own accessible name", {
  for (sys in c("psoc", "psic")) {
    html <- panel_html(sys)
    heading_id <- paste0("dual-search-", sys, "-heading")
    expect_true(grepl("<section", html, fixed = TRUE))
    expect_true(grepl(
      paste0('aria-labelledby="', heading_id, '"'), html, fixed = TRUE
    ))
    expect_true(grepl(paste0('id="', heading_id, '"'), html, fixed = TRUE))
  }
})

test_that("dual_search_panel_ui() rejects an unknown side rather than emitting a blank panel", {
  expect_error(dual_search_panel_ui("psgc"), "unknown system_id")
})

# --- Accessibility: real labels, never placeholder-only ----------------

test_that("every input and select has an associated <label for=...> element", {
  html <- screen_html()
  ids <- form_control_ids(html)
  expect_gte(length(ids), 4L)
  for (id in ids) {
    expect_true(
      grepl(paste0('for="', id, '"'), html, fixed = TRUE),
      info = paste("no <label for=> found for input id", id)
    )
  }
})

test_that("label elements carry non-empty text, not just a for= attribute", {
  html <- screen_html()
  labels <- unlist(stringr::str_extract_all(html, "<label[^>]*>.*?</label>"))
  expect_gte(length(labels), 4L)
  text <- trimws(gsub("<[^>]*>", "", labels))
  expect_true(all(nzchar(text)))
})

# --- Structural walk over the tag tree ---------------------------------

test_that("the screen contains exactly two panel sections, one per system", {
  collect <- function(x, acc = list()) {
    if (inherits(x, "shiny.tag")) {
      acc <- c(acc, list(x))
      for (child in x$children) acc <- collect(child, acc)
    } else if (is.list(x)) {
      for (child in x) acc <- collect(child, acc)
    }
    acc
  }
  nodes <- collect(dual_search_ui())
  sections <- Filter(function(n) identical(n$name, "section"), nodes)
  classes <- vapply(sections, function(n) {
    cls <- n$attribs$class
    if (is.null(cls)) "" else as.character(cls)[[1]]
  }, character(1))
  panels <- grep("psa-dual-panel", classes, value = TRUE)
  expect_length(panels, 2L)
  expect_true(any(grepl("psa-dual-panel--psoc", panels, fixed = TRUE)))
  expect_true(any(grepl("psa-dual-panel--psic", panels, fixed = TRUE)))
})

# --- Functional independence of the pure state helpers -----------------

test_that("the per-side helpers hold no shared mutable state", {
  # No superassignment anywhere in these functions: they cannot write into
  # an enclosing environment, so one side's call can never reach the other.
  for (fn in list(dual_search_side_result,
                  dual_search_side_selection,
                  dual_search_side_count_text,
                  dual_search_id,
                  dual_search_panel_ui,
                  dual_search_ui)) {
    src <- paste(deparse(body(fn)), collapse = "\n")
    expect_false(grepl("<<-", src, fixed = TRUE))
    expect_false(grepl("assign(", src, fixed = TRUE))
  }
  # Each per-side helper is told which side it is working on; none of them
  # can discover the other side's state, because none of them take one.
  expect_true("system" %in% names(formals(dual_search_side_result)))
  expect_equal(
    names(formals(dual_search_side_selection)),
    c("result", "rows_selected")
  )
})

test_that("selection derivation is pure and per-side", {
  d <- data.frame(
    code  = c("2611", "2612"),
    label = c("Lawyer", "Judge"),
    stringsAsFactors = FALSE
  )
  res <- list(
    data = d, total_matches = 2L, returned_count = 2L,
    limit = 100, is_truncated = FALSE
  )
  snapshot <- res

  expect_equal(nrow(dual_search_side_selection(res, NULL)), 0L)
  expect_equal(nrow(dual_search_side_selection(res, integer(0))), 0L)
  expect_equal(dual_search_side_selection(res, 2L)$code, "2612")
  # A stale index (one round-trip after the query changed) must yield an
  # empty selection, never an error and never a wrong row.
  expect_equal(nrow(dual_search_side_selection(res, 99L)), 0L)

  # The helper mutated nothing it was handed.
  expect_identical(res, snapshot)
})

test_that("the count line delegates to the canonical format_result_count()", {
  skip_if_not(exists("format_result_count"))
  res <- list(
    data = NULL, total_matches = 7L, returned_count = 7L,
    limit = 100, is_truncated = FALSE
  )
  expect_equal(dual_search_side_count_text(res, "nurse"), "7 results")
  expect_equal(
    dual_search_side_count_text(res, ""),
    "7 results \u00b7 browsing"
  )
  expect_equal(
    dual_search_side_count_text(res, NULL),
    "7 results \u00b7 browsing"
  )
})

test_that("running the PSOC side cannot change any PSIC value", {
  skip_if_not(exists("search_classification_result"))

  psoc_version <- classification_versions("psoc")[[1]]
  psic_version <- classification_versions("psic")[[1]]

  before <- dual_search_side_result("psic", psic_version, "farming", limit = 10)

  # Interleave several PSOC searches, including clearing the PSOC query.
  invisible(dual_search_side_result("psoc", psoc_version, "teacher", limit = 10))
  invisible(dual_search_side_result("psoc", psoc_version, "", limit = 10))
  invisible(dual_search_side_result("psoc", psoc_version, "nurse", limit = 10))

  after <- dual_search_side_result("psic", psic_version, "farming", limit = 10)
  expect_identical(before, after)

  # ...and the reverse direction.
  psoc_before <- dual_search_side_result("psoc", psoc_version, "teacher", limit = 10)
  invisible(dual_search_side_result("psic", psic_version, "", limit = 10))
  invisible(dual_search_side_result("psic", psic_version, "mining", limit = 10))
  psoc_after <- dual_search_side_result("psoc", psoc_version, "teacher", limit = 10)
  expect_identical(psoc_before, psoc_after)
})

test_that("each side's result contains only its own system's records", {
  skip_if_not(exists("search_classification_result"))

  psoc <- dual_search_side_result("psoc", classification_versions("psoc")[[1]],
                                   "teacher", limit = 10)
  psic <- dual_search_side_result("psic", classification_versions("psic")[[1]],
                                   "farming", limit = 10)
  if (nrow(psoc$data) > 0L) expect_true(all(psoc$data$system == "psoc"))
  if (nrow(psic$data) > 0L) expect_true(all(psic$data$system == "psic"))
  expect_true(all(
    c("data", "total_matches", "returned_count", "limit", "is_truncated") %in%
      names(psoc)
  ))
})

# ---------------------------------------------------------------------
# Asymmetric success/failure through the hybrid engine
# ---------------------------------------------------------------------
#
# These name the scenarios explicitly rather than leaving them implicit in
# the interleaving tests above: a query that only the hybrid tiers can
# answer on one side must not affect a genuinely-zero-match query on the
# other side, in either direction.

test_that("PSOC succeeds via a hybrid tier while PSIC has no match, without leakage", {
  skip_if_not(exists("search_classification_result"))

  psoc_v <- classification_versions("psoc")[[1]]
  psic_v <- classification_versions("psic")[[1]]

  # "heavy truck driver" only resolves through tiers 7/8 -- there is no
  # exact/prefix/substring hit in PSOC 2022 for this exact phrase.
  psoc <- dual_search_side_result("psoc", psoc_v, "heavy truck driver", limit = 10L)
  psic <- dual_search_side_result("psic", psic_v, "qqqxzzvwk", limit = 10L)

  expect_gt(psoc$total_matches, 0L)
  expect_true("8332" %in% psoc$data$code)
  expect_equal(psic$total_matches, 0L)
  expect_equal(nrow(psic$data), 0L)
})

test_that("PSIC succeeds via a hybrid tier while PSOC has no match, without leakage", {
  skip_if_not(exists("search_classification_result"))

  psoc_v <- classification_versions("psoc")[[1]]
  psic_v <- classification_versions("psic")[[1]]

  psic <- dual_search_side_result("psic", psic_v, "bakery products manufacture", limit = 10L)
  psoc <- dual_search_side_result("psoc", psoc_v, "qqqxzzvwk", limit = 10L)

  expect_gt(psic$total_matches, 0L)
  expect_equal(psoc$total_matches, 0L)
  expect_equal(nrow(psoc$data), 0L)
})

test_that("both sides can succeed via hybrid tiers simultaneously with disjoint codes", {
  skip_if_not(exists("search_classification_result"))

  psoc_v <- classification_versions("psoc")[[1]]
  psic_v <- classification_versions("psic")[[1]]

  psoc <- dual_search_side_result("psoc", psoc_v, "heavy truck driver", limit = 10L)
  psic <- dual_search_side_result("psic", psic_v, "bakery", limit = 10L)

  expect_gt(psoc$total_matches, 0L)
  expect_gt(psic$total_matches, 0L)
  expect_length(intersect(psoc$data$code, psic$data$code), 0L)
  expect_true(all(psoc$data$system == "psoc"))
  expect_true(all(psic$data$system == "psic"))
})

test_that("selecting a row on one side never populates the other side's selection", {
  skip_if_not(exists("search_classification_result"))
  skip_if_not(exists("dual_search_side_selection"))

  psoc_v <- classification_versions("psoc")[[1]]
  psic_v <- classification_versions("psic")[[1]]

  psoc <- dual_search_side_result("psoc", psoc_v, "heavy truck driver", limit = 10L)
  psic <- dual_search_side_result("psic", psic_v, "bakery", limit = 10L)

  psoc_selected <- dual_search_side_selection(psoc, 1L)
  psic_unselected <- dual_search_side_selection(psic, NULL)

  expect_equal(nrow(psoc_selected), 1L)
  expect_equal(nrow(psic_unselected), 0L)
  expect_true(all(psoc_selected$system == "psoc"))
})

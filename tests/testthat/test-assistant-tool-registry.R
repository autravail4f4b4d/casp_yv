# W1-E: the RM tool schema must expose exactly the systems the application
# actually carries.
#
# This guards a defect that was live in the shipped build: the tool enum was
# a hand-written seven-element list from when the app had seven systems.
# pscc, ptscs and pscrcs were added later and the list was never updated, so
# `ellmer`'s generated JSON schema FORBADE the model from naming them. RM
# could not answer "What is PSCC code 0101.29.00-001?" or "What are the
# components of PTSCS?" at all -- the failure was in the tool contract, not
# in the model, the prompt or the data, which makes it the kind of bug that
# looks like a model quality problem and wastes the investigation elsewhere.
#
# The enum is now derived from classification_registry(). These tests pin
# that derivation rather than the current list of ten, so registering an
# eleventh system cannot silently leave RM unable to see it.

test_that("the registry is the single source of classification system ids", {
  ids <- classification_registry()$id

  expect_gt(length(ids), 0L)
  expect_false(any(duplicated(ids)))
  expect_true(all(nzchar(ids)))
  # The three systems the stale enum was missing must be present.
  for (id in c("pscc", "ptscs", "pscrcs")) {
    expect_true(id %in% ids, info = id)
  }
})

test_that("assistant_tools.R contains no hand-written system list", {
  # A literal list is exactly how the enum went stale, so its absence is
  # worth asserting directly on the source.
  path <- testthat::test_path("..", "..", "R", "assistant", "assistant_tools.R")
  skip_if_not(file.exists(path))
  src <- paste(readLines(path, warn = FALSE), collapse = "\n")

  # No c("psgc", "psic", ...) style literal enumerations of systems.
  expect_false(grepl('c\\(\\s*"psgc"\\s*,\\s*"psic"', src))
  expect_true(grepl("classification_registry\\(\\)\\$id", src))
})

test_that("every RM tool builds and the system enum covers every registry id", {
  skip_if_not_installed("ellmer")

  tools <- rm_assistant_tools()
  expect_gte(length(tools), 5L)

  ids <- classification_registry()$id

  # ellmer builds an S7 TypeObject whose fields live under @properties;
  # each enum field carries its allowed values in @values.
  found_system_enum <- FALSE
  for (tool in tools) {
    props <- tryCatch(tool@arguments@properties, error = function(e) NULL)
    if (is.null(props) || is.null(props$system)) next
    values <- tryCatch(props$system@values, error = function(e) NULL)
    if (is.null(values)) next
    found_system_enum <- TRUE
    expect_setequal(values, ids)
  }
  expect_true(found_system_enum)
})

test_that("PSCC and PSCCS are both reachable and remain distinct", {
  # These two acronyms are one character apart and mean entirely different
  # things. Both must be independently queryable, and neither may resolve to
  # the other.
  ids <- classification_registry()$id
  expect_true("pscc" %in% ids)
  expect_true("psccs" %in% ids)

  reg <- classification_registry()
  pscc_name <- reg$display_name[reg$id == "pscc"][[1]]
  psccs_name <- reg$display_name[reg$id == "psccs"][[1]]

  expect_match(pscc_name, "Commodity", ignore.case = TRUE)
  expect_match(psccs_name, "Crime", ignore.case = TRUE)
  expect_false(identical(pscc_name, psccs_name))
})

test_that("the search tool reaches the systems the stale enum excluded", {
  # The end-to-end consequence: a search through the RM tool layer must
  # actually return results for the three previously unreachable systems.
  for (sys in c("pscc", "ptscs", "pscrcs")) {
    res <- assistant_search_classification(system = sys, query = "", limit = 3L)
    expect_false(isTRUE(res$error), info = sys)
    expect_true(!is.null(res$results), info = sys)
  }
})

test_that("common pairings remain supporting evidence, never authority", {
  # The RM fallback may consult pairings, but a code taken from them must
  # still be verified against the canonical repository before presentation.
  res <- assistant_search_common_pairings(occupation = "Truck Driver", limit = 3L)
  skip_if(isFALSE(res$available), "pairings artifact unavailable")

  expect_match(res$evidence_caveat, "Supporting evidence only", fixed = TRUE)
  expect_match(res$evidence_caveat, "assistant_get_classification_entry", fixed = TRUE)

  # And the code it offers really does verify.
  hit <- Filter(function(r) identical(r$occupation, "Truck Driver"), res$results)
  expect_gte(length(hit), 1L)
  entry <- get_classification_entry("psoc", "2022", hit[[1L]]$confirmed_psoc)
  expect_equal(nrow(entry), 1L)
})

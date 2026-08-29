# RM orchestration hardening: assistant_get_classification_system_info().
#
# These pin the deterministic system-metadata contract so a system-level
# question (PSCC vs PSCCS, PTSCS/PSCrCS components) can be grounded without
# calling assistant_search_classification() -- the wrong tool for a
# question that is not about a specific code or entry.

test_that("a known system returns found = TRUE with the expected field set", {
  res <- assistant_get_classification_system_info("pscc")
  expect_true(res$found)
  expect_equal(sort(names(res)), sort(c("found", ASSISTANT_SYSTEM_INFO_FIELDS)))
})

test_that("PSCC and PSCCS are independently reachable and never conflated", {
  pscc <- assistant_get_classification_system_info("pscc")
  psccs <- assistant_get_classification_system_info("psccs")

  expect_true(pscc$found)
  expect_true(psccs$found)
  expect_match(pscc$display_name, "Commodity", ignore.case = TRUE)
  expect_match(psccs$display_name, "Crime", ignore.case = TRUE)
  expect_false(identical(pscc$display_name, psccs$display_name))
  expect_false(identical(pscc$id, psccs$id))
})

test_that("PTSCS reports its official name and its real verified components", {
  res <- assistant_get_classification_system_info("ptscs")
  expect_true(res$found)
  expect_match(res$display_name, "Tourism", ignore.case = TRUE)
  expect_true(res$is_composite)
  expect_true(length(res$available_components) > 0L)
  expect_true(all(nzchar(res$available_components)))
})

test_that("PSCrCS reports its official name and its real verified components", {
  res <- assistant_get_classification_system_info("pscrcs")
  expect_true(res$found)
  expect_match(res$display_name, "Creative", ignore.case = TRUE)
  expect_true(res$is_composite)
  expect_true(length(res$available_components) > 0L)
})

test_that("a non-composite system reports zero components rather than omitting the field", {
  res <- assistant_get_classification_system_info("psoc")
  expect_true(res$found)
  expect_false(res$is_composite)
  expect_equal(length(res$available_components), 0L)
})

test_that("an unknown/nonexistent system returns found = FALSE with no fabricated metadata", {
  res <- assistant_get_classification_system_info("not_a_real_system")
  expect_false(res$found)
  expect_equal(res$requested_system, "not_a_real_system")
  expect_match(res$message, "not.*classification system", ignore.case = TRUE)
  expect_true(length(res$known_systems) > 0L)
})

test_that("every field returned is sourced from classification_registry(), never hand-restated", {
  reg <- classification_registry()
  for (id in reg$id) {
    res <- assistant_get_classification_system_info(id)
    row <- reg[reg$id == id, , drop = FALSE]
    expect_equal(res$display_name, row$display_name[[1L]], info = id)
    expect_equal(res$current_version, row$current_version[[1L]], info = id)
    expect_equal(res$source_url, row$source_url[[1L]], info = id)
  }
})

test_that("a blank or missing system id is a structured error, not a crash", {
  res <- assistant_get_classification_system_info(NULL)
  expect_true(isTRUE(res$error) || isFALSE(res$found))
})

test_that("system info never returns entry-shaped fields (code, label) for a system query", {
  res <- assistant_get_classification_system_info("psoc")
  expect_false("code" %in% names(res))
  expect_false("label" %in% names(res))
})

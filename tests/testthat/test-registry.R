test_that("classification_registry registers all 7 expected systems", {
  reg <- classification_registry()
  expect_equal(nrow(reg), 7)
  expect_setequal(reg$id, c("psgc", "psic", "psoc", "psced", "pcoicop", "pcpc", "psccs"))
})

test_that("every system has non-empty display_name/short_name/source/source_url", {
  reg <- classification_registry()
  expect_true(all(nzchar(reg$display_name)))
  expect_true(all(nzchar(reg$short_name)))
  expect_true(all(nzchar(reg$source)))
  expect_true(all(nzchar(reg$source_url)))
  expect_true(all(!is.na(reg$display_name)))
  expect_true(all(!is.na(reg$short_name)))
})

test_that("current_version is always one of available_versions", {
  reg <- classification_registry()
  for (i in seq_len(nrow(reg))) {
    expect_true(
      reg$current_version[[i]] %in% reg$available_versions[[i]],
      info = sprintf("system '%s' current_version '%s' not in available_versions",
                      reg$id[[i]], reg$current_version[[i]])
    )
  }
})

test_that("available_levels is non-empty for every system", {
  reg <- classification_registry()
  for (i in seq_len(nrow(reg))) {
    expect_true(
      length(reg$available_levels[[i]]) > 0,
      info = sprintf("system '%s' has empty available_levels", reg$id[[i]])
    )
    expect_true(all(nzchar(reg$available_levels[[i]])))
  }
})

test_that("registry marks PSA as the source for every system", {
  reg <- classification_registry()
  expect_true(all(reg$source == "Philippine Statistics Authority"))
})

test_that("adapter column names an adapter for every system", {
  reg <- classification_registry()
  expect_true(all(nzchar(reg$adapter)))
})

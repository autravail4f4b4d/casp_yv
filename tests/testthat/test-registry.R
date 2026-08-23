test_that("classification_registry registers all 10 expected systems", {
  reg <- classification_registry()
  expect_equal(nrow(reg), 10)
  expect_setequal(reg$id, c(
    "psgc", "psic", "psoc", "psced", "pcoicop", "pcpc", "psccs",
    # Added in the pre-staging ingestion milestone.
    "pscc", "ptscs", "pscrcs"
  ))
})

test_that("PSCC and PSCCS are distinct systems with their correct canonical names", {
  # Regression guard for META-01. These two acronyms differ by one letter
  # and name completely unrelated classifications; the registry previously
  # carried the commodity name on the crime classification. Asserted
  # independently, and asserted as the CANONICAL registry value rather than
  # anything a UI layer might alias over the top of it.
  reg <- classification_registry()

  expect_equal(
    reg$display_name[reg$id == "pscc"],
    "Philippine Standard Commodity Classification"
  )
  expect_equal(
    reg$display_name[reg$id == "psccs"],
    "Philippine Standard Classification of Crime for Statistical Purposes"
  )

  # Neither may carry the other's wording.
  expect_false(grepl("Crime", reg$display_name[reg$id == "pscc"], fixed = TRUE))
  expect_false(grepl("Commodity", reg$display_name[reg$id == "psccs"], fixed = TRUE))

  expect_equal(reg$current_version[reg$id == "pscc"], "2022")
  expect_equal(reg$current_version[reg$id == "psccs"], "2018")
})

test_that("composite systems expose components; ordinary systems do not", {
  reg <- classification_registry()

  expect_true(reg$is_composite[reg$id == "ptscs"])
  expect_true(reg$is_composite[reg$id == "pscrcs"])
  expect_setequal(
    reg$available_components[reg$id == "ptscs"][[1]],
    c("tourism_industry", "tourism_product")
  )
  expect_setequal(
    reg$available_components[reg$id == "pscrcs"][[1]],
    c("creative_industry", "creative_good_service", "creative_occupation")
  )

  for (id in c("psgc", "psic", "psoc", "psced", "pcoicop", "pcpc", "psccs", "pscc")) {
    expect_false(reg$is_composite[reg$id == id], info = id)
    expect_length(reg$available_components[reg$id == id][[1]], 0)
  }
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

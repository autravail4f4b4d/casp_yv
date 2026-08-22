test_that("new_classification_tibble builds a well-formed row", {
  d <- new_classification_tibble(
    system = "psic", version = "2026", level = "sub-class",
    code = "62010", label = "Computer programming activities",
    description = NA_character_, parent_code = "6201",
    status = "current", source = "Philippine Statistics Authority",
    source_url = "https://psa.gov.ph/classification/psic"
  )
  expect_equal(names(d), CLASSIFICATION_SCHEMA_COLUMNS)
  expect_true(is.character(d$code))
  expect_equal(d$code, "62010")
})

test_that("new_classification_tibble recycles scalar columns across codes", {
  d <- new_classification_tibble(
    system = "psic", version = "2026", level = "section",
    code = c("A", "B"), label = c("Agriculture", "Mining"),
    parent_code = NA_character_, status = "current",
    source = "Philippine Statistics Authority",
    source_url = "https://psa.gov.ph/classification/psic"
  )
  expect_equal(nrow(d), 2)
  expect_equal(d$version, c("2026", "2026"))
})

test_that("validate_classification_tibble rejects missing columns", {
  bad <- tibble::tibble(system = "psic")
  expect_error(validate_classification_tibble(bad), "missing required column")
})

test_that("validate_classification_tibble rejects non-character code (leading zeros)", {
  bad <- tibble::tibble(
    system = "psic", version = "2019", level = "section", code = 1,
    label = "x", description = NA_character_, parent_code = NA_character_,
    status = "current", source = "PSA", source_url = "https://psa.gov.ph"
  )
  expect_error(validate_classification_tibble(bad), "must be character")
})

test_that("validate_classification_tibble rejects unknown status values", {
  bad <- tibble::tibble(
    system = "psic", version = "2019", level = "section", code = "A",
    label = "x", description = NA_character_, parent_code = NA_character_,
    status = "draft", source = "PSA", source_url = "https://psa.gov.ph"
  )
  expect_error(validate_classification_tibble(bad), "current.*archived")
})

# Tests for R/correspondence/schema.R -- the correspondence relationship
# schema, independent of any build/service logic.

test_that("new_correspondence_tibble builds a valid row and columns are the right types", {
  row <- new_correspondence_tibble(
    source_system = "psic", source_version = "2019", source_code = "01161",
    source_level = "sub-class", source_label = "Growing of abaca",
    target_system = "psic", target_version = "2026", target_code = "01161",
    target_level = "sub-class", target_label = "Growing of abaca",
    relation_type = "unchanged", provenance = "derived", confidence = "high",
    confidence_score = 85, method = "exact_code_match", evidence = "exact match",
    review_status = "auto"
  )
  expect_equal(names(row), CORRESPONDENCE_SCHEMA_COLUMNS)
  expect_true(is.character(row$source_code))
  expect_true(is.character(row$target_code))
  expect_true(is.double(row$confidence_score))
  expect_equal(nrow(row), 1L)
})

test_that("validate_correspondence_tibble rejects missing columns", {
  df <- tibble::tibble(source_system = "psic")
  expect_error(validate_correspondence_tibble(df), "missing required column")
})

test_that("validate_correspondence_tibble rejects non-character code columns", {
  row <- new_correspondence_tibble(
    source_system = "psic", source_version = "2019", source_code = "01161",
    source_level = "sub-class", source_label = "x",
    target_system = "psic", target_version = "2026", target_code = "01161",
    target_level = "sub-class", target_label = "x",
    relation_type = "unchanged", provenance = "derived", confidence = "high"
  )
  row$source_code <- as.numeric(row$source_code)
  expect_error(validate_correspondence_tibble(row), "must be character")
})

test_that("validate_correspondence_tibble rejects invalid relation_type/provenance/confidence/review_status", {
  base <- list(
    source_system = "psic", source_version = "2019", source_code = "01161",
    source_level = "sub-class", source_label = "x",
    target_system = "psic", target_version = "2026", target_code = "01161",
    target_level = "sub-class", target_label = "x"
  )
  expect_error(
    do.call(new_correspondence_tibble, c(base, list(relation_type = "bogus", provenance = "derived", confidence = "high"))),
    "relation_type must be one of"
  )
  expect_error(
    do.call(new_correspondence_tibble, c(base, list(relation_type = "unchanged", provenance = "bogus", confidence = "high"))),
    "provenance must be one of"
  )
  expect_error(
    do.call(new_correspondence_tibble, c(base, list(relation_type = "unchanged", provenance = "derived", confidence = "bogus"))),
    "confidence must be one of"
  )
  expect_error(
    do.call(new_correspondence_tibble, c(base, list(relation_type = "unchanged", provenance = "derived", confidence = "high", review_status = "bogus"))),
    "review_status must be one of"
  )
})

test_that("a 'discontinued' row may have NA target_code/target_label", {
  row <- new_correspondence_tibble(
    source_system = "psic", source_version = "2019", source_code = "01531",
    source_level = "sub-class", source_label = "x",
    target_system = "psic", target_version = "2026",
    relation_type = "discontinued", provenance = "derived", confidence = "moderate"
  )
  expect_equal(nrow(row), 1L)
  expect_true(is.na(row$target_code))
  expect_true(is.na(row$target_label))
})

test_that("a 'new' row may have NA source_code/source_label", {
  row <- new_correspondence_tibble(
    source_system = "psic", source_version = "2019",
    target_system = "psic", target_version = "2026", target_code = "01153",
    target_level = "sub-class", target_label = "Growing of Burley tobacco",
    relation_type = "new", provenance = "derived", confidence = "moderate"
  )
  expect_equal(nrow(row), 1L)
  expect_true(is.na(row$source_code))
  expect_true(is.na(row$source_label))
})

test_that("a non-discontinued/non-new row must not have NA target/source code", {
  expect_error(
    new_correspondence_tibble(
      source_system = "psic", source_version = "2019", source_code = "01161",
      source_level = "sub-class", source_label = "x",
      target_system = "psic", target_version = "2026",
      relation_type = "unchanged", provenance = "derived", confidence = "high"
    ),
    "non-NA target_code"
  )
  expect_error(
    new_correspondence_tibble(
      source_system = "psic", source_version = "2019",
      target_system = "psic", target_version = "2026", target_code = "01161",
      target_level = "sub-class", target_label = "x",
      relation_type = "unchanged", provenance = "derived", confidence = "high"
    ),
    "non-NA source_code"
  )
})

test_that("core enums always/only contain the documented values", {
  expect_setequal(
    CORRESPONDENCE_RELATION_TYPES,
    c("unchanged", "renamed", "split", "merged", "reclassified",
      "new", "discontinued", "complex", "possible", "unknown")
  )
  expect_setequal(CORRESPONDENCE_PROVENANCE_VALUES, c("official", "derived", "suggested"))
  expect_setequal(CORRESPONDENCE_CONFIDENCE_VALUES, c("high", "moderate", "low"))
})

test_that("the schema has no numeric value/count/allocation column", {
  # Guards against ever accidentally adding a statistical-redistribution
  # column: correspondence is a lookup/reference relationship, never a
  # basis for reallocating statistical values (spec section 19).
  suspect <- grep("value|count|allocation|amount|total", CORRESPONDENCE_SCHEMA_COLUMNS,
                   ignore.case = TRUE, value = TRUE)
  expect_length(suspect, 0)
})

test_that("CORRESPONDENCE_STATISTICAL_WARNING carries the required wording", {
  expect_match(CORRESPONDENCE_STATISTICAL_WARNING, "not provide a basis for automatically reallocating")
})

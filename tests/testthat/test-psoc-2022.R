test_that("PSOC 2022 artifacts exist and load offline", {
  expect_true(file.exists("../../data/psoc_2022.rds"))
  expect_true(file.exists("../../data/psoc_2022_metadata.rds"))
  d <- psoc2022_get()
  expect_s3_class(d, "tbl_df")
  meta <- psoc2022_metadata()
  expect_type(meta, "list")
})

test_that("PSOC 2022 canonical schema is valid", {
  d <- psoc2022_get()
  expect_equal(names(d), CLASSIFICATION_SCHEMA_COLUMNS)
  expect_true(is.character(d$code))
  expect_false(is.numeric(d$code))
  expect_true(all(d$system == "psoc"))
  expect_true(all(d$version == "2022"))
  expect_true(all(d$status == "current"))
  expect_true(all(d$source == "Philippine Statistics Authority"))
})

test_that("PSOC 2022 exposes exactly the four canonical hierarchy levels", {
  expect_setequal(psoc2022_levels(), c("major_group", "sub_major_group", "minor_group", "unit_group"))
  d <- psoc2022_get()
  expect_setequal(unique(d$level), c("major_group", "sub_major_group", "minor_group", "unit_group"))
})

test_that("PSOC 2022 structural counts match PSA's stated hierarchy where verified, with unit-group discrepancy documented", {
  d <- psoc2022_get()
  expect_equal(sum(d$level == "major_group"), 10)
  expect_equal(sum(d$level == "sub_major_group"), 43)
  expect_equal(sum(d$level == "minor_group"), 130)
  # PSA's technical notes state 456 unit groups; the official workbook
  # itself (verified: no duplicate codes, no malformed codes, every parent
  # chain resolves) contains 466. This mirrors the PSIC Revision 5
  # groups discrepancy (261 parsed vs. 260 stated) -- a real, documented
  # PSA-side count discrepancy, not a parsing defect. Assert against the
  # metadata's own recorded count so this test stays honest rather than
  # hardcoding a number that could silently drift from what the build
  # script actually produced.
  meta <- psoc2022_metadata()
  expect_equal(sum(d$level == "unit_group"), meta$parsed_counts$unit_group)
  expect_equal(meta$psa_stated_counts$unit_group, 456)
})

test_that("PSOC 2022 referential integrity: every parent_code resolves to a real parent row", {
  d <- psoc2022_get()
  check <- function(child_level, parent_level) {
    child_parents <- unique(d$parent_code[d$level == child_level])
    parent_codes <- d$code[d$level == parent_level]
    expect_true(all(child_parents %in% parent_codes), info = paste(child_level, "->", parent_level))
  }
  check("sub_major_group", "major_group")
  check("minor_group", "sub_major_group")
  check("unit_group", "minor_group")
  expect_true(all(is.na(d$parent_code[d$level == "major_group"])))
})

test_that("PSA's documented 2022 update example resolves correctly (2121 Mathematicians / 2123 Actuaries split)", {
  d <- psoc2022_get(level = "unit_group")
  math <- d[d$code == "2121", ]
  act <- d[d$code == "2123", ]
  expect_equal(nrow(math), 1)
  expect_equal(nrow(act), 1)
  expect_match(toupper(math$label), "MATHEMATIC")
  expect_match(toupper(act$label), "ACTUAR")
  # Both belong to the same minor group (211, per real 2022 PSOC data).
  expect_equal(math$parent_code, act$parent_code)
})

test_that("PSOC 2022 level filter returns only the requested level", {
  d <- psoc2022_get(level = "major_group")
  expect_true(all(d$level == "major_group"))
  expect_equal(nrow(d), 10)
})

test_that("psoc2022_get rejects an unsupported level with a clear error", {
  expect_error(psoc2022_get(level = "nonexistent"), "Unsupported PSOC level")
})

test_that("missing PSOC 2022 artifact fails loudly rather than masquerading as 2022", {
  expect_error(
    psoc2022_get(data_path = "no/such/file/psoc_2022.rds"),
    "PSOC 2022 runtime artifact is missing"
  )
  expect_error(
    psoc2022_metadata(metadata_path = "no/such/file/psoc_2022_metadata.rds"),
    "PSOC 2022 runtime artifact is missing"
  )
})

test_that("PSOC 2022 metadata records official source and manual-retrieval provenance honestly", {
  meta <- psoc2022_metadata()
  expect_equal(meta$system, "psoc")
  expect_equal(meta$version, "2022")
  expect_equal(meta$status, "current")
  expect_equal(meta$source, "Philippine Statistics Authority")
  expect_true(nzchar(meta$source_url))
  expect_true(nzchar(meta$source_artifact_url))
  expect_true(nzchar(meta$sha256))
  expect_match(meta$retrieval_method, "manual")
  expect_match(meta$retrieval_method, "Cloudflare")
})

test_that("registry: PSOC 2022 is current, PSOC 2012 remains archived and searchable", {
  reg <- classification_registry()
  psoc_row <- reg[reg$id == "psoc", ]
  expect_equal(nrow(psoc_row), 1)
  expect_equal(psoc_row$current_version, "2022")
  expect_true("2012" %in% psoc_row$available_versions[[1]])
  expect_true("2022" %in% psoc_row$available_versions[[1]])

  expect_equal(classification_versions("psoc"), psoc_row$available_versions[[1]])

  current_data <- get_classification("psoc", "2022")
  expect_true(all(current_data$status == "current"))

  archived_data <- get_classification("psoc", "2012")
  expect_true(all(archived_data$status == "archived"))
  expect_true(nrow(archived_data) > 0)
})

test_that("get_classification never silently substitutes 2012 when asked for 2022", {
  d <- get_classification("psoc", "2022")
  expect_true(all(d$version == "2022"))
  expect_false(any(d$version == "2012"))
})

test_that("search_classification works against real PSOC 2022 data", {
  res <- search_classification("psoc", "2022", "2121")
  expect_true(nrow(res) >= 1)
  expect_equal(res$code[[1]], "2121")

  res2 <- search_classification("psoc", "2022", "mathematicians")
  expect_true(any(toupper(res2$label) == "MATHEMATICIANS"))
})

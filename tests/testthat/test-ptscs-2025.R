# PTSCS 2025 (Version 2.1) adapter + artifact contract tests.
#
# PTSCS is a composite/thematic system: it borrows codes from two other
# classifications rather than minting its own, so these tests focus on
# (a) the frozen canonical schema still being honoured exactly, and
# (b) the component provenance that gives PTSCS records their meaning
#     surviving the build -- especially the prohibition on silently
#     re-coding tourism industries from 2019 PSIC onto PSIC Revision 5.

test_that("PTSCS 2025 artifacts exist and load offline", {
  expect_true(file.exists("../../data/ptscs_2025_v2_1.rds"))
  expect_true(file.exists("../../data/ptscs_2025_v2_1_metadata.rds"))
  d <- ptscs2025_get()
  expect_s3_class(d, "tbl_df")
  meta <- ptscs2025_metadata()
  expect_type(meta, "list")
})

test_that("PTSCS 2025 honours the frozen canonical schema in its first 10 columns", {
  d <- ptscs2025_get()
  expect_equal(names(d)[seq_along(CLASSIFICATION_SCHEMA_COLUMNS)], CLASSIFICATION_SCHEMA_COLUMNS)
  expect_silent(validate_classification_tibble(d))
  expect_true(all(vapply(d[CLASSIFICATION_SCHEMA_COLUMNS], is.character, logical(1))))
  expect_true(all(d$system == "ptscs"))
  expect_true(all(d$source == "Philippine Statistics Authority"))
  expect_true(all(nzchar(d$source_url)))
})

test_that("PTSCS 2025 carries its composite-provenance extras after the canonical 10", {
  d <- ptscs2025_get()
  extras <- names(d)[-seq_along(CLASSIFICATION_SCHEMA_COLUMNS)]
  expect_equal(extras, PTSCS_2025_EXTRA_COLUMNS)
  for (col in PTSCS_2025_EXTRA_COLUMNS) {
    expect_true(col %in% names(d), info = col)
    expect_true(is.character(d[[col]]), info = col)
  }
})

test_that("PTSCS 2025 version is 2025-v2.1 and every record is current", {
  expect_equal(ptscs2025_versions(), "2025-v2.1")
  d <- ptscs2025_get()
  expect_true(all(d$version == "2025-v2.1"))
  expect_true(all(d$status == "current"))
  expect_equal(ptscs2025_metadata()$status, "current")
})

test_that("PTSCS 2025 has exactly two components, matching the workbook's two data sheets", {
  expect_setequal(ptscs2025_components(), c("tourism_industry", "tourism_product"))
  d <- ptscs2025_get()
  expect_setequal(unique(d$component), c("tourism_industry", "tourism_product"))
  expect_setequal(ptscs2025_metadata()$components, c("tourism_industry", "tourism_product"))
})

test_that("PTSCS 2025 exposes no fake hierarchy: level == component, parent_code always NA", {
  # PTSCS publishes no code hierarchy of its own. The canonical `level`
  # column therefore carries the component id, and no parent/child
  # relationship is manufactured.
  expect_setequal(ptscs2025_levels(), ptscs2025_components())
  d <- ptscs2025_get()
  expect_setequal(unique(d$level), ptscs2025_components())
  expect_equal(d$level, d$component)
  expect_true(all(is.na(d$parent_code)))
})

test_that("PTSCS 2025 parsed counts match what the build actually produced, and official 176/214 are recorded", {
  meta <- ptscs2025_metadata()
  d <- ptscs2025_get()
  # Assert against the build's own recorded counts so this test can never
  # silently drift from the artifact, then assert PSA's official targets
  # separately.
  expect_equal(sum(d$component == "tourism_industry"), meta$parsed_counts$tourism_industry)
  expect_equal(sum(d$component == "tourism_product"), meta$parsed_counts$tourism_product)
  expect_equal(nrow(d), meta$parsed_counts$tourism_industry + meta$parsed_counts$tourism_product)

  expect_equal(as.integer(meta$official_counts$tourism_industry), 176L)
  expect_equal(as.integer(meta$official_counts$tourism_product), 214L)
})

test_that("PTSCS 2025 tourism industries carry 2019 PSIC provenance", {
  ind <- ptscs2025_get(component = "tourism_industry")
  expect_true(nrow(ind) > 0)
  expect_true(all(ind$source_system == "psic"))
  expect_true(all(ind$source_version == "2019"))
  expect_match(unique(ind$source_label), "2019", fixed = TRUE)
  expect_equal(ind$source_code, ind$code)

  meta <- ptscs2025_metadata()
  expect_equal(meta$underlying_classifications$tourism_industry$source_system, "psic")
  expect_equal(meta$underlying_classifications$tourism_industry$source_version, "2019")
})

test_that("no PTSCS tourism industry record is silently re-coded onto PSIC Revision 5 (2026)", {
  # Explicit guard on the spec's prohibition. The application carries PSIC
  # 2026, but PSA defines PTSCS Version 2.1 against the 2019 PSIC, so no
  # industry record may claim a 2026 source_version.
  ind <- ptscs2025_get(component = "tourism_industry")
  expect_false(any(ind$source_version == "2026"))
  expect_equal(unique(ind$source_version), "2019")

  d <- ptscs2025_get()
  expect_false(any(d$source_version == "2026"))

  meta <- ptscs2025_metadata()
  expect_false(identical(meta$underlying_classifications$tourism_industry$source_version, "2026"))
})

test_that("PTSCS 2025 tourism products carry CPC Version 2.1 provenance", {
  prod <- ptscs2025_get(component = "tourism_product")
  expect_true(nrow(prod) > 0)
  expect_true(all(prod$source_system == "cpc"))
  expect_true(all(prod$source_version == "2.1"))
  expect_match(unique(prod$source_label), "Central Product Classification")
  expect_equal(prod$source_code, prod$code)

  meta <- ptscs2025_metadata()
  expect_equal(meta$underlying_classifications$tourism_product$source_system, "cpc")
  expect_equal(meta$underlying_classifications$tourism_product$source_version, "2.1")
})

test_that("PTSCS 2025 codes stay strings: never numeric-coerced, width preserved", {
  d <- ptscs2025_get()
  expect_true(is.character(d$code))
  expect_false(is.numeric(d$code))
  expect_true(is.character(d$source_code))
  # Every PTSCS code in this workbook is a 5-character code from its
  # underlying classification; a numeric round-trip would drop any leading
  # zero and change these widths.
  expect_true(all(nchar(d$code) == 5L))
  expect_true(all(grepl("^[0-9]{5}$", d$code)))
  expect_equal(nchar(as.character(d$code)), nchar(d$code))
})

test_that("PTSCS 2025 major_category is preserved and non-empty on every record", {
  d <- ptscs2025_get()
  expect_false(anyNA(d$major_category))
  expect_true(all(nzchar(d$major_category)))
  expect_false(anyNA(d$major_category_group))
  expect_true(all(nzchar(d$major_category_group)))
  # Multiple distinct thematic categories per component (the workbook groups
  # both components under numbered tourism categories).
  ind <- d[d$component == "tourism_industry", ]
  prod <- d[d$component == "tourism_product", ]
  expect_gt(length(unique(ind$major_category)), 1)
  expect_gt(length(unique(prod$major_category)), 1)

  meta <- ptscs2025_metadata()
  expect_true(length(meta$major_categories$tourism_industry) > 0)
  expect_true(length(meta$major_categories$tourism_product) > 0)
})

test_that("PTSCS 2025 component filter returns only the requested component", {
  ind <- ptscs2025_get(component = "tourism_industry")
  expect_true(all(ind$component == "tourism_industry"))
  expect_false(any(ind$component == "tourism_product"))

  prod <- ptscs2025_get(component = "tourism_product")
  expect_true(all(prod$component == "tourism_product"))
  expect_false(any(prod$component == "tourism_industry"))

  expect_equal(nrow(ind) + nrow(prod), nrow(ptscs2025_get()))
})

test_that("PTSCS 2025 level filter mirrors the component filter", {
  by_level <- ptscs2025_get(level = "tourism_product")
  by_component <- ptscs2025_get(component = "tourism_product")
  expect_equal(nrow(by_level), nrow(by_component))
  expect_true(all(by_level$level == "tourism_product"))
})

test_that("PTSCS 2025 rejects unsupported level/component values with clear errors", {
  expect_error(ptscs2025_get(level = "sub-class"), "Unsupported PTSCS level")
  expect_error(ptscs2025_get(component = "tourism_widget"), "Unsupported PTSCS component")
})

test_that("real PTSCS fixtures resolve with their official labels and provenance", {
  # Fixtures taken verbatim from the official workbook -- no invented codes.
  ind <- ptscs2025_get(component = "tourism_industry")
  hotels <- ind[ind$code == "55101", ]
  expect_equal(nrow(hotels), 1)
  expect_equal(hotels$label, "Hotels")
  expect_equal(hotels$source_system, "psic")
  expect_equal(hotels$source_version, "2019")
  expect_match(hotels$major_category, "Accommodation for Visitors")

  prod <- ptscs2025_get(component = "tourism_product")
  accom <- prod[prod$code == "63111", ]
  expect_equal(nrow(accom), 1)
  expect_match(accom$label, "Room or unit accommodation services for visitors")
  expect_equal(accom$source_system, "cpc")
  expect_equal(accom$source_version, "2.1")
  expect_match(accom$major_category, "Accommodation Services for Visitors")
})

test_that("PTSCS 2025 codes are unique within each component", {
  ind <- ptscs2025_get(component = "tourism_industry")
  prod <- ptscs2025_get(component = "tourism_product")
  expect_false(any(duplicated(ind$code)))
  expect_false(any(duplicated(prod$code)))
})

test_that("missing PTSCS artifact fails loudly and names the build script", {
  expect_error(
    ptscs2025_get(data_path = "no/such/file/ptscs_2025_v2_1.rds"),
    "scripts/build_ptscs_2025.R",
    fixed = TRUE
  )
  expect_error(
    ptscs2025_metadata(metadata_path = "no/such/file/ptscs_2025_v2_1_metadata.rds"),
    "scripts/build_ptscs_2025.R",
    fixed = TRUE
  )
  expect_error(
    ptscs2025_get(data_path = "no/such/file/ptscs_2025_v2_1.rds"),
    "runtime artifact is missing"
  )
})

test_that("PTSCS 2025 metadata records official provenance without leaking local paths", {
  meta <- ptscs2025_metadata()
  expect_equal(meta$system, "ptscs")
  expect_equal(meta$version, "2025-v2.1")
  expect_true(nzchar(meta$display_version))
  expect_equal(meta$source, "Philippine Statistics Authority")
  expect_equal(meta$source_url, "https://psa.gov.ph/classification/ptscs")
  expect_true(nzchar(meta$retrieved_at))
  expect_match(meta$sha256, "^[0-9a-f]{64}$")
  expect_equal(meta$build_script, "scripts/build_ptscs_2025.R")

  # source_artifact must be the workbook FILENAME, never an absolute local path.
  expect_equal(meta$source_artifact, "PTSCS-Version-2.1.xlsx")
  expect_false(grepl("[A-Za-z]:[\\\\/]", meta$source_artifact))
  expect_false(grepl("^/", meta$source_artifact))
})

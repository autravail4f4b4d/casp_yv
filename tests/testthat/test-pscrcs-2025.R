# Tests for the Philippine Standard Creative Classification System (PSCrCS)
# 2025 build-time normalization pipeline and runtime adapter.
#
# helper.R sources every file under R/, so new_classification_tibble(),
# CLASSIFICATION_SCHEMA_COLUMNS, and the pscrcs2025_*() adapter functions are
# already available here.
#
# All fixtures below are real records taken from the official PSA workbook
# data-raw/PSCrCS_classification.xlsx -- no invented codes or labels.

test_that("data/pscrcs_2025.rds and data/pscrcs_2025_metadata.rds exist and load", {
  expect_true(file.exists(file.path("..", "..", "data", "pscrcs_2025.rds")))
  expect_true(file.exists(file.path("..", "..", "data", "pscrcs_2025_metadata.rds")))

  d <- pscrcs2025_get()
  expect_true(tibble::is_tibble(d))
  expect_true(nrow(d) > 0)

  meta <- pscrcs2025_metadata()
  expect_type(meta, "list")
})

test_that("first ten columns are exactly CLASSIFICATION_SCHEMA_COLUMNS, in order", {
  d <- pscrcs2025_get()
  n <- length(CLASSIFICATION_SCHEMA_COLUMNS)
  expect_equal(names(d)[seq_len(n)], CLASSIFICATION_SCHEMA_COLUMNS)
  # The frozen canonical schema itself must still validate.
  expect_true(validate_classification_tibble(d))
})

test_that("composite provenance columns are appended after the canonical ten", {
  d <- pscrcs2025_get()
  n <- length(CLASSIFICATION_SCHEMA_COLUMNS)
  expect_equal(
    names(d)[-seq_len(n)],
    c("component", "major_category", "source_system", "source_version", "source_code")
  )
  for (col in PSCRCS_2025_EXTRA_COLUMNS) {
    expect_true(col %in% names(d))
    expect_true(is.character(d[[col]]))
  }
})

test_that("system/version/status are pscrcs / 2025 / current on every row", {
  d <- pscrcs2025_get()
  expect_true(all(d$system == "pscrcs"))
  expect_true(all(d$version == "2025"))
  expect_true(all(d$status == "current"))
  expect_equal(pscrcs2025_versions(), "2025")
})

test_that("all three components are preserved", {
  d <- pscrcs2025_get()
  expect_setequal(
    unique(d$component),
    c("creative_industry", "creative_good_service", "creative_occupation")
  )
  expect_equal(
    pscrcs2025_components(),
    c("creative_industry", "creative_good_service", "creative_occupation")
  )
})

test_that("creative industries carry 2019 PSIC provenance", {
  ind <- pscrcs2025_get(component = "creative_industry")
  expect_true(nrow(ind) > 0)
  expect_true(all(ind$source_system == "psic"))
  expect_true(all(ind$source_version == "2019"))
})

test_that("NO creative-industry record claims PSIC 2026 / Revision 5", {
  # Guards the explicit spec prohibition against silently substituting the
  # 2026 PSIC (Revision 5) for the 2019 PSIC that PSCrCS is actually built on.
  ind <- pscrcs2025_get(component = "creative_industry")
  expect_false(any(ind$source_version == "2026"))
  expect_equal(unique(ind$source_version), "2019")

  meta <- pscrcs2025_metadata()
  expect_equal(meta$underlying_classifications$creative_industry$source_system, "psic")
  expect_equal(meta$underlying_classifications$creative_industry$source_version, "2019")
  expect_false(identical(meta$underlying_classifications$creative_industry$source_version, "2026"))
})

test_that("creative goods and services carry CPC 2.1 provenance", {
  gs <- pscrcs2025_get(component = "creative_good_service")
  expect_true(nrow(gs) > 0)
  expect_true(all(gs$source_system == "cpc"))
  expect_true(all(gs$source_version == "2.1"))
})

test_that("creative occupations carry 2022 PSOC provenance", {
  occ <- pscrcs2025_get(component = "creative_occupation")
  expect_true(nrow(occ) > 0)
  expect_true(all(occ$source_system == "psoc"))
  expect_true(all(occ$source_version == "2022"))
})

test_that("codes are character strings preserved verbatim from the workbook", {
  d <- pscrcs2025_get()
  expect_true(is.character(d$code))
  expect_true(is.character(d$source_code))
  # PSCrCS reuses the underlying classification's code verbatim.
  expect_equal(d$source_code, d$code)

  # Fixed code widths are the practical guard against a numeric coercion
  # somewhere in the pipeline (which is what would silently eat a leading
  # zero). PSIC sub-class and CPC sub-class codes are 5 characters; PSOC unit
  # group codes are 4.
  expect_true(all(nchar(pscrcs2025_get(component = "creative_industry")$code) == 5))
  expect_true(all(nchar(pscrcs2025_get(component = "creative_good_service")$code) == 5))
  expect_true(all(nchar(pscrcs2025_get(component = "creative_occupation")$code) == 4))

  # Real fixtures from the workbook, asserted exactly as issued.
  occ <- pscrcs2025_get(component = "creative_occupation")
  expect_true("2166" %in% occ$code)
  expect_equal(occ$label[occ$code == "2166"], "Graphic and multimedia designers")

  ind <- pscrcs2025_get(component = "creative_industry")
  expect_true("13120" %in% ind$code)
  expect_equal(ind$label[ind$code == "13120"], "Weaving of textiles")

  gs <- pscrcs2025_get(component = "creative_good_service")
  expect_true("26510" %in% gs$code)
  expect_equal(gs$label[gs$code == "26510"], "Woven fabrics of silk or of silk waste")
})

test_that("leading-zero handling is recorded honestly in metadata", {
  meta <- pscrcs2025_metadata()
  d <- pscrcs2025_get()
  # This particular workbook contains no leading-zero codes; the build records
  # the observed count rather than any of us assuming one exists.
  expect_equal(meta$leading_zero_code_count, sum(grepl("^0", d$code)))
})

test_that("component filter returns only that component", {
  for (comp in pscrcs2025_components()) {
    sub <- pscrcs2025_get(component = comp)
    expect_true(nrow(sub) > 0)
    expect_true(all(sub$component == comp))
    expect_equal(unique(sub$component), comp)
  }
})

test_that("level filter mirrors the component filter (no manufactured hierarchy)", {
  d <- pscrcs2025_get()
  # No hierarchy exists in the source workbook, so level == component and
  # parent_code is NA everywhere.
  expect_equal(pscrcs2025_levels(), pscrcs2025_components())
  expect_equal(d$level, d$component)
  expect_true(all(is.na(d$parent_code)))

  by_level <- pscrcs2025_get(level = "creative_occupation")
  by_component <- pscrcs2025_get(component = "creative_occupation")
  expect_equal(nrow(by_level), nrow(by_component))
  expect_equal(by_level$code, by_component$code)

  meta <- pscrcs2025_metadata()
  expect_false(meta$major_category_available)
  expect_true(all(is.na(d$major_category)))
})

test_that("unsupported level and component are rejected with clear errors", {
  expect_error(pscrcs2025_get(level = "not-a-real-level"), "Unsupported PSCrCS level")
  expect_error(pscrcs2025_get(component = "not-a-real-component"), "Unsupported PSCrCS component")
})

test_that("parsed counts match the metadata's own record and the official targets", {
  d <- pscrcs2025_get()
  meta <- pscrcs2025_metadata()

  # Assert the data against what the build actually recorded, so these do not
  # silently drift apart if the workbook is re-parsed.
  for (comp in pscrcs2025_components()) {
    expect_equal(
      sum(d$component == comp),
      as.integer(meta$parsed_counts[[comp]]),
      info = comp
    )
  }
  expect_equal(nrow(d), sum(unlist(meta$parsed_counts)))

  # Separately assert the official PSA targets are recorded, and that the
  # parse actually hit them.
  expect_equal(as.integer(meta$official_counts$creative_industry), 317L)
  expect_equal(as.integer(meta$official_counts$creative_good_service), 409L)
  expect_equal(as.integer(meta$official_counts$creative_occupation), 114L)
  expect_true(meta$counts_match)
})

test_that("codes are unique within each component", {
  d <- pscrcs2025_get()
  expect_equal(sum(duplicated(d[, c("component", "code")])), 0)
})

test_that("metadata records correct current/adopted provenance", {
  meta <- pscrcs2025_metadata()
  expect_equal(meta$system, "pscrcs")
  expect_equal(meta$version, "2025")
  expect_equal(meta$status, "current")
  expect_equal(meta$adopted, "2025")
  expect_equal(
    meta$official_name,
    "Philippine Standard Creative Classification System (PSCrCS)"
  )
  expect_equal(meta$source, "Philippine Statistics Authority")
  expect_equal(meta$source_url, "https://psa.gov.ph/classification/pscrcs/")
  expect_true(nzchar(meta$sha256))
  expect_true(nzchar(meta$retrieved_at))

  # source_artifact must be a bare filename, never an absolute local path.
  expect_equal(meta$source_artifact, "PSCrCS_classification.xlsx")
  expect_false(grepl("[/\\\\]", meta$source_artifact))
  expect_false(grepl("^[A-Za-z]:", meta$source_artifact))

  # Evidence captured from the workbook's own Metadata sheet.
  expect_equal(
    meta$workbook_metadata$Title,
    "Philippine Standard Creative Classification System (PSCrCS)"
  )
  expect_equal(meta$workbook_metadata$`Publication date`, "08 September 2025")
})

test_that("missing runtime artifact produces a clear developer-facing error", {
  # Point at a path guaranteed not to exist rather than touching the real
  # committed artifact, exercising the same missing-file code path.
  .pscrcs2025_reset_cache()
  bogus_path <- file.path(tempdir(), "does-not-exist-pscrcs_2025.rds")
  expect_false(file.exists(bogus_path))
  expect_error(
    pscrcs2025_get(data_path = bogus_path),
    "Run scripts/build_pscrcs_2025.R",
    fixed = TRUE
  )

  bogus_meta_path <- file.path(tempdir(), "does-not-exist-pscrcs_2025_metadata.rds")
  expect_error(
    pscrcs2025_metadata(metadata_path = bogus_meta_path),
    "Run scripts/build_pscrcs_2025.R",
    fixed = TRUE
  )
})

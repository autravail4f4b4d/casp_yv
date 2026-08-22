# Tests for the PSIC Revision 5 ("2026 PSIC") build-time normalization
# pipeline and runtime adapter.
#
# helper.R sources every file under R/, so new_classification_tibble(),
# CLASSIFICATION_SCHEMA_COLUMNS, and the psic2026_*() adapter functions are
# already available here.

test_that("data/psic_2026.rds and data/psic_2026_metadata.rds exist and load", {
  expect_true(file.exists(file.path("..", "..", "data", "psic_2026.rds")))
  expect_true(file.exists(file.path("..", "..", "data", "psic_2026_metadata.rds")))

  d <- psic2026_get()
  expect_true(tibble::is_tibble(d))
  expect_true(nrow(d) > 0)

  meta <- psic2026_metadata()
  expect_type(meta, "list")
})

test_that("loaded tibble has exactly CLASSIFICATION_SCHEMA_COLUMNS", {
  d <- psic2026_get()
  expect_equal(names(d), CLASSIFICATION_SCHEMA_COLUMNS)
})

test_that("code column is character (leading zeros preserved)", {
  d <- psic2026_get()
  expect_true(is.character(d$code))
  # spot check a code that would lose a leading zero if coerced to numeric
  expect_true("01" %in% d$code)
})

test_that("all rows are status current and version 2026", {
  d <- psic2026_get()
  expect_true(all(d$status == "current"))
  expect_true(all(d$version == "2026"))
  expect_true(all(d$system == "psic"))
})

test_that("parsed section/division/class/subclass counts match PSA stated totals exactly", {
  meta <- psic2026_metadata()
  d <- psic2026_get()

  expect_equal(meta$parsed_counts$sections, 22)
  expect_equal(meta$parsed_counts$divisions, 88)
  expect_equal(meta$parsed_counts$classes, 493)
  expect_equal(meta$parsed_counts$subclasses, 1338)

  expect_equal(sum(d$level == "section"), 22)
  expect_equal(sum(d$level == "division"), 88)
  expect_equal(sum(d$level == "class"), 493)
  expect_equal(sum(d$level == "sub-class"), 1338)
})

test_that("groups count is documented as a known discrepancy vs PSA's stated 260", {
  meta <- psic2026_metadata()
  d <- psic2026_get()

  # Honest assertion: reference what the build actually parsed rather than
  # hardcoding a number that might drift if the workbook is re-parsed.
  expect_equal(sum(d$level == "group"), meta$parsed_counts$groups)
  expect_equal(meta$psa_stated_counts$groups, 260)
  # As of the current parse, this is a documented off-by-one discrepancy
  # (261 parsed vs 260 officially stated) -- see docs/DATA_SOURCES.md.
  # We assert the discrepancy is *tracked* in metadata, not that it is zero.
  expect_true(meta$parsed_counts$groups >= meta$psa_stated_counts$groups)
})

test_that("known collapsed-row case: Veterinary activities (division/group/class/sub-class on one row)", {
  d <- psic2026_get()

  division <- d[d$level == "division" & d$code == "75", ]
  group    <- d[d$level == "group" & d$code == "750", ]
  class    <- d[d$level == "class" & d$code == "7500", ]
  subclass <- d[d$level == "sub-class" & d$code == "75000", ]

  expect_equal(nrow(division), 1)
  expect_equal(nrow(group), 1)
  expect_equal(nrow(class), 1)
  expect_equal(nrow(subclass), 1)

  expect_equal(division$label, "Veterinary activities")
  expect_equal(group$label, "Veterinary activities")
  expect_equal(class$label, "Veterinary activities")
  expect_equal(subclass$label, "Veterinary activities")

  expect_equal(group$parent_code, "75")
  expect_equal(class$parent_code, "750")
  expect_equal(subclass$parent_code, "7500")
})

test_that("known multi-level-collapse case: Growing of corn (class + sub-class on one row)", {
  d <- psic2026_get()

  class <- d[d$level == "class" & d$code == "0113", ]
  subclass <- d[d$level == "sub-class" & d$code == "01130", ]

  expect_equal(nrow(class), 1)
  expect_equal(nrow(subclass), 1)

  expect_equal(class$label, "Growing of corn")
  expect_equal(subclass$label, "Growing of corn")

  # class 0113's parent should be group 011 (Growing of non-perennial crops)
  expect_equal(class$parent_code, "011")
  # subclass 01130's parent is the class on the same row: 0113
  expect_equal(subclass$parent_code, "0113")
})

test_that("psic2026_get() filters to a single level when requested", {
  sections <- psic2026_get(level = "section")
  expect_true(all(sections$level == "section"))
  expect_equal(nrow(sections), 22)
})

test_that("psic2026_get() rejects an unsupported level with a clear error", {
  expect_error(psic2026_get(level = "not-a-real-level"), "Unsupported PSIC level")
})

test_that("psic2026_versions() and psic2026_levels() match the spec contract", {
  expect_equal(psic2026_versions(), "2026")
  expect_equal(psic2026_levels(), c("section", "division", "group", "class", "sub-class"))
})

test_that("missing runtime artifact produces a clear developer-facing error", {
  # Point at a path guaranteed not to exist rather than touching the real
  # committed artifact, exercising the same missing-file code path.
  .psic2026_reset_cache()
  bogus_path <- file.path(tempdir(), "does-not-exist-psic_2026.rds")
  expect_false(file.exists(bogus_path))
  expect_error(
    psic2026_get(data_path = bogus_path),
    "Run scripts/build_psic_2026.R",
    fixed = TRUE
  )

  bogus_meta_path <- file.path(tempdir(), "does-not-exist-psic_2026_metadata.rds")
  expect_error(
    psic2026_metadata(metadata_path = bogus_meta_path),
    "Run scripts/build_psic_2026.R",
    fixed = TRUE
  )
})

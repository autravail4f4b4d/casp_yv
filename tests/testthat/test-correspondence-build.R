# Tests for the *built* correspondence artifact (data/psic_2019_to_2026_correspondence.rds),
# produced by scripts/build_psic_correspondence.R. These tests load the
# already-committed artifact -- they do not re-run the build script (which
# depends on data-raw/ISIC4-5_Correspondence_Table.xlsx and the phscs
# package) -- and assert on real, previously-verified codes rather than
# fabricated fixtures.

correspondence_path <- function() {
  candidates <- c(
    "data/psic_2019_to_2026_correspondence.rds",
    file.path("..", "..", "data", "psic_2019_to_2026_correspondence.rds")
  )
  for (p in candidates) if (file.exists(p)) return(p)
  candidates[1]
}

test_that("the built correspondence artifact exists and loads offline", {
  expect_true(file.exists(correspondence_path()))
  cw <- readRDS(correspondence_path())
  expect_s3_class(cw, "data.frame")
  expect_true(nrow(cw) > 0)
})

cw <- readRDS(correspondence_path())

test_that("the artifact conforms to the canonical correspondence schema", {
  expect_silent(validate_correspondence_tibble(cw))
})

test_that("source_code and target_code are always character, never numeric", {
  expect_true(is.character(cw$source_code))
  expect_true(is.character(cw$target_code))
  # A representative code with a leading zero must survive as a string.
  expect_true("01161" %in% cw$source_code)
})

test_that("provenance is only official/derived/suggested, and official never appears", {
  expect_true(all(cw$provenance %in% CORRESPONDENCE_PROVENANCE_VALUES))
  # Per docs/CORRESPONDENCE_SOURCES.md: no official PSA PSIC 2019<->2026
  # crosswalk was found as of this build, so nothing here may claim to be
  # PSA-official. This is a real guard, not just documentation -- if this
  # ever fails, it means either (a) an official mapping was wrongly
  # produced by the deterministic build, which is a bug, or (b) a genuine
  # official source was found and integrated, in which case this test (and
  # docs/CORRESPONDENCE_SOURCES.md's "Reconciling" section) must be
  # revisited deliberately, not silently loosened.
  expect_false("official" %in% cw$provenance)
})

test_that("relation_type is always one of the documented enum values", {
  expect_true(all(cw$relation_type %in% CORRESPONDENCE_RELATION_TYPES))
})

test_that("confidence is always high/moderate/low", {
  expect_true(all(cw$confidence %in% CORRESPONDENCE_CONFIDENCE_VALUES))
})

test_that("every PSIC 2019 sub-class code has at least one output row (exhaustive coverage)", {
  suppressWarnings(suppressPackageStartupMessages(library(phscs)))
  sub19_codes <- unique(phscs_get("psic", "2019")[phscs_get("psic", "2019")$level == "sub-class", ]$code)
  sub_rows <- cw[cw$source_level == "sub-class" | (is.na(cw$source_level) & cw$target_level == "sub-class"), ]
  covered <- unique(sub_rows$source_code[!is.na(sub_rows$source_code)])
  expect_true(all(sub19_codes %in% covered))
})

test_that("a genuine unchanged 1:1 case resolves correctly: 01161 Growing of abaca", {
  row <- cw[cw$source_code %in% "01161" & cw$source_version == "2019" & cw$target_version == "2026", ]
  expect_equal(nrow(row), 1L)
  expect_equal(row$target_code, "01161")
  expect_equal(row$relation_type, "unchanged")
  expect_equal(row$provenance, "derived")
  expect_equal(row$confidence, "high")
})

test_that("a genuine split case exists and resolves: 01179 splits into 01171 and 01172", {
  rows <- cw[cw$source_code %in% "01179" & cw$source_version == "2019" & cw$target_version == "2026", ]
  expect_true(nrow(rows) >= 2)
  expect_true(all(rows$relation_type == "split"))
  expect_setequal(c("01171", "01172"), rows$target_code)
})

test_that("a genuine merged case exists: 01211 and 01212 both merge into 01210", {
  rows <- cw[cw$target_code %in% "01210" & cw$relation_type == "merged", ]
  expect_true(nrow(rows) >= 2)
  expect_setequal(c("01211", "01212"), rows$source_code)
  expect_true(all(rows$confidence == "high"))
})

test_that("a code with no plausible match resolves to 'discontinued' without erroring, target NA", {
  row <- cw[cw$source_code %in% "01531" & cw$source_version == "2019" & cw$target_version == "2026", ]
  expect_equal(nrow(row), 1L)
  expect_equal(row$relation_type, "discontinued")
  expect_true(is.na(row$target_code))
})

test_that("a genuinely new 2026 code with no 2019 counterpart is recorded, source NA", {
  row <- cw[cw$target_code %in% "01153" & cw$relation_type == "new", ]
  expect_equal(nrow(row), 1L)
  expect_true(is.na(row$source_code))
  expect_equal(row$provenance, "derived")
})

test_that("no numeric value/count/allocation column exists on the built data (statistical safety)", {
  suspect <- grep("value|count|allocation|amount|total", names(cw), ignore.case = TRUE, value = TRUE)
  expect_length(suspect, 0)
})

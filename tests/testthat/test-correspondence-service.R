# Tests for R/correspondence/service.R -- the runtime bidirectional lookup
# and search functions over the built correspondence artifact.

test_that("source audit is documented", {
  path <- "docs/CORRESPONDENCE_SOURCES.md"
  if (!file.exists(path)) path <- file.path("..", "..", "docs", "CORRESPONDENCE_SOURCES.md")
  expect_true(file.exists(path))
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_true(nchar(txt) > 500)
  expect_match(txt, "official PSA")
  expect_match(txt, "provenance", ignore.case = TRUE)
})

test_that("get_psic_correspondence forward lookup (2019->2026) finds the abaca unchanged case", {
  .correspondence_reset_cache()
  res <- get_psic_correspondence("01161", from_version = "2019", to_version = "2026")
  expect_equal(nrow(res), 1L)
  expect_equal(res$from_code, "01161")
  expect_equal(res$to_code, "01161")
  expect_equal(res$relation_type, "unchanged")
})

test_that("get_psic_correspondence reverse lookup (2026->2019) matches the forward lookup", {
  .correspondence_reset_cache()
  fwd <- get_psic_correspondence("01161", from_version = "2019", to_version = "2026")
  rev <- get_psic_correspondence("01161", from_version = "2026", to_version = "2019")
  expect_equal(nrow(rev), 1L)
  expect_equal(rev$from_code, "01161")
  expect_equal(rev$to_code, "01161")
  expect_equal(rev$relation_type, fwd$relation_type)
  expect_equal(rev$confidence, fwd$confidence)
})

test_that("get_psic_correspondence reverse lookup finds all sources of a merge target", {
  .correspondence_reset_cache()
  res <- get_psic_correspondence("01210", from_version = "2026", to_version = "2019")
  expect_true(nrow(res) >= 2)
  expect_true(all(res$relation_type == "merged"))
  expect_setequal(c("01211", "01212"), res$to_code)
})

test_that("get_psic_correspondence returns a zero-row tibble (not NULL, not an error) for an unknown code", {
  .correspondence_reset_cache()
  res <- get_psic_correspondence("99999-does-not-exist", from_version = "2019", to_version = "2026")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("get_psic_correspondence resolves a split into multiple candidate rows", {
  .correspondence_reset_cache()
  res <- get_psic_correspondence("01179", from_version = "2019", to_version = "2026")
  expect_true(nrow(res) >= 2)
  expect_true(all(res$relation_type == "split"))
  expect_setequal(c("01171", "01172"), res$to_code)
})

test_that("get_psic_correspondence resolves a discontinued code without erroring", {
  .correspondence_reset_cache()
  res <- get_psic_correspondence("01531", from_version = "2019", to_version = "2026")
  expect_equal(nrow(res), 1L)
  expect_equal(res$relation_type, "discontinued")
  expect_true(is.na(res$to_code))
})

test_that("get_psic_correspondence rejects from_version == to_version", {
  expect_error(get_psic_correspondence("01161", from_version = "2019", to_version = "2019"))
})

test_that("search_psic_correspondence finds a known label fragment", {
  .correspondence_reset_cache()
  res <- search_psic_correspondence("abaca", from_version = "2019", to_version = "2026")
  expect_true(nrow(res) >= 1)
  expect_true(any(grepl("abaca", tolower(res$from_label)) | grepl("abaca", tolower(res$to_label))))
})

test_that("search_psic_correspondence finds a known code fragment", {
  .correspondence_reset_cache()
  res <- search_psic_correspondence("01161", from_version = "2019", to_version = "2026")
  expect_true(nrow(res) >= 1)
  expect_true(any(res$from_code == "01161"))
})

test_that("search_psic_correspondence respects limit", {
  .correspondence_reset_cache()
  res <- search_psic_correspondence("growing", from_version = "2019", to_version = "2026", limit = 3)
  expect_true(nrow(res) <= 3)
})

test_that("search_psic_correspondence returns a zero-row tibble for a nonsense query", {
  .correspondence_reset_cache()
  res <- search_psic_correspondence("zzzznonexistentqueryzzzz", from_version = "2019", to_version = "2026")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("load_psic_correspondence errors clearly (not silently) when the artifact is missing", {
  expect_error(
    load_psic_correspondence(data_path = "does/not/exist.rds"),
    "missing"
  )
})

test_that("no function in the correspondence service performs numeric statistical redistribution", {
  # There is simply no function that takes a numeric value/count and splits
  # or allocates it across correspondence targets -- naturally true since
  # no such function is defined. This test documents/guards that intent.
  service_fns <- c("get_psic_correspondence", "search_psic_correspondence", "load_psic_correspondence")
  for (fn in service_fns) {
    expect_true(exists(fn, mode = "function"))
  }
  expect_false(exists("reallocate_psic_correspondence_value", mode = "function"))
  expect_false(exists("redistribute_psic_statistics", mode = "function"))
})

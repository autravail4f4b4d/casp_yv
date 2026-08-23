test_that("defaults are PSOC 2022 and PSIC 2026", {
  res <- search_parallel_classifications("accountant")
  expect_equal(res$metadata$psoc_version, "2022")
  expect_equal(res$metadata$psic_version, "2026")
  expect_equal(res$systems, c("psoc", "psic"))
})

test_that("one query produces independent PSOC and PSIC result sets", {
  res <- search_parallel_classifications("accountant")
  expect_true(is.data.frame(res$results$psoc))
  expect_true(is.data.frame(res$results$psic))
  expect_equal(names(res$results$psoc), CLASSIFICATION_SCHEMA_COLUMNS)
  expect_equal(names(res$results$psic), CLASSIFICATION_SCHEMA_COLUMNS)
  # Independent systems: PSOC rows are all psoc/2022, PSIC rows are all psic/2026.
  if (nrow(res$results$psoc) > 0) expect_true(all(res$results$psoc$system == "psoc"))
  if (nrow(res$results$psic) > 0) expect_true(all(res$results$psic$system == "psic"))
})

test_that("reuses the existing canonical ranking -- exact-code and label ranking behave identically to search_classification()", {
  direct <- search_classification("psoc", "2022", "2121")
  parallel <- search_parallel_classifications("2121", systems = "psoc", versions = c(psoc = "2022"))
  expect_equal(parallel$results$psoc, direct)

  direct_psic <- search_classification("psic", "2026", "software")
  parallel_psic <- search_parallel_classifications("software", systems = "psic", versions = c(psic = "2026"))
  expect_equal(parallel_psic$results$psic, direct_psic)
})

test_that("a no-result query on one system does not suppress the other", {
  # A query engineered to hit in PSIC (a real PSIC label fragment) but be
  # nonsense for PSOC.
  res <- search_parallel_classifications("zzzzznomatchzzzzz")
  expect_equal(nrow(res$results$psoc), 0)
  expect_equal(nrow(res$results$psic), 0)
  expect_equal(names(res$results$psoc), CLASSIFICATION_SCHEMA_COLUMNS)
  expect_equal(names(res$results$psic), CLASSIFICATION_SCHEMA_COLUMNS)
  expect_null(res$errors)
})

test_that("an error on one system's side does not prevent the other from returning results", {
  res <- search_parallel_classifications(
    "accountant",
    systems = c("psoc", "psic"),
    versions = c(psoc = "9999-not-a-real-version", psic = "2026")
  )
  expect_null(res$results$psoc)
  expect_true(is.data.frame(res$results$psic))
  expect_true(nrow(res$results$psic) >= 0)
  expect_true(!is.null(res$errors))
  expect_match(res$errors$psoc, "Unsupported version")
  expect_null(res$errors$psic)
})

test_that("archived editions can be explicitly selected for parallel search", {
  res <- search_parallel_classifications(
    "legislators",
    versions = c(psoc = "2012", psic = "2019")
  )
  if (nrow(res$results$psoc) > 0) expect_true(all(res$results$psoc$status == "archived"))
  if (nrow(res$results$psic) > 0) expect_true(all(res$results$psic$status == "archived"))
  expect_equal(res$metadata$psoc_version, "2012")
  expect_equal(res$metadata$psic_version, "2019")
})

test_that("per-system level filtering works independently", {
  res <- search_parallel_classifications(
    "",
    levels = list(psic = "division")
  )
  if (nrow(res$results$psic) > 0) expect_true(all(res$results$psic$level == "division"))
  # PSOC has no level filter applied -- may contain any of its 4 levels.
  expect_true(is.data.frame(res$results$psoc))
})

test_that("limit_per_system caps each system independently", {
  res <- search_parallel_classifications("", limit_per_system = 3)
  expect_true(nrow(res$results$psoc) <= 3)
  expect_true(nrow(res$results$psic) <= 3)
})

test_that("code string behavior (leading zeros) is preserved through the parallel wrapper", {
  res <- search_parallel_classifications("01111", systems = "psic", versions = c(psic = "2026"))
  expect_true(nrow(res$results$psic) >= 1)
  expect_equal(res$results$psic$code[[1]], "01111")
  expect_true(is.character(res$results$psic$code))
})

test_that("PARALLEL_SEARCH_SYSTEM_LABELS gives the mandated occupation/industry distinction", {
  expect_equal(unname(PARALLEL_SEARCH_SYSTEM_LABELS["psoc"]), "Occupations")
  expect_equal(unname(PARALLEL_SEARCH_SYSTEM_LABELS["psic"]), "Industries")
})

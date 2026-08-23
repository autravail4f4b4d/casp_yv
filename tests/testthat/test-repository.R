test_that("get_classification loads every registered system/version without error", {
  reg <- classification_registry()
  for (i in seq_len(nrow(reg))) {
    system <- reg$id[[i]]
    for (version in reg$available_versions[[i]]) {
      d <- get_classification(system, version)
      # The canonical contract is that the first 10 columns are exactly
      # CLASSIFICATION_SCHEMA_COLUMNS, in order. Composite/thematic systems
      # (PTSCS, PSCrCS) legitimately append provenance columns after them --
      # component, major_category, source_system/version/code -- because
      # they mint no codes of their own and the underlying classification
      # is part of the record's meaning. Canonical consumers index by name
      # and ignore extras, so this is an extension, not a relaxation: the
      # 10 canonical columns must still all be present, in order, first.
      expect_equal(
        names(d)[seq_along(CLASSIFICATION_SCHEMA_COLUMNS)],
        CLASSIFICATION_SCHEMA_COLUMNS,
        info = paste(system, version)
      )
      expect_true(nrow(d) > 0, info = paste(system, version))
      expect_true(is.character(d$code), info = paste(system, version))
    }
  }
})

test_that("get_classification filters to a single level", {
  d <- get_classification("psic", "2026", level = "section")
  expect_true(all(d$level == "section"))
  expect_true(nrow(d) == 22)
})

test_that("PSIC 2026 is current and queryable; PSIC 2019 remains queryable as archived", {
  cur <- get_classification("psic", "2026")
  expect_true(all(cur$status == "current"))

  archived <- get_classification("psic", "2019")
  expect_true(all(archived$status == "archived"))

  versions <- classification_versions("psic")
  expect_true(all(c("2019", "2026") %in% versions))
})

test_that("PSGC release enumeration is exposed through the repository", {
  versions <- classification_versions("psgc")
  expect_true(psgc::latest_release() %in% versions)
  expect_true(length(versions) >= 2)
})

test_that("classification_levels validates system+version and lists real levels", {
  levels <- classification_levels("psic", "2026")
  expect_setequal(levels, c("section", "division", "group", "class", "sub-class"))
})

test_that("get_classification raises a clear error for an unsupported system", {
  expect_error(get_classification("not-a-system", "1"), "Unsupported classification system")
  expect_error(get_classification("not-a-system", "1"), "Available systems")
})

test_that("get_classification raises a clear error for an unsupported version, listing available ones", {
  err <- tryCatch(get_classification("psic", "1999"), error = function(e) conditionMessage(e))
  expect_match(err, "Unsupported version")
  expect_match(err, "2019")
  expect_match(err, "2026")
})

test_that("get_classification raises a clear error for an unsupported level", {
  err <- tryCatch(get_classification("psic", "2026", level = "nonexistent"), error = function(e) conditionMessage(e))
  expect_match(err, "Unsupported level")
  expect_match(err, "section")
})

test_that("search_classification wraps the search engine over live repository data", {
  # Exact-code hit against real PSIC 2026 data (verified real code/label).
  res <- search_classification("psic", "2026", "01111")
  expect_true(nrow(res) >= 1)
  expect_equal(res$code[[1]], "01111")

  # Blank query behaves as Browse (spec 5.2): non-empty, capped at limit.
  browse <- search_classification("psic", "2026", "", level = "section", limit = 5)
  expect_equal(nrow(browse), 5)
  expect_true(all(browse$level == "section"))

  # No-match query never errors.
  none <- search_classification("psic", "2026", "zzzzznomatch")
  expect_equal(nrow(none), 0)
  expect_equal(names(none), CLASSIFICATION_SCHEMA_COLUMNS)
})

test_that("search_classification validates system/version/level the same way get_classification does", {
  expect_error(search_classification("psic", "1999", "x"), "Unsupported version")
  expect_error(search_classification("psic", "2026", "x", level = "nope"), "Unsupported level")
})

test_that("get_classification_entry returns exactly one row for a known code", {
  entry <- get_classification_entry("psic", "2026", "01111")
  expect_equal(nrow(entry), 1)
  expect_equal(entry$code, "01111")
  expect_equal(entry$version, "2026")
  expect_equal(entry$status, "current")
})

test_that("get_classification_entry returns zero rows (not an error) for an unknown code", {
  entry <- get_classification_entry("psic", "2026", "00000-nope")
  expect_equal(nrow(entry), 0)
  expect_equal(names(entry), CLASSIFICATION_SCHEMA_COLUMNS)
})

test_that("get_classification_entry never coerces codes to numbers (leading zeros preserved)", {
  entry <- get_classification_entry("psic", "2019", "01")
  expect_equal(nrow(entry), 1)
  expect_equal(entry$code, "01")
})

test_that("classification_metadata reports correct status/display_version per system", {
  meta_2026 <- classification_metadata("psic", "2026")
  expect_equal(meta_2026$status, "current")
  expect_equal(meta_2026$display_version, "PSIC Revision 5 (2026)")
  expect_true(nzchar(meta_2026$source_url))

  meta_2019 <- classification_metadata("psic", "2019")
  expect_equal(meta_2019$status, "archived")

  meta_psgc <- classification_metadata("psgc", psgc::latest_release())
  expect_equal(meta_psgc$status, "current")
  expect_equal(meta_psgc$system, "psgc")
})

test_that("UAT: exact PSOC code search ranks the exact match first", {
  res <- search_classification("psoc", "2012", "1111")
  expect_true(nrow(res) >= 1)
  expect_equal(res$code[[1]], "1111")
  expect_equal(res$label[[1]], "Legislators")
})

test_that("UAT: PSOC text search finds a known occupation by keyword", {
  res <- search_classification("psoc", "2012", "legislators")
  expect_true(any(res$code == "1111"))
})

test_that("UAT: PSGC current release name search", {
  res <- search_classification("psgc", psgc::latest_release(), "Bukidnon")
  expect_true(any(res$label == "Bukidnon"))
})

test_that("UAT: PSGC old (archived) release search still works and is marked archived", {
  older <- "Q1_2023"
  expect_true(older %in% classification_versions("psgc"))
  res <- search_classification("psgc", older, "Ilocos Norte")
  expect_true(any(res$label == "Ilocos Norte"))
  expect_true(all(res$status == "archived"))
})

test_that("UAT: classification level filter narrows real results to one level", {
  res <- search_classification("psic", "2026", "", level = "division", limit = 500)
  expect_true(nrow(res) > 0)
  expect_true(all(res$level == "division"))
})

test_that("UAT: special characters (literal dot in a PCOICOP code) match literally, not as a regex wildcard", {
  res <- search_classification("pcoicop", "2020", "01.1.3")
  expect_true(any(res$code == "01.1.3"))
  # A regex-wildcard interpretation of "." would also match e.g. "0111.3" or
  # unrelated 6-character codes; guard that every match actually contains a
  # literal dot at that position.
  expect_true(all(grepl("01.1.3", res$code, fixed = TRUE) | grepl(tolower("01.1.3"), tolower(res$label), fixed = TRUE) | grepl(tolower("01.1.3"), tolower(res$description), fixed = TRUE)))
})

test_that("switching classification/version never silently mixes editions", {
  psic_2019 <- get_classification("psic", "2019")
  psic_2026 <- get_classification("psic", "2026")
  expect_true(all(psic_2019$version == "2019"))
  expect_true(all(psic_2026$version == "2026"))
  # Section count differs (2019 has 21 sections per phscs; 2026 has 22) --
  # a real behavioral guard against the two editions' data being merged.
  expect_false(
    sum(psic_2019$level == "section") == sum(psic_2026$level == "section") &&
      identical(sort(psic_2019$code[psic_2019$level == "section"]),
                sort(psic_2026$code[psic_2026$level == "section"]))
  )
})

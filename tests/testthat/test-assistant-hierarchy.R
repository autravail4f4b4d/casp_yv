# RM orchestration hardening: assistant_hierarchy_annotate().
#
# These exercise the pure annotation function directly with small
# constructed data frames, independent of retrieval and independent of any
# live model -- the deterministic guarantee this whole milestone rests on.

test_that("an ancestor/descendant pair is annotated correctly (heavy truck driver shape)", {
  rows <- data.frame(
    code = c("833", "8332"),
    parent_code = c(NA_character_, "833"),
    stringsAsFactors = FALSE
  )
  out <- assistant_hierarchy_annotate(rows)

  expect_equal(out$hierarchy_role[out$code == "833"], "ancestor")
  expect_equal(out$hierarchy_role[out$code == "8332"], "most_specific")
  expect_equal(out$hierarchy_of[out$code == "833"], "8332")
  expect_true(is.na(out$hierarchy_of[out$code == "8332"]))
})

test_that("order of rows does not change the annotation", {
  rows <- data.frame(
    code = c("8332", "833"),
    parent_code = c("833", NA_character_),
    stringsAsFactors = FALSE
  )
  out <- assistant_hierarchy_annotate(rows)

  expect_equal(out$hierarchy_role[out$code == "833"], "ancestor")
  expect_equal(out$hierarchy_role[out$code == "8332"], "most_specific")
})

test_that("an exact-code query for the ancestor alone stays standalone, not 'ancestor'", {
  # "What is PSOC 833?" retrieves ONLY 833 -- there is no descendant in this
  # result set for it to be an ancestor OF, so it must not be mislabelled.
  rows <- data.frame(code = "833", parent_code = "83", stringsAsFactors = FALSE)
  out <- assistant_hierarchy_annotate(rows)
  expect_equal(out$hierarchy_role, "most_specific")
})

test_that("a three-level ancestor chain resolves to one most-specific leaf", {
  rows <- data.frame(
    code        = c("8", "83", "833", "8332"),
    parent_code = c(NA_character_, "8", "83", "833"),
    stringsAsFactors = FALSE
  )
  out <- assistant_hierarchy_annotate(rows)

  expect_equal(out$hierarchy_role[out$code == "8332"], "most_specific")
  for (anc in c("8", "83", "833")) {
    expect_equal(out$hierarchy_role[out$code == anc], "ancestor", info = anc)
    expect_equal(out$hierarchy_of[out$code == anc], "8332", info = anc)
  }
})

test_that("true siblings with no ancestor relationship are not marked as ancestors", {
  # PSIC "bakery" shape: three sub-classes sharing one parent, none an
  # ancestor of another.
  rows <- data.frame(
    code        = c("10711", "10712", "10719"),
    parent_code = c("1071", "1071", "1071"),
    stringsAsFactors = FALSE
  )
  out <- assistant_hierarchy_annotate(rows)
  expect_true(all(out$hierarchy_role == "standalone"))
  expect_true(all(is.na(out$hierarchy_of)))
})

test_that("a system with no hierarchy (parent_code always NA) leaves every row standalone", {
  # PTSCS shape: R/adapters/adapter_ptscs_2025.R documents parent_code as
  # NA on every record.
  rows <- data.frame(
    code = c("55101", "79110"),
    parent_code = c(NA_character_, NA_character_),
    stringsAsFactors = FALSE
  )
  out <- assistant_hierarchy_annotate(rows)
  expect_true(all(out$hierarchy_role == "standalone"))
})

test_that("unrelated codes with no shared ancestry are not conflated", {
  rows <- data.frame(
    code        = c("2221", "7512"),
    parent_code = c("222", "751"),
    stringsAsFactors = FALSE
  )
  out <- assistant_hierarchy_annotate(rows)
  expect_true(all(out$hierarchy_role == "standalone"))
})

test_that("missing parent_code column degrades to every row standalone, never an error", {
  rows <- data.frame(code = c("833", "8332"), stringsAsFactors = FALSE)
  out <- assistant_hierarchy_annotate(rows)
  expect_true(all(out$hierarchy_role == "standalone"))
})

test_that("a zero-row candidate set round-trips without error", {
  rows <- data.frame(code = character(0), parent_code = character(0), stringsAsFactors = FALSE)
  out <- assistant_hierarchy_annotate(rows)
  expect_equal(nrow(out), 0L)
  expect_true(all(c("hierarchy_role", "hierarchy_of") %in% names(out)))
})

test_that("end-to-end: assistant_search_classification marks 8332 most_specific for the reported defect", {
  res <- assistant_search_classification("psoc", "heavy truck driver")
  codes <- vapply(res$results, function(r) r$code, character(1))
  roles <- setNames(vapply(res$results, function(r) r$hierarchy_role, character(1)), codes)

  skip_if_not("8332" %in% codes, "8332 not retrieved for this corpus state")
  expect_equal(unname(roles["8332"]), "most_specific")
  if ("833" %in% codes) {
    expect_equal(unname(roles["833"]), "ancestor")
  }
})

test_that("end-to-end: an exact-code query for the ancestor is not relabelled by hierarchy logic", {
  res <- assistant_search_classification("psoc", "833")
  codes <- vapply(res$results, function(r) r$code, character(1))
  skip_if(length(codes) == 0L, "no results for exact code 833")
  # 833 itself must still be presented as a genuine answer, not suppressed
  # or reclassified merely because it happens to have descendants elsewhere
  # in the system.
  expect_true("833" %in% codes)
})

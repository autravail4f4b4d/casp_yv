# W1-A: classification-level semantics.
#
# The level ORDER is derived from measured code depth per system, not from
# a hard-coded ladder, so these tests assert the derivation as well as the
# PSOC ladder the specification names explicitly.

test_that("the PSOC ladder maps digits to the specified levels and roles", {
  expect <- list(
    list(code = "8",    level = "major_group",     depth = 1L, role = "aggregate"),
    list(code = "83",   level = "sub_major_group", depth = 2L, role = "aggregate"),
    list(code = "833",  level = "minor_group",     depth = 3L, role = "aggregate"),
    list(code = "8332", level = "unit_group",      depth = 4L, role = "detailed")
  )
  for (e in expect) {
    r <- assistant_coding_level("psoc", NULL, e$code)
    expect_true(r$found, info = e$code)
    expect_identical(r$classification_level, e$level, info = e$code)
    expect_identical(r$code_depth, e$depth, info = e$code)
    expect_identical(r$coding_role, e$role, info = e$code)
  }
})

test_that("only the PSOC Unit Group is the detailed coding level", {
  expect_true(assistant_coding_level("psoc", NULL, "8332")$is_detailed_coding_level)
  expect_true(assistant_coding_level("psoc", NULL, "2221")$is_detailed_coding_level)
  expect_false(assistant_coding_level("psoc", NULL, "833")$is_detailed_coding_level)
  expect_false(assistant_coding_level("psoc", NULL, "83")$is_detailed_coding_level)
})

test_that("level display names read as PSA writes them", {
  expect_identical(assistant_level_display("unit_group"), "Unit Group")
  expect_identical(assistant_level_display("minor_group"), "Minor Group")
  expect_identical(assistant_level_display("sub_major_group"), "Sub-major Group")
  expect_identical(assistant_level_display("sub-class"), "Sub-class")
  expect_true(is.na(assistant_level_display(NA_character_)))
})

test_that("PSIC's own ladder resolves independently of PSOC's", {
  expect_identical(assistant_coding_level("psic", NULL, "A")$coding_role, "aggregate")
  expect_identical(assistant_coding_level("psic", NULL, "0113")$coding_role, "aggregate")
  expect_identical(assistant_coding_level("psic", NULL, "01130")$coding_role, "detailed")
  expect_identical(assistant_coding_level("psic", NULL, "01130")$classification_level, "sub-class")
})

test_that("a fixed-width system is structural, not aggregate/detailed", {
  # Every PSGC code is 10 characters at every level, so code depth cannot
  # rank Region against Barangay -- claiming one is "detailed" would be
  # an invented judgement.
  r <- assistant_coding_level("psgc", NULL, "0631000000")
  expect_true(r$found)
  expect_identical(r$coding_role, "structural")
  expect_false(r$is_detailed_coding_level)
})

test_that("composite systems report component, not a coding depth", {
  for (sys in c("ptscs", "pscrcs")) {
    map <- assistant_level_map(sys)
    skip_if(is.null(map), sys)
    expect_identical(map$kind, "composite", info = sys)
  }
  expect_identical(assistant_coding_level("pscrcs", NULL, "58110")$coding_role, "component")
})

test_that("the level map is measured from the repository, broadest to most detailed", {
  map <- assistant_level_map("psoc", "2022")
  expect_identical(map$kind, "hierarchical")
  expect_identical(map$levels,
                   c("major_group", "sub_major_group", "minor_group", "unit_group"))
  expect_identical(map$detailed, "unit_group")
})

test_that("an unverified code yields found = FALSE and no level claim", {
  r <- assistant_coding_level("psoc", NULL, "99999")
  expect_false(r$found)
  expect_null(r$coding_role)
  expect_match(r$message, "could not be verified")
})

test_that("child codes of an aggregate come from canonical parent_code only", {
  kids <- assistant_child_codes("psoc", NULL, "833")
  codes <- vapply(kids$children, function(k) k$code, character(1))
  expect_setequal(codes, c("8331", "8332"))
  expect_true(all(vapply(kids$children, function(k) k$level, character(1)) == "unit_group"))
})

test_that("a detailed code has no children", {
  expect_equal(assistant_child_codes("psoc", NULL, "8332")$count, 0L)
})

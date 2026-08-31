# v10 -- full-chain ancestry and canonical depth.
#
# `assistant_hierarchy_annotate()` links only parents that are themselves
# in the candidate set. A bounded shortlist frequently omits an
# intermediate level, and when it does the chain breaks silently: for a
# national public-administration query the survivors were Section P,
# Division 84, Class 8411 and sub-class 84119, but the Group 841 between
# 84 and 8411 was never retrieved, so 84 was labelled "standalone" and
# outranked 8411 -- degrading the answer from the canonical ceiling to an
# entire PSIC sector.

test_that("an ancestor is detected across an unretrieved intermediate level", {
  # 841 (Group) is deliberately absent, exactly as in the live set.
  codes <- c("84", "P", "8411", "84119")
  counts <- .assistant_ancestor_of_other(codes, "psic", "2026")
  names(counts) <- codes

  expect_gt(counts[["P"]], counts[["84"]])     # Section covers the most
  expect_gt(counts[["84"]], counts[["8411"]])  # Division covers more than Class
  expect_identical(counts[["84119"]], 0L)      # the leaf covers nothing
})

test_that("a code is never counted as its own ancestor", {
  expect_identical(.assistant_ancestor_of_other(c("8411"), "psic", "2026"), 0L)
  counts <- .assistant_ancestor_of_other(c("8411", "8411"), "psic", "2026")
  # Two copies of the same code are not ancestors of each other.
  expect_true(all(counts == 0L))
})

test_that("canonical depth increases down the real hierarchy", {
  d <- .assistant_canonical_depth(c("P", "84", "841", "8411", "84113"),
                                  "psic", "2026")
  expect_true(all(diff(d) > 0))
  expect_identical(d[[1L]], 0L)
})

test_that("a flat classification yields no ancestry and no depth", {
  reg <- classification_registry()
  skip_if_not("ptscs" %in% reg$id, "ptscs not registered")
  v <- reg$current_version[reg$id == "ptscs"][[1L]]
  rows <- utils::head(get_classification("ptscs", v), 5L)
  skip_if(nrow(rows) < 2L, "not enough ptscs rows")
  codes <- as.character(rows$code)
  expect_true(all(.assistant_ancestor_of_other(codes, "ptscs", v) == 0L))
  expect_true(all(.assistant_canonical_depth(codes, "ptscs", v) == 0L))
})

test_that("an unknown code ends the walk instead of erroring", {
  # `map[["absent"]]` throws on an atomic vector; the walk must use single
  # brackets. A code from another system is the normal case, not an error.
  expect_silent(.assistant_ancestor_of_other(c("ZZZZ", "8411"), "psic", "2026"))
  expect_identical(.assistant_canonical_depth("ZZZZ", "psic", "2026"), 0L)
})

test_that("the parent map is memoised and resettable", {
  .assistant_parent_map_reset()
  a <- .assistant_parent_map("psic", "2026")
  b <- .assistant_parent_map("psic", "2026")
  expect_identical(a, b)
  expect_gt(length(a), 100L)
})

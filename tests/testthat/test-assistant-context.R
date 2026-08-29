# Spec 13: post-retrieval context-consistency gate.

test_that("the nursery/nurse false positive is rejected", {
  # The exact staging defect: 6118 is canonical but is not a plausible
  # answer to "nurse". It reached the candidate set only because "nurse"
  # is a literal substring of "nursery".
  expect_false(assistant_context_plausible(
    c("nurse", "nursing"),
    "GARDENERS, HORTICULTURAL AND NURSERY GROWERS"
  ))
})

test_that("the correct nursing record is accepted", {
  expect_true(assistant_context_plausible(
    c("nurse", "nursing"),
    "NURSING PROFESSIONALS"
  ))
})

test_that("whole-token support is required, not substring containment", {
  # "nurse" IS contained in "nursery" as characters; that must not count.
  expect_false(assistant_context_plausible("nurse", "NURSERY GROWERS"))
  expect_true(assistant_context_plausible("grower", "NURSERY GROWERS"))
})

test_that("a genuine typo still passes the gate", {
  # The gate reuses the retrieval evidence floor, so real typos survive.
  expect_true(assistant_context_plausible("trcuk", "HEAVY TRUCK AND LORRY DRIVERS"))
  expect_true(assistant_context_plausible("carpentar", "CARPENTERS AND JOINERS"))
})

test_that("an unrelated candidate is rejected outright", {
  expect_false(assistant_context_plausible("nurse", "BUS AND TRAM DRIVERS"))
  expect_false(assistant_context_plausible("carpenter", "NURSING PROFESSIONALS"))
})

test_that("the official description is consulted when the title alone is silent", {
  expect_true(assistant_context_plausible(
    "welder", "SOME UNRELATED TITLE",
    description = "Workers in this group weld and cut metal parts; includes welder duties."
  ))
})

test_that("an empty query is not used to reject anything", {
  expect_true(assistant_context_plausible(character(0), "ANY LABEL"))
  expect_true(assistant_context_plausible("the", "ANY LABEL"))
})

test_that("the filter drops only the implausible rows and can legitimately empty a set", {
  rows <- data.frame(
    code = c("6118", "2221"),
    label = c("GARDENERS, HORTICULTURAL AND NURSERY GROWERS", "NURSING PROFESSIONALS"),
    stringsAsFactors = FALSE
  )
  kept <- assistant_context_filter(rows, c("nurse", "nursing"))
  expect_identical(kept$code, "2221")

  only_bad <- assistant_context_filter(rows[1, , drop = FALSE], c("nurse", "nursing"))
  expect_equal(nrow(only_bad), 0L)
})

test_that("the gate consults no model confidence, only verified text", {
  # Same label, same verdict, regardless of any surrounding state -- the
  # function is pure and takes no confidence argument.
  a <- assistant_context_plausible("nurse", "GARDENERS, HORTICULTURAL AND NURSERY GROWERS")
  b <- assistant_context_plausible("nurse", "GARDENERS, HORTICULTURAL AND NURSERY GROWERS")
  expect_identical(a, b)
  expect_false("confidence" %in% names(formals(assistant_context_plausible)))
})

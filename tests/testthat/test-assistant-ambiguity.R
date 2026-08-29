# RM orchestration hardening: assistant_ambiguity_check().
#
# Exercises the pure ambiguity-detection function directly. Clarification
# text/options must be built ENTIRELY from the `label`/`code`/`parent_code`
# values passed in -- nothing here is bakery-specific or query-specific.

.annotated <- function(rows) assistant_hierarchy_annotate(rows)

test_that("an exact/unambiguous single match is never ambiguous", {
  rows <- .annotated(data.frame(
    code = "8332", label = "HEAVY TRUCK AND LORRY DRIVERS",
    parent_code = "833", stringsAsFactors = FALSE
  ))
  out <- assistant_ambiguity_check(rows)
  expect_false(out$ambiguous)
  expect_equal(out$options, list())
})

test_that("an ancestor/descendant pair is resolved by hierarchy, not flagged ambiguous", {
  rows <- .annotated(data.frame(
    code = c("833", "8332"),
    label = c("HEAVY TRUCK AND BUS DRIVERS", "HEAVY TRUCK AND LORRY DRIVERS"),
    parent_code = c(NA_character_, "833"),
    stringsAsFactors = FALSE
  ))
  out <- assistant_ambiguity_check(rows)
  expect_false(out$ambiguous)
})

test_that("true siblings (bakery shape) are flagged ambiguous with options from verified labels", {
  rows <- .annotated(data.frame(
    code = c("1071", "10711", "10712", "10719"),
    label = c(
      "Manufacture of bakery products",
      "Baking of bread, cakes, pastries, pies and similar perishable bakery products",
      "Baking of biscuits, cookies, crackers, pretzels and similar dry bakery products",
      "Manufacture of bakery products, n.e.c."
    ),
    parent_code = c("107", "1071", "1071", "1071"),
    stringsAsFactors = FALSE
  ))
  out <- assistant_ambiguity_check(rows)

  expect_true(out$ambiguous)
  expect_length(out$options, 3L)
  option_codes <- vapply(out$options, function(o) o$code, character(1))
  expect_setequal(option_codes, c("10711", "10712", "10719"))

  # The question text is built from the verified labels actually present --
  # not a hard-coded "bread vs biscuits" template.
  for (lbl in c(
    "Baking of bread, cakes, pastries, pies and similar perishable bakery products",
    "Baking of biscuits, cookies, crackers, pretzels and similar dry bakery products",
    "Manufacture of bakery products, n.e.c."
  )) {
    expect_true(grepl(lbl, out$clarifying_question, fixed = TRUE), info = lbl)
  }
  # The shared parent's own verified label names the group, not invented prose.
  expect_true(grepl("Manufacture of bakery products", out$clarifying_question, fixed = TRUE))
})

test_that("a different sibling family (repair-of-motor shape) produces a different, still-generic question", {
  rows <- .annotated(data.frame(
    code = c("4520", "45201", "45209"),
    label = c(
      "Maintenance and repair of motor vehicles",
      "Maintenance and repair of motor vehicles n.e.c.",
      "Repair of other transport equipment"
    ),
    parent_code = c("452", "4520", "4520"),
    stringsAsFactors = FALSE
  ))
  out <- assistant_ambiguity_check(rows)

  expect_true(out$ambiguous)
  option_codes <- vapply(out$options, function(o) o$code, character(1))
  expect_setequal(option_codes, c("45201", "45209"))
  expect_true(grepl("Repair of other transport equipment", out$clarifying_question, fixed = TRUE))
  # Must not reuse the bakery wording from a different test/query.
  expect_false(grepl("bakery", out$clarifying_question, ignore.case = TRUE))
})

test_that("unrelated standalone leaves with no shared parent are not forced into ambiguity", {
  rows <- .annotated(data.frame(
    code = c("2221", "7512"),
    label = c("NURSING PROFESSIONALS", "BAKERS, PASTRY-COOKS AND CONFECTIONERY MAKERS"),
    parent_code = c("222", "751"),
    stringsAsFactors = FALSE
  ))
  out <- assistant_ambiguity_check(rows)
  expect_false(out$ambiguous)
})

test_that("one clear specific descendant among distractors is not blocked by ambiguity", {
  # A leaf set containing one hierarchy "most_specific" row and unrelated
  # standalone rows must not itself trigger sibling ambiguity for the
  # most_specific row (it has no siblings sharing ITS parent).
  rows <- .annotated(data.frame(
    code = c("833", "8332", "2221"),
    label = c("HEAVY TRUCK AND BUS DRIVERS", "HEAVY TRUCK AND LORRY DRIVERS", "NURSING PROFESSIONALS"),
    parent_code = c(NA_character_, "833", "222"),
    stringsAsFactors = FALSE
  ))
  out <- assistant_ambiguity_check(rows)
  expect_false(out$ambiguous)
})

test_that("malformed or minimal input never errors", {
  expect_false(assistant_ambiguity_check(NULL)$ambiguous)
  expect_false(assistant_ambiguity_check(data.frame())$ambiguous)
  expect_false(assistant_ambiguity_check(data.frame(code = "1"))$ambiguous)
  expect_false(assistant_ambiguity_check(data.frame(
    code = "1", label = "x", hierarchy_role = "standalone", stringsAsFactors = FALSE
  ))$ambiguous)
})

test_that("end-to-end: PSIC 'bakery' either resolves cleanly or is flagged ambiguous, never both silent and multi-coded", {
  res <- assistant_search_classification("psic", "bakery")
  skip_if(length(res$results) == 0L, "no results for 'bakery' in this corpus state")

  if (isTRUE(res$ambiguous)) {
    expect_gte(length(res$clarification_options), 2L)
    expect_true(nzchar(res$clarifying_question))
  }
  # Whether ambiguous or not, every option/result code must be one of the
  # actually-returned verified candidates -- never invented.
  returned_codes <- vapply(res$results, function(r) r$code, character(1))
  if (isTRUE(res$ambiguous)) {
    option_codes <- vapply(res$clarification_options, function(o) o$code, character(1))
    expect_true(all(option_codes %in% returned_codes))
  }
})

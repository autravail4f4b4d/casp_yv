# Tests for search_classification_data() (R/search.R).
#
# Fixture built entirely with new_classification_tibble() -- no adapters,
# no repository, no registry. Search only ever operates on one
# already-fetched dataset at a time, so a single system/version is enough.
#
# Fixture design note: rows are built so that, for a given test's query,
# only the intended row(s) match. Distinctive tokens ("6201", "abc123",
# "01.1.1.11", "(household appliances)") are used instead of short/common
# substrings precisely to avoid accidental cross-tier contamination (e.g.
# a single-letter query would spuriously substring-match many unrelated
# English words).

make_fixture <- function() {
  new_classification_tibble(
    system = "psic",
    version = "2026",
    level = c(
      "section",   # 1  code exact match target for query "6201"
      "section",   # 2  code prefix match target for query "6201"
      "section",   # 3  label exact match target for query "6201"
      "section",   # 4  label prefix match target for query "6201"
      "section",   # 5  label substring match target for query "6201"
      "sub-class", # 6  description-only match target for query "6201"
      "section",   # 7  no match at all for query "6201" (control)
      "section",   # 8  label exact match (whitespace+case) for "computer programming"
      "sub-class", # 9  label prefix match for "computer programming"
      "class",     # 10 PCOICOP-style dotted code
      "section",   # 11 parentheses in label
      "section"    # 12 case-insensitive code match target
    ),
    code = c(
      "6201",
      "620199",
      "Z1",
      "Z2",
      "Z3",
      "Z4",
      "Z5",
      "A",
      "B",
      "01.1.1.11",
      "Z9",
      "abc123"
    ),
    label = c(
      "Alpha unrelated label",                          # 1
      "Beta unrelated label",                            # 2
      "6201",                                             # 3 exact label match (after normalization)
      "6201 handbook section",                            # 4 label prefix match
      "See section 6201 handbook",                        # 5 label substring match
      "General guidance",                                 # 6 label doesn't match; description will
      "Nothing related here",                             # 7 no match anywhere
      "Computer   Programming",                           # 8 irregular whitespace, exact match target
      "Computer programming and other IT services",       # 9 prefix match target
      "Retail sale of rice",                              # 10
      "Repair services (household appliances)",           # 11 parentheses
      "Something totally different"                       # 12
    ),
    description = c(
      NA_character_,
      NA_character_,
      NA_character_,
      NA_character_,
      NA_character_,
      "Refer to code 6201 for more info",  # 6
      NA_character_,                        # 7: NA description, must not crash substring check
      NA_character_,
      NA_character_,
      NA_character_,
      NA_character_,
      NA_character_
    ),
    parent_code = NA_character_,
    status = "current",
    source = "Philippine Statistics Authority",
    source_url = "https://psa.gov.ph/classification/psic"
  )
}

test_that("all 6 tiers resolve in priority order for one query hitting multiple tiers", {
  d <- make_fixture()
  res <- search_classification_data(d, "6201")
  # row7 ("Nothing related here", no description) must NOT appear.
  expect_equal(res$code, c("6201", "620199", "Z1", "Z2", "Z3", "Z4"))
})

test_that("exact code match ranks above code-prefix match", {
  d <- make_fixture()
  res <- search_classification_data(d, "6201")
  expect_equal(res$code[1], "6201")
  expect_equal(res$code[2], "620199")
})

test_that("code matches rank above label matches, which rank above description matches", {
  d <- make_fixture()
  res <- search_classification_data(d, "6201")
  tiers_in_order <- res$code
  # positions: code-exact, code-prefix, label-exact, label-prefix,
  # label-substring, description-substring
  expect_equal(which(tiers_in_order == "6201"), 1)
  expect_equal(which(tiers_in_order == "620199"), 2)
  expect_equal(which(tiers_in_order == "Z1"), 3)
  expect_equal(which(tiers_in_order == "Z2"), 4)
  expect_equal(which(tiers_in_order == "Z3"), 5)
  expect_equal(which(tiers_in_order == "Z4"), 6)
})

test_that("case-insensitivity works for code queries", {
  d <- make_fixture()
  res <- search_classification_data(d, "ABC123")
  expect_equal(res$code, "abc123")
})

test_that("case-insensitivity works for label queries", {
  d <- make_fixture()
  res <- search_classification_data(d, "CoMpUtEr PrOgRaMmInG")
  expect_true(all(c("A", "B") %in% res$code))
})

test_that("whitespace normalization: irregular-spaced label matches single-spaced query", {
  d <- make_fixture()
  res <- search_classification_data(d, "computer programming")
  # row 8's label is "Computer   Programming" (irregular internal spacing);
  # it must exact-match (tier 3) against the single-spaced query.
  row8 <- res[res$code == "A", ]
  expect_equal(nrow(row8), 1)
  # row 9's label starts with the (normalized) query -> tier 4.
  row9 <- res[res$code == "B", ]
  expect_equal(nrow(row9), 1)
  expect_true(which(res$code == "A") < which(res$code == "B"))
})

test_that("whitespace normalization: irregular-spaced query matches normally-spaced label", {
  d <- make_fixture()
  res <- search_classification_data(d, "computer    programming")
  expect_true("A" %in% res$code)
  expect_true("B" %in% res$code)
})

test_that("regex metacharacter in query (dot) matches literally, not as a wildcard", {
  d <- make_fixture()
  res <- search_classification_data(d, "01.1.1.11")
  expect_equal(res$code, "01.1.1.11")

  # If "." were treated as regex "any character", this garbled query would
  # also match. It must not.
  res2 <- search_classification_data(d, "01x1x1x11")
  expect_equal(nrow(res2), 0)
})

test_that("regex metacharacters in query (parentheses) match literal label text", {
  d <- make_fixture()
  res <- search_classification_data(d, "(household appliances)")
  expect_equal(res$code, "Z9")
})

test_that("level filtering restricts results to the requested level only", {
  d <- make_fixture()
  res <- search_classification_data(d, "6201", level = "section")
  expect_true(all(res$level == "section"))
  # row 6 (Z4) is level "sub-class" and must be excluded by the filter.
  expect_false("Z4" %in% res$code)
  expect_equal(res$code, c("6201", "620199", "Z1", "Z2", "Z3"))
})

test_that("level filtering to a nonexistent level returns zero rows without erroring", {
  d <- make_fixture()
  res <- search_classification_data(d, "6201", level = "does-not-exist")
  expect_equal(nrow(res), 0)
  expect_equal(names(res), CLASSIFICATION_SCHEMA_COLUMNS)
})

test_that("limit truncates results to the requested count while preserving tier order", {
  d <- make_fixture()
  res <- search_classification_data(d, "6201", limit = 3)
  expect_equal(nrow(res), 3)
  expect_equal(res$code, c("6201", "620199", "Z1"))
})

test_that("blank query ('') returns unranked data capped at limit", {
  d <- make_fixture()
  res <- search_classification_data(d, "", limit = 5)
  expect_equal(nrow(res), 5)
  expect_equal(res$code, d$code[1:5])
})

test_that("whitespace-only query returns unranked data capped at limit", {
  d <- make_fixture()
  res <- search_classification_data(d, "   ", limit = 3)
  expect_equal(nrow(res), 3)
  expect_equal(res$code, d$code[1:3])
})

test_that("NULL query returns unranked data capped at limit", {
  d <- make_fixture()
  res <- search_classification_data(d, NULL, limit = 4)
  expect_equal(nrow(res), 4)
  expect_equal(res$code, d$code[1:4])
})

test_that("NA query returns unranked data capped at limit", {
  d <- make_fixture()
  res <- search_classification_data(d, NA_character_, limit = 4)
  expect_equal(nrow(res), 4)
  expect_equal(res$code, d$code[1:4])
})

test_that("blank query respects level filtering", {
  d <- make_fixture()
  res <- search_classification_data(d, "", level = "class")
  expect_equal(nrow(res), 1)
  expect_equal(res$code, "01.1.1.11")
})

test_that("no-match query returns a zero-row tibble with correct columns, not an error or NULL", {
  d <- make_fixture()
  res <- search_classification_data(d, "zzz_no_such_thing_zzz")
  expect_equal(nrow(res), 0)
  expect_equal(names(res), CLASSIFICATION_SCHEMA_COLUMNS)
  expect_false(is.null(res))
})

test_that("a query matching only on code (not label/description) returns correctly", {
  d <- make_fixture()
  res <- search_classification_data(d, "01.1.1.11")
  expect_equal(nrow(res), 1)
  expect_equal(res$code, "01.1.1.11")
})

test_that("description with NA values does not crash substring matching", {
  d <- make_fixture()
  # Several fixture rows have description = NA; this search must not error.
  expect_error(search_classification_data(d, "6201"), NA)
  res <- search_classification_data(d, "more info")
  expect_equal(res$code, "Z4")
})

test_that("leading-zero code is matched literally on exact code search", {
  d <- new_classification_tibble(
    system = "pcoicop", version = "2026", level = "class",
    code = "01111", label = "Rice",
    status = "current", source = "Philippine Statistics Authority",
    source_url = "https://psa.gov.ph/classification/pcoicop"
  )
  res <- search_classification_data(d, "01111")
  expect_equal(res$code, "01111")
  expect_true(is.character(res$code))
})

test_that("leading-zero code is matched literally on code-prefix search, not numeric-coerced", {
  d <- new_classification_tibble(
    system = "pcoicop", version = "2026", level = "class",
    code = c("01111", "1111"), label = c("Rice", "Some other item"),
    status = "current", source = "Philippine Statistics Authority",
    source_url = "https://psa.gov.ph/classification/pcoicop"
  )
  res <- search_classification_data(d, "0111")
  # Only the code that literally starts with "0111" should match; "1111"
  # must NOT match even though 111 == 0111 numerically.
  expect_equal(res$code, "01111")
})

test_that("result is never NULL and never errors for an empty input tibble", {
  d <- make_fixture()[0, ]
  res <- search_classification_data(d, "anything")
  expect_false(is.null(res))
  expect_equal(nrow(res), 0)
  expect_equal(names(res), CLASSIFICATION_SCHEMA_COLUMNS)
})

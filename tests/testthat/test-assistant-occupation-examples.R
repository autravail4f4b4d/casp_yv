# C7: canonical example-occupation evidence.
#
# These pin BOTH the parser (against the real template wording variants
# found in the repository) and the discrimination it enables, without
# naming any query/code pair inside the implementation.

test_that("the parser reads the 'classified here' list and drops the 'elsewhere' list", {
  d <- paste(
    "Some prose about the group.",
    "Examples of the occupations classified here: Call center agent,",
    "Customer service representative",
    "Some related occupations classified elsewhere: Call center salesperson - 5244,",
    "Telephone operator - 4223"
  )
  ex <- assistant_parse_example_occupations(d)
  expect_true("Call center agent" %in% ex)
  expect_true("Customer service representative" %in% ex)
  # Anything after the "elsewhere" anchor belongs to a DIFFERENT code.
  expect_false(any(grepl("salesperson", ex, ignore.case = TRUE)))
  expect_false(any(grepl("Telephone operator", ex, fixed = TRUE)))
})

test_that("all measured template wording variants parse", {
  variants <- c(
    "Examples of the occupations classified here: Alpha, Beta",
    "Examples of the occupations classified here are: Alpha, Beta",
    "Example of the occupations classified here: Alpha, Beta"
  )
  for (v in variants) {
    ex <- assistant_parse_example_occupations(v)
    expect_true("Alpha" %in% ex, info = v)
    expect_true("Beta" %in% ex, info = v)
  }
})

test_that("both 'elsewhere' anchor variants are honoured", {
  for (anchor in c("Some related occupations classified elsewhere",
                   "A related occupations classified elsewhere")) {
    d <- paste0("Examples of the occupations classified here: Alpha ",
                anchor, ": Gamma - 9999")
    ex <- assistant_parse_example_occupations(d)
    expect_true("Alpha" %in% ex, info = anchor)
    expect_false(any(grepl("Gamma", ex, fixed = TRUE)), info = anchor)
  }
})

test_that("slash-packed examples yield both the whole phrase and its parts", {
  ex <- assistant_parse_example_occupations(
    "Examples of the occupations classified here: Mayor/Vice Mayor, Senator"
  )
  expect_true("Mayor/Vice Mayor" %in% ex)
  expect_true("Mayor" %in% ex)
  expect_true("Vice Mayor" %in% ex)
})

test_that("a description with no examples section yields nothing", {
  expect_length(assistant_parse_example_occupations("Just prose, no template."), 0L)
  expect_length(assistant_parse_example_occupations(NA_character_), 0L)
  expect_length(assistant_parse_example_occupations(""), 0L)
})

test_that("examples are available for current PSOC codes via the archived twin", {
  # PSOC 2022 carries no descriptions of its own; the evidence is borrowed
  # from the archived edition where code AND label are unchanged.
  expect_gt(length(assistant_example_occupations("psoc", "2022", "1111")), 0L)
  expect_gt(length(assistant_example_occupations("psoc", "2022", "4222")), 0L)
  expect_gt(length(assistant_example_occupations("psoc", "2022", "2122")), 0L)
})

test_that("scoring separates an exact example from a merely-contained one", {
  ex <- c("Call center agent", "Customer service representative")
  expect_equal(assistant_example_evidence_score("call center agent", ex),
               ASSISTANT_EXAMPLE_SCORE_EXACT)
  expect_equal(assistant_example_evidence_score("agent", ex),
               ASSISTANT_EXAMPLE_SCORE_SUBSET)
  expect_equal(assistant_example_evidence_score("welder", ex),
               ASSISTANT_EXAMPLE_SCORE_NONE)
})

test_that("mayor is canonically evidenced under 1111 and nowhere else in 111x", {
  for (code in c("1112", "1113", "1114")) {
    expect_equal(assistant_code_example_score("psoc", "2022", code, "mayor"),
                 ASSISTANT_EXAMPLE_SCORE_NONE, info = code)
  }
  expect_gt(assistant_code_example_score("psoc", "2022", "1111", "mayor"),
            ASSISTANT_EXAMPLE_SCORE_NONE)
})

test_that("the call-center pair is separated by example evidence alone", {
  info_q <- "call center agent"
  sales_q <- "call center sales agent"
  expect_gt(assistant_code_example_score("psoc", "2022", "4222", info_q),
            assistant_code_example_score("psoc", "2022", "5244", info_q))
  expect_gt(assistant_code_example_score("psoc", "2022", "5244", sales_q),
            assistant_code_example_score("psoc", "2022", "4222", sales_q))
})

test_that("statistician evidence points at 2122 and not at neighbouring groups", {
  expect_gt(assistant_code_example_score("psoc", "2022", "2122", "statistician"),
            ASSISTANT_EXAMPLE_SCORE_NONE)
  # 2631 Economists only CROSS-REFERENCES a statistician code; that must
  # not be read as evidence for 2631 itself.
  expect_equal(assistant_code_example_score("psoc", "2022", "2631", "statistician"),
               ASSISTANT_EXAMPLE_SCORE_NONE)
})

test_that("the example index can find codes lexical retrieval would miss", {
  hits <- assistant_codes_matching_examples("psoc", "2022", "city administrator")
  expect_true("1112" %in% hits$code)
  expect_false("1111" %in% hits$code)
})

test_that("example evidence never invents a code outside the repository", {
  hits <- assistant_codes_matching_examples("psoc", "2022", "mayor")
  expect_gt(nrow(hits), 0L)
  for (cd in hits$code) {
    expect_equal(nrow(get_classification_entry("psoc", "2022", cd)), 1L, info = cd)
  }
})

test_that("an unknown phrase matches no examples at all", {
  hits <- assistant_codes_matching_examples("psoc", "2022", "professional AI prompt engineer")
  expect_equal(nrow(hits), 0L)
})

# Tests for the assistant's supplementary knowledge artifacts and their
# accessors (R/assistant/assistant_data.R, built by
# scripts/build_assistant_assets.R).
#
# The emphasis is data integrity: codes must remain character strings with
# their leading zeros intact, the published "no fixed PSIC" rows must
# survive as NA rather than being filled or dropped, multi-code and range
# strings must be preserved verbatim, and the rule set must be a genuine
# compaction rather than the whole source document.

# Frozen contract, restated here on purpose so a change to the module's own
# constants cannot silently redefine what the tests check.
EXPECTED_PAIRINGS_COLUMNS <- c(
  "occupation", "confirmed_psoc", "source_industry", "original_psic",
  "psic_rev5_code", "psic_rev5_rule", "mapping_confidence", "mapping_note",
  "psa_source", "has_fixed_psic",
  "confirmed_psoc_label", "psoc_confidence", "psoc_provenance",
  "psoc_curation_note"
)

EXPECTED_PAIRINGS_CHARACTER_COLUMNS <-
  setdiff(EXPECTED_PAIRINGS_COLUMNS, "has_fixed_psic")

EXPECTED_RULES_COLUMNS <- c("topic", "title", "rule", "example")

EXPECTED_RULE_TOPICS <- c(
  "unit_of_classification", "economic_activity", "principal_activity",
  "secondary_activity", "ancillary_activity", "independent_mixed",
  "top_down_bottom_up", "horizontal_integration", "vertical_integration",
  "outsourced_subcontracted", "vague_information", "common_mistakes"
)

# Counts produced by the recorded build run of
# scripts/build_assistant_assets.R against
# data-raw/CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping.xlsx ("PSIC Rev5 Mapping").
BUILD_PAIRINGS_ROWS <- 253L
BUILD_NO_FIXED_PSIC_ROWS <- 44L

EN_DASH <- "–"


# ---------------------------------------------------------------------
# Artifacts load
# ---------------------------------------------------------------------

test_that("both built artifacts exist and load", {
  pairings <- assistant_common_pairings()
  rules <- assistant_psic_rules()

  expect_false(is.null(pairings))
  expect_false(is.null(rules))
  expect_s3_class(pairings, "data.frame")
  expect_s3_class(rules, "data.frame")
  expect_gt(nrow(pairings), 200)
  expect_equal(nrow(rules), length(EXPECTED_RULE_TOPICS))
})


# ---------------------------------------------------------------------
# Pairings: schema
# ---------------------------------------------------------------------

test_that("pairings match the frozen column contract exactly and in order", {
  pairings <- assistant_common_pairings()

  expect_identical(names(pairings), EXPECTED_PAIRINGS_COLUMNS)
  expect_equal(ncol(pairings), length(EXPECTED_PAIRINGS_COLUMNS))
})

test_that("every code-bearing pairings column is character, never numeric", {
  pairings <- assistant_common_pairings()

  for (col in EXPECTED_PAIRINGS_CHARACTER_COLUMNS) {
    expect_true(is.character(pairings[[col]]),
                info = paste0("column '", col, "' must be character"))
    # Explicitly guard the failure mode that destroys leading zeros.
    expect_false(is.numeric(pairings[[col]]),
                 info = paste0("column '", col, "' must not be numeric"))
    expect_false(is.factor(pairings[[col]]),
                 info = paste0("column '", col, "' must not be a factor"))
  }

  expect_true(is.logical(pairings$has_fixed_psic))
  expect_false(any(is.na(pairings$has_fixed_psic)))
})

test_that("pairings row count matches the recorded build", {
  expect_equal(nrow(assistant_common_pairings()), BUILD_PAIRINGS_ROWS)
})

test_that("every pairing row carries a confirmed 2022 PSOC code", {
  pairings <- assistant_common_pairings()

  expect_false(any(is.na(pairings$confirmed_psoc)))
  expect_false(any(trimws(pairings$confirmed_psoc) == ""))
})


# ---------------------------------------------------------------------
# Pairings: data integrity
# ---------------------------------------------------------------------

test_that("leading zeros on classification codes survive the build", {
  pairings <- assistant_common_pairings()

  zero_psic <- pairings$original_psic[grepl("^0", pairings$original_psic)]
  zero_rev5 <- pairings$psic_rev5_code[grepl("^0", pairings$psic_rev5_code)]

  # There really are leading-zero codes in this source (agriculture and
  # fishing divisions, e.g. "01121"). If none are found, the workbook was
  # read as numeric somewhere.
  expect_gt(length(zero_psic) + length(zero_rev5), 0)

  # Round-trip a concrete value: it must still start with "0" and must not
  # parse back to its own numeric rendering.
  sample_code <- c(zero_psic, zero_rev5)[1]
  expect_true(startsWith(sample_code, "0"))
  expect_true(is.character(sample_code))
  expect_false(identical(sample_code, as.character(suppressWarnings(
    as.numeric(sample_code)
  ))))
})

test_that("published 'no fixed PSIC' rows are preserved as NA, not filled or dropped", {
  pairings <- assistant_common_pairings()

  na_rows <- is.na(pairings$psic_rev5_code)

  expect_equal(sum(na_rows), BUILD_NO_FIXED_PSIC_ROWS)
  # has_fixed_psic is exactly the negation of NA-ness -- no other rows.
  expect_identical(pairings$has_fixed_psic, !na_rows)
  expect_equal(sum(!pairings$has_fixed_psic), BUILD_NO_FIXED_PSIC_ROWS)
  expect_equal(sum(pairings$has_fixed_psic),
               BUILD_PAIRINGS_ROWS - BUILD_NO_FIXED_PSIC_ROWS)

  # The NA must be a real NA, never an empty string or a placeholder that
  # would read as a code downstream.
  expect_true(all(is.na(pairings$psic_rev5_code[na_rows])))
  expect_false(any(pairings$psic_rev5_code[na_rows] %in% c("", "NA", "N/A"),
                   na.rm = TRUE))

  # These rows are still full rows: the occupation and PSOC survive.
  expect_false(any(is.na(pairings$occupation[na_rows])))
  expect_false(any(is.na(pairings$confirmed_psoc[na_rows])))
})

test_that("mapping_confidence is preserved with meaningful distinct values", {
  pairings <- assistant_common_pairings()

  values <- unique(pairings$mapping_confidence)
  values <- values[!is.na(values)]

  expect_gt(length(values), 1)
  expect_false(any(trimws(values) == ""))
  # The grades published in the source workbook.
  expect_true(all(c("High", "Medium", "Low") %in% values))
  expect_gt(sum(pairings$mapping_confidence == "High", na.rm = TRUE), 0)
})

test_that("multi-code and range strings survive verbatim", {
  pairings <- assistant_common_pairings()
  codes <- pairings$psic_rev5_code

  multi <- codes[grepl(" / ", codes, fixed = TRUE)]
  ranges <- codes[grepl(EN_DASH, codes, fixed = TRUE)]

  # Alternatives such as "96211 / 96220" must not have been split into
  # separate rows or reduced to a single pick.
  expect_gt(length(multi), 0)
  # Ranges such as "01171-01189" are published with an EN DASH (U+2013);
  # it must not have been normalized to an ASCII hyphen.
  expect_gt(length(ranges), 0)
  expect_true(any(grepl(EN_DASH, codes, fixed = TRUE)))

  # A verbatim string keeps its embedded whitespace layout.
  expect_true(all(grepl("^[^/]+( / [^/]+)+$", multi)))
})

test_that("text fields are trimmed and free of embedded newlines", {
  pairings <- assistant_common_pairings()

  for (col in EXPECTED_PAIRINGS_CHARACTER_COLUMNS) {
    values <- pairings[[col]]
    values <- values[!is.na(values)]
    if (length(values) == 0) next
    expect_identical(values, trimws(values),
                     info = paste0("column '", col, "' must be trimmed"))
    expect_false(any(grepl("[\r\n]", values)),
                 info = paste0("column '", col, "' must have no newlines"))
  }
})

test_that("source text is otherwise preserved verbatim, including curly apostrophes", {
  pairings <- assistant_common_pairings()

  # The source workbook writes "Gov't" with a curly apostrophe (U+2019).
  # Silent transliteration would mean the text was not preserved verbatim.
  expect_true(any(grepl("’", pairings$source_industry, fixed = TRUE)))
})


# ---------------------------------------------------------------------
# Rules artifact
# ---------------------------------------------------------------------

test_that("rules match the frozen column contract", {
  rules <- assistant_psic_rules()

  expect_identical(names(rules), EXPECTED_RULES_COLUMNS)
  for (col in EXPECTED_RULES_COLUMNS) {
    expect_true(is.character(rules[[col]]),
                info = paste0("column '", col, "' must be character"))
  }
})

test_that("all 12 rule topics are present, exactly once, with the contract keys", {
  rules <- assistant_psic_rules()

  expect_equal(nrow(rules), 12L)
  expect_setequal(rules$topic, EXPECTED_RULE_TOPICS)
  expect_equal(anyDuplicated(rules$topic), 0L)
  expect_false(any(is.na(rules$topic)))
})

test_that("every rule has a non-empty title and rule body", {
  rules <- assistant_psic_rules()

  expect_false(any(is.na(rules$title)))
  expect_false(any(trimws(rules$title) == ""))
  expect_false(any(is.na(rules$rule)))
  expect_false(any(trimws(rules$rule) == ""))
})

test_that("rule bodies are compacted, not pasted source sections", {
  rules <- assistant_psic_rules()
  rule_chars <- nchar(rules$rule, type = "chars")

  # Compaction ceiling: an entry over this is a copied section, not a
  # distillation.
  expect_true(all(rule_chars < 2000),
              info = paste("over-long topics:",
                           paste(rules$topic[rule_chars >= 2000], collapse = ", ")))
  # ...but each must still carry substantive decision logic.
  expect_true(all(rule_chars > 200))
})

test_that("the rules artifact does not embed the whole source document", {
  rules <- assistant_psic_rules()

  total_chars <- sum(nchar(rules$rule, type = "chars")) +
    sum(nchar(rules$example, type = "chars"), na.rm = TRUE)

  # The source PSIC_Chatbot_Classification_Rules.md is ~55,000 characters.
  # The runtime artifact must be a small fraction of that -- shipping the
  # full document to the model on every turn is what it exists to avoid.
  expect_lt(total_chars, 20000)

  # The excluded speaker-note / slide appendices must not have leaked in.
  all_text <- paste(c(rules$rule, rules$example[!is.na(rules$example)]),
                    collapse = " ")
  expect_false(grepl("Speaker Notes", all_text, fixed = TRUE))
  expect_false(grepl("Slide ", all_text, fixed = TRUE))
})

test_that("examples are either real text or NA, never empty strings", {
  rules <- assistant_psic_rules()

  supplied <- rules$example[!is.na(rules$example)]
  expect_gt(length(supplied), 0)
  expect_false(any(trimws(supplied) == ""))
})

test_that("operative rule content is retained for key topics", {
  rules <- assistant_psic_rules()
  get_rule <- function(key) rules$rule[rules$topic == key]

  # Value added is THE principal-activity criterion; losing it would make
  # the compaction useless.
  expect_true(grepl("value added", get_rule("principal_activity"),
                    ignore.case = TRUE))
  # The vague-information topic's operative content is its probing
  # questions -- they must have survived compaction.
  expect_true(grepl("\\?", get_rule("vague_information")))
  # Horizontal integration's rule is same-subclass, not principal activity.
  expect_true(grepl("subclass", get_rule("horizontal_integration"),
                    ignore.case = TRUE))
  # The hard prohibitions must remain prohibitions.
  expect_true(grepl("not", get_rule("common_mistakes"), ignore.case = TRUE))
})


# ---------------------------------------------------------------------
# Synonyms: correctly unavailable in V1
# ---------------------------------------------------------------------

test_that("assistant_synonyms() returns NULL while no approved source exists", {
  expect_null(assistant_synonyms())
})


# ---------------------------------------------------------------------
# Status reporting and graceful degradation
# ---------------------------------------------------------------------

test_that("assistant_data_status() reports the real availability of each artifact", {
  status <- assistant_data_status()

  expect_type(status, "list")
  expect_setequal(names(status), c("common_pairings", "psic_rules", "synonyms"))
  expect_true(all(vapply(status, is.logical, logical(1))))
  expect_true(all(vapply(status, length, integer(1)) == 1L))

  expect_true(status$common_pairings)
  expect_true(status$psic_rules)
  expect_false(status$synonyms)
})

test_that("a missing artifact degrades to NULL rather than erroring", {
  missing_path <- file.path(tempdir(), "assistant_definitely_missing.rds")
  if (file.exists(missing_path)) unlink(missing_path)

  # Degradation is mandatory: the assistant must keep working against
  # official classification search when a supplementary artifact is gone.
  expect_silent(p <- assistant_common_pairings(data_path = missing_path))
  expect_null(p)

  # Rules included: the CALLER is responsible for telling the user that
  # detailed PSIC rule assistance is unavailable. The accessor must not
  # error, and must never substitute anything for the missing artifact.
  expect_silent(r <- assistant_psic_rules(data_path = missing_path))
  expect_null(r)

  expect_silent(s <- assistant_synonyms(data_path = missing_path))
  expect_null(s)
})

test_that("an explicit data_path is honoured exactly, with no fallback search", {
  # The real artifact resolves by default...
  expect_false(is.null(assistant_common_pairings()))
  # ...but an explicit bad path must not quietly fall back to it.
  expect_null(assistant_common_pairings(
    data_path = file.path(tempdir(), "nope", "assistant_common_pairings.rds")
  ))
})

test_that("artifacts are memoized so the RDS is read once per process", {
  .assistant_data_reset_cache()

  first <- assistant_common_pairings()
  expect_false(is.null(first))

  # Identical object back on the second call, without touching disk.
  second <- assistant_common_pairings()
  expect_identical(first, second)

  rules_first <- assistant_psic_rules()
  rules_second <- assistant_psic_rules()
  expect_identical(rules_first, rules_second)

  # The cache holds entries rather than being a no-op.
  expect_gt(length(ls(.assistant_data_cache)), 0)
})

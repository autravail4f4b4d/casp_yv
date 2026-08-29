# W1-B: slot decomposition contract and controlled candidate-generation
# vocabulary.

test_that("expansion always keeps the user's own wording first", {
  out <- assistant_expand_query("nurse")
  expect_identical(out[[1L]], "nurse")
  expect_true("nursing" %in% out)
})

test_that("expansion fires on a whole phrase and on individual tokens", {
  expect_true("rice farmer" %in% assistant_expand_query("palay farmer"))
  expect_true("rice" %in% assistant_expand_query("palay"))
  expect_true("secondary education" %in% assistant_expand_query("high school"))
})

test_that("an unknown phrase expands to itself only, never to something invented", {
  out <- assistant_expand_query("professional AI prompt engineer")
  expect_identical(out, "professional AI prompt engineer")
})

test_that("the controlled vocabulary maps words to words, never to codes", {
  # A code-shaped expansion would move authority out of the canonical
  # repository, which the specification forbids outright.
  all_targets <- unlist(ASSISTANT_QUERY_EXPANSIONS, use.names = FALSE)
  expect_false(any(grepl("^[0-9]", all_targets)))
  expect_false(any(grepl("^[A-Z]$", all_targets)))
})

test_that("no expansion maps an occupation to an industry activity", {
  # Guards the "no giant occupation -> industry lookup table" rule: an
  # expansion target must never be phrased as an establishment activity.
  all_targets <- unlist(ASSISTANT_QUERY_EXPANSIONS, use.names = FALSE)
  expect_false(any(grepl("activities of |manufacture of |public administration",
                         all_targets, ignore.case = TRUE)))
})

test_that("supplying an establishment activity means no clarification is needed", {
  s <- assistant_slot_contract("nurse", "private hospital")
  expect_identical(s$occupation_query, "nurse")
  expect_identical(s$psic_activity_query, "private hospital")
  expect_true(s$context_known)
  expect_false(s$needs_psic_clarification)
  expect_true(is.na(s$clarification_reason))
})

test_that("omitting the establishment activity always demands clarification", {
  s <- assistant_slot_contract("carpenter", NULL)
  expect_identical(s$occupation_query, "carpenter")
  expect_true(is.na(s$psic_activity_query))
  expect_false(s$context_known)
  expect_true(s$needs_psic_clarification)
  expect_match(s$clarification_reason, "cannot be determined from the occupation alone")
})

test_that("a blank establishment activity is treated as absent, not as context", {
  for (blank in list(NULL, "", "   ", NA_character_)) {
    s <- assistant_slot_contract("carpenter", blank)
    expect_true(s$needs_psic_clarification)
  }
})

test_that("clarification asks about real-world facts, never about codes", {
  q <- assistant_establishment_question("carpenter")
  expect_match(q, "carpenter", fixed = TRUE)
  expect_match(q, "main activity", ignore.case = TRUE)
  # The user must not need to know the classification system to answer.
  expect_false(grepl("PSIC|PSOC|code", q, ignore.case = TRUE))
  for (generic in ASSISTANT_ESTABLISHMENT_QUESTIONS) {
    expect_false(grepl("PSIC|PSOC|which code", generic, ignore.case = TRUE), info = generic)
  }
})

test_that("establishment hints are detected only when a workplace is actually named", {
  expect_false(assistant_phrase_has_establishment_hint("nurse"))
  expect_false(assistant_phrase_has_establishment_hint("carpenter"))
  expect_true(assistant_phrase_has_establishment_hint("nurse in a private hospital"))
  expect_true(assistant_phrase_has_establishment_hint("teacher in private high school"))
})

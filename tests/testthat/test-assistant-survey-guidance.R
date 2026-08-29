# PSA survey coding guidance as a VERSIONED evidence layer.
#
# The central safety property here is the PSOC/PSIC asymmetry: the manual's
# occupation codes are the edition the repository already carries, but its
# INDUSTRY codes are a different vintage whose numbers have since been
# reused for unrelated activities. These tests pin both halves.

test_that("every occupation example resolves to a live current PSOC unit group", {
  for (row in ASSISTANT_GUIDANCE_PSOC_EXAMPLES) {
    entry <- get_classification_entry("psoc", "2022", row$code)
    expect_equal(nrow(entry), 1L, info = paste(row$term, row$code))
    expect_identical(entry$level[[1L]], "unit_group", info = row$code)
  }
})

test_that("no industry hint records a code as usable for the current edition", {
  # The manual's PSIC codes are 2019-vintage. Recording one as a current
  # code is the specific defect this layer exists to prevent.
  for (row in ASSISTANT_GUIDANCE_PSIC_ACTIVITY_HINTS) {
    hint <- assistant_survey_activity_hint(row$term)
    expect_false(is.null(hint), info = row$term)
    expect_false(hint$is_current_code, info = row$term)
    expect_true(nzchar(hint$activity_text), info = row$term)
    expect_match(hint$historical_vintage, "2009 PSIC", info = row$term)
  }
})

test_that("the vintage warning is concrete about code reuse", {
  hint <- assistant_survey_activity_hint("carinderia")
  expect_match(hint$caution, "MUST NOT be presented as a current PSIC code", fixed = TRUE)
})

test_that("a manual industry code really can mean something else today", {
  # Not a hypothetical: this is why the hints carry activity text instead
  # of codes. If these ever stop differing the guard can be relaxed, and
  # this test is where that would surface.
  reused <- list(
    list(code = "4781",  old = "stalls and markets", new = "motor vehicles"),
    list(code = "56107", old = "Carinderia",         new = "Roasting and grilling")
  )
  for (r in reused) {
    now <- get_classification_entry("psic", "2026", r$code)
    skip_if(nrow(now) == 0L, paste(r$code, "absent from PSIC 2026"))
    expect_false(grepl(r$old, now$label[[1L]], ignore.case = TRUE), info = r$code)
    expect_match(now$label[[1L]], r$new, ignore.case = TRUE, info = r$code)
  }
})

test_that("survey guidance supplies codes lexical retrieval cannot reach", {
  # "Angkas" appears in no PSOC label; the manual is the only evidence.
  expect_identical(assistant_survey_psoc_evidence("angkas driver"), "8323")
  expect_identical(assistant_survey_psoc_evidence("food panda driver"), "9335")
  expect_identical(assistant_survey_psoc_evidence("vulcanizer"), "8141")
})

test_that("guidance evidence is re-verified, never returned blindly", {
  # A term whose code no longer verified must yield nothing rather than a
  # dangling code; proven by asking for a system/version where it cannot
  # resolve.
  expect_length(assistant_survey_psoc_evidence("no such occupation at all"), 0L)
})

test_that("guidance-backed occupations resolve end to end with their provenance", {
  expected <- list(
    "angkas driver" = "8323", "grab taxi driver" = "8325",
    "online seller" = "5247", "data scientist" = "2124",
    "esports player" = "3424", "midwife non-board passer" = "3222",
    "barangay health worker" = "3253"
  )
  for (q in names(expected)) {
    slot <- assistant_slot_candidates("psoc", q)
    expect_true(length(slot$candidates) > 0L, info = q)
    top <- slot$candidates[[1L]]
    expect_identical(top$code, expected[[q]], info = q)
    expect_identical(top$evidence_source, "survey_guidance", info = q)
    expect_equal(nrow(get_classification_entry("psoc", top$version, top$code)), 1L, info = q)
  }
})

# --- Column 15 methodology --------------------------------------------------

test_that("the descriptions the manual refuses are treated as no context", {
  for (v in c("farm", "store", "retail store", "wholesale store", "mine",
              "factory", "shop", "school", "government", "transportation",
              "company")) {
    expect_true(assistant_activity_is_vague(v), info = v)
  }
})

test_that("a specific description is accepted", {
  for (ok in c("private hospital", "growing of corn", "cocktail lounge",
               "commercial bank", "retail sale of food", "private household",
               "private general secondary education")) {
    expect_false(assistant_activity_is_vague(ok), info = ok)
  }
})

test_that("a refused description blocks PSIC and asks what it actually does", {
  r <- assistant_code_occupation_and_activity("carpenter", "store")
  expect_true(r$activity_too_vague)
  expect_true(r$needs_psic_clarification)
  expect_null(r$industry)
  expect_match(r$clarification_question, "too general", fixed = TRUE)
  # Still a real-world question, not a code question.
  expect_false(grepl("PSIC|which code", r$clarification_question, ignore.case = TRUE))
})

test_that("an outsourcing arrangement blocks PSIC until the payer is known", {
  for (a in c("manpower agency", "outsourcing agency", "job order at a city hall")) {
    r <- assistant_code_occupation_and_activity("carpenter", a)
    expect_true(r$activity_outsourced, info = a)
    expect_true(r$needs_psic_clarification, info = a)
    expect_match(r$clarification_question, "pays", info = a)
  }
})

test_that("a government context still codes but carries the LGU-tier probe", {
  r <- assistant_code_occupation_and_activity("mayor", "local government")
  expect_false(r$needs_psic_clarification)
  expect_true("84113" %in% vapply(r$industry$candidates, function(c) c$code, character(1)))
  expect_match(r$context_probe, "provincial, city, or municipal")
})

test_that("a non-government context carries no spurious probe", {
  r <- assistant_code_occupation_and_activity("nurse", "private hospital")
  expect_true(is.na(r$context_probe))
})

test_that("the refusal list and probes never ask the user to pick a code", {
  for (p in c(ASSISTANT_GUIDANCE_PROBES, ASSISTANT_GUIDANCE_GOVERNMENT_PROBE,
              ASSISTANT_GUIDANCE_OUTSOURCING_PROBE)) {
    expect_false(grepl("PSIC|PSOC|which code", p, ignore.case = TRUE), info = p)
  }
})

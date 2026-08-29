# G2: contextual resolver, plus the transcript-derived regression corpus.
#
# Every expected code in the corpus was independently verified against the
# canonical repository before being written down (see the `provenance`
# column); the first test below re-proves that on every run, so the corpus
# can never drift into asserting a code the repository does not carry.

.rmc_cases <- function() {
  path <- testthat::test_path("..", "..", "data-raw", "rm_contextual_coding_eval_cases.csv")
  skip_if_not(file.exists(path), "contextual coding corpus missing")
  utils::read.csv(path, colClasses = "character", stringsAsFactors = FALSE)
}

.codes_of <- function(slot) {
  if (is.null(slot) || length(slot$candidates) == 0L) return(character(0))
  vapply(slot$candidates, function(c) c$code, character(1))
}

# ---------------------------------------------------------------------------
# Corpus integrity
# ---------------------------------------------------------------------------

test_that("the corpus loads with the documented columns and unique case ids", {
  cases <- .rmc_cases()
  expect_gt(nrow(cases), 0L)
  expect_true(all(c(
    "case_id", "query", "occupation_slot", "establishment_slot",
    "expected_psoc_code", "expected_psoc_level", "expected_psoc_role",
    "expected_psic_code", "expected_psic_level", "expected_psic_role",
    "expected_behavior", "requires_psic_clarification",
    "requires_psic_detail_clarification", "context_type",
    "notes", "provenance"
  ) %in% names(cases)))
  expect_false(any(duplicated(cases$case_id)))
})

test_that("expected coding roles in the corpus match the canonical role", {
  cases <- .rmc_cases()
  for (i in seq_len(nrow(cases))) {
    for (sys in c("psoc", "psic")) {
      code <- trimws(cases[[paste0("expected_", sys, "_code")]][[i]])
      role <- trimws(cases[[paste0("expected_", sys, "_role")]][[i]])
      if (!nzchar(code) || !nzchar(role)) next
      r <- assistant_coding_level(sys, NULL, code)
      expect_identical(r$coding_role, role,
                       info = paste(cases$case_id[[i]], sys, code))
    }
  }
})

test_that("expected PSIC levels in the corpus match the canonical level", {
  cases <- .rmc_cases()
  for (i in seq_len(nrow(cases))) {
    code <- trimws(cases$expected_psic_code[[i]])
    lvl <- trimws(cases$expected_psic_level[[i]])
    if (!nzchar(code) || !nzchar(lvl)) next
    r <- assistant_coding_level("psic", "2026", code)
    expect_identical(r$classification_level, lvl, info = cases$case_id[[i]])
  }
})

test_that("no corpus expectation is a wildcard or pseudo code", {
  # Guards the '0112x' class of defect: only exact canonical codes may
  # ever be written down as an expectation.
  cases <- .rmc_cases()
  codes <- c(cases$expected_psoc_code, cases$expected_psic_code)
  codes <- trimws(codes[nzchar(trimws(codes))])
  expect_false(any(grepl("[xX*#]$", codes)))
  expect_false(any(grepl("[^0-9A-Za-z.-]", codes)))
})

test_that("every expected code in the corpus resolves in the canonical repository", {
  cases <- .rmc_cases()
  for (i in seq_len(nrow(cases))) {
    psoc <- trimws(cases$expected_psoc_code[[i]])
    psic <- trimws(cases$expected_psic_code[[i]])
    if (nzchar(psoc)) {
      expect_equal(nrow(get_classification_entry("psoc", "2022", psoc)), 1L,
                   info = paste(cases$case_id[[i]], "psoc", psoc))
    }
    if (nzchar(psic)) {
      expect_equal(nrow(get_classification_entry("psic", "2026", psic)), 1L,
                   info = paste(cases$case_id[[i]], "psic", psic))
    }
  }
})

test_that("expected PSOC levels in the corpus match the canonical level", {
  cases <- .rmc_cases()
  for (i in seq_len(nrow(cases))) {
    code <- trimws(cases$expected_psoc_code[[i]])
    lvl <- trimws(cases$expected_psoc_level[[i]])
    if (!nzchar(code) || !nzchar(lvl)) next
    r <- assistant_coding_level("psoc", "2022", code)
    expect_identical(r$classification_level, lvl, info = cases$case_id[[i]])
  }
})

# ---------------------------------------------------------------------------
# Slot separation -- the structural fix
# ---------------------------------------------------------------------------

test_that("the tool takes occupation and activity as separate arguments", {
  fmls <- names(formals(assistant_code_occupation_and_activity))
  expect_true("occupation" %in% fmls)
  expect_true("establishment_activity" %in% fmls)
  # There must be no single free-text field that could carry a whole
  # undecomposed sentence to both systems.
  expect_false(any(c("query", "text", "question") %in% fmls))
})

test_that("an occupation alone never produces a guessed PSIC", {
  r <- assistant_code_occupation_and_activity("carpenter")
  expect_false(r$context_known)
  expect_true(r$needs_psic_clarification)
  expect_null(r$industry)
  expect_true(nzchar(r$clarification_question))
})

test_that("PSOC and PSIC are resolved from their own slots only", {
  r <- assistant_code_occupation_and_activity("corn farmer", "growing of corn")
  expect_identical(r$occupation$system, "psoc")
  expect_identical(r$industry$system, "psic")
  expect_identical(r$occupation$query, "corn farmer")
  expect_identical(r$industry$query, "growing of corn")
})

# ---------------------------------------------------------------------------
# Transcript regression cases
# ---------------------------------------------------------------------------

test_that("corn farmer resolves both slots (staging failure RMC-005)", {
  r <- assistant_code_occupation_and_activity("corn farmer", "growing of corn")
  expect_true("6112" %in% .codes_of(r$occupation))
  expect_true("01130" %in% .codes_of(r$industry))
})

test_that("nurse rejects the nursery grower and resolves nursing (RMC-006/018)", {
  r <- assistant_code_occupation_and_activity("nurse", "private hospital")
  occ <- .codes_of(r$occupation)
  expect_false("6118" %in% occ)
  expect_identical(occ[[1L]], "2221")
  expect_gte(r$occupation$rejected_incompatible, 1L)
  expect_true("8612" %in% .codes_of(r$industry))
})

test_that("secondary teacher reaches secondary education on both sides (RMC-007)", {
  r <- assistant_code_occupation_and_activity(
    "secondary education teacher", "private general secondary education"
  )
  expect_identical(.codes_of(r$occupation)[[1L]], "2330")
  expect_true("85312" %in% .codes_of(r$industry))
})

test_that("barangay health worker resolves PSOC but clarifies PSIC (RMC-008)", {
  r <- assistant_code_occupation_and_activity("barangay health worker")
  expect_identical(.codes_of(r$occupation)[[1L]], "3253")
  expect_true(r$needs_psic_clarification)
  expect_null(r$industry)
})

# ---------------------------------------------------------------------------
# BHW: "health worker" and "health aide" are DIFFERENT occupations
# ---------------------------------------------------------------------------
#
# PSOC separates community-based health work (3253 COMMUNITY HEALTH
# WORKERS) from institution-based patient-care assistance (5321 HEALTH
# CARE ASSISTANTS, whose canonical example list contains "Barangay health
# aide"). A future synonym edit that collapses worker <-> aide would
# silently merge two real occupations, so the split is pinned here.

test_that("the BHW wording and the health-aide wording resolve to different codes", {
  worker <- assistant_slot_candidates("psoc", "barangay health worker")
  aide <- assistant_slot_candidates("psoc", "barangay health aide")

  expect_identical(worker$candidates[[1L]]$code, "3253")
  expect_identical(aide$candidates[[1L]]$code, "5321")
  expect_false(identical(worker$candidates[[1L]]$code, aide$candidates[[1L]]$code))
})

test_that("the BHW acronym reaches the worker code, not the aide code", {
  for (q in c("BHW", "bhw")) {
    top <- assistant_slot_candidates("psoc", q)$candidates[[1L]]$code
    expect_identical(top, "3253", info = q)
  }
})

test_that("the neighbouring control terms keep their own codes", {
  expect_identical(
    assistant_slot_candidates("psoc", "community health worker")$candidates[[1L]]$code,
    "3253"
  )
  expect_identical(
    assistant_slot_candidates("psoc", "health care assistant")$candidates[[1L]]$code,
    "5321"
  )
})

test_that("the controlled vocabulary never equates worker with aide", {
  # The expansion of any "worker" wording must not introduce "aide", and
  # vice versa -- that is the specific edit that would merge 3253 and 5321.
  for (q in c("barangay health worker", "community health worker", "bhw")) {
    expect_false(any(grepl("aide", assistant_expand_query(q), ignore.case = TRUE)),
                 info = q)
  }
  expect_false(any(grepl("\\bworker", assistant_expand_query("barangay health aide"),
                         ignore.case = TRUE)))
})

test_that("BHW pairing evidence agrees with the resolver and is marked curated", {
  res <- assistant_search_common_pairings(occupation = "Barangay Health Worker")
  skip_if(isFALSE(res$available), "pairings artifact unavailable")
  hit <- Filter(function(r) grepl("Barangay Health Worker", r$occupation, fixed = TRUE),
                res$results)
  expect_gte(length(hit), 1L)
  expect_identical(hit[[1L]]$confirmed_psoc, "3253")
  expect_identical(hit[[1L]]$psoc_provenance, "curated")
  # And the curated code is a real current-edition entry.
  expect_equal(nrow(get_classification_entry("psoc", "2022", "3253")), 1L)
})

test_that("BHW paired coding never infers an industry from the title", {
  # Neither "barangay" nor "health" in the occupation may select a PSIC.
  r <- assistant_code_occupation_and_activity("barangay health worker")
  expect_null(r$industry)
  expect_true(r$needs_psic_clarification)
  expect_false(grepl("84113|8610|8620", r$clarification_question))
  expect_match(r$clarification_question, "main activity", ignore.case = TRUE)
})

test_that("archived example evidence is labelled as such and never changes the edition", {
  aide <- assistant_slot_candidates("psoc", "barangay health aide")
  top <- aide$candidates[[1L]]
  expect_identical(top$evidence_source, "archived_example")
  # The presented code/label/version remain the CURRENT edition's own.
  expect_identical(top$version, "2022")
  entry <- get_classification_entry("psoc", "2022", top$code)
  expect_equal(nrow(entry), 1L)
  expect_identical(top$label, entry$label[[1L]])
})

test_that("a current-label match is not mislabelled as archived evidence", {
  # "corn farmer" is named neither in an archived example list nor in the
  # PSA survey manual, so it must resolve on the current label alone.
  cf <- assistant_slot_candidates("psoc", "corn farmer")
  expect_identical(cf$candidates[[1L]]$code, "6112")
  expect_identical(cf$candidates[[1L]]$evidence_source, "current_label")
})

test_that("survey-manual provenance outranks the archived-example label", {
  # "community health worker" is named directly in the PSA manual, so its
  # provenance must be the manual rather than a borrowed archived example.
  worker <- assistant_slot_candidates("psoc", "community health worker")
  expect_identical(worker$candidates[[1L]]$code, "3253")
  expect_identical(worker$candidates[[1L]]$evidence_source, "survey_guidance")
})

test_that("mayor resolves to 1111 LEGISLATORS, not 1112 (RMC-009)", {
  r <- assistant_code_occupation_and_activity("mayor", "local government")
  expect_identical(.codes_of(r$occupation)[[1L]], "1111")
  expect_true("84113" %in% .codes_of(r$industry))
})

test_that("vice mayor resolves to the same canonical example entry (RMC-009b)", {
  r <- assistant_code_occupation_and_activity("vice mayor")
  expect_identical(.codes_of(r$occupation)[[1L]], "1111")
})

test_that("city administrator is NOT generalized to 1111 (RMC-009c)", {
  # The negative control for the mayor fix: local-government officials are
  # not all Legislators, and the example lists say so.
  r <- assistant_code_occupation_and_activity("city administrator")
  expect_identical(.codes_of(r$occupation)[[1L]], "1112")
})

test_that("statistician resolves to 2122 (RMC-015)", {
  r <- assistant_code_occupation_and_activity("statistician")
  expect_identical(.codes_of(r$occupation)[[1L]], "2122")
  # PSIC still may not be inferred from the occupation.
  expect_true(r$needs_psic_clarification)
  expect_null(r$industry)
})

test_that("call center agent resolves to 4222, sales wording to 5244 (RMC-011/011b/011c)", {
  info <- assistant_code_occupation_and_activity("call center agent", "call center activities")
  expect_identical(.codes_of(info$occupation)[[1L]], "4222")
  expect_true("82200" %in% .codes_of(info$industry))

  sales <- assistant_code_occupation_and_activity("call center sales agent")
  expect_identical(.codes_of(sales$occupation)[[1L]], "5244")

  tm <- assistant_code_occupation_and_activity("telemarketer")
  expect_identical(.codes_of(tm$occupation)[[1L]], "5244")
})

test_that("carpenter resolves PSOC and asks, instead of dumping industries (RMC-010)", {
  r <- assistant_code_occupation_and_activity("carpenter")
  expect_identical(.codes_of(r$occupation)[[1L]], "7115")
  expect_null(r$industry)
  expect_match(r$clarification_question, "main activity", ignore.case = TRUE)
})

test_that("call center agent surfaces both canonical occupations (RMC-011)", {
  r <- assistant_code_occupation_and_activity("call center agent", "call center activities")
  occ <- .codes_of(r$occupation)
  expect_true(all(c("4222", "5244") %in% occ))
  expect_true("82200" %in% .codes_of(r$industry))
})

test_that("palay farmer resolves PSOC and asks before a detailed PSIC sub-class (RMC-012)", {
  r <- assistant_code_occupation_and_activity("palay farmer", "growing of rice")
  expect_identical(.codes_of(r$occupation)[[1L]], "6111")
  # Generic palay growing supports the CLASS only; the irrigated/rainfed/
  # upland distinction has to be asked for.
  expect_true(r$industry$detail_clarification_needed)
  expect_identical(r$industry$supported_aggregate_code, "0112")
})

test_that("naming the water regime settles the palay sub-class without asking (RMC-012b/c/d)", {
  expected <- list(
    "growing of rice in irrigated lowland" = "01121",
    "growing of rice in rainfed lowland"   = "01122",
    "growing of rice in upland"            = "01123"
  )
  for (activity in names(expected)) {
    r <- assistant_code_occupation_and_activity("palay farmer", activity)
    expect_identical(.codes_of(r$industry)[[1L]], expected[[activity]], info = activity)
    expect_false(r$industry$detail_clarification_needed, info = activity)
  }
})

test_that("corn is the control case: one sub-class means no clarification (RMC-005)", {
  # PSIC 0113 has exactly ONE sub-class, so asking would be pointless. This
  # is what proves the resolver reads the canonical hierarchy rather than
  # always asking about agriculture.
  r <- assistant_code_occupation_and_activity("corn farmer", "growing of corn")
  expect_identical(.codes_of(r$occupation)[[1L]], "6112")
  expect_identical(.codes_of(r$industry)[[1L]], "01130")
  expect_false(r$industry$detail_clarification_needed)
  expect_equal(nrow(get_classification_entry("psic", "2026", "01130")), 1L)
})

test_that("generic private hospital yields the aggregate plus a detail question (RMC-006)", {
  r <- assistant_code_occupation_and_activity("nurse", "private hospital")
  expect_identical(.codes_of(r$occupation)[[1L]], "2221")
  expect_true(r$industry$detail_clarification_needed)
  expect_identical(r$industry$supported_aggregate_code, "8612")
})

test_that("naming the hospital type settles the sub-class without asking (RMC-006b)", {
  r <- assistant_code_occupation_and_activity("nurse", "private general hospital")
  expect_identical(.codes_of(r$occupation)[[1L]], "2221")
  expect_identical(.codes_of(r$industry)[[1L]], "86121")
  expect_false(r$industry$detail_clarification_needed)
})

test_that("no pseudo or wildcard code can reach a final result", {
  # '0112x' was written into an earlier report as though it were a code.
  # Every code the resolver emits must be an exact canonical row.
  queries <- list(
    list("palay farmer", "growing of rice"),
    list("nurse", "private hospital"),
    list("corn farmer", "growing of corn"),
    list("mayor", "local government")
  )
  for (q in queries) {
    r <- assistant_code_occupation_and_activity(q[[1]], q[[2]])
    for (slot in list(r$occupation, r$industry)) {
      if (is.null(slot)) next
      for (cand in slot$candidates) {
        expect_false(grepl("[xX*#]$", cand$code), info = cand$code)
        expect_equal(nrow(get_classification_entry(slot$system, slot$version, cand$code)),
                     1L, info = cand$code)
      }
      agg <- slot$supported_aggregate_code
      if (!is.na(agg)) {
        expect_equal(nrow(get_classification_entry(slot$system, slot$version, agg)), 1L,
                     info = agg)
      }
    }
  }
})

test_that("mananagat surfaces the canonical fishery alternatives (RMC-013)", {
  r <- assistant_code_occupation_and_activity("mananagat")
  occ <- .codes_of(r$occupation)
  expect_true(length(intersect(occ, c("6226", "6227", "6229"))) >= 2L)
})

test_that("an occupation with no authoritative code abstains (RMC-016)", {
  r <- assistant_code_occupation_and_activity("professional AI prompt engineer")
  expect_equal(r$occupation$count, 0L)
  expect_length(r$occupation$candidates, 0L)
})

# ---------------------------------------------------------------------------
# Coding-level policy inside the resolver
# ---------------------------------------------------------------------------

test_that("occupation coding ranks the detailed Unit Group above its ancestor", {
  r <- assistant_code_occupation_and_activity("heavy truck driver")
  occ <- .codes_of(r$occupation)
  expect_identical(occ[[1L]], "8332")
  if ("833" %in% occ) {
    expect_gt(which(occ == "833"), which(occ == "8332"))
  }
})

test_that("every returned candidate carries its level and coding role", {
  r <- assistant_code_occupation_and_activity("nurse", "private hospital")
  for (c in c(r$occupation$candidates, r$industry$candidates)) {
    expect_true(nzchar(c$level_display))
    expect_true(c$coding_role %in% ASSISTANT_CODING_ROLES)
  }
})

test_that("every returned candidate is a real canonical record", {
  r <- assistant_code_occupation_and_activity("corn farmer", "growing of corn")
  for (c in r$occupation$candidates) {
    expect_equal(nrow(get_classification_entry("psoc", c$version, c$code)), 1L, info = c$code)
  }
  for (c in r$industry$candidates) {
    expect_equal(nrow(get_classification_entry("psic", c$version, c$code)), 1L, info = c$code)
  }
})

test_that("the guidance never calls the PSIC a corresponding code for the occupation", {
  r <- assistant_code_occupation_and_activity("nurse", "private hospital")
  expect_match(r$guidance, "never label the PSIC a 'corresponding code'", fixed = TRUE)
})

# Regression tests for the approved curated occupation -> PSOC 2022
# corrections.
#
# These four occupations were graded Low confidence by the CBMS 2024
# mapping workbook and were reviewed manually. Three were corrected; the
# fourth (Truck Driver) was confirmed at the code the workbook already
# carried, with only its confidence raised. The tests below pin all four
# outcomes, the provenance/confidence bookkeeping that goes with them, and
# the separation between occupation and industry that a curated PSOC
# override must never disturb.
#
# The corrections live in data-raw/curated_psoc_overrides.csv (the
# authoritative source layer) and reach the runtime through
# scripts/build_assistant_assets.R. A test failing here means either the
# artifact was regenerated without the overrides file, or the overrides
# file was changed without review.

CURATED_OVERRIDES_CSV <- testthat::test_path("..", "..", "data-raw",
                                             "curated_psoc_overrides.csv")

# occupation phrase (preserved exactly as published) -> approved PSOC 2022
# unit group, plus the kind of review decision and the code the source
# workbook carries. Restated literally so a change to the CSV cannot
# silently redefine what is being asserted.
APPROVED_PSOC_MAPPINGS <- list(
  list(occupation = "E-load Retailer", psoc = "5211",
       label = "STALL AND MARKET SALESPERSONS",
       kind = "correction", workbook_psoc = "1420"),
  list(occupation = "Apartment Owner", psoc = "5153",
       label = "BUILDING CARETAKERS",
       kind = "correction", workbook_psoc = "1219"),
  list(occupation = "Avon Dealer",     psoc = "5243",
       label = "DOOR-TO-DOOR SALESPERSONS",
       kind = "correction", workbook_psoc = "5242"),
  # Not a code change: the workbook already carried 8332. Only the
  # confidence was raised.
  list(occupation = "Truck Driver",    psoc = "8332",
       label = "HEAVY TRUCK AND LORRY DRIVERS",
       kind = "confirmation", workbook_psoc = "8332"),
  # PSA survey coding guidance codes the BHW to community health work
  # rather than the institution-based patient-care assistance the
  # workbook chose. "Barangay health aide" is a DIFFERENT occupation term
  # and stays at 5321; the two must not be merged.
  list(occupation = "Barangay Health Worker (BHW)", psoc = "3253",
       label = "COMMUNITY HEALTH WORKERS",
       kind = "correction", workbook_psoc = "5321")
)

pairing_row <- function(occupation) {
  pairings <- assistant_common_pairings()
  skip_if(is.null(pairings), "pairings artifact unavailable")
  row <- pairings[pairings$occupation == occupation, , drop = FALSE]
  expect_equal(nrow(row), 1L,
               info = paste0("expected exactly one row for '", occupation, "'"))
  row
}


# ---------------------------------------------------------------------
# The codes resolve in the canonical repository
# ---------------------------------------------------------------------

test_that("each approved PSOC code resolves to its official 2022 label", {
  for (m in APPROVED_PSOC_MAPPINGS) {
    entry <- get_classification_entry("psoc", "2022", m$psoc)

    expect_equal(nrow(entry), 1L, info = m$psoc)
    expect_identical(entry$code[[1L]], m$psoc)
    expect_identical(entry$label[[1L]], m$label)
    expect_identical(entry$level[[1L]], "unit_group")
    expect_identical(entry$status[[1L]], "current")
  }
})


# ---------------------------------------------------------------------
# The artifact carries the approved mappings
# ---------------------------------------------------------------------

test_that("each approved occupation maps to exactly the approved PSOC code", {
  for (m in APPROVED_PSOC_MAPPINGS) {
    row <- pairing_row(m$occupation)
    expect_identical(row$confirmed_psoc[[1L]], m$psoc, info = m$occupation)
  }
})

test_that("the stored label is the canonical PSOC 2022 title, not workbook text", {
  for (m in APPROVED_PSOC_MAPPINGS) {
    row <- pairing_row(m$occupation)
    expect_identical(row$confirmed_psoc_label[[1L]], m$label, info = m$occupation)
    # And it genuinely agrees with the repository, not just with itself.
    canonical <- get_classification_entry("psoc", "2022", m$psoc)$label[[1L]]
    expect_identical(row$confirmed_psoc_label[[1L]], canonical)
  }
})

test_that("curated rows are High confidence with curated provenance", {
  for (m in APPROVED_PSOC_MAPPINGS) {
    row <- pairing_row(m$occupation)
    expect_identical(row$psoc_confidence[[1L]], "High", info = m$occupation)
    expect_identical(row$psoc_provenance[[1L]], "curated", info = m$occupation)
    # Never mislabelled as an official PSA correspondence.
    expect_false(row$psoc_provenance[[1L]] %in% c("official", "derived", "suggested"))
  }
})

test_that("curated rows carry a rationale note", {
  for (m in APPROVED_PSOC_MAPPINGS) {
    row <- pairing_row(m$occupation)
    note <- row$psoc_curation_note[[1L]]
    expect_false(is.na(note), info = m$occupation)
    expect_gt(nchar(note), 40)
  }
})

test_that("the original reported occupation phrase is preserved verbatim", {
  pairings <- assistant_common_pairings()
  skip_if(is.null(pairings), "pairings artifact unavailable")

  for (m in APPROVED_PSOC_MAPPINGS) {
    expect_true(m$occupation %in% pairings$occupation, info = m$occupation)
  }
})

test_that("existing source and context fields survive the override", {
  # The override touches the occupation layer only. These were captured
  # from the pre-override artifact.
  expected_context <- list(
    "E-load Retailer" = list(source_industry = "E-load Retailing",
                             original_psic = "47891",
                             psic_rev5_code = "61209"),
    "Apartment Owner" = list(source_industry = "Apartment Operation",
                             original_psic = "68141",
                             psic_rev5_code = "68101"),
    "Avon Dealer"     = list(source_industry = "Cosmetics Retailing",
                             original_psic = "47723",
                             psic_rev5_code = "47724"),
    "Truck Driver"    = list(source_industry = "Hardware",
                             original_psic = "47521 – 47528",
                             psic_rev5_code = paste(
                               "47521", "47522", "47523", "47524", "47525",
                               "47526", "47529", sep = " / "))
  )

  for (occ in names(expected_context)) {
    row <- pairing_row(occ)
    want <- expected_context[[occ]]
    expect_identical(row$source_industry[[1L]], want$source_industry, info = occ)
    expect_identical(row$original_psic[[1L]], want$original_psic, info = occ)
    expect_identical(row$psic_rev5_code[[1L]], want$psic_rev5_code, info = occ)
    expect_false(is.na(row$psa_source[[1L]]), info = occ)
    expect_false(is.na(row$mapping_note[[1L]]), info = occ)
  }
})


# ---------------------------------------------------------------------
# Confirmed, not corrected: Truck Driver
# ---------------------------------------------------------------------

test_that("PSOC 8331 and 8332 are distinct occupations and 8331 is not trucks", {
  bus <- get_classification_entry("psoc", "2022", "8331")
  truck <- get_classification_entry("psoc", "2022", "8332")

  expect_identical(bus$label[[1L]], "BUS AND TRAM DRIVERS")
  expect_identical(truck$label[[1L]], "HEAVY TRUCK AND LORRY DRIVERS")
  expect_false(grepl("truck|lorry", bus$label[[1L]], ignore.case = TRUE))
})

test_that("'Truck Driver' is confirmed at 8332, the code the workbook already had", {
  row <- pairing_row("Truck Driver")

  expect_identical(row$confirmed_psoc[[1L]], "8332")
  expect_identical(row$confirmed_psoc_label[[1L]], "HEAVY TRUCK AND LORRY DRIVERS")
  expect_identical(row$psoc_confidence[[1L]], "High")
  expect_identical(row$psoc_provenance[[1L]], "curated")
  expect_false(is.na(row$psoc_curation_note[[1L]]))
})

test_that("the Truck Driver override is a confirmation, never a code change", {
  skip_if_not(file.exists(CURATED_OVERRIDES_CSV), "overrides CSV not found")
  ov <- utils::read.csv(CURATED_OVERRIDES_CSV, colClasses = "character")
  row <- ov[ov$occupation == "Truck Driver", , drop = FALSE]

  expect_equal(nrow(row), 1L)
  expect_identical(row$override_kind[[1L]], "confirmation")
  # The defining property: the workbook code and the curated code are the
  # same, so nothing was superseded.
  expect_identical(row$source_workbook_psoc[[1L]], "8332")
  expect_identical(row$curated_psoc[[1L]], "8332")
  expect_identical(row$source_workbook_psoc[[1L]], row$curated_psoc[[1L]])

  # The note must say so rather than reading as a correction.
  expect_match(row$curation_note[[1L]], "NOT a code change", fixed = TRUE)
  expect_match(row$curation_note[[1L]], "already the correct code", fixed = TRUE)
})

test_that("no curated override targets 8331", {
  skip_if_not(file.exists(CURATED_OVERRIDES_CSV), "overrides CSV not found")
  ov <- utils::read.csv(CURATED_OVERRIDES_CSV, colClasses = "character")

  expect_false("8331" %in% ov$curated_psoc)
  expect_false("8331" %in% ov$source_workbook_psoc)

  pairings <- assistant_common_pairings()
  skip_if(is.null(pairings), "pairings artifact unavailable")
  expect_false("8331" %in% pairings$confirmed_psoc[pairings$occupation == "Truck Driver"])
})

test_that("a confirmation row still reports 8332's own label, not 8331's", {
  row <- pairing_row("Truck Driver")
  expect_false(grepl("bus|tram", row$confirmed_psoc_label[[1L]], ignore.case = TRUE))
})


# ---------------------------------------------------------------------
# Occupation / industry separation
# ---------------------------------------------------------------------

test_that("'e-load retailer' does not drift to a PSIC code", {
  row <- pairing_row("E-load Retailer")

  # The occupation answer is a PSOC unit group, and it is not the PSIC
  # code sitting in the same row.
  expect_identical(row$confirmed_psoc[[1L]], "5211")
  expect_false(identical(row$confirmed_psoc[[1L]], row$psic_rev5_code[[1L]]))
  expect_false(identical(row$confirmed_psoc[[1L]], row$original_psic[[1L]]))

  # 5211 is a PSOC code and is not a PSIC Revision 5 class.
  expect_equal(nrow(get_classification_entry("psoc", "2022", "5211")), 1L)
  expect_equal(nrow(get_classification_entry("psic", "2026", "5211")), 0L)

  # The row's PSIC evidence is untouched by the occupation correction.
  expect_identical(row$psic_rev5_code[[1L]], "61209")
  expect_true(row$has_fixed_psic[[1L]])
})

test_that("'truck driver' resolves as an occupation, not an industry", {
  psoc_entry <- get_classification_entry("psoc", "2022", "8332")
  expect_equal(nrow(psoc_entry), 1L)
  expect_identical(psoc_entry$system[[1L]], "psoc")

  # The same digits are not a PSIC Revision 5 class.
  expect_equal(nrow(get_classification_entry("psic", "2026", "8332")), 0L)

  # And the pairing row's PSIC side remains the hardware-retail evidence,
  # which is the industry of the employer, not the driver's occupation.
  row <- pairing_row("Truck Driver")
  expect_true(grepl("^475", row$original_psic[[1L]]))
  expect_false(identical(row$confirmed_psoc[[1L]], row$original_psic[[1L]]))
})

test_that("'apartment owner' retains its ambiguity rationale", {
  row <- pairing_row("Apartment Owner")
  note <- row$psoc_curation_note[[1L]]

  expect_false(is.na(note))
  # The note must actually record that the mapping is conditional rather
  # than presenting 5153 as unconditional.
  expect_match(note, "AMBIGUITY RETAINED", fixed = TRUE)
  expect_match(note, "personally performs", fixed = TRUE)

  # The real-estate PSIC evidence is retained and not collapsed into the
  # occupation answer.
  expect_identical(row$psic_rev5_code[[1L]], "68101")
  expect_false(identical(row$confirmed_psoc[[1L]], row$psic_rev5_code[[1L]]))
})

test_that("'avon dealer' resolves to the approved PSOC occupation", {
  row <- pairing_row("Avon Dealer")

  expect_identical(row$confirmed_psoc[[1L]], "5243")
  expect_identical(row$confirmed_psoc_label[[1L]], "DOOR-TO-DOOR SALESPERSONS")
  # Specifically no longer the sales-demonstrator group it superseded.
  expect_false(identical(row$confirmed_psoc[[1L]], "5242"))
  expect_identical(
    get_classification_entry("psoc", "2022", "5242")$label[[1L]],
    "SALES DEMONSTRATORS"
  )
})


# ---------------------------------------------------------------------
# The tool layer surfaces the corrections
# ---------------------------------------------------------------------

test_that("assistant_search_common_pairings returns the curated mapping", {
  skip_if(is.null(assistant_common_pairings()), "pairings artifact unavailable")

  for (m in APPROVED_PSOC_MAPPINGS) {
    # Generous limit: "Truck Driver" is also a substring of several other
    # published phrases, and the exact row must still be in the shortlist.
    res <- assistant_search_common_pairings(occupation = m$occupation, limit = 25L)

    expect_true(res$available, info = m$occupation)
    expect_gte(res$total_matches, 1L)

    hit <- Filter(function(r) identical(r$occupation, m$occupation), res$results)
    expect_equal(length(hit), 1L, info = m$occupation)
    expect_identical(hit[[1L]]$confirmed_psoc, m$psoc)
    expect_identical(hit[[1L]]$confirmed_psoc_label, m$label)
    expect_identical(hit[[1L]]$psoc_provenance, "curated")
    expect_identical(hit[[1L]]$psoc_confidence, "High")
  }
})

test_that("the tool never exposes the curated mapping as an official PSA code", {
  skip_if(is.null(assistant_common_pairings()), "pairings artifact unavailable")

  res <- assistant_search_common_pairings(occupation = "Avon Dealer", limit = 3L)
  # The pairing caveat still applies to curated rows: they are evidence,
  # and the code must still be verified against the repository.
  expect_match(res$evidence_caveat, "Supporting evidence only", fixed = TRUE)
  expect_match(res$evidence_caveat, "assistant_get_classification_entry", fixed = TRUE)
})


# ---------------------------------------------------------------------
# The overrides file is the source of truth, not the .rds
# ---------------------------------------------------------------------

test_that("the curated overrides source file exists and is well formed", {
  expect_true(file.exists(CURATED_OVERRIDES_CSV))

  ov <- utils::read.csv(CURATED_OVERRIDES_CSV, colClasses = "character")

  expect_setequal(
    names(ov),
    c("occupation", "override_kind", "source_workbook_psoc", "curated_psoc",
      "psoc_confidence", "psoc_provenance", "curation_note")
  )
  expect_equal(nrow(ov), length(APPROVED_PSOC_MAPPINGS))
  expect_true(all(ov$psoc_provenance == "curated"))
  expect_true(all(ov$psoc_confidence == "High"))
  expect_false(anyDuplicated(ov$occupation) > 0L)
  expect_true(all(ov$override_kind %in% c("correction", "confirmation")))

  # Every targeted code must be a real PSOC 2022 unit group, and the CSV
  # must not carry a label of its own -- labels come from the repository.
  for (i in seq_len(nrow(ov))) {
    expect_equal(nrow(get_classification_entry("psoc", "2022", ov$curated_psoc[i])), 1L,
                 info = ov$curated_psoc[i])
  }
  expect_false(any(grepl("label", names(ov), ignore.case = TRUE)))
})

test_that("the CSV and the built artifact agree", {
  skip_if(is.null(assistant_common_pairings()), "pairings artifact unavailable")
  skip_if_not(file.exists(CURATED_OVERRIDES_CSV), "overrides CSV not found")

  ov <- utils::read.csv(CURATED_OVERRIDES_CSV, colClasses = "character")

  for (i in seq_len(nrow(ov))) {
    row <- pairing_row(ov$occupation[i])
    expect_identical(row$confirmed_psoc[[1L]], ov$curated_psoc[i])
    expect_identical(row$psoc_confidence[[1L]], ov$psoc_confidence[i])
    expect_identical(row$psoc_provenance[[1L]], ov$psoc_provenance[i])

    if (identical(ov$override_kind[i], "correction")) {
      # The superseded code is genuinely gone from the artifact.
      expect_false(identical(row$confirmed_psoc[[1L]], ov$source_workbook_psoc[i]))
    } else {
      # A confirmation must leave the workbook's own code in place.
      expect_identical(row$confirmed_psoc[[1L]], ov$source_workbook_psoc[i])
    }
  }
})

test_that("override_kind matches what each row actually does", {
  skip_if_not(file.exists(CURATED_OVERRIDES_CSV), "overrides CSV not found")
  ov <- utils::read.csv(CURATED_OVERRIDES_CSV, colClasses = "character")

  changes <- ov$source_workbook_psoc != ov$curated_psoc
  expect_identical(ov$override_kind == "correction", changes)
  expect_identical(ov$override_kind == "confirmation", !changes)

  # And the declared kinds agree with what the tests above assert.
  declared <- setNames(ov$override_kind, ov$occupation)
  for (m in APPROVED_PSOC_MAPPINGS) {
    expect_identical(unname(declared[m$occupation]), m$kind, info = m$occupation)
  }
})


# ---------------------------------------------------------------------
# Nothing else moved
# ---------------------------------------------------------------------

test_that("only the approved rows are curated; the rest keep workbook provenance", {
  pairings <- assistant_common_pairings()
  skip_if(is.null(pairings), "pairings artifact unavailable")

  curated <- pairings[pairings$psoc_provenance == "curated", , drop = FALSE]
  expect_equal(nrow(curated), length(APPROVED_PSOC_MAPPINGS))
  expect_setequal(curated$occupation,
                  vapply(APPROVED_PSOC_MAPPINGS, `[[`, character(1), "occupation"))

  expect_setequal(unique(pairings$psoc_provenance), c("source_workbook", "curated"))
  expect_false(any(is.na(pairings$psoc_provenance)))

  # Non-curated rows never carry a curation note.
  others <- pairings[pairings$psoc_provenance == "source_workbook", , drop = FALSE]
  expect_true(all(is.na(others$psoc_curation_note)))
})

test_that("the remaining workbook Low-confidence rows were not silently upgraded", {
  pairings <- assistant_common_pairings()
  skip_if(is.null(pairings), "pairings artifact unavailable")

  # The workbook grades five occupations Low. Four have now been reviewed
  # and raised to High; Videoke Rental Owner has not been reviewed and must
  # still read Low rather than being swept up with the others.
  still_low <- pairings$occupation[
    pairings$psoc_confidence == "Low" & !is.na(pairings$psoc_confidence)
  ]
  expect_setequal(still_low, "Videoke Rental Owner")

  row <- pairing_row("Videoke Rental Owner")
  expect_identical(row$psoc_provenance[[1L]], "source_workbook")
  expect_true(is.na(row$psoc_curation_note[[1L]]))
})

test_that("the PSIC mapping confidence was not touched by the PSOC correction", {
  # mapping_confidence grades the PSIC mapping and is a different
  # judgement from psoc_confidence. Values recorded before the correction.
  expected <- c("E-load Retailer" = "Medium",
                "Apartment Owner" = "High",
                "Avon Dealer" = "High",
                "Truck Driver" = "Medium")

  for (occ in names(expected)) {
    row <- pairing_row(occ)
    expect_identical(row$mapping_confidence[[1L]], unname(expected[occ]), info = occ)
  }
})

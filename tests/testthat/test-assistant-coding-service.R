# W1-B: the mandatory deterministic coding service.
#
# Section 24 of the spec lists the exact live failures from pre-staging-v7.
# Each one is a permanent test here, asserted on the STRUCTURED packet --
# selected code and allowed_codes -- not on prose.

.svc <- function(...) assistant_coding_service(...)
.psoc <- function(p) if (is.null(p$occupation)) NA_character_ else p$occupation$selected_code
.psic <- function(p) {
  if (is.null(p$industry) || is.null(p$industry$selected_code)) NA_character_
  else p$industry$selected_code
}

test_that("the packet carries the documented shape", {
  p <- .svc("carpenter")
  expect_true(p$status %in% ASSISTANT_CODING_STATUSES)
  expect_identical(p$request_type, "contextual_coding")
  expect_true(all(c("occupation", "industry", "clarification",
                    "allowed_codes", "requested_systems") %in% names(p)))
  expect_true(all(c("psoc", "psic") %in% names(p$allowed_codes)))
})

# --- Mayor (live: 1112 in one session, no PSOC in another) -----------------

test_that("mayor resolves to 1111 and never 1112", {
  p <- .svc("mayor", "local government")
  expect_identical(.psoc(p), "1111")
  expect_identical(.psic(p), "84113")
  expect_false("1112" %in% assistant_allowed_codes(p))
  expect_identical(p$status, "resolved")
})

test_that("mayor without establishment context still yields a PSOC", {
  p <- .svc("mayor", requested_systems = "psoc")
  expect_identical(.psoc(p), "1111")
  expect_false(identical(p$status, "no_verified_match"))
})

test_that("city administrator does not collapse into the mayor answer", {
  expect_identical(.psoc(.svc("city administrator", requested_systems = "psoc")), "1112")
})

# --- Call centre -----------------------------------------------------------

test_that("call-centre wording selects the right unit group", {
  expect_identical(.psoc(.svc("call center agent", requested_systems = "psoc")), "4222")
  expect_identical(.psoc(.svc("call center sales agent", requested_systems = "psoc")), "5244")
  expect_identical(.psoc(.svc("telemarketer", requested_systems = "psoc")), "5244")
})

# --- BHW (live: 3253 and 5329 shown as peers) ------------------------------

test_that("BHW selects 3253 and 5329 is not an allowed peer", {
  for (q in c("barangay health worker", "BHW", "bhw")) {
    p <- .svc(q, requested_systems = "psoc")
    expect_identical(.psoc(p), "3253", info = q)
    expect_false("5329" %in% assistant_allowed_codes(p), info = q)
    expect_length(p$allowed_codes$psoc, 1L)
  }
})

test_that("barangay health aide stays a different occupation", {
  expect_identical(.psoc(.svc("barangay health aide", requested_systems = "psoc")), "5321")
})

# --- Teacher (live: correct PSOC, preschool PSIC) --------------------------

test_that("private high-school teacher never returns a preschool PSIC", {
  # v10 (spec 20): the PSIC must NOT descend to a detailed subclass while
  # several current compatible siblings remain -- general vs technical /
  # vocational, and with vs without special needs. It returns the verified
  # parent and asks one real-world question instead. This previously
  # resolved straight to 85312, which was over-specific: the wording does
  # not state the special-needs facet, so the subclass was being decided
  # by ranking rather than by evidence.
  p <- .svc("secondary education teacher", "private general secondary education")
  expect_identical(.psoc(p), "2330")
  expect_identical(.psic(p), "8531")
  expect_identical(p$industry$coding_role, "aggregate")
  expect_identical(p$clarification$missing_slot, "establishment_activity_detail")
  # Still never preschool, and no unauthorised detailed code leaks through.
  expect_false(any(grepl("^8510", assistant_allowed_codes(p))))
  expect_identical(p$allowed_codes$psic, "8531")
})

# --- Corn / palay ----------------------------------------------------------

test_that("corn farmer keeps its PSIC and asks nothing", {
  p <- .svc("corn farmer", "growing of corn")
  expect_identical(.psoc(p), "6112")
  expect_identical(.psic(p), "01130")
  expect_identical(p$status, "resolved")
})

test_that("palay farmer yields the rice aggregate plus a detail question", {
  p <- .svc("palay farmer", "growing of rice")
  expect_identical(.psoc(p), "6111")
  expect_identical(.psic(p), "0112")
  expect_identical(p$status, "clarification_required")
  expect_identical(p$clarification$missing_slot, "establishment_activity_detail")
  # Only the supported aggregate may be stated; no detailed child leaks.
  expect_setequal(p$allowed_codes$psic, "0112")
})

# --- Carpenter (live: archived 41001 / industry dump) ----------------------

test_that("carpenter resolves PSOC and blocks PSIC behind a question", {
  p <- .svc("carpenter")
  expect_identical(.psoc(p), "7115")
  expect_identical(p$status, "clarification_required")
  expect_identical(p$clarification$missing_slot, "establishment_activity")
  expect_length(p$allowed_codes$psic, 0L)
})

test_that("no construction PSIC is authorised from the occupation alone", {
  p <- .svc("carpenter")
  for (leaked in c("41001", "41002", "4100", "42100")) {
    expect_false(leaked %in% assistant_allowed_codes(p), info = leaked)
  }
})

# --- TNVS (live: 5165 DRIVING INSTRUCTORS / no classification) -------------

test_that("angkas and food panda select their own unit groups", {
  a <- .svc("angkas driver", requested_systems = "psoc")
  expect_identical(.psoc(a), "8323")
  expect_false("5165" %in% assistant_allowed_codes(a))

  f <- .svc("food panda driver", requested_systems = "psoc")
  expect_identical(.psoc(f), "9335")
  expect_false("5165" %in% assistant_allowed_codes(f))
})

# --- Outsourcing precondition (spec 15) ------------------------------------

test_that("an agency deployment blocks PSIC on wage_payer, not on public/private", {
  p <- .svc("janitor", "manpower agency at a hospital")
  expect_identical(p$status, "clarification_required")
  expect_identical(p$clarification$missing_slot, "wage_payer")
  expect_length(p$allowed_codes$psic, 0L)
  expect_match(p$clarification$question, "pays", ignore.case = TRUE)
  # The public/private question must NOT be asked first.
  expect_false(grepl("public or private", p$clarification$question, ignore.case = TRUE))
})

test_that("once the payer is known PSIC resolution proceeds", {
  p <- .svc("janitor", "private general hospital", wage_payer = "establishment")
  expect_false(identical(p$clarification$missing_slot, "wage_payer"))
  expect_true(length(p$allowed_codes$psic) > 0L)
})

# --- No-code safety --------------------------------------------------------

test_that("an occupation with no authoritative code authorises nothing", {
  p <- .svc("professional AI prompt engineer", requested_systems = "psoc")
  expect_identical(p$status, "no_verified_match")
  expect_length(assistant_allowed_codes(p), 0L)
})

# --- Current-edition enforcement (spec 17) ---------------------------------

test_that("every selected code is from the current edition", {
  for (args in list(list("mayor", "local government"),
                    list("corn farmer", "growing of corn"),
                    list("nurse", "private general hospital"))) {
    p <- do.call(.svc, args)
    for (half in list(p$occupation, p$industry)) {
      if (is.null(half) || is.null(half$selected_code) || is.na(half$selected_code)) next
      expect_identical(tolower(half$status_current), "current", info = half$selected_code)
    }
  }
})

test_that("every authorised code verifies in the current canonical repository", {
  p <- .svc("mayor", "local government")
  expect_equal(nrow(get_classification_entry("psoc", "2022", p$occupation$selected_code)), 1L)
  expect_equal(nrow(get_classification_entry("psic", "2026", p$industry$selected_code)), 1L)
})

test_that("current-edition enforcement is on by default", {
  expect_true(.svc("carpenter")$current_edition_enforced)
})

# --- decision, not candidate pool (spec 11) --------------------------------

test_that("the packet exposes one selected code per system, never a pool", {
  p <- .svc("barangay health worker", requested_systems = "psoc")
  expect_length(p$occupation$selected_code, 1L)
  expect_null(p$occupation$candidates)
  expect_length(p$allowed_codes$psoc, 1L)
})

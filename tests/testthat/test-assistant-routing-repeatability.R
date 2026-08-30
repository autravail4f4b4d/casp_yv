# Spec 25: repeatability harness.
#
# The live defect was not a wrong answer so much as an UNSTABLE one -- the
# same query took different authoritative routes and produced different
# codes in different fresh sessions. These tests re-run the router and the
# coding service from fresh state and require the structured outcome to be
# byte-identical every time. Prose is deliberately not compared.

.repeat_outcome <- function(query, occupation, establishment_activity = NULL,
                            requested_systems = c("psoc", "psic")) {
  route <- assistant_route_request(query)
  packet <- assistant_coding_service(
    occupation = occupation,
    establishment_activity = establishment_activity,
    requested_systems = requested_systems
  )
  list(
    route = route$route,
    requested_systems = sort(route$requested_systems),
    status = packet$status,
    psoc = if (is.null(packet$occupation)) NA_character_ else packet$occupation$selected_code,
    psic = if (is.null(packet$industry) || is.null(packet$industry$selected_code)) {
      NA_character_
    } else {
      packet$industry$selected_code
    },
    psoc_version = if (is.null(packet$occupation)) NA_character_ else packet$occupation$version,
    psic_version = if (is.null(packet$industry)) NA_character_ else packet$industry$version,
    missing_slot = packet$clarification$missing_slot,
    allowed = sort(assistant_allowed_codes(packet))
  )
}

# The eight queries spec 25 names, plus the two the failure matrix adds.
.REPEAT_CASES <- list
.repeat_cases <- list(
  list(q = "mayor psoc psic",                        occ = "mayor",                        act = "local government"),
  list(q = "call center agent psoc",                 occ = "call center agent",            act = NULL, sys = "psoc"),
  list(q = "BHW psoc",                               occ = "BHW",                          act = NULL, sys = "psoc"),
  list(q = "teacher in private high school psoc psic", occ = "secondary education teacher", act = "private general secondary education"),
  list(q = "corn farmer psoc psic",                  occ = "corn farmer",                  act = "growing of corn"),
  list(q = "carpenter psoc psic",                    occ = "carpenter",                    act = NULL),
  list(q = "angkas driver psoc",                     occ = "angkas driver",                act = NULL, sys = "psoc"),
  list(q = "food panda bicycle driver psoc",         occ = "food panda bicycle driver",    act = NULL, sys = "psoc")
)

test_that("every critical query yields an identical structured outcome across runs", {
  N <- 12L
  for (case in .repeat_cases) {
    sys <- if (is.null(case$sys)) c("psoc", "psic") else case$sys
    runs <- lapply(seq_len(N), function(i) {
      .repeat_outcome(case$q, case$occ, case$act, sys)
    })
    first <- runs[[1L]]
    for (i in seq_len(N)) {
      expect_identical(runs[[i]], first,
                       info = sprintf("%s (run %d)", case$q, i))
    }
  }
})

test_that("repeatability holds after the per-process caches are reset", {
  # A stale memo could make the FIRST call differ from later ones, which is
  # exactly the shape of a cross-session inconsistency.
  baseline <- .repeat_outcome("mayor psoc psic", "mayor", "local government")
  .assistant_level_cache_reset()
  .assistant_examples_cache_reset()
  expect_identical(.repeat_outcome("mayor psoc psic", "mayor", "local government"),
                   baseline)
})

test_that("the route is stable independent of the coding service", {
  for (case in .repeat_cases) {
    routes <- vapply(1:25, function(i) assistant_route_request(case$q)$route, character(1))
    expect_length(unique(routes), 1L)
  }
})

test_that("allowed-code sets are stable and never empty for a resolved case", {
  for (case in .repeat_cases) {
    sys <- if (is.null(case$sys)) c("psoc", "psic") else case$sys
    o <- .repeat_outcome(case$q, case$occ, case$act, sys)
    if (identical(o$status, "resolved")) {
      expect_true(length(o$allowed) > 0L, info = case$q)
    }
    o2 <- .repeat_outcome(case$q, case$occ, case$act, sys)
    expect_identical(o$allowed, o2$allowed, info = case$q)
  }
})

test_that("the specific live regressions cannot recur", {
  mayor <- .repeat_outcome("mayor psoc psic", "mayor", "local government")
  expect_identical(mayor$psoc, "1111")
  expect_false("1112" %in% mayor$allowed)
  expect_false(is.na(mayor$psoc))

  # Raw phrase, vehicle qualifier included -- confirmed live defect: this
  # exact wording used to miss the manual's "food panda driver" entry and
  # fall through to 5165 DRIVING INSTRUCTORS.
  panda <- .repeat_outcome("food panda bicycle driver psoc", "food panda bicycle driver",
                           NULL, "psoc")
  expect_identical(panda$psoc, "9335")
  expect_false("5165" %in% panda$allowed)

  bhw <- .repeat_outcome("BHW psoc", "BHW", NULL, "psoc")
  expect_identical(bhw$psoc, "3253")
  expect_false("5329" %in% bhw$allowed)

  teach <- .repeat_outcome("teacher in private high school psoc psic",
                           "secondary education teacher",
                           "private general secondary education")
  expect_identical(teach$psic, "85312")

  corn <- .repeat_outcome("corn farmer psoc psic", "corn farmer", "growing of corn")
  expect_false(is.na(corn$psic))

  carp <- .repeat_outcome("carpenter psoc psic", "carpenter", NULL)
  expect_identical(carp$missing_slot, "establishment_activity")
  expect_false(any(grepl("^4[0-9]{3,4}$", carp$allowed)))
})

test_that("current editions are stable across runs", {
  for (i in 1:5) {
    o <- .repeat_outcome("mayor psoc psic", "mayor", "local government")
    expect_identical(o$psoc_version, "2022")
    expect_identical(o$psic_version, "2026")
  }
})

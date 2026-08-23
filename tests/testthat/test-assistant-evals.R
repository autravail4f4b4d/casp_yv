# Deterministic guardrails over the RM evaluation fixture
# (tests/evals/rm_assistant_cases.yml).
#
# These tests do NOT call a model. They do two things:
#
#   1. Keep the fixture structurally honest (all 12 representative cases
#      from the spec present, each fully specified) so a future live
#      evaluation run has something complete to replay.
#
#   2. Verify the *factual claims* the fixture makes about this
#      application's own data, so the behaviours the fixture demands are
#      actually protecting against something real. If PSOC "999999"
#      silently became a valid code, case 09's grounding expectation
#      would be vacuous -- this catches that.

.eval_fixture_path <- function() {
  candidates <- c(
    "tests/evals/rm_assistant_cases.yml",
    file.path("..", "evals", "rm_assistant_cases.yml"),
    file.path("..", "..", "tests", "evals", "rm_assistant_cases.yml")
  )
  for (p in candidates) if (file.exists(p)) return(p)
  candidates[[1]]
}

.load_eval_fixture <- function() {
  testthat::skip_if_not_installed("yaml")
  path <- .eval_fixture_path()
  testthat::skip_if_not(file.exists(path), "rm_assistant_cases.yml not found")
  yaml::read_yaml(path)
}

test_that("evaluation fixture loads and declares all 12 representative cases", {
  fx <- .load_eval_fixture()
  expect_true(is.list(fx))
  expect_true(!is.null(fx$cases))
  ids <- vapply(fx$cases, function(c) as.character(c$id), character(1))
  expect_equal(length(fx$cases), 12)
  expect_setequal(ids, sprintf("%02d", 1:12))
  expect_false(anyDuplicated(ids) > 0)
})

test_that("every evaluation case is fully specified", {
  fx <- .load_eval_fixture()
  for (case in fx$cases) {
    label <- paste0("case ", case$id)
    expect_true(nzchar(case$title %||% ""), info = label)
    expect_true(nzchar(case$user %||% ""), info = label)
    expect_true(nzchar(case$language %||% ""), info = label)
    expect_true(nzchar(case$focus %||% ""), info = label)
    # Both directions matter: what RM must do, and what fails the case.
    expect_true(length(case$expect) > 0, info = label)
    expect_true(length(case$must_not) > 0, info = label)
  }
})

test_that("evaluation fixture covers the required languages", {
  fx <- .load_eval_fixture()
  langs <- vapply(fx$cases, function(c) c$language, character(1))
  # Spec requires English, Cebuano/Bisaya and mixed-language coverage at minimum.
  expect_true("en" %in% langs)
  expect_true("ceb" %in% langs)
  expect_true("mixed" %in% langs)
})

test_that("evaluation fixture covers each required behaviour category", {
  fx <- .load_eval_fixture()
  foci <- vapply(fx$cases, function(c) c$focus, character(1))
  expect_true("grounding_no_fabrication" %in% foci)
  expect_true("psoc_psic_separation" %in% foci)
  expect_true("psic_vague_probing" %in% foci)
  expect_true("psic_principal_activity" %in% foci)
  expect_true("psic_ancillary_activity" %in% foci)
  expect_true("system_routing" %in% foci)
  expect_true("archive_semantics" %in% foci)
  expect_true(any(grepl("multilingual", foci)))
})

# --- The deterministic claims: verified against the real application data ---

test_that("case 09's unverifiable PSOC code genuinely does not exist (grounding rule protects something real)", {
  fx <- .load_eval_fixture()
  case <- Filter(function(c) identical(as.character(c$id), "09"), fx$cases)[[1]]
  det <- case$deterministic
  expect_equal(det$check, "entry_not_found")

  entry <- get_classification_entry(det$system, det$version, det$code)
  expect_equal(nrow(entry), 0)
})

test_that("case 10's routing target (PSGC) is a real registered system covering geography", {
  fx <- .load_eval_fixture()
  case <- Filter(function(c) identical(as.character(c$id), "10"), fx$cases)[[1]]
  det <- case$deterministic
  expect_equal(det$check, "registry_has_system")

  reg <- classification_registry()
  expect_true(det$system %in% reg$id)
  row <- reg[reg$id == det$system, ]
  expect_true(nzchar(row$display_name))
  # Barangay is a real level in the current PSGC release, so the routing
  # advice the fixture demands is actionable.
  levels <- classification_levels("psgc", row$current_version[[1]])
  expect_true("Bgy" %in% levels)
})

test_that("case 11's archived PSIC edition really is archived, and the current one really is current", {
  fx <- .load_eval_fixture()
  case <- Filter(function(c) identical(as.character(c$id), "11"), fx$cases)[[1]]
  det <- case$deterministic
  expect_equal(det$check, "version_status")

  meta <- classification_metadata(det$system, det$version)
  expect_equal(meta$status, det$status)

  reg <- classification_registry()
  current <- reg$current_version[reg$id == det$system][[1]]
  expect_false(identical(current, det$version))
  expect_equal(classification_metadata(det$system, current)$status, "current")
})

test_that("the occupation/industry separation the fixture demands matches the real registry", {
  # Case 05 hinges on PSOC and PSIC being genuinely different systems with
  # their own current editions -- assert that, so the separation requirement
  # can never be quietly undermined by a registry change.
  reg <- classification_registry()
  expect_true(all(c("psoc", "psic") %in% reg$id))
  psoc_current <- reg$current_version[reg$id == "psoc"][[1]]
  psic_current <- reg$current_version[reg$id == "psic"][[1]]
  expect_equal(psoc_current, "2022")
  expect_equal(psic_current, "2026")
})

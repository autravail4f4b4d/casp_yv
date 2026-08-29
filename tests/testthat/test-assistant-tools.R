# RM Classification Assistant — tool wrapper tests (Wave 1B).
#
# These tests encode the milestone's non-negotiable grounding rule
# (spec 2.1 / 19.2) as executable assertions rather than leaving it to the
# system prompt:
#
#   NO RETRIEVED CLASSIFICATION CODE = NO CLASSIFICATION CODE PRESENTED
#   AS THE ANSWER.
#
# Fixtures are used for the two evidence artifacts (common pairings, PSIC
# rules) so this file is green whether or not Workstream A's artifacts have
# landed; matching tests run against the REAL artifacts and skip when they
# are absent.

# ---------------------------------------------------------------------------
# Fixtures matching the frozen assistant_data.R contract
# ---------------------------------------------------------------------------

fixture_pairings <- function() {
  tibble::tibble(
    occupation = c(
      "Accountant",
      "Barangay Health Worker",
      "Hairdresser",
      "Rice Farmer"
    ),
    confirmed_psoc = c("2411", "3253", "5141", "6111"),
    source_industry = c(
      "Private company",
      "Government / LGU",
      "Personal service activities",
      "Agriculture"
    ),
    original_psic = c("69200", "86901", "96020", "01110"),
    # Row 1 is a deliberate no-fixed-PSIC row; row 3 is a multi-code string;
    # row 4 is an en-dash range. All must survive verbatim.
    psic_rev5_code = c(NA_character_, "84121", "96211 / 96220", "01171–01189"),
    psic_rev5_rule = c(
      "No fixed PSIC code in the source document",
      "General public administration activities",
      "Hairdressing and other beauty treatment",
      "Growing of cereals and leguminous crops"
    ),
    mapping_confidence = c("N/A", "High", "Medium", "High"),
    mapping_note = c(
      "The employing establishment's actual activity must be reported",
      "",
      "",
      ""
    ),
    psa_source = rep("CBMS 2024 PSOC-PSIC Rev5 mapping", 4L),
    has_fixed_psic = c(FALSE, TRUE, TRUE, TRUE),
    # The occupation layer. Row 3 stands in for an approved curated
    # correction so the tool's handling of both provenances is exercised.
    confirmed_psoc_label = c(
      "ACCOUNTANTS",
      "COMMUNITY HEALTH WORKERS",
      "HAIRDRESSERS",
      "FIELD CROP AND VEGETABLE GROWERS"
    ),
    psoc_confidence = c("High", "High", "High", "Low"),
    psoc_provenance = c(
      "source_workbook", "source_workbook", "curated", "source_workbook"
    ),
    psoc_curation_note = c(
      NA_character_, NA_character_, "Approved curated correction.", NA_character_
    )
  )
}

fixture_rules <- function() {
  tibble::tibble(
    topic = ASSISTANT_PSIC_RULE_TOPICS,
    title = paste("Title for", ASSISTANT_PSIC_RULE_TOPICS),
    rule = paste("Rule text for", ASSISTANT_PSIC_RULE_TOPICS),
    example = paste("Example for", ASSISTANT_PSIC_RULE_TOPICS)
  )
}

have_real_pairings <- function() {
  fn <- get0("assistant_common_pairings", mode = "function", ifnotfound = NULL)
  !is.null(fn) && !is.null(tryCatch(fn(), error = function(e) NULL))
}

have_real_rules <- function() {
  fn <- get0("assistant_psic_rules", mode = "function", ifnotfound = NULL)
  !is.null(fn) && !is.null(tryCatch(fn(), error = function(e) NULL))
}

# ---------------------------------------------------------------------------
# Bounded results — the model must never be able to pull a whole table
# ---------------------------------------------------------------------------

test_that("classification search returns at most 6 results by default", {
  res <- assistant_search_classification("psic", "growing")

  expect_null(res$error)
  expect_lte(length(res$results), ASSISTANT_DEFAULT_LIMIT)
  expect_equal(res$returned, length(res$results))
})

test_that("a caller-supplied oversized limit is clamped to the hard maximum", {
  # A blank query browses the whole edition, so total_matches is far above
  # any sane limit — exactly the case the clamp exists for.
  res <- assistant_search_classification("psic", "", limit = 1000)

  expect_null(res$error)
  expect_lte(length(res$results), ASSISTANT_MAX_LIMIT)
  expect_equal(res$returned, ASSISTANT_MAX_LIMIT)
  expect_gt(res$total_matches, ASSISTANT_MAX_LIMIT)
  expect_true(res$truncated)
})

test_that("limit clamping helper handles nonsense input without erroring", {
  expect_equal(.assistant_clamp_limit(NULL), ASSISTANT_DEFAULT_LIMIT)
  expect_equal(.assistant_clamp_limit(NA), ASSISTANT_DEFAULT_LIMIT)
  expect_equal(.assistant_clamp_limit(0), 1L)
  expect_equal(.assistant_clamp_limit(-5), 1L)
  expect_equal(.assistant_clamp_limit(1e9), ASSISTANT_MAX_LIMIT)
  expect_equal(.assistant_clamp_limit(3), 3L)
})

test_that("pairings search returns at most 6 rows by default and clamps at 25", {
  pairings <- fixture_pairings()
  wide <- pairings[rep(seq_len(nrow(pairings)), 20L), , drop = FALSE]

  res <- assistant_search_common_pairings(.pairings = wide)
  expect_true(res$available)
  expect_lte(length(res$results), ASSISTANT_DEFAULT_LIMIT)

  res_big <- assistant_search_common_pairings(limit = 1000, .pairings = wide)
  expect_lte(length(res_big$results), ASSISTANT_MAX_LIMIT)
  expect_equal(res_big$returned, ASSISTANT_MAX_LIMIT)
  expect_gt(res_big$total_matches, ASSISTANT_MAX_LIMIT)
})

# ---------------------------------------------------------------------------
# Compactness — no full canonical schema, no full descriptions
# ---------------------------------------------------------------------------

test_that("search results expose only the compact fields, plus derived hierarchy roles", {
  res <- assistant_search_classification("psoc", "accountant")

  expect_gt(length(res$results), 0L)
  row <- res$results[[1L]]

  expect_equal(names(row), ASSISTANT_SEARCH_FIELDS)
  expect_true(all(c("hierarchy_role", "hierarchy_of") %in% names(row)))
  # The full canonical 10-column schema must NOT reach the model here.
  # `hierarchy_role`/`hierarchy_of` are DERIVED fields, not raw schema
  # columns -- raw `parent_code` itself stays hidden.
  expect_false("source_url" %in% names(row))
  expect_false("parent_code" %in% names(row))
  expect_false("description" %in% names(row))
  expect_false(all(CLASSIFICATION_SCHEMA_COLUMNS %in% names(row)))
})

test_that("long descriptions are truncated in search results", {
  # PSOC 2012 major groups carry multi-hundred-character descriptions.
  res <- assistant_search_classification("psoc", "Managers", version = "2012")
  expect_gt(length(res$results), 0L)

  row <- res$results[[1L]]

  # Resolve the source row by code AND level. A code is not unique within
  # a system+version -- archived PSOC 2012 has 13 one-character codes for
  # 10 major groups, so get_classification_entry("psoc","2012","1")
  # returns 2 rows and indexing $description would give a length-2 vector.
  src <- get_classification("psoc", "2012")
  full <- src$description[src$code == row$code & src$level == row$level][[1L]]

  expect_gt(nchar(full), ASSISTANT_SHORT_DESCRIPTION_CHARS)
  expect_equal(nchar(row$short_description), ASSISTANT_SHORT_DESCRIPTION_CHARS + 3L)
  expect_true(endsWith(row$short_description, "..."))
  expect_true(startsWith(full, substr(row$short_description, 1L, ASSISTANT_SHORT_DESCRIPTION_CHARS)))
})

test_that("every search result's short_description respects the truncation cap", {
  # Guard the cap generally, not just for one hand-picked row.
  for (sv in list(c("psic", "2019"), c("psccs", "2018"), c("pcoicop", "2020"))) {
    res <- assistant_search_classification(sv[[1]], "a", version = sv[[2]])
    for (row in res$results) {
      if (!is.na(row$short_description)) {
        expect_lte(
          nchar(row$short_description),
          ASSISTANT_SHORT_DESCRIPTION_CHARS + 3L
        )
      }
    }
  }
})

test_that("a non-unique code reports its additional matches instead of hiding them", {
  # Real quirk of the archived phscs PSOC 2012 edition (see the comment in
  # assistant_get_classification_entry): code "1" resolves to more than one
  # official row. The tool must surface that rather than present the first
  # match as the whole truth.
  raw <- get_classification_entry("psoc", "2012", "1")
  skip_if_not(nrow(raw) > 1L, "PSOC 2012 code '1' is unique in this build")

  res <- assistant_get_classification_entry("psoc", "2012", "1")
  expect_true(res$found)
  expect_equal(res$additional_matches, nrow(raw) - 1L)
  expect_true(nzchar(res$additional_matches_note))
})

test_that("a unique code reports no additional matches", {
  res <- assistant_get_classification_entry("psoc", "2022", "2121")
  expect_true(res$found)
  expect_null(res$additional_matches)
})

test_that("NA descriptions stay NA rather than becoming the string 'NA'", {
  expect_true(is.na(.assistant_truncate(NA_character_)))
  expect_equal(.assistant_truncate("short"), "short")
})

test_that("registry results are compact and omit the adapter metadata graph", {
  res <- assistant_classification_registry()

  expect_null(res$error)
  expect_equal(res$count, 10L)
  expect_equal(length(res$systems), 10L)

  ids <- vapply(res$systems, function(s) s$id, character(1))
  expect_setequal(ids, c(
    "psgc", "psic", "psoc", "psced", "pcoicop", "pcpc", "psccs",
    "pscc", "ptscs", "pscrcs"
  ))

  row <- res$systems[[1L]]
  expect_equal(names(row), ASSISTANT_REGISTRY_FIELDS)
  expect_false("adapter" %in% names(row))
  expect_false("available_levels" %in% names(row))
  expect_false("supports_history" %in% names(row))
})

# ---------------------------------------------------------------------------
# Codes are character — leading zeros survive
# ---------------------------------------------------------------------------

test_that("search preserves codes as character with leading zeros", {
  res <- assistant_search_classification("psic", "01111")

  expect_gt(length(res$results), 0L)
  row <- res$results[[1L]]
  expect_identical(row$code, "01111")
  expect_true(is.character(row$code))
  expect_false(is.numeric(row$code))
})

test_that("entry verification preserves codes as character with leading zeros", {
  res <- assistant_get_classification_entry("psic", "2026", "01111")

  expect_true(res$found)
  expect_identical(res$code, "01111")
  expect_true(is.character(res$code))
  expect_false(is.numeric(res$code))
})

# ---------------------------------------------------------------------------
# Verification: a miss is a miss (spec 19.2, eval Case 9)
# ---------------------------------------------------------------------------

test_that("an unknown PSOC code returns found = FALSE and is never presented as valid", {
  res <- assistant_get_classification_entry("psoc", "2022", "999999")

  expect_false(isTRUE(res$found))
  expect_identical(res$found, FALSE)
  expect_null(res$error)
  # No `code` field: the unverified value is echoed only as `requested_code`.
  expect_null(res$code)
  expect_null(res$label)
  expect_identical(res$requested_code, "999999")
  expect_true(nzchar(res$message))
  expect_match(res$message, "could not be verified", fixed = TRUE)
})

test_that("a nonsense PSIC code returns found = FALSE without erroring", {
  res <- assistant_get_classification_entry("psic", "2026", "ZZZZZ")

  expect_identical(res$found, FALSE)
  expect_null(res$code)
  expect_identical(res$requested_code, "ZZZZZ")
})

test_that("the entry tool never fuzzy-matches a near miss", {
  # "0111" is a real PSIC 2026 group; "01111x" is not. A near neighbour must
  # not be substituted.
  expect_true(assistant_get_classification_entry("psic", "2026", "0111")$found)
  expect_identical(assistant_get_classification_entry("psic", "2026", "01111x")$found, FALSE)
})

test_that("a verified hit returns the repository's own official label unchanged", {
  res <- assistant_get_classification_entry("psoc", "2022", "2121")
  official <- get_classification_entry("psoc", "2022", "2121")

  expect_true(res$found)
  expect_identical(res$code, "2121")
  expect_identical(res$label, official$label[[1L]])
  expect_identical(res$source, official$source[[1L]])
  expect_equal(names(res), c("found", ASSISTANT_ENTRY_FIELDS))
})

test_that("an empty code is reported as unverified rather than searched", {
  res <- assistant_get_classification_entry("psoc", "2022", "")
  expect_identical(res$found, FALSE)
  expect_null(res$code)
})

# ---------------------------------------------------------------------------
# Current / archived status is preserved, never relabelled
# ---------------------------------------------------------------------------

test_that("PSOC 2022 is reported current and PSOC 2012 archived", {
  current <- assistant_get_classification_entry("psoc", "2022", "2121")
  expect_identical(current$version, "2022")
  expect_identical(current$status, "current")

  archived <- assistant_get_classification_entry("psoc", "2012", "1")
  expect_true(archived$found)
  expect_identical(archived$version, "2012")
  expect_identical(archived$status, "archived")
})

test_that("PSIC 2026 is reported current and PSIC 2019 archived", {
  current <- assistant_get_classification_entry("psic", "2026", "01111")
  expect_identical(current$status, "current")

  archived <- assistant_get_classification_entry("psic", "2019", "01111")
  expect_true(archived$found)
  expect_identical(archived$version, "2019")
  expect_identical(archived$status, "archived")
})

test_that("search results carry the edition's real status, archived included", {
  current <- assistant_search_classification("psoc", "accountant")
  expect_true(all(vapply(current$results, function(r) r$status, character(1)) == "current"))

  archived <- assistant_search_classification("psoc", "Managers", version = "2012")
  expect_true(all(vapply(archived$results, function(r) r$status, character(1)) == "archived"))
  expect_true(all(vapply(archived$results, function(r) r$version, character(1)) == "2012"))
})

# ---------------------------------------------------------------------------
# Default version resolution never picks an archived edition
# ---------------------------------------------------------------------------

test_that("omitting version resolves to the current edition", {
  expect_identical(assistant_search_classification("psoc", "accountant")$version, "2022")
  expect_identical(assistant_search_classification("psic", "growing")$version, "2026")

  expect_identical(assistant_get_classification_entry("psoc", code = "2121")$version, "2022")
  expect_identical(assistant_get_classification_entry("psic", code = "01111")$version, "2026")

  expect_identical(.assistant_current_version("psoc"), "2022")
  expect_identical(.assistant_current_version("psic"), "2026")
})

# ---------------------------------------------------------------------------
# Errors become structured results, never exceptions or stack traces
# ---------------------------------------------------------------------------

test_that("an unsupported system returns a safe structured error, not an exception", {
  res <- assistant_search_classification("not_a_system", "anything")

  expect_true(isTRUE(res$error))
  expect_true(nzchar(res$message))
  expect_false(grepl("Error in", res$message, fixed = TRUE))
  expect_false(grepl("\n", res$message, fixed = TRUE))
  expect_match(res$message, "Available systems", fixed = TRUE)
})

test_that("an unsupported version returns a safe structured error", {
  res <- assistant_get_classification_entry("psoc", "1999", "2121")

  expect_true(isTRUE(res$error))
  expect_false(isTRUE(res$found))
  expect_false(grepl("Error in", res$message, fixed = TRUE))
  expect_match(res$message, "Available versions", fixed = TRUE)
})

test_that("an unsupported level returns a safe structured error", {
  res <- assistant_search_classification("psoc", "accountant", level = "not_a_level")

  expect_true(isTRUE(res$error))
  expect_false(grepl("Error in", res$message, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Common pairings: evidence only, and no-code stays no-code
# ---------------------------------------------------------------------------

test_that("a no-fixed-PSIC pairing row is returned with its code still NA", {
  res <- assistant_search_common_pairings(
    occupation = "accountant",
    .pairings = fixture_pairings()
  )

  expect_true(res$available)
  expect_equal(length(res$results), 1L)

  row <- res$results[[1L]]
  expect_identical(row$occupation, "Accountant")
  expect_identical(row$has_fixed_psic, FALSE)
  expect_true(is.na(row$psic_rev5_code))
  # Never back-filled from original_psic, and never dropped from results.
  expect_identical(row$original_psic, "69200")
  expect_false(identical(row$psic_rev5_code, row$original_psic))
  expect_identical(row$mapping_confidence, "N/A")
})

test_that("every pairings result carries the supporting-evidence-only caveat", {
  res <- assistant_search_common_pairings(.pairings = fixture_pairings())

  expect_true(is.character(res$evidence_caveat))
  expect_true(nzchar(res$evidence_caveat))
  expect_match(res$evidence_caveat, "evidence", ignore.case = TRUE)
  expect_match(res$evidence_caveat, "assistant_get_classification_entry", fixed = TRUE)

  filtered <- assistant_search_common_pairings(
    psoc_code = "3253",
    .pairings = fixture_pairings()
  )
  expect_true(nzchar(filtered$evidence_caveat))
})

test_that("multi-code and en-dash range PSIC strings survive verbatim", {
  pairings <- fixture_pairings()

  multi <- assistant_search_common_pairings(occupation = "hairdresser", .pairings = pairings)
  expect_identical(multi$results[[1L]]$psic_rev5_code, "96211 / 96220")

  ranged <- assistant_search_common_pairings(occupation = "rice farmer", .pairings = pairings)
  expect_identical(ranged$results[[1L]]$psic_rev5_code, "01171–01189")
})

test_that("pairings results expose only the documented fields", {
  res <- assistant_search_common_pairings(.pairings = fixture_pairings())
  expect_equal(names(res$results[[1L]]), ASSISTANT_PAIRING_FIELDS)
  expect_false("psa_source" %in% names(res$results[[1L]]))
})

test_that("pairings filters are case-insensitive literal substrings, not regex", {
  pairings <- fixture_pairings()

  expect_equal(length(assistant_search_common_pairings(
    occupation = "ACCOUNT", .pairings = pairings)$results), 1L)

  # A regex metacharacter must be matched literally and therefore find nothing.
  regexy <- assistant_search_common_pairings(occupation = ".*", .pairings = pairings)
  expect_equal(regexy$total_matches, 0L)
  expect_equal(length(regexy$results), 0L)
})

test_that("pairings filters AND-combine", {
  pairings <- fixture_pairings()

  both <- assistant_search_common_pairings(
    occupation = "worker", industry_context = "government", .pairings = pairings
  )
  expect_equal(both$total_matches, 1L)
  expect_identical(both$results[[1L]]$confirmed_psoc, "3253")

  contradictory <- assistant_search_common_pairings(
    occupation = "worker", industry_context = "agriculture", .pairings = pairings
  )
  expect_equal(contradictory$total_matches, 0L)
})

# ---------------------------------------------------------------------------
# PSIC rules: one topic at a time, and no model-memory fallback
# ---------------------------------------------------------------------------

test_that("the rule tool returns exactly one topic", {
  res <- assistant_get_psic_rule("principal_activity", .rules = fixture_rules())

  expect_true(res$available)
  expect_true(res$found)
  expect_identical(res$topic, "principal_activity")
  expect_equal(names(res), c("available", "found", "topic", "title", "rule", "example"))
  expect_false("rules" %in% names(res))
})

test_that("an unknown rule topic returns the valid-topic list without erroring", {
  res <- assistant_get_psic_rule("how_do_i_classify_vibes", .rules = fixture_rules())

  expect_false(isTRUE(res$found))
  expect_identical(res$valid_topics, ASSISTANT_PSIC_RULE_TOPICS)
  expect_equal(length(res$valid_topics), 12L)
  expect_true(nzchar(res$message))
})

test_that("a missing rules artifact refuses model-memory substitution", {
  res <- assistant_get_psic_rule("principal_activity", .rules = NULL)

  expect_identical(res$available, FALSE)
  expect_null(res$rule)
  expect_match(res$reason, "model memory", ignore.case = TRUE)
  expect_match(res$reason, "unavailable", ignore.case = TRUE)
})

test_that("all 12 documented rule topics are retrievable from a conforming artifact", {
  rules <- fixture_rules()
  for (topic in ASSISTANT_PSIC_RULE_TOPICS) {
    res <- assistant_get_psic_rule(topic, .rules = rules)
    expect_true(res$found)
    expect_identical(res$topic, topic)
  }
})

# ---------------------------------------------------------------------------
# Degradation: a missing evidence artifact must not disable the assistant
# ---------------------------------------------------------------------------

test_that("a missing pairings artifact degrades gracefully and leaves search working", {
  res <- assistant_search_common_pairings(occupation = "accountant", .pairings = NULL)

  expect_identical(res$available, FALSE)
  expect_true(nzchar(res$reason))
  expect_null(res$results)

  # Official classification tools are unaffected.
  search <- assistant_search_classification("psoc", "accountant")
  expect_null(search$error)
  expect_gt(length(search$results), 0L)
  expect_true(assistant_get_classification_entry("psoc", "2022", "2121")$found)
})

test_that("the synonym stub is unavailable and never fabricates candidates", {
  res <- assistant_lookup_synonyms("magsasaka")
  expect_identical(res$available, FALSE)
  expect_null(res$results)
  expect_match(res$reason, "fabricate", ignore.case = TRUE)
})

# ---------------------------------------------------------------------------
# Registered tool surface
# ---------------------------------------------------------------------------

test_that("rm_assistant_tools() registers exactly the eight read-only tools", {
  skip_if_not_installed("ellmer")

  tools <- rm_assistant_tools()

  expect_type(tools, "list")
  expect_equal(length(tools), 8L)
  expect_true(all(vapply(
    tools, function(t) inherits(t, "ellmer::ToolDef"), logical(1)
  )))

  names_registered <- vapply(tools, function(t) t@name, character(1))
  expect_equal(names_registered, RM_ASSISTANT_TOOL_NAMES)

  # No fabricated synonym capability in V1.
  expect_false("assistant_lookup_synonyms" %in% names_registered)

  # A future edit cannot silently add a mutating tool without failing here.
  expect_setequal(names_registered, c(
    "assistant_search_classification",
    "assistant_get_classification_entry",
    "assistant_classification_registry",
    "assistant_search_common_pairings",
    "assistant_get_psic_rule",
    "assistant_get_classification_system_info",
    "assistant_code_occupation_and_activity",
    "assistant_coding_level"
  ))
})

test_that("every registered tool is annotated read-only and non-destructive", {
  skip_if_not_installed("ellmer")

  for (t in rm_assistant_tools()) {
    ann <- t@annotations
    expect_identical(ann$read_only_hint, TRUE)
    expect_identical(ann$destructive_hint, FALSE)
    expect_identical(ann$open_world_hint, FALSE)
  }
})

test_that("the injection seams are not visible in any registered tool schema", {
  skip_if_not_installed("ellmer")

  for (t in rm_assistant_tools()) {
    # A tool with no arguments (e.g. the registry tool) has NULL names
    # here, and startsWith(NULL, ".") errors -- normalise first.
    arg_names <- names(t@arguments@properties)
    if (is.null(arg_names)) arg_names <- character(0)

    expect_false(".pairings" %in% arg_names)
    expect_false(".rules" %in% arg_names)
    expect_false(any(startsWith(arg_names, ".")))
  }
})

# ---------------------------------------------------------------------------
# Real Workstream A artifacts — skipped until they exist
# ---------------------------------------------------------------------------

test_that("the real common-pairings artifact honours the tool contract", {
  skip_if_not(have_real_pairings(), "assistant_common_pairings() artifact not available")

  res <- assistant_search_common_pairings(limit = 25)
  expect_true(res$available)
  expect_lte(length(res$results), ASSISTANT_MAX_LIMIT)
  expect_true(nzchar(res$evidence_caveat))
  expect_equal(names(res$results[[1L]]), ASSISTANT_PAIRING_FIELDS)
})

test_that("real no-fixed-PSIC rows keep their NA code", {
  skip_if_not(have_real_pairings(), "assistant_common_pairings() artifact not available")

  pairings <- assistant_common_pairings()
  no_fixed <- pairings[!is.na(pairings$has_fixed_psic) & !pairings$has_fixed_psic, , drop = FALSE]
  skip_if(nrow(no_fixed) == 0L, "no no-fixed-PSIC rows in the artifact")

  res <- assistant_search_common_pairings(
    occupation = no_fixed$occupation[[1L]], limit = 25
  )
  hits <- Filter(function(r) identical(r$has_fixed_psic, FALSE), res$results)
  expect_gt(length(hits), 0L)
  expect_true(all(vapply(hits, function(r) is.na(r$psic_rev5_code), logical(1))))
})

test_that("the real PSIC rules artifact serves single topics", {
  skip_if_not(have_real_rules(), "assistant_psic_rules() artifact not available")

  res <- assistant_get_psic_rule("principal_activity")
  expect_true(res$available)
  expect_true(res$found)
  expect_identical(res$topic, "principal_activity")
  expect_true(nzchar(res$rule))
})

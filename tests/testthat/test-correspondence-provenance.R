# Workstream D acceptance tests: provenance discipline on the section-level
# structural graph, plus a documentation guard on
# docs/CORRESPONDENCE_SOURCES.md.
#
# Spec section 15's rule in one line: `official` is reserved for an explicit
# PSA-published correspondence record. Deriving a mapping by combining two
# official *structures* is not the same thing, and must not be labelled
# official -- neither in the graph nor in the prose that documents it.

# Tests run with the working directory at tests/testthat; the same
# repo-root-vs-testthat candidate walk used by
# R/correspondence/service.R's `.correspondence_resolve_default_path()`.
.provenance_repo_file <- function(rel_path) {
  for (p in c(rel_path, file.path("..", "..", rel_path))) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

# ---------------------------------------------------------------------------
# Provenance on the structural graph
# ---------------------------------------------------------------------------

test_that("no structural-graph edge claims 'official' provenance", {
  expect_false("official" %in% PSIC_SECTION_GRAPH$provenance_default)
})

test_that("every structural-graph edge defaults to 'derived'", {
  expect_true(all(PSIC_SECTION_GRAPH$provenance_default == "derived"))
})

test_that("provenance_default uses the shared schema vocabulary, not a private one", {
  # CORRESPONDENCE_PROVENANCE_VALUES lives in R/correspondence/schema.R and
  # is the single definition; this asserts the graph conforms to it rather
  # than redefining the allowed values here.
  expect_true(all(PSIC_SECTION_GRAPH$provenance_default %in% CORRESPONDENCE_PROVENANCE_VALUES))
  expect_setequal(CORRESPONDENCE_PROVENANCE_VALUES, c("official", "derived", "suggested"))
})

test_that("every edge carries a non-empty rationale", {
  expect_false(anyNA(PSIC_SECTION_GRAPH$rationale))
  expect_true(all(nzchar(trimws(PSIC_SECTION_GRAPH$rationale))))
  # A rationale must actually explain something, not be a placeholder.
  expect_true(all(nchar(PSIC_SECTION_GRAPH$rationale) >= 40))
})

test_that("every edge carries a non-empty evidence_key", {
  expect_false(anyNA(PSIC_SECTION_GRAPH$evidence_key))
  expect_true(all(nzchar(trimws(PSIC_SECTION_GRAPH$evidence_key))))
})

test_that("every evidence_key names only registered evidence sources", {
  keys <- unlist(strsplit(PSIC_SECTION_GRAPH$evidence_key, ";", fixed = TRUE))
  expect_gt(length(keys), 0)
  expect_true(all(nzchar(keys)))
  unknown <- setdiff(unique(keys), names(.PSIC_STRUCTURAL_EVIDENCE_KEYS))
  expect_identical(unknown, character(0))
})

test_that("the repair migration edge cites the PSA Section T training material", {
  gt <- PSIC_SECTION_GRAPH[PSIC_SECTION_GRAPH$from_section == "G" &
                             PSIC_SECTION_GRAPH$to_section == "T", ]
  expect_identical(nrow(gt), 1L)
  expect_true(grepl("psa_section_t_training", gt$evidence_key, fixed = TRUE))
  expect_identical(gt$provenance_default, "derived")
})

test_that("every registered evidence key is actually used by at least one edge", {
  used <- unique(unlist(strsplit(PSIC_SECTION_GRAPH$evidence_key, ";", fixed = TRUE)))
  expect_setequal(used, names(.PSIC_STRUCTURAL_EVIDENCE_KEYS))
})

# ---------------------------------------------------------------------------
# Documentation guard
# ---------------------------------------------------------------------------

test_that("docs/CORRESPONDENCE_SOURCES.md exists", {
  expect_true(file.exists(.provenance_repo_file("docs/CORRESPONDENCE_SOURCES.md")))
})

test_that("the sources doc uses the required 'not incorporated' framing", {
  txt <- paste(readLines(.provenance_repo_file("docs/CORRESPONDENCE_SOURCES.md"),
                         warn = FALSE), collapse = " ")
  txt <- gsub("[[:space:]]+", " ", txt)
  expect_true(grepl(
    "No explicit PSA 2019 . Revision 5 correspondence table has been incorporated into this application as of this build",
    txt
  ))
})

test_that("the sources doc does not claim an official PSA crosswalk has been incorporated", {
  txt <- paste(readLines(.provenance_repo_file("docs/CORRESPONDENCE_SOURCES.md"),
                         warn = FALSE), collapse = " ")
  txt <- tolower(gsub("[[:space:]]+", " ", txt))

  forbidden <- c(
    "official psa crosswalk has been incorporated",
    "official psa correspondence table has been incorporated",
    "incorporated the official psa",
    "psa has published an official correspondence",
    "this application contains an official psa correspondence"
  )
  for (phrase in forbidden) {
    expect_false(grepl(phrase, txt, fixed = TRUE), info = phrase)
  }
})

test_that("the sources doc records the two official PSA structural sources", {
  txt <- paste(readLines(.provenance_repo_file("docs/CORRESPONDENCE_SOURCES.md"),
                         warn = FALSE), collapse = " ")
  txt <- gsub("[[:space:]]+", " ", txt)
  expect_true(grepl("Revision 5 broad structure", txt, ignore.case = TRUE))
  expect_true(grepl("Section T", txt, fixed = TRUE))
  expect_true(grepl("Correspondence Tables", txt, fixed = TRUE))
  expect_true(grepl("953", txt, fixed = TRUE))
})

test_that("the sources doc states derived evidence is not official PSA correspondence", {
  txt <- paste(readLines(.provenance_repo_file("docs/CORRESPONDENCE_SOURCES.md"),
                         warn = FALSE), collapse = " ")
  txt <- gsub("[[:space:]]+", " ", txt)
  expect_true(grepl("Derived evidence is not official PSA correspondence", txt,
                    ignore.case = TRUE))
  expect_true(grepl("ISIC Rev.4", txt, fixed = TRUE))
})

test_that("the sources doc documents the three structural restructurings", {
  txt <- paste(readLines(.provenance_repo_file("docs/CORRESPONDENCE_SOURCES.md"),
                         warn = FALSE), collapse = " ")
  txt <- gsub("[[:space:]]+", " ", txt)
  # G trade/repair redistribution, J -> J/K split, K-onward letter shift.
  expect_true(grepl("trade/repair redistribution", txt, ignore.case = TRUE))
  expect_true(grepl("2019 J . 2026 J . 2026 K", txt))
  expect_true(grepl("letter shift", txt, ignore.case = TRUE))
})

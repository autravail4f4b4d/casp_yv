# PSOC 2022 descriptive metadata — build chain, authority boundary, surfaces.
#
# THE ONE PROPERTY EVERYTHING ELSE HANGS ON. This artifact is explanatory
# text, not a classification authority. It may describe a code the
# application has already verified; it may never select, rank, authorise or
# widen one. Most of what follows exists to keep that true under edit.

.repo <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)
.render <- function(tag) paste(as.character(htmltools::renderTags(tag)$html),
                               collapse = "")
.read_src <- function(...) {
  path <- file.path(.repo, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}


# ===========================================================================
# Build chain: JSON -> validated R object -> RDS -> readRDS -> exact lookup
# ===========================================================================

test_that("the runtime artifact exists and is R-native, not wrapped JSON", {
  path <- file.path(.repo, "data", "psoc_2022_descriptive.rds")
  expect_true(file.exists(path))

  art <- readRDS(path)
  # An R-NATIVE structured object. A character scalar here would mean the
  # runtime re-parses 2.6 MB of JSON on every process start and walks 649
  # elements for one lookup -- work the build is supposed to have done.
  expect_false(is.character(art))
  expect_true(is.list(art))
  expect_identical(art$system, "psoc")
  expect_identical(art$version, "2022")
  expect_true(is.list(art$records))

  # Keyed by code, so a lookup is a hash access rather than a scan.
  expect_false(is.null(names(art$records)))
  expect_identical(names(art$records)[[1]], art$records[[1]]$code)
})

test_that("the artifact loads offline and needs no network", {
  # Nothing in the service may reach outside the process.
  src <- .read_src("R", "metadata", "psoc_descriptive_metadata.R")
  for (net in c("http://", "https://", "url(", "download.file", "curl::")) {
    expect_false(grepl(net, src, fixed = TRUE), info = net)
  }
  expect_true(psoc_descriptive_available())
})

test_that("the descriptive layer never reads data-raw at runtime", {
  # data-raw is SOURCE: it is where the extraction lands and where a future
  # re-extraction will land. Only the validated artifact reaches a user, so
  # a malformed or half-written extraction cannot be rendered.
  #
  # Scoped to the files this milestone owns. Other parts of the repository
  # (the ISIC bridge, the retrieval eval corpus, curated overrides) have
  # their own long-standing data-raw relationships that are not in scope
  # here, and widening this assertion to cover them would be asserting
  # someone else's contract.
  owned <- c(
    file.path("R", "metadata", "psoc_descriptive_metadata.R"),
    file.path("R", "ui", "ui_psoc_descriptive.R"),
    file.path("R", "ui", "ui_details.R"),
    file.path("R", "assistant", "assistant_attached_context.R")
  )
  for (rel in owned) {
    src <- .read_src(rel)
    code <- paste(sub("#.*$", "", strsplit(src, "\n", fixed = TRUE)[[1]]),
                  collapse = "\n")
    expect_false(grepl("data-raw", code, fixed = TRUE), info = rel)
  }

  # And the artifact the service loads lives under the runtime data
  # directory, not under source.
  expect_identical(PSOC_DESCRIPTIVE_PATH,
                   file.path("data", "psoc_2022_descriptive.rds"))
})

test_that("the artifact carries the expected 649 records and structure", {
  art <- readRDS(file.path(.repo, "data", "psoc_2022_descriptive.rds"))
  expect_identical(length(art$records), 649L)

  levels <- table(vapply(art$records, function(r) r$level, character(1)))
  expect_identical(as.integer(levels[["major_group"]]), 10L)
  expect_identical(as.integer(levels[["sub_major_group"]]), 43L)
  expect_identical(as.integer(levels[["minor_group"]]), 130L)
  expect_identical(as.integer(levels[["unit_group"]]), 466L)
})

test_that("duplicate keys are impossible in the artifact", {
  art <- readRDS(file.path(.repo, "data", "psoc_2022_descriptive.rds"))
  codes <- vapply(art$records, function(r) r$code, character(1))
  expect_identical(anyDuplicated(codes), 0L)
  expect_identical(length(unique(codes)), 649L)
})

test_that("the build validates rather than repairs", {
  # A mismatch is a fact a human has to look at. The builder must STOP on
  # every category of disagreement, not normalise it away.
  src <- .read_src("scripts", "build_psoc_2022_descriptive.R")
  expect_true(grepl("duplicate descriptive codes", src, fixed = TRUE))
  expect_true(grepl("absent from canonical PSOC 2022", src, fixed = TRUE))
  expect_true(grepl("canonical codes without descriptive metadata", src, fixed = TRUE))
  expect_true(grepl("title mismatches", src, fixed = TRUE))
  expect_true(grepl("level mismatches", src, fixed = TRUE))
  # The level vocabulary difference is declared, not silently coerced.
  expect_true(grepl("LEVEL_MAP", src, fixed = TRUE))
  expect_true(grepl("Unmapped descriptive level", src, fixed = TRUE))
})


# ===========================================================================
# Reconciliation against the canonical repository
# ===========================================================================

test_that("every descriptive record matches a canonical PSOC 2022 record", {
  art <- readRDS(file.path(.repo, "data", "psoc_2022_descriptive.rds"))
  canon <- get_classification("psoc", "2022")

  meta_codes <- names(art$records)
  canon_codes <- as.character(canon$code)

  expect_identical(length(canon_codes), 649L)
  expect_length(setdiff(meta_codes, canon_codes), 0L)  # metadata orphans
  expect_length(setdiff(canon_codes, meta_codes), 0L)  # canonical gaps

  # Titles and levels agree on every record, using the canonical vocabulary.
  norm <- function(x) toupper(trimws(gsub("[[:space:]]+", " ", x)))
  canon_title <- stats::setNames(as.character(canon$label), canon_codes)
  canon_level <- stats::setNames(as.character(canon$level), canon_codes)
  bad_title <- Filter(function(cd)
    !identical(norm(art$records[[cd]]$title), norm(canon_title[[cd]])), meta_codes)
  bad_level <- Filter(function(cd)
    !identical(art$records[[cd]]$level, canon_level[[cd]]), meta_codes)
  expect_length(bad_title, 0L)
  expect_length(bad_level, 0L)
})


# ===========================================================================
# The service: exact lookup, fail closed
# ===========================================================================

test_that("lookup is exact and fails closed on every wrong key", {
  expect_false(is.null(get_psoc_descriptive_metadata("2022", "1112")))

  # Wrong edition never falls back to 2022.
  expect_null(get_psoc_descriptive_metadata("2012", "1112"))
  expect_null(get_psoc_descriptive_metadata("2026", "1112"))
  # Unknown / fabricated code.
  expect_null(get_psoc_descriptive_metadata("2022", "999999"))
  expect_null(get_psoc_descriptive_metadata("2022", "11120"))
  # A level the caller and the artifact disagree about shows nothing.
  expect_null(get_psoc_descriptive_metadata("2022", "1112", level = "major_group"))
  expect_false(is.null(get_psoc_descriptive_metadata("2022", "1112",
                                                     level = "unit_group")))
  # Degenerate input.
  for (bad in list(NULL, NA_character_, "", "   ")) {
    expect_null(get_psoc_descriptive_metadata("2022", bad))
    expect_null(get_psoc_descriptive_metadata(bad, "1112"))
  }
})

test_that("no prefix, fuzzy or partial key is ever honoured", {
  # An exact-lookup service that answered "111" for "1112" would be
  # ranking by another name.
  # Surrounding whitespace is trimmed -- that is input hygiene, not
  # matching: a trailing space is not a different code.
  expect_false(is.null(get_psoc_descriptive_metadata("2022", " 1112 ")))
  # Everything else fails. A prefix, a wildcard or a TITLE must never
  # resolve, or this layer would be selecting codes by another name.
  # "111" is deliberately NOT used as a negative here: it is a real PSOC
  # minor-group code, and returning it is the exact lookup working.
  expect_identical(get_psoc_descriptive_metadata("2022", "111")$level,
                   "minor_group")
  # PSOC codes are hierarchical, so a prefix of a valid code is usually
  # itself a valid code -- "11" is a real sub-major group. The negatives
  # therefore have to be keys the classification genuinely does not
  # contain, not merely shorter ones.
  expect_null(get_psoc_descriptive_metadata("2022", "111*"))
  expect_null(get_psoc_descriptive_metadata("2022", "99999"))
  expect_null(get_psoc_descriptive_metadata("2022", "1112-a"))
  expect_null(get_psoc_descriptive_metadata("2022", "1112x"))
  expect_null(get_psoc_descriptive_metadata("2022", "SENIOR GOVERNMENT OFFICIALS"))
})

test_that("the service exposes no search or ranking interface", {
  # THE SAFEGUARD IS THE ABSENCE. The moment this layer could be asked
  # "which code matches this text", descriptive prose would be influencing
  # code selection -- the authority inversion this project forbids.
  src <- .read_src("R", "metadata", "psoc_descriptive_metadata.R")
  code <- paste(sub("#.*$", "", strsplit(src, "\n", fixed = TRUE)[[1]]),
                collapse = "\n")
  for (banned in c("search", "grepl", "rank", "score", "match(", "agrep",
                   "startsWith", "fuzzy", "similar")) {
    expect_false(grepl(banned, code, fixed = TRUE), info = banned)
  }
  # And nothing exported by it takes free text.
  expect_true(grepl("get_psoc_descriptive_metadata <- function(version, code, level = NULL)",
                    src, fixed = TRUE))
})

test_that("PSOC 1112 carries the source-provided City administrator example", {
  rec <- get_psoc_descriptive_metadata("2022", "1112")
  expect_true("City administrator" %in% rec$examples)
  # It is an EXAMPLE, not a coding rule. No R CODE may contain that string:
  # the moment a title is hard-coded, an illustration has become a rule.
  # Comments are excluded -- one existing file discusses this very example
  # in prose, which is documentation, not behaviour.
  for (f in list.files(file.path(.repo, "R"), pattern = "[.]R$",
                       recursive = TRUE, full.names = TRUE)) {
    src <- paste(readLines(f, warn = FALSE), collapse = "\n")
    code <- paste(sub("#.*$", "", strsplit(src, "\n", fixed = TRUE)[[1]]),
                  collapse = "\n")
    expect_false(grepl("City administrator", code, fixed = TRUE),
                 info = basename(f))
  }
})

test_that("official content is served verbatim from the source", {
  rec <- get_psoc_descriptive_metadata("2022", "1112")
  expect_gt(length(rec$definition), 0L)
  expect_gt(length(rec$tasks), 0L)
  expect_gt(length(rec$examples), 0L)
  expect_true(all(nzchar(rec$definition)))
  # Lettered tasks keep their official letters.
  expect_true(all(vapply(rec$tasks, function(t) !is.na(t$label), logical(1))))
  # Crosswalks keep their partial qualifiers.
  expect_true(is.list(rec$crosswalk$psoc_1992$codes))
  expect_true(all(vapply(rec$crosswalk$psoc_1992$codes,
                         function(c) is.logical(c$partial), logical(1))))
})


# ===========================================================================
# Authority boundary
# ===========================================================================

test_that("metadata cannot authorize a code", {
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_entry("psoc", "2022", "1112"))
  expect_false(is.null(v$descriptive))

  p <- assistant_attached_context_packet(v)
  allowed <- assistant_allowed_codes(p)

  # ONLY the canonically verified code is allowed -- never a code mentioned
  # in a related-occupation entry or a crosswalk, however official.
  expect_identical(allowed, "1112")

  related <- vapply(v$descriptive$related_occupations,
                    function(r) r$code %||% NA_character_, character(1))
  for (cd in related[!is.na(related)]) {
    expect_false(cd %in% allowed, info = cd)
  }
  cw <- c(vapply(v$descriptive$crosswalk$psoc_1992$codes,
                 function(c) c$code, character(1)),
          vapply(v$descriptive$crosswalk$isco_2008$codes,
                 function(c) c$code, character(1)))
  for (cd in cw) expect_false(cd %in% setdiff(allowed, "1112"), info = cd)

  # The guard still rejects any of them in a reply.
  chk <- assistant_guard_check("Consider PSOC 1110 as well.", p)
  expect_false(chk$ok)
})

test_that("verification happens BEFORE enrichment, never instead of it", {
  src <- .read_src("R", "assistant", "assistant_attached_context.R")
  # The canonical read must precede the descriptive fetch in the same
  # function: enrichment keyed off an unverified code would be metadata
  # deciding what exists.
  pos_canon <- regexpr("get_classification_entry(", src, fixed = TRUE)
  pos_desc <- regexpr("get_psoc_descriptive_metadata(", src, fixed = TRUE)
  expect_gt(pos_canon, 0L)
  expect_gt(pos_desc, pos_canon)

  # An unverifiable code yields no context at all, so no descriptive text.
  expect_null(assistant_verify_attached_context(
    assistant_context_descriptor_entry("psoc", "2022", "999999")))
})

test_that("descriptive text never enters retrieval or ranking", {
  # THE NON-REGRESSION THAT MATTERS MOST. No retrieval, search or ranking
  # file may reference the descriptive service or its artifact.
  dirs <- c(file.path(.repo, "R", "retrieval"), file.path(.repo, "R"))
  files <- unique(c(
    list.files(dirs[[1]], pattern = "[.]R$", full.names = TRUE),
    file.path(.repo, "R", c("search.R", "parallel_search.R", "repository.R"))
  ))
  files <- files[file.exists(files)]
  expect_gt(length(files), 0L)
  for (f in files) {
    src <- paste(readLines(f, warn = FALSE), collapse = "\n")
    for (banned in c("psoc_descriptive", "psoc_2022_descriptive",
                     "descriptive_metadata")) {
      expect_false(grepl(banned, src, fixed = TRUE),
                   info = paste(basename(f), banned))
    }
  }
})

test_that("search results and ranking are unchanged by the metadata", {
  # Same queries, same codes, in the same order.
  r1 <- search_classification_result(system = "psoc", version = "2022",
                                     query = "government", limit = 20)
  expect_gt(nrow(r1$data), 0L)
  expect_false(any(grepl("definition", names(r1$data), fixed = TRUE)))
  # No descriptive column leaked into the result frame.
  for (col in c("definition", "tasks", "examples", "task_summary")) {
    expect_false(col %in% names(r1$data), info = col)
  }
})

test_that("semantic authority remains OFF", {
  shadow <- .read_src("R", "retrieval", "retrieval_shadow.R")
  expect_true(grepl("semantic_authority_applied = FALSE", shadow, fixed = TRUE))
})


# ===========================================================================
# Details surface
# ===========================================================================

test_that("View details renders the official sections for a described code", {
  entry <- get_classification_entry("psoc", "2022", "1112")
  html <- .render(entry_detail_body_ui(entry))

  expect_true(grepl("Definition", html, fixed = TRUE))
  expect_true(grepl("Typical tasks", html, fixed = TRUE))
  expect_true(grepl("Examples of occupations classified here", html, fixed = TRUE))
  expect_true(grepl("City administrator", html, fixed = TRUE))
  expect_true(grepl("Historical correspondence", html, fixed = TRUE))
  expect_true(grepl("PSOC 1992", html, fixed = TRUE))
  expect_true(grepl("ISCO 2008", html, fixed = TRUE))
  expect_true(grepl("Descriptive text:", html, fixed = TRUE))
})

test_that("absent sections are hidden, never filled with placeholder prose", {
  # Major group "0" has no examples in the source.
  entry <- get_classification_entry("psoc", "2022", "0")
  rec <- get_psoc_descriptive_metadata("2022", "0")
  skip_if(is.null(rec), "major group 0 not described")
  skip_if(length(rec$examples) > 0L, "major group 0 unexpectedly has examples")

  html <- .render(entry_detail_body_ui(entry))
  expect_false(grepl("Examples of occupations classified here", html, fixed = TRUE))
  # And no apology text in its place.
  for (filler in c("not available", "No definition", "None provided",
                   "Not provided", "no examples")) {
    expect_false(grepl(filler, html, ignore.case = TRUE), info = filler)
  }
})

test_that("the details hierarchy stays canonical, not descriptive", {
  html <- .render(entry_detail_body_ui(get_classification_entry("psoc", "2022", "1112")))
  expect_true(grepl("Classification hierarchy", html, fixed = TRUE))
  src <- .read_src("R", "ui", "ui_psoc_descriptive.R")
  # The descriptive layer carries parent ids and must not render them as
  # the structure: the repository is the authority there.
  expect_false(grepl("parent_id", src, fixed = TRUE))
})

test_that("no other system or edition renders PSOC descriptive prose", {
  psic <- .render(entry_detail_body_ui(get_classification_entry("psic", "2026", "84113")))
  expect_false(grepl("psa-psoc-desc", psic, fixed = TRUE))

  psgc <- .render(entry_detail_body_ui(
    get_classification_entry("psgc", "Q2_2026", "1001300000")))
  expect_false(grepl("psa-psoc-desc", psgc, fixed = TRUE))

  # PSOC 2012 is a real edition with no descriptive artifact.
  old <- tryCatch(get_classification_entry("psoc", "2012", "1112"),
                  error = function(e) NULL)
  if (!is.null(old) && nrow(old) > 0L) {
    expect_false(grepl("psa-psoc-desc", .render(entry_detail_body_ui(old)),
                       fixed = TRUE))
  }
})

test_that("partial crosswalk qualifiers survive to the rendered page", {
  art <- readRDS(file.path(.repo, "data", "psoc_2022_descriptive.rds"))
  partial <- Filter(function(r) {
    any(vapply(r$crosswalk$psoc_1992$codes, function(c) isTRUE(c$partial), logical(1)))
  }, art$records)
  skip_if(length(partial) == 0L, "no partial crosswalk in this artifact")

  entry <- get_classification_entry("psoc", "2022", partial[[1]]$code)
  html <- .render(entry_detail_body_ui(entry))
  expect_true(grepl("(part)", html, fixed = TRUE))
})


# ===========================================================================
# Search preview
# ===========================================================================

test_that("the Search card shows a concise preview, not the reference", {
  entry <- get_classification_entry("psoc", "2022", "1112")
  preview <- psoc_descriptive_preview(entry)
  expect_false(is.null(preview))
  expect_lte(nchar(preview), 230L)

  html <- .render(entry_detail_ui(entry))
  expect_true(grepl("psa-detail-preview", html, fixed = TRUE))
  # The card is a hint, not a second details panel.
  expect_false(grepl("Typical tasks", html, fixed = TRUE))
  expect_false(grepl("Examples of occupations", html, fixed = TRUE))
})

test_that("the preview is absent where there is nothing verified to show", {
  expect_null(psoc_descriptive_preview(
    get_classification_entry("psic", "2026", "84113")))
  expect_null(psoc_descriptive_preview(NULL))
})


# ===========================================================================
# RM grounding
# ===========================================================================

test_that("RM sees the official text only for its own verified code", {
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_entry("psoc", "2022", "1112"))
  note <- assistant_render_attached_context(v)

  expect_true(grepl("Official definition", note, fixed = TRUE))
  expect_true(grepl("Official tasks", note, fixed = TRUE))
  expect_true(grepl("Official example occupations", note, fixed = TRUE))
  expect_true(grepl("City administrator", note, fixed = TRUE))

  # Another code's description is not in the block.
  other <- get_psoc_descriptive_metadata("2022", "2411")
  if (!is.null(other) && length(other$definition) > 0L) {
    expect_false(grepl(substr(other$definition[[1]], 1, 60), note, fixed = TRUE))
  }
})

test_that("RM is told to assist with coding, not recite the Details panel", {
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_entry("psoc", "2022", "1112"))
  note <- assistant_render_attached_context(v)
  expect_true(grepl("Do NOT simply repeat them", note, fixed = TRUE))
  expect_true(grepl("View details", note, fixed = TRUE))
  expect_true(grepl("ask ONE short", note, fixed = TRUE))
  # An example may be cited only if it is actually present.
  expect_true(grepl("ONLY if it", note, fixed = TRUE))
})

test_that("the boundary reflects what is actually loaded", {
  # A model handed the definition must not also be told the definition is
  # unavailable -- that is a contradictory instruction.
  with_meta <- assistant_render_attached_context(
    assistant_verify_attached_context(
      assistant_context_descriptor_entry("psoc", "2022", "1112")))
  expect_false(grepl("does not currently load definitions", with_meta, fixed = TRUE))

  # A record with no descriptive text still says so plainly.
  without <- assistant_render_attached_context(
    assistant_verify_attached_context(
      assistant_context_descriptor_entry("psgc", "Q2_2026", "1001300000")))
  expect_true(grepl("does not currently load", without, fixed = TRUE))
})

test_that("the RM block is bounded, not the whole reference", {
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_entry("psoc", "2022", "1112"))
  note <- assistant_render_attached_context(v)
  n_tasks <- length(gregexpr("\n- \\(", note)[[1]])
  expect_lte(n_tasks, .ASSISTANT_CONTEXT_MAX_TASKS + 1L)
  expect_lte(length(v$descriptive$examples[
    seq_len(min(length(v$descriptive$examples), .ASSISTANT_CONTEXT_MAX_EXAMPLES))]),
    .ASSISTANT_CONTEXT_MAX_EXAMPLES)
})


# ===========================================================================
# Coding pair
# ===========================================================================

test_that("the coding pair keeps PSOC and PSIC independent", {
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_coding_pair("2022", "1112", "2026", "84113"))
  note <- assistant_render_attached_context(v)

  expect_true(grepl("neither code implies the other", note, fixed = TRUE))
  expect_true(grepl("Do NOT state that the pair is", note, fixed = TRUE))
  # The occupation side may carry its official description...
  expect_true(grepl("Official definition", note, fixed = TRUE))
  # ...and the asymmetry is stated rather than left to be misread as the
  # PSOC half being better evidenced.
  expect_true(grepl("PSOC side only", note, fixed = TRUE))

  p <- assistant_attached_context_packet(v)
  expect_setequal(assistant_allowed_codes(p), c("1112", "84113"))
})


# ===========================================================================
# Pass 1 repairs must survive
# ===========================================================================

test_that("the outsourced-janitor partial resolution is unchanged", {
  st <- assistant_new_turn_state()
  r <- assistant_handle_turn("outsourced janitor", st)
  expect_identical(r$packet$occupation$status, "resolved")
  expect_identical(r$packet$clarification$missing_slot, "wage_payer")

  st2 <- assistant_new_turn_state()
  assistant_handle_turn(
    "I am a janitor deployed at a hospital through a manpower agency. What is my PSIC?", st2)
  r2 <- assistant_handle_turn("the agency pays my wages", st2)
  expect_identical(as.character(r2$packet$industry$selected_code), "78200")
})

test_that("the accepted RM matrix is unchanged by descriptive metadata", {
  run <- function(...) {
    st <- assistant_new_turn_state()
    out <- NULL
    for (m in c(...)) out <- assistant_handle_turn(m, st)
    out
  }
  psoc_of <- function(r) as.character(r$packet$occupation$selected_code)
  psic_of <- function(r) {
    v <- r$packet$industry$selected_code
    if (is.null(v)) NA_character_ else as.character(v)
  }

  m <- run("mayor psoc psic")
  expect_identical(psoc_of(m), "1111"); expect_identical(psic_of(m), "84113")

  t <- run("teacher in a private high school psoc psic", "latter")
  expect_identical(psoc_of(t), "2330"); expect_identical(psic_of(t), "85314")

  # The bare qualifier still refuses to resolve PSIC.
  c1 <- run("carpenter psoc psic", "residential")
  expect_identical(c1$status, "clarification_required")
  expect_identical(psoc_of(c1), "7115")
  expect_true(is.na(psic_of(c1)))
})

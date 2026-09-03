# Build the PSOC 2022 descriptive-metadata runtime artifact.
#
#   data-raw/psoc_2022_structured.json   canonical source, checked in, never
#                                        edited by this script
#            |  jsonlite::fromJSON
#            v
#   validation + reconciliation against the canonical PSOC 2022 repository
#            |
#            v
#   an R-NATIVE structured object, keyed by code
#            |  saveRDS
#            v
#   data/psoc_2022_descriptive.rds       compiled runtime artifact
#
# Run from the repository root:
#   Rscript scripts/build_psoc_2022_descriptive.R
#
# WHY AN R-NATIVE OBJECT AND NOT THE JSON TEXT IN AN RDS. Re-parsing a 2.6 MB
# JSON string on every process start, and then walking a 649-element list to
# find one code, is work the build can do once. The artifact is a named list
# keyed by code, so a lookup is a single hash access and the runtime never
# parses anything.
#
# WHY THE APPLICATION MUST NOT READ data-raw. `data-raw/` is source: it is
# where the extraction lands and where a future re-extraction will land. The
# running application reads only the validated, compiled artifact, so a
# malformed or half-written source file can never reach a user -- this script
# fails loudly instead.
#
# THIS SCRIPT NEVER REPAIRS THE SOURCE. Every check below either passes or
# stops the build. A mismatch is a fact about the artifact that a human has
# to look at, not something to paper over at build time.

suppressMessages({
  stopifnot(requireNamespace("jsonlite", quietly = TRUE))
})

stopifnot(dir.exists("R"), dir.exists("data-raw"), dir.exists("data"))

SOURCE_JSON <- file.path("data-raw", "psoc_2022_structured.json")
TARGET_RDS <- file.path("data", "psoc_2022_descriptive.rds")

# The canonical repository is the authority on what PSOC 2022 contains. It
# is loaded here purely to VALIDATE the descriptive artifact against it.
invisible(lapply(sort(list.files("R", pattern = "[.]R$", recursive = TRUE,
                                 full.names = TRUE)), source))

message("Reading ", SOURCE_JSON)
raw <- jsonlite::fromJSON(SOURCE_JSON, simplifyVector = FALSE)

stopifnot(
  is.list(raw),
  identical(raw$schema_version, "1.0.0"),
  is.list(raw$records),
  length(raw$records) > 0L
)

# ---- helpers ---------------------------------------------------------------

.chr1 <- function(x) {
  if (is.null(x)) return(NA_character_)
  v <- as.character(x)[[1L]]
  if (length(v) == 0L || is.na(v)) NA_character_ else v
}

# A list-of-objects -> character vector of one field, in SOURCE ORDER. Order
# is content here: definition paragraphs and lettered tasks read in sequence.
.field_vec <- function(items, field) {
  if (is.null(items) || length(items) == 0L) return(character(0))
  out <- vapply(items, function(it) .chr1(it[[field]]), character(1))
  out[!is.na(out) & nzchar(out)]
}

.tasks <- function(items) {
  if (is.null(items) || length(items) == 0L) return(list())
  lapply(items, function(it) {
    list(label = .chr1(it$label), text = .chr1(it$text))
  })
}

.related <- function(items) {
  if (is.null(items) || length(items) == 0L) return(list())
  lapply(items, function(it) {
    list(title = .chr1(it$title), code = .chr1(it$code),
         partial = isTRUE(it$partial))
  })
}

.crosswalk_side <- function(side) {
  if (is.null(side)) return(NULL)
  codes <- if (is.null(side$codes)) list() else lapply(side$codes, function(c) {
    list(code = .chr1(c$code), partial = isTRUE(c$partial))
  })
  # `raw` is retained verbatim: the workbook sometimes states a mapping the
  # parsed codes cannot fully express, and dropping it would lose the only
  # record of what the source actually said.
  list(raw = .chr1(side$raw), codes = codes)
}

# THE LEVEL VOCABULARY BRIDGE.
#
# The descriptive artifact says `major` / `submajor` / `minor` / `unit`; the
# canonical repository says `major_group` / `sub_major_group` /
# `minor_group` / `unit_group`. Reconciliation showed a clean 1:1 bijection
# across all 649 records, so this is a naming difference and not a data
# difference. It is declared explicitly, and the build fails on any level
# the map does not cover -- rather than being normalised away silently.
LEVEL_MAP <- c(
  major    = "major_group",
  submajor = "sub_major_group",
  minor    = "minor_group",
  unit     = "unit_group"
)

# ---- transform -------------------------------------------------------------

records <- lapply(raw$records, function(r) {
  src_level <- .chr1(r$level)
  if (is.na(src_level) || !src_level %in% names(LEVEL_MAP)) {
    stop("Unmapped descriptive level '", src_level, "' for code ", .chr1(r$code),
         call. = FALSE)
  }
  list(
    code = .chr1(r$code),
    title = .chr1(r$title),
    # Both vocabularies are kept: the canonical one is what the application
    # joins on, the source one is what the artifact said.
    level = unname(LEVEL_MAP[[src_level]]),
    level_source = src_level,
    parent_id = .chr1(r$parent_id),
    major_group = .chr1(r$major_group),
    sub_major_group = .chr1(r$sub_major_group),
    minor_group = .chr1(r$minor_group),
    unit_group = .chr1(r$unit_group),
    definition = .field_vec(r$definition_paragraphs, "text"),
    tasks = .tasks(r$tasks),
    task_summary = .field_vec(r$task_summary_paragraphs, "text"),
    examples = .field_vec(r$examples, "title"),
    related_occupations = .related(r$related_occupations),
    exclusions = .field_vec(r$exclusions, "text"),
    notes = .field_vec(r$notes, "text"),
    crosswalk = list(
      psoc_1992 = .crosswalk_side(r$crosswalk$psoc_1992),
      isco_2008 = .crosswalk_side(r$crosswalk$isco_2008)
    ),
    source = list(
      sheet = .chr1(r$source$sheet),
      heading_row = if (is.null(r$source$heading_row)) NA_integer_ else
        as.integer(r$source$heading_row)
    )
  )
})

codes <- vapply(records, function(r) r$code, character(1))
names(records) <- codes

# ---- validation ------------------------------------------------------------

fail <- function(...) stop("[build-psoc-descriptive] ", ..., call. = FALSE)

if (anyNA(codes) || any(!nzchar(codes))) fail("record with a missing code")
if (anyDuplicated(codes)) {
  fail("duplicate descriptive codes: ",
       paste(unique(codes[duplicated(codes)]), collapse = ", "))
}

EXPECTED_TOTAL <- 649L
EXPECTED_LEVELS <- c(major_group = 10L, sub_major_group = 43L,
                     minor_group = 130L, unit_group = 466L)

if (length(records) != EXPECTED_TOTAL) {
  fail("expected ", EXPECTED_TOTAL, " records, found ", length(records))
}
lv <- table(vapply(records, function(r) r$level, character(1)))
for (nm in names(EXPECTED_LEVELS)) {
  got <- if (nm %in% names(lv)) as.integer(lv[[nm]]) else 0L
  if (!identical(got, EXPECTED_LEVELS[[nm]])) {
    fail("level ", nm, ": expected ", EXPECTED_LEVELS[[nm]], ", found ", got)
  }
}

# RECONCILIATION AGAINST THE CANONICAL REPOSITORY. The descriptive artifact
# may describe only codes the repository actually publishes; a descriptive
# record for a code the application does not recognise would be metadata
# with nothing to attach to, and a canonical code is never given a title
# from this artifact.
canon <- get_classification("psoc", "2022")
canon_codes <- as.character(canon$code)

missing_canon <- setdiff(codes, canon_codes)
if (length(missing_canon)) {
  fail(length(missing_canon), " descriptive codes absent from canonical PSOC 2022: ",
       paste(utils::head(missing_canon, 10), collapse = ", "))
}
missing_meta <- setdiff(canon_codes, codes)
if (length(missing_meta)) {
  fail(length(missing_meta), " canonical codes without descriptive metadata: ",
       paste(utils::head(missing_meta, 10), collapse = ", "))
}

norm_title <- function(x) toupper(trimws(gsub("[[:space:]]+", " ", x)))
canon_title <- stats::setNames(as.character(canon$label), canon_codes)
canon_level <- stats::setNames(as.character(canon$level), canon_codes)
bad_title <- character(0)
bad_level <- character(0)
for (cd in codes) {
  if (!identical(norm_title(records[[cd]]$title), norm_title(canon_title[[cd]]))) {
    bad_title <- c(bad_title, cd)
  }
  if (!identical(records[[cd]]$level, canon_level[[cd]])) {
    bad_level <- c(bad_level, cd)
  }
}
if (length(bad_title)) {
  fail(length(bad_title), " title mismatches, e.g. ",
       paste(utils::head(bad_title, 10), collapse = ", "))
}
if (length(bad_level)) {
  fail(length(bad_level), " level mismatches, e.g. ",
       paste(utils::head(bad_level, 10), collapse = ", "))
}

# ---- write -----------------------------------------------------------------

artifact <- list(
  system = "psoc",
  version = "2022",
  schema_version = raw$schema_version,
  # Provenance travels with the artifact so the running application can say
  # where the descriptive text came from without reading data-raw.
  source = list(
    file_name = .chr1(raw$source$file_name),
    sha256 = .chr1(raw$source$sha256),
    extraction_method = .chr1(raw$source$extraction_method),
    issuing_authority = "Philippine Statistics Authority"
  ),
  built_from = basename(SOURCE_JSON),
  level_map = LEVEL_MAP,
  records = records
)

saveRDS(artifact, TARGET_RDS, version = 2L)

message("Wrote ", TARGET_RDS, " (", length(records), " records, ",
        format(file.size(TARGET_RDS), big.mark = ","), " bytes)")
message("Levels: ", paste(sprintf("%s=%d", names(lv), as.integer(lv)),
                          collapse = ", "))
